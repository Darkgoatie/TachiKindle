#include "log.h"
#include <stdio.h>
#include <stdarg.h>
#include <time.h>

static FILE *logf = NULL;

int log_init(const char *path) {
    if (logf) fclose(logf);
    logf = fopen(path, "a");
    return logf ? 0 : -1;
}

void log_close(void) {
    if (logf) { fclose(logf); logf = NULL; }
}

void log_msg(const char *fmt, ...) {
    if (!logf) return;
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    fprintf(logf, "[%02d:%02d:%02d] ", tmv.tm_hour, tmv.tm_min, tmv.tm_sec);

    va_list ap;
    va_start(ap, fmt);
    vfprintf(logf, fmt, ap);
    va_end(ap);

    fprintf(logf, "\n");
    fflush(logf);
}
