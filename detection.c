#include <linux/kernel.h>
#include <linux/timekeeping.h>
#include <linux/string.h>

#include "detection.h"

#define WRITE_THRESHOLD 50000
#define READ_THRESHOLD 100000
#define WEAR_LIMIT 200000

static char event_log[MAX_LOGS][128];
static int log_index = 0;

static int write_alert_active = 0;
static int read_alert_active = 0;
static int wear_alert_active = 0;

static void save_event(const char *msg);

static void save_event(const char *msg)
{
    snprintf(
        event_log[log_index],
        sizeof(event_log[log_index]),
        "%s",
        msg
    );

    log_index++;

    if (log_index >= MAX_LOGS)
        log_index = 0;
}

static void log_with_timestamp(const char *message)
{
    struct timespec64 ts;

    char final_msg[128];

    ktime_get_real_ts64(&ts);

    snprintf(
        final_msg,
        sizeof(final_msg),
        "[%lld] %s",
        (long long)ts.tv_sec,
        message
    );

    save_event(final_msg);

    printk(
        KERN_WARNING
        "[SDHEALTH] %s\n",
        final_msg
    );
}

void check_anomaly(
    unsigned long reads,
    unsigned long writes
)
{
    if (writes > WRITE_THRESHOLD)
    {
        if (!write_alert_active)
        {
            log_with_timestamp(
                "WARNING: Excessive write activity detected"
            );

            write_alert_active = 1;
        }
    }
    else
    {
        write_alert_active = 0;
    }

    if (reads > READ_THRESHOLD)
    {
        if (!read_alert_active)
        {
            log_with_timestamp(
                "WARNING: Excessive read activity detected"
            );

            read_alert_active = 1;
        }
    }
    else
    {
        read_alert_active = 0;
    }

    if (writes > WEAR_LIMIT)
    {
        if (!wear_alert_active)
        {
            log_with_timestamp(
                "ALERT: Potential SD card wear detected"
            );

            wear_alert_active = 1;
        }
    }
    else
    {
        wear_alert_active = 0;
    }

    if (reads == 0 && writes > 1000)
    {
        log_with_timestamp(
            "ERROR: Possible statistics corruption detected"
        );
    }
}

int get_log_count(void)
{
    return log_index;
}

const char *get_log_entry(int index)
{
    if (index < 0 || index >= MAX_LOGS)
        return NULL;

    return event_log[index];
}