/* Host-side smoke test of the screen state machine + reader logic,
   without touching fb.h/input.h (which need real Kindle hardware).
   Exercises app.c's transition logic and ui_*_handle() functions
   directly by hand-constructing ci_event_t values, so Phase 3's
   navigation logic gets verified before/independent of a live touch
   test on the device. */
#include "app.h"
#include "ui_library.h"
#include "ui_chapters.h"
#include "ui_reader.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    app_t app;
    memset(&app, 0, sizeof(app));
    app.screen = SCREEN_LIBRARY;
    library_scan(&app.lib, "tests/fixtures/library");
    progress_init(&app.prog);
    assert(app.lib.n_series == 2); /* Alpha, Beta (Empty excluded) */

    /* library -> chapters via tap (must land inside the actual first
       list row -- (20,20) is the list's top-left origin per
       ui_library_draw/ui_library_handle's widget_list_hit_test call;
       a tap at (0,0) is legitimately outside the list now that taps
       are hit-tested against real row geometry, not just "wherever
       swipe last left the cursor"). */
    ci_event_t tap = { EV_TAP, 30, 30 };
    ui_library_handle(&app, &tap);
    assert(app.screen == SCREEN_CHAPTERS);
    assert(app.sel_chapter == 0);
    printf("ok: library tap enters chapters\n");

    /* find whichever series index sorted first and confirm chapter nav */
    series_t *s = &app.lib.series[app.sel_series];
    int n = (int)s->n_chapters;
    assert(n >= 1);

    ci_event_t swipe_up = { EV_SWIPE_U, 0, 0 };
    for (int i = 0; i < n + 2; i++) ui_chapters_handle(&app, &swipe_up);
    assert(app.sel_chapter == n - 1); /* clamps at last chapter, doesn't overrun */
    printf("ok: chapter list swipe clamps at bounds\n");

    /* back from chapters returns to library */
    ci_event_t back = { EV_KEY_BACK, 0, 0 };
    ui_chapters_handle(&app, &back);
    assert(app.screen == SCREEN_LIBRARY);
    printf("ok: back from chapters returns to library\n");

    /* back from library exits the app */
    ui_library_handle(&app, &back);
    assert(app.screen == SCREEN_EXIT);
    printf("ok: back from library exits\n");

    library_free(&app.lib);
    progress_free(&app.prog);
    printf("ALL OK\n");
    return 0;
}
