#include "app.h"
#include "fb.h"
#include "input.h"
#include "ui_library.h"
#include "ui_chapters.h"
#include "ui_reader.h"
#include "ui_repo.h"
#include "widget.h"
#include "log.h"
#include <string.h>

/* Top-left corner tap zone that quits from any screen, regardless of
   what the current screen's own handler does with taps. Exists
   because a screen-specific "back" chain can get the user stuck
   (e.g. reader -> chapters -> library -> back does nothing extra),
   and because the hardware power/back key isn't present on every
   Kindle input layout -- see input.c's key_fd fallback. Drawn as a
   small marked box so it's discoverable, not a hidden gesture. */
#define QUIT_ZONE_PX 70

void app_init(app_t *app, const char *library_root, const char *progress_path) {
    memset(app, 0, sizeof(*app));
    app->screen = SCREEN_LIBRARY;
    app->sel_series = 0;
    app->sel_chapter = 0;
    app->page = 0;
    app->zoom = ZOOM_FIT_PAGE;
    app->running = 1;

    library_scan(&app->lib, library_root);
    progress_init(&app->prog);
    progress_load(&app->prog, progress_path);

    log_msg("app_init: %zu series found under %s", app->lib.n_series, library_root);
}

void app_shutdown(app_t *app) {
    if (app->open_archive) {
        archive_close(&app->cur_archive);
        app->open_archive = 0;
    }
    library_free(&app->lib);
    progress_free(&app->prog);
}

int app_step(app_t *app) {
    if (app->screen == SCREEN_EXIT) {
        app->running = 0;
        return 1;
    }

    ci_event_t ev;
    int got = input_poll(&ev, 500);

    if (got) {
        if (ev.type == EV_QUIT) {
            app->screen = SCREEN_EXIT;
            app->running = 0;
            return 1;
        }

        /* Quit-zone tap check happens before screen dispatch so it
           always wins, even on a screen whose own handler would
           otherwise treat that tap as "advance"/"open". */
        if (ev.type == EV_TAP && ev.x <= QUIT_ZONE_PX && ev.y <= QUIT_ZONE_PX) {
            app->screen = SCREEN_EXIT;
            app->running = 0;
            log_msg("app_step: quit via corner tap zone");
            return 1;
        }

        switch (app->screen) {
            case SCREEN_LIBRARY:
                ui_library_handle(app, &ev);
                break;
            case SCREEN_CHAPTERS:
                ui_chapters_handle(app, &ev);
                break;
            case SCREEN_READER:
                ui_reader_handle(app, &ev);
                break;
            case SCREEN_REPO_LIST:
                ui_repo_list_handle(app, &ev);
                break;
            case SCREEN_REPO_ADD:
                ui_repo_add_handle(app, &ev);
                break;
            case SCREEN_EXT_LIST:
                ui_ext_list_handle(app, &ev);
                break;
            default:
                break;
        }

        /* Redraw only after an event actually changed something --
           e-ink has no frame rate, drawing when nothing changed just
           burns battery and adds ghosting for no benefit. */
        switch (app->screen) {
            case SCREEN_LIBRARY:
                ui_library_draw(app);
                break;
            case SCREEN_CHAPTERS:
                ui_chapters_draw(app);
                break;
            case SCREEN_READER:
                ui_reader_draw(app);
                break;
            case SCREEN_REPO_LIST:
                ui_repo_list_draw(app);
                break;
            case SCREEN_REPO_ADD:
                ui_repo_add_draw(app);
                break;
            case SCREEN_EXT_LIST:
                ui_ext_list_draw(app);
                break;
            default:
                break;
        }
        if (app->screen != SCREEN_EXIT) app_draw_quit_zone();
    }

    return app->screen == SCREEN_EXIT;
}

void app_draw_quit_zone(void) {
    widget_button_t q = { "X", 4, 4, QUIT_ZONE_PX - 8, QUIT_ZONE_PX - 8 };
    widget_draw_button(&q, 0);
    fb_refresh_partial(q.x, q.y, q.w, q.h);
}
