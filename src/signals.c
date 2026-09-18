#include "signals.h"
#include "fb.h"
#include "log.h"
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

/* Async-signal-safe as far as practical: log_msg uses stdio which isn't
   strictly signal-safe, but on a single-threaded app about to die this
   is the pragmatic tradeoff every small embedded tool makes -- the
   alternative (write() with hand-built strings) buys safety we don't
   need here at a real cost to debuggability of the one log a user could
   actually send us. */
static void handle_fatal(int sig) {
    log_msg("fatal signal %d received, shutting down framebuffer", sig);
    fb_shutdown();
    log_close();
    signal(sig, SIG_DFL);
    raise(sig);
}

void signals_install(void) {
    signal(SIGSEGV, handle_fatal);
    signal(SIGBUS, handle_fatal);
    signal(SIGTERM, handle_fatal);
}
