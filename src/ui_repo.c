#include "ui_repo.h"
#include "repo_store.h"
#include "fb.h"
#include "widget.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define REPOS_JSON_PATH "/mnt/us/tachikindle/repos.json"
#define EXT_DIR "/mnt/us/tachikindle/extensions/"
#define DEFAULT_REPO_URL "https://raw.githubusercontent.com/darkgoatie/tachikindle-sources/main"

static repo_store_t g_store;

void ui_repo_enter_list(app_t *app) {
    repo_store_load(&g_store, REPOS_JSON_PATH);
    /* First run (no repos.json yet, or it exists but is empty):
       seed the user's own default repo so it's selectable without
       having to type the URL in by hand every fresh install. */
    if (g_store.count == 0) {
        repo_store_add(&g_store, DEFAULT_REPO_URL);
        repo_store_save(&g_store, REPOS_JSON_PATH);
    }
    app->n_repos = g_store.count;
    for (int i = 0; i < g_store.count && i < APP_MAX_REPOS; i++) {
        snprintf(app->repo_urls[i], sizeof(app->repo_urls[i]), "%s", g_store.urls[i]);
    }
    if (app->sel_repo >= app->n_repos) app->sel_repo = app->n_repos > 0 ? app->n_repos - 1 : 0;
    app->download_status[0] = '\0';
}

/* Row count is n_repos + 1: the extra trailing row is always
   "+ Add Repo", selecting/tapping it enters SCREEN_REPO_ADD instead
   of opening a repo -- kept as a synthetic last row rather than a
   separate always-visible button so the same widget_draw_list
   scroll/selection logic used everywhere else just works here too. */
void ui_repo_list_draw(app_t *app) {
    fb_clear();

    int total_rows = app->n_repos + 1;
    char **labels = malloc(sizeof(char *) * total_rows);
    for (int i = 0; i < app->n_repos; i++) {
        labels[i] = strdup(app->repo_urls[i]);
    }
    labels[app->n_repos] = strdup("+ Add Repo");

    widget_draw_list((const char **)labels, total_rows, app->sel_repo,
                      20, 20, fb_width() - 40, fb_height() - 100);

    if (app->download_status[0]) {
        widget_toast(app->download_status);
    }

    for (int i = 0; i < total_rows; i++) free(labels[i]);
    free(labels);
    fb_refresh_full();
}

void ui_repo_list_handle(app_t *app, const ci_event_t *ev) {
    int total_rows = app->n_repos + 1;

    switch (ev->type) {
        case EV_SWIPE_U:
            if (app->sel_repo < total_rows - 1) app->sel_repo++;
            break;
        case EV_SWIPE_D:
            if (app->sel_repo > 0) app->sel_repo--;
            break;
        case EV_TAP: {
            int hit = widget_list_hit_test(ev->x, ev->y, total_rows,
                                            app->sel_repo, 20, 20, fb_width() - 40, fb_height() - 100);
            if (hit < 0) break;
            app->sel_repo = hit;
            if (app->sel_repo == app->n_repos) {
                /* "+ Add Repo" row */
                app->url_entry[0] = '\0';
                app->url_entry_len = 0;
                app->screen = SCREEN_REPO_ADD;
            } else if (app->n_repos > 0) {
                app->cur_repo_index_loaded = 0;
                app->sel_ext = 0;
                app->download_status[0] = '\0';
                app->screen = SCREEN_EXT_LIST;
            }
            break;
        }
        case EV_KEY_BACK:
            app->screen = SCREEN_LIBRARY;
            break;
        default:
            break;
    }
}

/* Minimal on-screen keyboard: lowercase QWERTY rows plus a symbol row
   with exactly what a URL needs (: / . - _) since that's the only
   text this app ever asks the user to type. No shift/uppercase --
   repo URLs don't need it, and skipping it avoids a second keyboard
   layout to draw and hit-test. Rows are simple fixed grids, not
   variable-width per key, so hit-testing is just integer division.
   Anchored to the bottom of the screen (like KOReader's own
   VirtualKeyboard) rather than a fixed offset from the top, so it
   sits where a real keyboard would and doesn't waste vertical space
   on devices with a taller/shorter panel. */
#define KB_KEY_W 58
#define KB_KEY_H 58
#define KB_ROWS 4
#define KB_SYM_ROW 1 /* symbol/backspace/go row, drawn below the letter rows */
#define KB_TOTAL_ROWS (KB_ROWS + KB_SYM_ROW)
#define KB_ORIGIN_X 10
#define KB_BOTTOM_MARGIN 20

