// Creates the Linux kernel module infrastructure for the SD Card Health Monitoring System.
// This module creates /dev/sdhealth and allows user programs to communicate with the kernel driver through read() and write().

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include "detection.h"

#define DEVICE_NAME "sdhealth"
#define CLASS_NAME  "sdhealth_class"

static dev_t dev_number;                 // stores major and minor device numbers
static struct cdev sdhealth_cdev;        // character device structure
static struct class *sdhealth_class;     // device class shown under /sys/class
static struct device *sdhealth_device;   // represents /dev/sdhealth

static unsigned long READ_count = 0;     // stores SD card read operations
static unsigned long WRITE_count = 0;    // stores SD card write operations

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

    f = filp_open("/sys/block/mmcblk0/stat", O_RDONLY, 0);
    if (IS_ERR(f))
    {
        printk(KERN_ERR,
            "[SDHEALTH] ERROR: Failed to open /sys/block/mmcblk0/stat\n");
        return;
    }

    bytes_read = kernel_read(f, buf, sizeof(buf) - 1, &pos);
    filp_close(f, NULL);

    if (bytes_read <= 0)
    {
        printk(KERN_ERR,
            "[SDHEALTH] ERROR: Failed to read SD card stats\n");
        return;
    }

    buf[bytes_read] = '\0';

    sscanf(buf, "%lu %*u %*u %*u %lu", &READ_count, &WRITE_count);
}

static ssize_t sdhealth_read(struct file *file, char __user *buffer,
                             size_t len, loff_t *offset)
{
    char msg[128];
    int msg_len;

    if (*offset > 0)
        return 0;

    update_stats();

    check_anomaly(
    READ_count,
    WRITE_count
    );

    msg_len = snprintf(
        msg,
        sizeof(msg),
        "SD Health Monitor\n"
        "Total reads: %lu\n"
        "Total writes: %lu\n",
        READ_count,
        WRITE_count
    );

    /* Prevent copying more bytes than the user requested */
    if (msg_len > len)
        msg_len = len;

    if (copy_to_user(buffer, msg, msg_len))
        return -EFAULT;

    *offset += msg_len;

    printk(KERN_INFO "[SDHEALTH] Read statistics sent to user space\n");

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

    return 0;
}

static void __exit sdhealth_exit(void)
{
    print_event_logs();
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