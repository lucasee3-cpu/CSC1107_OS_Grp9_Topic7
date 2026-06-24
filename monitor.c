/*
 * This program communicates with the /dev/sdhealth kernel module using
 * the read() and write() system calls. It presents a simple numbered
 * menu allowing the user to view SD card stats (choosing the poll
 * interval), check kernel logs, or exit cleanly.
 *
 * Usage: sudo ./monitor
 * Exit:  Choose option 3 from the menu, or press Ctrl+C
*/

#include <stdio.h>      
#include <fcntl.h>      
#include <unistd.h>     
#include <string.h>     
#include <strings.h>    /* strcasecmp() for case-insensitive "all" check */
#include <signal.h>     
#include <stdlib.h>     

/* ------------------------------------------------------------------ */
/* Constants                                                           */
/* ------------------------------------------------------------------ */

#define DEVICE_PATH      "/dev/sdhealth" /* path to the kernel device  */
#define BUFFER_SIZE      512             /* max bytes to read per poll */
#define DEFAULT_INTERVAL 2              /* default refresh rate (secs) */
#define MIN_INTERVAL     1              /* minimum refresh rate (secs) */
#define MAX_INTERVAL     60             /* maximum refresh rate (secs) */
#define CMD_REQUEST      "REQUEST_STATS" /* command sent to kernel     */
#define DMESG_LINES      15             /* number of dmesg lines shown */


// Global flag - set to 0 by the signal handler to stop the program
static volatile int running = 1;



// Sets running to 0 so loop exits cleanly
static void handle_sigint(int sig)
{
    (void)sig;
    running = 0;
    printf("\n[monitor] Ctrl+C received - returning to menu...\n");
}


// Clears terminal screen
static void clear_screen(void)
{
    printf("\033[2J\033[H");
}

// Prints the initial program banner when running the program
static void print_banner(void)
{
    printf("============================================\n");
    printf("   SD Card Health Monitor - User Space App \n");
    printf("   Device : %-30s\n", DEVICE_PATH);
    printf("============================================\n\n");
}


// Prints the menu options
static void print_menu(void)
{
    printf("  1. View SD card stats (live polling)\n");
    printf("  2. View kernel log (dmesg)\n");
    printf("  3. Exit\n");
    printf("\nEnter choice: ");
}

/* ------------------------------------------------------------------ */
/* do_single_read                                                      */
/*                                                                     */
/* Opens /dev/sdhealth, sends a write() command to the kernel, then  */
/* reads the stats back with read(). Returns the number of bytes      */
/* read, or -1 on error.                                              */
/*                                                                     */
/* ------------------------------------------------------------------ */

static int do_single_read(char *buffer, size_t buf_size)
{
    int fd;
    int bytes_written;
    int bytes_read;

    /* Open the device fresh each time to reset the offset */
    fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0)
    {
        perror("[monitor] ERROR: Failed to open " DEVICE_PATH);
        return -1;
    }

    /* WRITE: send command to kernel - visible in dmesg */
    bytes_written = write(fd, CMD_REQUEST, strlen(CMD_REQUEST));
    if (bytes_written < 0)
    {
        perror("[monitor] ERROR: write() failed");
        close(fd);
        return -1;
    }

    /* READ: receive stats string from kernel */
    bytes_read = read(fd, buffer, buf_size - 1);
    if (bytes_read < 0)
    {
        perror("[monitor] ERROR: read() failed");
        close(fd);
        return -1;
    }

    close(fd);

    if (bytes_read > 0)
        buffer[bytes_read] = '\0';  /* null-terminate for safe printing */

    return bytes_read;
}

/* ------------------------------------------------------------------ */
/* prompt_interval                                                     */
/*                                                                     */
/* Asks the user how often to poll, validates the value against        */
/* MIN_INTERVAL/MAX_INTERVAL, and returns the chosen interval.         */
/* Pressing Enter with no input keeps the default.                     */
/* ------------------------------------------------------------------ */

