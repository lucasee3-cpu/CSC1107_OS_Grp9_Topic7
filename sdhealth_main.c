// Creates the Linux kernel module infrastructure for the SD Card Health Monitoring System.
// This module creates /dev/sdhealth and allows user programs to communicate with the kernel driver through read() and write().

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/timer.h>
#include <linux/types.h>
#include <linux/workqueue.h>    /* required for struct work_struct and schedule_work() */
#include "detection.h"

#define DEVICE_NAME "sdhealth"
#define CLASS_NAME  "sdhealth_class"

static dev_t dev_number;                 // stores major and minor device numbers
static struct cdev sdhealth_cdev;        // character device structure
static struct class *sdhealth_class;     // device class shown under /sys/class
static struct device *sdhealth_device;   // represents /dev/sdhealth
static struct timer_list sd_timer;       // linux kernel data structure representing a timer
static struct work_struct sd_work;       // work item submitted to the kernel workqueue
                                         // allows update_stats() to run in process context
                                         // where filp_open() is safe to call
static bool initial_reading = true;      // set initial_reading to be true

static unsigned long READ_count = 0;         // stores SD card read operations
static unsigned long WRITE_count = 0;        // stores SD card write operations
static unsigned long READ_rate = 0;          // operations per timer interval
static unsigned long WRITE_rate = 0;         // operations per timer interval
static unsigned long PREV_READ_count = 0;    // stores previous SD card read operations
static unsigned long PREV_WRITE_count = 0;   // stores previous SD card write operations
static unsigned long READ_sectors = 0;
static unsigned long WRITE_sectors = 0;
static unsigned long PREV_READ_sectors = 0;
static unsigned long PREV_WRITE_sectors = 0;
static unsigned long READ_KBps = 0;
static unsigned long WRITE_KBps = 0;
static unsigned long interval_jiffies = HZ;
static void sd_timer_callback(struct timer_list *t);


static int sdhealth_open(struct inode *inode, struct file *file)
{
    printk(KERN_INFO "[SDHEALTH] Device opened\n");
    return 0;
}


static int sdhealth_release(struct inode *inode, struct file *file)
{
    printk(KERN_INFO "[SDHEALTH] Device closed\n");
    return 0;
}


