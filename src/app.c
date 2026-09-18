#include "app.h"
#include "fb.h"
#include "input.h"
#include "ui_library.h"
#include "ui_chapters.h"
#include "ui_reader.h"
#include "log.h"
#include <string.h>

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
            default:
                break;
        }
    }

    return app->screen == SCREEN_EXIT;
}