static int prompt_interval(void)
{
    char input[32];
    int  interval;

    printf("  How often should the stats refresh?\n");
    printf("  (Enter %d-%d seconds, or press Enter for default %d)\n",
           MIN_INTERVAL, MAX_INTERVAL, DEFAULT_INTERVAL);
    printf("  Interval : ");
    fflush(stdout);

    if (fgets(input, sizeof(input), stdin) == NULL)
        return DEFAULT_INTERVAL;

    input[strcspn(input, "\n")] = '\0';

    /* Blank input (just Enter) keeps the default */
    if (strlen(input) == 0)
        return DEFAULT_INTERVAL;

    interval = atoi(input);

    if (interval < MIN_INTERVAL || interval > MAX_INTERVAL)
    {
        printf("\n[monitor] Invalid value - using default %d sec\n",
               DEFAULT_INTERVAL);
        sleep(1);
        return DEFAULT_INTERVAL;
    }

    return interval;
}

/* ------------------------------------------------------------------ */
/* menu_view_stats                                                     */
/*                                                                     */
/* Option 1: Asks the user for a poll interval, then polls            */
/* /dev/sdhealth repeatedly at that interval, printing stats each     */
/* time. Press Ctrl+C to stop polling and return to the main menu.    */
/* ------------------------------------------------------------------ */

static void menu_view_stats(void)
{
    char buffer[BUFFER_SIZE];
    int  bytes_read;
    int  poll_count = 0;
    int  interval;

    /* Ask how often to poll before starting */
    clear_screen();
    printf("============================================\n");
    printf("  Live SD Card Stats - Setup                \n");
    printf("============================================\n\n");
    interval = prompt_interval();

    /* Reset running flag in case Ctrl+C was pressed before */
    running = 1;

    clear_screen();
    printf("============================================\n");
    printf("  Live SD Card Stats\n");
    printf("  Refresh: every %d second(s)               \n", interval);
    printf("============================================\n\n");

    while (running)
    {
        poll_count++;

        bytes_read = do_single_read(buffer, sizeof(buffer));

        if (bytes_read < 0)
        {
            printf("[monitor] ERROR: Could not read from device\n");
            break;
        }
        else if (bytes_read == 0)
        {
            printf("[monitor] WARNING: No data returned from kernel\n");
        }
        else
        {
            /* Move cursor up to overwrite previous stats for clean display */
                clear_screen();

            printf("  Poll #%-5d\n", poll_count);
            printf("--------------------------------------------\n");
            printf("%s", buffer);
            printf("--------------------------------------------\n");
            printf("  Sent : \"%s\" (%lu bytes)\n", CMD_REQUEST, strlen(CMD_REQUEST));
            printf("  Next update in %d second(s)...\n  Ctrl+C to go back\n", interval);
        }

        if (running)
            sleep(interval);
    }

    /* Restore running flag for the main menu loop */
    running = 1;

    printf("\n[monitor] Returning to main menu...\n");
    sleep(1);
}

/* ------------------------------------------------------------------ */
/* menu_view_kernel_log                                                */
/*                                                                     */
/* Option 2: Runs dmesg and filters for [SDHEALTH] messages so the   */
/* user can see what the kernel module has been logging.              */
/* ------------------------------------------------------------------ */

