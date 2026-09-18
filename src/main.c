#include "app.h"
#include "fb.h"
#include "input.h"
#include "log.h"
#include "ui_library.h"
#include "signals.h"

int main(void) {
    log_init("/mnt/us/tachikindle/tachikindle.log");
    log_msg("starting");
    signals_install();

    if (fb_init() != 0) {
        log_msg("fb_init failed");
        return 1;
    }
    if (input_init() != 0) {
        log_msg("input_init failed (no touch device found)");
        fb_shutdown();
        return 1;
    }

    app_t app;
    app_init(&app, "/mnt/us/tachikindle/library", "/mnt/us/tachikindle/progress.tsv");

    /* Draw the initial screen once before the event loop starts polling,
       otherwise the first frame is a blank/uninitialized framebuffer. */
    ui_library_draw(&app);

    while (app.running) {
        app_step(&app);
    }

    app_shutdown(&app);
    input_shutdown();
    fb_shutdown();
    log_msg("exiting cleanly");
    log_close();
    return 0;
}