static void update_stats(void)
{
    struct file *f;
    char buf[256];
    loff_t pos = 0;
    ssize_t bytes_read;

    unsigned long current_read;
    unsigned long current_write;
    unsigned long current_read_sectors;
    unsigned long current_write_sectors;
    unsigned long read_sector_delta;
    unsigned long write_sector_delta;

    f = filp_open("/sys/block/mmcblk0/stat", O_RDONLY, 0);
    if (IS_ERR(f)) {
        printk(KERN_WARNING "[SDHEALTH] Failed to open /sys/block/mmcblk0/stat\n");
        return;
    }

    bytes_read = kernel_read(f, buf, sizeof(buf) - 1, &pos);
    filp_close(f, NULL);

    if (bytes_read <= 0) {
        printk(KERN_WARNING "[SDHEALTH] Failed to read SD card stats\n");
        return;
    }

    buf[bytes_read] = '\0';

    /*
     * /sys/block/mmcblk0/stat fields (only capturing what we need):
     *  1  reads completed       → current_read
     *  2  reads merged          → skipped (%*u)
     *  3  sectors read          → current_read_sectors
     *  4  time reading (ms)     → skipped (%*u)
     *  5  writes completed      → current_write
     *  6  writes merged         → skipped (%*u)
     *  7  sectors written       → current_write_sectors
     *
     * Note: %*u skips a field without storing it.
     * Using %*u instead of %*lu avoids kernel sscanf warnings.
     */
    if (sscanf(buf, "%lu %*u %lu %*u %lu %*u %lu",
               &current_read,
               &current_read_sectors,
               &current_write,
               &current_write_sectors) != 4)
    {
        printk(KERN_WARNING "[SDHEALTH] Failed to parse the relevant statistics\n");
        return;
    }

    if (initial_reading) {  // ensures logical starting values upon the first run
                            // function gets skipped after the first run
        READ_rate = 0;
        WRITE_rate = 0;
        READ_KBps = 0;
        WRITE_KBps = 0;

        PREV_READ_count = current_read;
        PREV_WRITE_count = current_write;

        READ_count = current_read;
        WRITE_count = current_write;

        PREV_READ_sectors = current_read_sectors;
        PREV_WRITE_sectors = current_write_sectors;

        READ_sectors = current_read_sectors;
        WRITE_sectors = current_write_sectors;

        initial_reading = false;
        return;
    }

    READ_rate  = current_read  - PREV_READ_count;   // calculation
    WRITE_rate = current_write - PREV_WRITE_count;  // calculation

    read_sector_delta  = current_read_sectors  - PREV_READ_sectors;    // calculation
    write_sector_delta = current_write_sectors - PREV_WRITE_sectors;   // calculation

    READ_KBps  = (read_sector_delta  * 512) / 1024;
    WRITE_KBps = (write_sector_delta * 512) / 1024;

    PREV_READ_count  = current_read;                // updates the previous snapshot
    PREV_WRITE_count = current_write;               // updates the previous snapshot

    PREV_READ_sectors  = current_read_sectors;      // updates the previous snapshot
    PREV_WRITE_sectors = current_write_sectors;     // updates the previous snapshot

    READ_count  = current_read;                     // updates current totals
    WRITE_count = current_write;                    // updates current totals

    READ_sectors  = current_read_sectors;           // updates current totals
    WRITE_sectors = current_write_sectors;          // updates current totals
}

/* ------------------------------------------------------------------ */
/* sd_work_handler                                                     */
/*                                                                     */
/* Runs in process context via the kernel workqueue. This is where    */
/* update_stats() is safely called from the timer, since filp_open()  */
/* requires process context and cannot be called directly from the    */
/* timer callback which runs in softirq (interrupt) context.          */
/* ------------------------------------------------------------------ */

static void sd_work_handler(struct work_struct *w)
{
    update_stats();
    check_anomaly(READ_count, WRITE_count);

    printk(KERN_INFO "[SDHEALTH] Timer updated the following statistics, Read rate: %lu and Write rate: %lu\n",
           READ_rate, WRITE_rate);
}

/* ------------------------------------------------------------------ */
/* sd_timer_callback                                                   */
/*                                                                     */
/* Runs in softirq (interrupt) context every 1 second. Cannot safely  */
/* call filp_open() directly, so it schedules sd_work_handler() via   */
/* the workqueue instead, then reschedules itself for the next tick.  */
/* ------------------------------------------------------------------ */

static void sd_timer_callback(struct timer_list *t)
{
    schedule_work(&sd_work);                            /* hand off to process context */
    mod_timer(&sd_timer, jiffies + interval_jiffies);  /* reschedule for next second  */
}

static ssize_t sdhealth_read(struct file *file, char __user *buffer,
                             size_t len, loff_t *offset)
{
    char msg[256];
    int msg_len;

    if (*offset > 0)
        return 0;

    /*
     * No update_stats() call here — the timer handles all stat updates
     * via sd_work_handler() every second. sdhealth_read() just serves
     * the most recently computed values, avoiding any race condition
     * between the timer and user-space reads.
     */

    printk(KERN_INFO "[SDHEALTH] Read statistics sent to user space\n");

    msg_len = snprintf(msg, sizeof(msg),
                       "SD Health Monitor\n"
                       "Reads          : %lu\n"
                       "Writes         : %lu\n"
                       "Read rate      : %lu/sec\n"
                       "Write rate     : %lu/sec\n"
                       "Read throughput: %lu KB/s\n"
                       "Write throughput: %lu KB/s\n"
                       "Read sectors   : %lu\n"
                       "Write sectors  : %lu\n",
                       READ_count, WRITE_count,
                       READ_rate, WRITE_rate,
                       READ_KBps, WRITE_KBps,
                       READ_sectors, WRITE_sectors);

    if (copy_to_user(buffer, msg, msg_len))
        return -EFAULT;

    *offset += msg_len;

    return msg_len;
}


