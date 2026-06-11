# SD Card Health Monitoring System
## Project Overview

This project implements a Linux Kernel Module (LKM) that monitors SD card activity on a Raspberry Pi. The module provides a character device interface that allows user-space applications to retrieve SD card read and write statistics through /dev/sdhealth.

## Instructions
To build
```
make
```
Load Module
```
sudo insmod sdhealth.ko
```
Verify Device Creation
```
ls -l /dev/sdhealth
```
Read SD Card Statistics
```
sudo cat /dev/sdhealth
```
Example Output
```
SD Health Monitor
Total reads: 11860
Total writes: 1101
```
Unload Module
```
sudo rmmod sdhealth
```