static void menu_view_kernel_log(void)
{
    char cmd[160];
    char input[32];
    int  num_lines;
    int  show_all_lines = 0;
    int  full_kernel_log = 0;

    clear_screen();
    printf("============================================\n");
    printf("  Kernel Log Viewer                          \n");
    printf("============================================\n\n");

    /* --- Scope choice: filtered (default) vs full kernel log --------- */
    printf("  View [1] SDHEALTH messages only, or [2] full kernel log?\n");
    printf("  [default: 1] : ");
    fflush(stdout);

    if (fgets(input, sizeof(input), stdin) != NULL)
    {
        input[strcspn(input, "\n")] = '\0';

        if (strcmp(input, "2") == 0)
        {
            full_kernel_log = 1;
        }
        /* anything else (including blank Enter, "1", or junk) stays
         * with the default filtered view */
    }

    /* --- Line count choice -------------------------------------------- */
    printf("\n  How many lines do you want to view?\n");
    printf("  (Enter a number, or type 'all' for the full log)\n");
    printf("  [default: %d] : ", DMESG_LINES);
    fflush(stdout);

    if (fgets(input, sizeof(input), stdin) == NULL)
    {
        num_lines = DMESG_LINES;
    }
    else
    {
        /* strip the trailing newline so strcmp works as expected */
        input[strcspn(input, "\n")] = '\0';

        if (strlen(input) == 0)
        {
            /* user just pressed Enter - use the default */
            num_lines = DMESG_LINES;
        }
        else if (strcasecmp(input, "all") == 0)
        {
            show_all_lines = 1;
        }
        else
        {
            num_lines = atoi(input);
            if (num_lines <= 0)
            {
                printf("\n[monitor] Invalid number - using default (%d)\n",
                       DMESG_LINES);
                num_lines = DMESG_LINES;
            }
        }
    }

    /*
     * Build the shell command from the two independent choices:
     *   - scope     : filtered to [SDHEALTH] only, or the full kernel log
     *   - line count: a specific number, or "all" (no tail filter)
     */
    if (full_kernel_log && show_all_lines)
    {
        snprintf(cmd, sizeof(cmd), "dmesg");
    }
    else if (full_kernel_log)
    {
        snprintf(cmd, sizeof(cmd), "dmesg | tail -%d", num_lines);
    }
    else if (show_all_lines)
    {
        snprintf(cmd, sizeof(cmd), "dmesg | grep '\\[SDHEALTH\\]'");
    }
    else
    {
        snprintf(cmd, sizeof(cmd),
                 "dmesg | grep '\\[SDHEALTH\\]' | tail -%d", num_lines);
    }

    printf("\nRunning: %s\n\n", cmd);

    if (system(cmd) == -1)
    {
        printf("[monitor] WARNING: Failed to execute dmesg command\n");
    }

    printf("\n[Press Enter to return to menu]");
    getchar();
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

int main(void)
{
    char input[32];
    int  choice;

    /* Register signal handler - Ctrl+C returns to menu, not hard exit */
    signal(SIGINT, handle_sigint);

    clear_screen();
    print_banner();
    printf("  Checking device availability...\n\n");

    /*
     * Test opens the device before showing the menu
     * Gives the user a clear error message early rather than
     * failing silently when they pick option 1.
     */
    int test_fd = open(DEVICE_PATH, O_RDWR);
    if (test_fd < 0)
    {
        perror("[monitor] ERROR: Cannot open " DEVICE_PATH);
        printf("[monitor] Hint: Is the kernel module loaded?\n");
        printf("[monitor] Try : sudo insmod sdhealth.ko\n");
        return 1;
    }
    close(test_fd);
    printf("  Device found at %s\n\n", DEVICE_PATH);

    /* ------------------------------------------------------------- */
    /* Main menu loop                                                 */
    /* ------------------------------------------------------------- */

    while (running)
    {
        clear_screen();
        print_banner();
        print_menu();

        if (fgets(input, sizeof(input), stdin) == NULL)
            break;

        choice = atoi(input);

        switch (choice)
        {
            case 1:
                menu_view_stats();
                break;

            case 2:
                menu_view_kernel_log();
                break;

            case 3:
                running = 0;
                break;

            default:
                printf("\n[monitor] Invalid choice. Please enter 1-3.\n");
                sleep(1);
                break;
        }
    }

    /* ------------------------------------------------------------- */
    /* Exit                                                           */
    /* ------------------------------------------------------------- */

    clear_screen();
    printf("============================================\n");
    printf("  SD Card Health Monitor - Goodbye!         \n");
    printf("  Check full kernel log: sudo dmesg | grep -i SDHEALTH\n");
    printf("============================================\n");

    return 0;
}
