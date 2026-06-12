#include <linux/module.h> // Linux kernel headers
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/timer.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/string.h>

static unsigned long READ_count = 0;  // initialize read count to 0 where read count is only > 0
static unsigned long WRITE_count = 0; // initialize write count to 0 where write count is only > 0
static int major;


static void update_stats(void){       // retrieve SD statistics from the kernel and store them in variables
    struct file *f;
    char buf[256];                    // temporary storage for raw text
    loff_t pos = 0;                   // file position (offset), means to start reading from the beginning of the file
                                      // set to 0 because each update should read fresh from the start

    f = filp_open("/sys/block/mmcblk0/stat", O_RDONLY, 0);  // this function is to open this sysfs file in the kernel space
    if (IS_ERR(f)){                   // if there is an error, stop the function immediately and do not crash the kernel
        return;
    }

    kernel_read(f, buf, sizeof(buf)-1, &pos);  // read the contents of the file into buf, buf should have the raw SD statistics text
    filp_close(f, NULL);              // release the file once done

    sscanf(buf, "%lu %*lu %*lu %*lu %lu", &READ_count, &WRITE_count); // give me the first and fifth field
    // %lu - reads this number
    // %*lu - skip number

}





static ssize_t sdmon_read(     // this is the read handler, Linux will call this function when the user program does
    struct file *file,         // read(fd, buffer, 100) because Linux knows what is read() by default
    char __user *buffer,       // this is a reference to user memory, a memory space in the user program where the kernel is allowed to write data
    size_t len,                // this is how many bytes the user asked for
    loff_t *offset             // current file position
){  
    char msg[128];             // temorary string stored in kernel memory
    int size;                  // variable to store message length

    update_stats();

    size = snprintf(msg, sizeof(msg), "Total reads: %lu\nTotal writes: %lu\n", READ_count, WRITE_count);

        // snprintf() is a function to format a text into a string buffer safely
        // the parameter msg is the destination buffer so youre telling Linux to put the final text into the 'msg' parameter
        // sizeof(msg) tells snprintf() DO NOT write any more than this many bytes into 'msg'
        // because we already set msg[100] earlier which is 100 bytes

    copy_to_user(buffer, msg, size); // copy_to_user() is an official built-in Linux kernel function provided by the API

    return size; // read() requires a return value so the user program knows exactly how many bytes were actually placed in the buffer
}


static int sdmon_open(struct inode *inode, struct file *file);
static int sdmon_release(struct inode *inode, struct file *file);


static struct file_operations fops = {
    .open = sdmon_open, // when user keys in open(), Linux finds the fops table and finds .open and calls sdmon_open()
    .read = sdmon_read, // literally means for read requests, call sdmon_read, equivalent to saying, fops.read = sdmon_read;
    .release = sdmon_release,
};




static int sdmon_open(  // open handler
    struct inode *inode,
    struct file *file
){
    printk(KERN_INFO "SD card monitoring module: Device Opened\n");
    return 0;
}

static int sdmon_release(  // close handler
    struct inode *inode,   // identity of the device
    struct file *file
){
    printk(KERN_INFO "SD card monitoring module: Device Closed\n");
    return 0;
}




static int __init sdmon_init(void){ 

    major = register_chrdev(0, "sdmon", &fops); // "sdmon" creates this pathing /dev/sdmon, 0 tells Linux to choose a free major number, &fops will be used when interacting with the device
        if (major < 0){
            printk(KERN_ERR "Failed to register sdmon\n");
            return major;
        }
    printk(KERN_INFO "SD card monitoring module: Registered with Major %d\n", major);


    printk(KERN_INFO "SD card monitoring module: Loaded Successfully\n");

    READ_count = 0;
    WRITE_count = 0;

    printk(KERN_INFO "SD card monitoring module: Read/Write counters set to 0\n");

    return 0;
}

static void __exit sdmon_exit(void){
    printk(KERN_INFO "SD card monitoring module: Unloaded Successfully\n");
    printk(KERN_INFO "SD card monitoring module: Final read count: %lu\n", READ_count);
    printk(KERN_INFO "SD card monitoring module: Final write count: %lu\n", WRITE_count);
    unregister_chrdev(major, "sdmon");
}

/*
static - internal use only
int - returns a 1(fail) or 0(success)
void - returns nothing
__init - kernel-level command (function only runs during module initialization)
__exit - kernel-level command (function only runs during module unloading)
*/ 




module_init(sdmon_init); // module_init is Linux kernel macro (startup function)
module_exit(sdmon_exit); // module_exit is Linux kernel macro (shutdown function)

/*
sdmon_init(void) - function takes in no parameters
sdmon_exit(void) - function takes in no parameters
*/

MODULE_LICENSE("GPL");
/*
MODULE_LICENSE("GPL") is important as it tells the Kernel that this module/code
is compatible with the Linux Kernel license rules. Without it, the module loads
with a warning. Linux will mark the kernel as "tainted" and impose restrictions.
*/                        
MODULE_AUTHOR("Reggie");
MODULE_DESCRIPTION("very good very nice");