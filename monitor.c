/*
 *  monitor.c — User-Space Monitor for SD Card Health Monitoring Driver
 *  CSC1107 Group 9 — Project 7
 *  Automation & Testing: Member 5 (Faris)
 *
 *  ---------------------------------------------------------------------------
 *  SKELETON VERSION — for testing the automation pipeline (Makefile, run.sh,
 *  cleanup.sh).  This minimal program:
 *
 *    1. Opens  /dev/sdhealth  (the character device created by the LKM).
 *    2. Sends a  write()  command to the kernel module.
 *    3. Reads  the statistics string back from the kernel.
 *    4. Prints  the stats to stdout.
 *
 *  Once Members 1–4 merge their work, this skeleton can be replaced with
 *  the full-featured menu-driven monitor from the kernel-user-comms branch.
 *  ---------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#define DEVICE_PATH     "/dev/sdhealth"
#define BUFFER_SIZE      4096
#define CMD_REQUEST      "REQUEST_STATS"

int main(void)
{
    int  fd;
    char buffer[BUFFER_SIZE];
    int  bytes_written;
    int  bytes_read;

    /* ---- open the device ------------------------------------------------ */
    fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0)
    {
        perror("[monitor] ERROR: Cannot open " DEVICE_PATH);
        fprintf(stderr,
                "[monitor] HINT: Is the kernel module loaded?\n"
                "[monitor] Try:  sudo insmod sdhealth.ko\n");
        return EXIT_FAILURE;
    }

    printf("[monitor] Connected to %s\n", DEVICE_PATH);

    /* ---- send command to the kernel module ------------------------------ */
    bytes_written = write(fd, CMD_REQUEST, strlen(CMD_REQUEST));
    if (bytes_written < 0)
    {
        perror("[monitor] ERROR: write() failed");
        close(fd);
        return EXIT_FAILURE;
    }
    printf("[monitor] Sent command: \"%s\" (%d bytes)\n",
           CMD_REQUEST, bytes_written);

    /* ---- read statistics back from the kernel --------------------------- */
    bytes_read = read(fd, buffer, sizeof(buffer) - 1);
    if (bytes_read < 0)
    {
        perror("[monitor] ERROR: read() failed");
        close(fd);
        return EXIT_FAILURE;
    }

    buffer[bytes_read] = '\0';   /* null-terminate for safe printing */

    /* ---- display stats -------------------------------------------------- */
    printf("\n============================================\n");
    printf("  SD Card Health Monitor — Statistics\n");
    printf("============================================\n");
    printf("%s", buffer);
    printf("============================================\n");

    /* ---- cleanup -------------------------------------------------------- */
    close(fd);
    return EXIT_SUCCESS;
}
