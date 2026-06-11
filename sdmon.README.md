Mental model:

SD Card Activity
        ↓
Linux Kernel Statistics
        ↓
Your Monitoring Module
        ↓
Processes / Calculates
        ↓
User Program Requests Data
        ↓
Statistics Displayed



Conceptually, the Raspberry PI actively keeps track of specific values by default such as read / write etc. The LKM simply fetches these data and displays for the user. 





fd = open("/dev/sdmon", O_RDONLY);
Linux internally creates a file descriptor (fd) and links it to a kernel "file object" and that file object contains pointers to driver functions

read(fd, buffer, 100) - this is outside the LKM, user tells the LKM to acquire the SD card read stats

sdmon_read() - this is inside the LKM which knows the exact read count

However, user memory and kernel memory cannot share memory so a 'bridge' is needed which is copy_to_user() 

   USER
    ↓↑
copy_to_user()
    ↓↑
  KERNEL


If the user program has this line,

char buffer[100];

read(fd, buffer, 100);

this creates a 'box' which is the buffer in user memory that can hold data


A simple analogy would be going to the vending machine to request a drink, you pass the vending a cup and the it fills up said cup.
The cup is the buffer...



copy_to_user(buffer, msg, size); 
This means to take the bytes in msg and physically copy them into the memory location pointed to by buffer

Parameters:
buffer -> user memory address (DESTINATION)
msg -> kernel string (SOURCE)
size -> number of bytes (HOW MUCH TO COPY)




In size = snprintf(msg, sizeof(msg), "Total Reads: %lu/n", READ_count);
msg receives the formatted text and snprintf() returns the number of characters it wrote

sizeof(msg) is basically a threshold to prevent buffer overflow

youre telling snprintf, you can write into msg but never exceed 100 bytes since we already declared char msg[100] which is 100 bytes



    User Program
         ↓
      read()
         ↓
    sdmon_read()
         ↓
    Get SD statistics
         ↓
      snprintf()
         ↓
    copy_to_user()
         ↓
     return size



KERN_INFO - 1st level
KERN_WARNING - 2nd level
KERN_ERR - 3rd level


Linux identifies devices using Major / Minor Numbers




sdmon_init()
      ↓
register_chrdev()  "/dev/sdmon"
      ↓
Linux knows about sdmon
      ↓
stores fops table

then...

User Program
      ↓
open("/dev/sdmon")
      ↓
Linux finds sdmon driver
      ↓
    read()
      ↓
   fops.read
      ↓
  sdmon_read()





dmesg will show "SD card monitoring module: Device Opened"

user will have smth like fd = open("/dev/sdmon", O_RDONLY); initially,
so the user will need to close the file session, close(fd);
.release is not closing the driver, it is closing one file session cus multiple users can open /dev/sdmon. So .release is a per-process cleanup


inode is the identity of the device, contains major/minor number, device identity and metadata about the file/device

file is this specific open session, contains the file position (offset), flags (read/write mode), pointer to the fops table, per-session data




The important data lives here on the Raspberry Pi
/sys/block/mmcblk0/stat

What is inside the block layer?
https://www.kernel.org/doc/html/v6.1/block/stat.html
