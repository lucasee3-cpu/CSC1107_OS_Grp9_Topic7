// sdhealth.c
// Member 1: Kernel Device Driver Lead
// Purpose: Core Linux kernel module infrastructure for SD Card Health Monitor

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>

#define DEVICE_NAME "sdhealth"
#define CLASS_NAME  "sdhealth_class"

static dev_t dev_number;
static struct cdev sdhealth_cdev;
static struct class *sdhealth_class;
static struct device *sdhealth_device;

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

// Placeholder read/write functions.
// Member 3 can expand these later.
static ssize_t sdhealth_read(struct file *file, char __user *buffer,
                             size_t len, loff_t *offset)
{
    char msg[] = "SD Health Monitor active\n";
    int msg_len = strlen(msg);

    if (*offset >= msg_len)
        return 0;

    if (copy_to_user(buffer, msg, msg_len))
        return -EFAULT;

    *offset += msg_len;
    printk(KERN_INFO "[SDHEALTH] Read operation completed\n");

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
    device_destroy(sdhealth_class, dev_number);
    class_destroy(sdhealth_class);
    cdev_del(&sdhealth_cdev);
    unregister_chrdev_region(dev_number, 1);

    printk(KERN_INFO "[SDHEALTH] Module unloaded successfully\n");
}

module_init(sdhealth_init);
module_exit(sdhealth_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Tim");
MODULE_DESCRIPTION("SD Card Health Monitoring Kernel Device Driver");
MODULE_VERSION("1.0");