#ifndef DETECTION_H
#define DETECTION_H
#define MAX_LOGS 50

void check_anomaly(
    unsigned long reads,
    unsigned long writes
);

int get_log_count(void);

const char *get_log_entry(int index);

#endif