static ssize_t sdhealth_write(struct file *file, const char __user *buffer,
                              size_t len, loff_t *offset)
{
    char kernel_buffer[128];

    if (len > sizeof(kernel_buffer) - 1)
        len = sizeof(kernel_buffer) - 1;

    if (copy_from_user(kernel_buffer, buffer, len))
        return -EFAULT;

    kernel_buffer[len] = '\0';

    printk(KERN_INFO "[SDHEALTH] Received from user space: %s\n", kernel_buffer);

    return len;
}


static struct file_operations fops = {
    .owner = THIS_MODULE,
    .open = sdhealth_open,
    .release = sdhealth_release,
    .read = sdhealth_read,
    .write = sdhealth_write,
};


static int __init sdhealth_init(void)
{
    int result;

    printk(KERN_INFO "[SDHEALTH] Initializing SD Health Monitor module\n");

    result = alloc_chrdev_region(&dev_number, 0, 1, DEVICE_NAME);
    if (result < 0) {
        printk(KERN_ALERT "[SDHEALTH] Failed to allocate device number\n");
        return result;
    }

    cdev_init(&sdhealth_cdev, &fops);
    sdhealth_cdev.owner = THIS_MODULE;

    result = cdev_add(&sdhealth_cdev, dev_number, 1);
    if (result < 0) {
        unregister_chrdev_region(dev_number, 1);
        printk(KERN_ALERT "[SDHEALTH] Failed to add character device\n");
        return result;
    }

    sdhealth_class = class_create(CLASS_NAME);
    if (IS_ERR(sdhealth_class)) {
        cdev_del(&sdhealth_cdev);
        unregister_chrdev_region(dev_number, 1);
        printk(KERN_ALERT "[SDHEALTH] Failed to create device class\n");
        return PTR_ERR(sdhealth_class);
    }

    sdhealth_device = device_create(sdhealth_class, NULL, dev_number, NULL, DEVICE_NAME);
    if (IS_ERR(sdhealth_device)) {
        class_destroy(sdhealth_class);
        cdev_del(&sdhealth_cdev);
        unregister_chrdev_region(dev_number, 1);
        printk(KERN_ALERT "[SDHEALTH] Failed to create /dev/sdhealth\n");
        return PTR_ERR(sdhealth_device);
    }

    printk(KERN_INFO "[SDHEALTH] Module loaded successfully\n");
    printk(KERN_INFO "[SDHEALTH] Device created at /dev/%s\n", DEVICE_NAME);

    initial_reading = true;

    INIT_WORK(&sd_work, sd_work_handler);              /* initialise the workqueue item  */
    timer_setup(&sd_timer, sd_timer_callback, 0);      /* set up the timer               */
    mod_timer(&sd_timer, jiffies + interval_jiffies);  /* schedule first timer tick      */

    return 0;
}


static void __exit sdhealth_exit(void)
{
    cancel_work_sync(&sd_work);         /* wait for any running work to finish before exit */
    timer_delete_sync(&sd_timer);       /* wait for any running timer callback to finish   */

    device_destroy(sdhealth_class, dev_number);
    class_destroy(sdhealth_class);
    cdev_del(&sdhealth_cdev);
    unregister_chrdev_region(dev_number, 1);

    printk(KERN_INFO "[SDHEALTH] Module unloaded successfully\n");
}


module_init(sdhealth_init);
module_exit(sdhealth_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("G V Timothy");
MODULE_DESCRIPTION("SD Card Health Monitoring Kernel Device Driver");
MODULE_VERSION("2.0");