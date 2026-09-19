#include "ui_chapters.h"
#include "ui_reader.h"
#include "fb.h"
#include "widget.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void ui_chapters_draw(app_t *app) {
    fb_clear();

    series_t *s = &app->lib.series[app->sel_series];
    if (s->n_chapters == 0) {
        widget_toast("No chapters in this series");
        fb_refresh_full();
        return;
    }

    char **labels = malloc(sizeof(char *) * s->n_chapters);
    for (size_t i = 0; i < s->n_chapters; i++) {
        int page = progress_get_page(&app->prog, s->name, s->chapters[i].name);
        char buf[256];
        /* small affordance so a library actually feels read, not just
           browsed: a dot for in-progress, a check for done. "done" here
           just means "has any saved page" -- a real completion signal
           needs total-page-count tracking, which ui_reader doesn't
           persist yet; tracked as a follow-up alongside thumbnails. */
        const char *marker = page > 0 ? "* " : "  ";
        snprintf(buf, sizeof(buf), "%s%s", marker, s->chapters[i].name);
        labels[i] = strdup(buf);
    }

    widget_draw_list((const char **)labels, (int)s->n_chapters, app->sel_chapter,
                      20, 20, fb_width() - 40, fb_height() - 40);

    for (size_t i = 0; i < s->n_chapters; i++) free(labels[i]);
    free(labels);
    fb_refresh_full();
}

void ui_chapters_handle(app_t *app, const ci_event_t *ev) {
    series_t *s = &app->lib.series[app->sel_series];
    if (s->n_chapters == 0) {
        if (ev->type == EV_KEY_BACK || ev->type == EV_TAP) {
            app->screen = SCREEN_LIBRARY;
        }
        return;
    }

    switch (ev->type) {
        case EV_SWIPE_U:
            if (app->sel_chapter < (int)s->n_chapters - 1) app->sel_chapter++;
            break;
        case EV_SWIPE_D:
            if (app->sel_chapter > 0) app->sel_chapter--;
            break;
        case EV_TAP: {
            int hit = widget_list_hit_test(ev->x, ev->y, (int)s->n_chapters,
                                            app->sel_chapter, 20, 20, fb_width() - 40, fb_height() - 40);
            if (hit < 0) break;
            app->sel_chapter = hit;
            app->screen = SCREEN_READER;
            ui_reader_enter(app);
            break;
        }
        case EV_KEY_BACK:
            app->screen = SCREEN_LIBRARY;
            break;
        default:
            break;
    }
}
