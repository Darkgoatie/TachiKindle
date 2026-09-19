#include "ui_library.h"
#include "ui_chapters.h"
#include "ui_repo.h"
#include "fb.h"
#include "widget.h"
#include <stdlib.h>

#define REPO_ZONE_PX 90

/* v1 renders the library as a scrollable text list of series names.
   The plan's cover-thumbnail grid is deferred: thumbnail generation
   needs archive_read_page + image_decode + a persistent cache dir,
   which only pays for itself once there's a reader to open into --
   wiring it now would be speculative. Tracked as a follow-up. */

void ui_library_draw(app_t *app) {
    fb_clear();

    if (app->lib.n_series == 0) {
        widget_toast("No comics found in /mnt/us/tachikindle/library");
    }

    widget_button_t repo_btn = {
        .label = "Repos", .x = fb_width() - REPO_ZONE_PX - 4, .y = 4,
        .w = REPO_ZONE_PX, .h = REPO_ZONE_PX - 20,
    };
    widget_draw_button(&repo_btn, 0);

    if (app->lib.n_series == 0) {
        fb_refresh_full();
        return;
    }

    const char **labels = malloc(sizeof(char *) * app->lib.n_series);
    for (size_t i = 0; i < app->lib.n_series; i++) {
        labels[i] = app->lib.series[i].name;
    }

    widget_draw_list(labels, (int)app->lib.n_series, app->sel_series,
                      20, 20, fb_width() - 40, fb_height() - 40);
    free(labels);
    fb_refresh_full();
}

void ui_library_handle(app_t *app, const ci_event_t *ev) {
    if (ev->type == EV_TAP && ev->x >= fb_width() - REPO_ZONE_PX - 4 && ev->y <= REPO_ZONE_PX) {
        ui_repo_enter_list(app);
        app->screen = SCREEN_REPO_LIST;
        return;
    }

    if (app->lib.n_series == 0) return;

    switch (ev->type) {
        case EV_SWIPE_U:
            if (app->sel_series < (int)app->lib.n_series - 1) app->sel_series++;
            break;
        case EV_SWIPE_D:
            if (app->sel_series > 0) app->sel_series--;
            break;
        case EV_TAP:
            app->sel_chapter = 0;
            app->screen = SCREEN_CHAPTERS;
            break;
        case EV_KEY_BACK:
            app->screen = SCREEN_EXIT;
            break;
        default:
            break;
    }
}