static int kb_origin_y(void) {
    return fb_height() - KB_BOTTOM_MARGIN - KB_TOTAL_ROWS * KB_KEY_H;
}

static const char *kb_rows[KB_ROWS] = {
    "1234567890",
    "qwertyuiop",
    "asdfghjkl",
    "zxcvbnm",
};
/* Symbol row lives past the letter rows at a fixed slot, plus
   Backspace and Go occupy the last two slots of that same row. */
static const char kb_symbols[] = ":/.-_";

void ui_repo_add_draw(app_t *app) {
    fb_clear();

    fb_text(20, 20, "Enter repo URL:", 3);
    fb_text(20, 60, app->url_entry[0] ? app->url_entry : "https://", 2);

    int origin_y = kb_origin_y();

    for (int r = 0; r < KB_ROWS; r++) {
        const char *row = kb_rows[r];
        int len = (int)strlen(row);
        for (int c = 0; c < len; c++) {
            char label[2] = { row[c], '\0' };
            widget_button_t btn = {
                .label = label,
                .x = KB_ORIGIN_X + c * KB_KEY_W,
                .y = origin_y + r * KB_KEY_H,
                .w = KB_KEY_W - 4,
                .h = KB_KEY_H - 4,
            };
            widget_draw_button(&btn, 0);
        }
    }

    int sym_row_y = origin_y + KB_ROWS * KB_KEY_H;
    int n_syms = (int)strlen(kb_symbols);
    for (int c = 0; c < n_syms; c++) {
        char label[2] = { kb_symbols[c], '\0' };
        widget_button_t btn = {
            .label = label,
            .x = KB_ORIGIN_X + c * KB_KEY_W,
            .y = sym_row_y,
            .w = KB_KEY_W - 4,
            .h = KB_KEY_H - 4,
        };
        widget_draw_button(&btn, 0);
    }

    widget_button_t back_btn = {
        .label = "<-", .x = KB_ORIGIN_X + n_syms * KB_KEY_W, .y = sym_row_y,
        .w = KB_KEY_W - 4, .h = KB_KEY_H - 4,
    };
    widget_draw_button(&back_btn, 0);

    widget_button_t go_btn = {
        .label = "Add", .x = KB_ORIGIN_X + (n_syms + 1) * KB_KEY_W, .y = sym_row_y,
        .w = KB_KEY_W * 2 - 4, .h = KB_KEY_H - 4,
    };
    widget_draw_button(&go_btn, 1);

    fb_refresh_full();
}

/* Maps a tap coordinate to whichever key occupies that cell, or -1 /
   a sentinel char for "no key here" / "backspace" / "go". Returns 1
   and fills *out_char if a letter/symbol key was hit, 0 otherwise --
   caller checks the two special zones (back_btn, go_btn) separately
   since they aren't single characters. */
static int kb_hit_char(int x, int y, char *out_char) {
    int origin_y = kb_origin_y();
    if (y < origin_y) return 0;
    int row = (y - origin_y) / KB_KEY_H;
    int col = (x - KB_ORIGIN_X) / KB_KEY_W;
    if (col < 0) return 0;

    if (row < KB_ROWS) {
        const char *r = kb_rows[row];
        if (col < (int)strlen(r)) {
            *out_char = r[col];
            return 1;
        }
        return 0;
    }
    if (row == KB_ROWS) {
        int n_syms = (int)strlen(kb_symbols);
        if (col < n_syms) {
            *out_char = kb_symbols[col];
            return 1;
        }
    }
    return 0;
}

void ui_repo_add_handle(app_t *app, const ci_event_t *ev) {
    if (ev->type == EV_KEY_BACK) {
        app->screen = SCREEN_REPO_LIST;
        return;
    }
    if (ev->type != EV_TAP) return;

    int sym_row_y = kb_origin_y() + KB_ROWS * KB_KEY_H;
    int n_syms = (int)strlen(kb_symbols);
    int back_x0 = KB_ORIGIN_X + n_syms * KB_KEY_W;
    int go_x0 = KB_ORIGIN_X + (n_syms + 1) * KB_KEY_W;

    if (ev->y >= sym_row_y && ev->y < sym_row_y + KB_KEY_H) {
        if (ev->x >= back_x0 && ev->x < go_x0) {
            if (app->url_entry_len > 0) app->url_entry[--app->url_entry_len] = '\0';
            return;
        }
        if (ev->x >= go_x0) {
            if (app->url_entry_len > 0) {
                repo_store_add(&g_store, app->url_entry);
                repo_store_save(&g_store, REPOS_JSON_PATH);
            }
            app->screen = SCREEN_REPO_LIST;
            ui_repo_enter_list(app);
            return;
        }
    }

    char ch;
    if (kb_hit_char(ev->x, ev->y, &ch)) {
        if (app->url_entry_len < APP_URL_ENTRY_MAX - 1) {
            app->url_entry[app->url_entry_len++] = ch;
            app->url_entry[app->url_entry_len] = '\0';
        }
    }
}

