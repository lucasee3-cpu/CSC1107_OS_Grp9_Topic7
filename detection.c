#include <linux/kernel.h>
#include <linux/timekeeping.h>
#include <linux/string.h>

#include "detection.h"

#define WRITE_THRESHOLD 1000
#define READ_THRESHOLD 5000

#define MAX_LOGS 50
#define LOG_SIZE 128

static char event_log[MAX_LOGS][LOG_SIZE];
static int log_index = 0;

// Prevent warning spam
static int write_alert_sent = 0;
static int read_alert_sent = 0;

// Forward declaration
static void save_event(const char *msg);

// Store an event into a circular log buffer.
static void save_event(const char *msg)
{
    snprintf(
        event_log[log_index],
        LOG_SIZE,
        "%s",
        msg
    );

    log_index++;

    if (log_index >= MAX_LOGS)
        log_index = 0;
}

//Print all stored logs. 
void print_event_logs(void)
{
    int i;

    printk(KERN_INFO
           "[SDHEALTH] ===== Event Log History =====\n");

    for (i = 0; i < MAX_LOGS; i++)
    {
        if (strlen(event_log[i]) > 0)
        {
            printk(KERN_INFO
                   "[SDHEALTH LOG] %s\n",
                   event_log[i]);
        }
    }

    printk(KERN_INFO
           "[SDHEALTH] ============================\n");
}

// Main anomaly detection routine
void check_anomaly(
    unsigned long reads,
    unsigned long writes
)
{
    struct timespec64 ts;
    char log_msg[LOG_SIZE];

    ktime_get_real_ts64(&ts);

    printk(KERN_INFO,
           "[SDHEALTH] check_anomaly(): reads=%lu writes=%lu\n",
           reads,
           writes);

    // Excessive write activity detection
    if (writes > WRITE_THRESHOLD)
    {
        if (!write_alert_sent)
        {
            snprintf(
                log_msg,
                sizeof(log_msg),
                "[%lld] WARNING: Excessive write activity detected (%lu writes)",
                (long long)ts.tv_sec,
                writes
            );

            save_event(log_msg);

            printk(KERN_WARNING,
                   "[SDHEALTH] %s\n",
                   log_msg);

            write_alert_sent = 1;
        }
    }
    else
    {
        write_alert_sent = 0;
    }

    // Excessive read activity detection
    if (reads > READ_THRESHOLD)
    {
        if (!read_alert_sent)
        {
            snprintf(
                log_msg,
                sizeof(log_msg),
                "[%lld] WARNING: Excessive read activity detected (%lu reads)",
                (long long)ts.tv_sec,
                reads
            );

            save_event(log_msg);

            printk(KERN_WARNING,
                   "[SDHEALTH] %s\n",
                   log_msg);

            read_alert_sent = 1;
        }
    }
    else
    {
        read_alert_sent = 0;
    }

    // Example health check.
    if (writes > (WRITE_THRESHOLD * 10))
    {
        snprintf(
            log_msg,
            sizeof(log_msg),
            "[%lld] CRITICAL: Possible SD wear detected (%lu writes)",
            (long long)ts.tv_sec,
            writes
        );

        save_event(log_msg);

        printk(KERN_ERR,
               "[SDHEALTH] %s\n",
               log_msg);
    }
}