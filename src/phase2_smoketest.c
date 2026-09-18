/* Phase 2 device-layer smoke test: draws a widget list on the real
   framebuffer, waits for one touch event, reports what it classified,
   then exits. Not part of the final app -- verifies fb.c/input.c/widget.c
   actually work together on hardware before Phase 3 builds screens on
   top of them. */
#include "fb.h"
#include "input.h"
#include "widget.h"
#include "log.h"
#include <stdio.h>

int main(void) {
    log_init("/mnt/us/tachikindle/smoketest.log");
    log_msg("phase2 smoketest starting");

    if (fb_init() != 0) {
        fprintf(stderr, "fb_init failed\n");
        return 1;
    }
    if (input_init() != 0) {
        fprintf(stderr, "input_init failed (no touch device found)\n");
        fb_shutdown();
        return 1;
    }

    fb_clear();

    const char *labels[] = {
        "Berserk",
        "Blame!",
        "Vagabond",
        "Vinland Saga",
    };
    widget_draw_list(labels, 4, 1, 40, 40, fb_width() - 80, 400);
    widget_toast("Tap anywhere -- waiting for touch (10s)");
    fb_refresh_full();

    ci_event_t ev;
    int got = input_poll(&ev, 10000);

    fb_clear();
    if (got) {
        const char *names[] = {
            "NONE", "TAP", "SWIPE_L", "SWIPE_R", "SWIPE_U", "SWIPE_D", "BACK", "QUIT"
        };
        char msg[128];
        snprintf(msg, sizeof(msg), "Got: %s @ (%d,%d)", names[ev.type], ev.x, ev.y);
        widget_toast(msg);
        log_msg("event: type=%d x=%d y=%d", ev.type, ev.x, ev.y);
    } else {
        widget_toast("Timed out waiting for touch");
        log_msg("timed out waiting for touch");
    }
    fb_refresh_full();

    input_shutdown();
    fb_shutdown();
    log_msg("phase2 smoketest done");
    log_close();
    return 0;
}