/* Extension list for the currently selected repo. The index fetch is
   synchronous and blocks the UI thread for its duration (network
   round-trip via curl) -- acceptable for v1 since it's a rare,
   user-initiated action, not something on a hot path. A future pass
   could show a spinner via a mid-fetch partial redraw if the delay
   proves annoying in practice. */
void ui_ext_list_draw(app_t *app) {
    fb_clear();

    if (!app->cur_repo_index_loaded) {
        widget_toast("Loading repo index...");
        fb_refresh_full();

        char idx_url[560];
        snprintf(idx_url, sizeof(idx_url), "%s/index.json", app->repo_urls[app->sel_repo]);
        char *data = NULL;
        size_t len = 0;
        if (repo_http_get(idx_url, 20, 2 * 1024 * 1024, &data, &len) == 0) {
            if (repo_index_parse(data, len, &app->cur_repo_index) == 0) {
                app->cur_repo_index_loaded = 1;
            }
            free(data);
        }
        if (!app->cur_repo_index_loaded) {
            fb_clear();
            widget_toast("Failed to load repo index");
            fb_refresh_full();
            return;
        }
        fb_clear();
    }

    repo_index *idx = &app->cur_repo_index;
    if (idx->count == 0) {
        widget_toast("No extensions in this repo");
        fb_refresh_full();
        return;
    }

    char **labels = malloc(sizeof(char *) * idx->count);
    for (size_t i = 0; i < idx->count; i++) {
        char buf[200];
        snprintf(buf, sizeof(buf), "%s [%s] (%s)", idx->entries[i].name,
                 idx->entries[i].lang, idx->entries[i].content_warning);
        labels[i] = strdup(buf);
    }
    widget_draw_list((const char **)labels, (int)idx->count, app->sel_ext,
                      20, 20, fb_width() - 40, fb_height() - 100);
    for (size_t i = 0; i < idx->count; i++) free(labels[i]);
    free(labels);

    if (app->download_status[0]) widget_toast(app->download_status);

    fb_refresh_full();
}

void ui_ext_list_handle(app_t *app, const ci_event_t *ev) {
    if (!app->cur_repo_index_loaded) {
        if (ev->type == EV_KEY_BACK) app->screen = SCREEN_REPO_LIST;
        return; /* still (re)drawing/fetching, ignore other input */
    }

    repo_index *idx = &app->cur_repo_index;
    switch (ev->type) {
        case EV_SWIPE_U:
            if (idx->count > 0 && app->sel_ext < (int)idx->count - 1) app->sel_ext++;
            break;
        case EV_SWIPE_D:
            if (app->sel_ext > 0) app->sel_ext--;
            break;
        case EV_TAP: {
            int hit = widget_list_hit_test(ev->x, ev->y, (int)idx->count,
                                            app->sel_ext, 20, 20, fb_width() - 40, fb_height() - 100);
            if (hit < 0) break;
            app->sel_ext = hit;
            char dest[512];
            snprintf(dest, sizeof(dest), "%s%s.tkext.json", EXT_DIR,
                     idx->entries[app->sel_ext].id);
            int rc = repo_download_extension(app->repo_urls[app->sel_repo],
                                              &idx->entries[app->sel_ext], dest);
            snprintf(app->download_status, sizeof(app->download_status),
                      rc == 0 ? "Downloaded %s" : "Failed: %s",
                      idx->entries[app->sel_ext].name);
            break;
        }
        case EV_KEY_BACK:
            repo_index_free(&app->cur_repo_index);
            app->cur_repo_index_loaded = 0;
            app->download_status[0] = '\0';
            app->screen = SCREEN_REPO_LIST;
            break;
        default:
            break;
    }
}
