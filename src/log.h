#ifndef CI_LOG_H
#define CI_LOG_H

/* Opens the on-device log file for appending; call once at startup.
   Safe to call again to reopen after a path change. */
int log_init(const char *path);
void log_close(void);
void log_msg(const char *fmt, ...);

#endif
