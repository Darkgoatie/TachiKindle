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

/* On-screen keyboard, geometry copied from KOReader's real English
   layout (frontend/ui/data/keyboardlayouts/en_keyboard.lua, fetched
   2026-09-19) -- same 5-row grid, same per-key width ratios (Shift/
   Backspace at 1.5x, spacebar at 3x a standard key), same row
   membership (digits row, QWERTY/ASDFGHJKL/ZXCVBNM rows, bottom row
   with symbol-toggle/globe/space/arrows/enter). What's deliberately
   NOT copied: KOReader's Shift/Sym layer switching, its swipe-per-key
   alternate characters, hold-popups, and multi-language layout
   support -- this app only ever needs to type a URL, so this is a
   single fixed lowercase+symbol layer, not the full interaction
   model. See ui_repo.h for that scope decision.

   Units: a "key width unit" is the base single-key width; a row's
   total unit count times KB_UNIT_PX gives the row's pixel width, so
   rows with different total units (KOReader's rows are NOT all the
   same total either) size proportionally instead of a fixed grid. */
#define KB_UNIT_PX 54
#define KB_KEY_H 58
#define KB_ROWS 5
#define KB_ORIGIN_X 10
#define KB_BOTTOM_MARGIN 20

typedef struct {
    const char *label; /* multi-char labels (Bksp, Enter, Space) render as-is */
    int         emits; /* character appended on tap; -1=backspace, -2=commit, 0=inert placeholder */
    float       width; /* in key-width units, matches KOReader's `width =` field */
} kb_key_t;

/* clang-format off */
static const kb_key_t kb_row1[] = { /* digits, 10 units total */
    {"1",'1',1},{"2",'2',1},{"3",'3',1},{"4",'4',1},{"5",'5',1},
    {"6",'6',1},{"7",'7',1},{"8",'8',1},{"9",'9',1},{"0",'0',1},
};
static const kb_key_t kb_row2[] = { /* qwertyuiop, 10 units */
    {"q",'q',1},{"w",'w',1},{"e",'e',1},{"r",'r',1},{"t",'t',1},
    {"y",'y',1},{"u",'u',1},{"i",'i',1},{"o",'o',1},{"p",'p',1},
};
static const kb_key_t kb_row3[] = { /* asdfghjkl, 9 units (KOReader's is too) */
    {"a",'a',1},{"s",'s',1},{"d",'d',1},{"f",'f',1},{"g",'g',1},
    {"h",'h',1},{"j",'j',1},{"k",'k',1},{"l",'l',1},
};
static const kb_key_t kb_row4[] = { /* Shift(1.5)+zxcvbnm+Bksp(1.5), 10 units */
    {"^",   0,  1.5f}, /* no shift layer -- kept as a visual placeholder key */
    {"z",'z',1},{"x",'x',1},{"c",'c',1},{"v",'v',1},
    {"b",'b',1},{"n",'n',1},{"m",'m',1},
    {"Bksp", -1, 1.5f}, /* emits=-1 is the backspace sentinel */
};
static const kb_key_t kb_row5[] = { /* sym-placeholder, :, space(3), ., Add(2) */
    {":",':',1},{"/",'/',1},{".", '.', 1},
    {"Space", ' ', 3.0f},
    {"-",'-',1},{"_",'_',1},
    {"Add", -2, 2.0f}, /* emits=-2 is the "commit URL" sentinel */
};
/* clang-format on */

static const kb_key_t *kb_rows[KB_ROWS] = { kb_row1, kb_row2, kb_row3, kb_row4, kb_row5 };
static const int kb_row_lens[KB_ROWS] = {
    sizeof(kb_row1) / sizeof(kb_row1[0]), sizeof(kb_row2) / sizeof(kb_row2[0]),
    sizeof(kb_row3) / sizeof(kb_row3[0]), sizeof(kb_row4) / sizeof(kb_row4[0]),
    sizeof(kb_row5) / sizeof(kb_row5[0]),
};

static int kb_origin_y(void) {
    return fb_height() - KB_BOTTOM_MARGIN - KB_ROWS * KB_KEY_H;
}

/* Shared geometry walk used by both drawing and hit-testing so they
   can never disagree about where a key actually is -- calls `visit`
   once per key with its pixel rect; visit returns nonzero to stop
   the walk early (used by hit-testing to short-circuit on a match). */
typedef int (*kb_visit_fn)(const kb_key_t *key, int x, int y, int w, int h, void *ctx);

static int kb_walk(kb_visit_fn visit, void *ctx) {
    int origin_y = kb_origin_y();
    for (int r = 0; r < KB_ROWS; r++) {
        int x = KB_ORIGIN_X;
        int y = origin_y + r * KB_KEY_H;
        for (int c = 0; c < kb_row_lens[r]; c++) {
            const kb_key_t *k = &kb_rows[r][c];
            int w = (int)(k->width * KB_UNIT_PX);
            if (visit(k, x, y, w, KB_KEY_H, ctx)) return 1;
            x += w;
        }
    }
    return 0;
}

static int kb_draw_visit(const kb_key_t *key, int x, int y, int w, int h, void *ctx) {
    (void)ctx;
    widget_button_t btn = { key->label, x, y, w - 4, h - 4 };
    widget_draw_button(&btn, key->emits == -2 /* highlight "Add" like KOReader's Enter accent */);
    return 0;
}

void ui_repo_add_draw(app_t *app) {
    fb_clear();

    fb_text(20, 20, "Enter repo URL:", 3);
    fb_text(20, 60, app->url_entry[0] ? app->url_entry : "https://", 2);

    kb_walk(kb_draw_visit, NULL);

    fb_refresh_full();
}

typedef struct { int x, y; int emits; int found; } kb_hit_ctx;

static int kb_hit_visit(const kb_key_t *key, int x, int y, int w, int h, void *ctx_) {
    kb_hit_ctx *ctx = ctx_;
    if (ctx->x >= x && ctx->x < x + w && ctx->y >= y && ctx->y < y + h) {
        ctx->emits = key->emits;
        ctx->found = 1;
        return 1;
    }
    return 0;
}

void ui_repo_add_handle(app_t *app, const ci_event_t *ev) {
    if (ev->type == EV_KEY_BACK) {
        app->screen = SCREEN_REPO_LIST;
        return;
    }
    if (ev->type != EV_TAP) return;

    kb_hit_ctx ctx = { ev->x, ev->y, 0, 0 };
    kb_walk(kb_hit_visit, &ctx);
    if (!ctx.found) return;

    if (ctx.emits == -1) { /* Bksp */
        if (app->url_entry_len > 0) app->url_entry[--app->url_entry_len] = '\0';
        return;
    }
    if (ctx.emits == -2) { /* Add */
        if (app->url_entry_len > 0) {
            repo_store_add(&g_store, app->url_entry);
            repo_store_save(&g_store, REPOS_JSON_PATH);
        }
        app->screen = SCREEN_REPO_LIST;
        ui_repo_enter_list(app);
        return;
    }
    if (ctx.emits == 0) return; /* placeholder key (Shift), does nothing in this scope */

    if (app->url_entry_len < APP_URL_ENTRY_MAX - 1) {
        app->url_entry[app->url_entry_len++] = ctx.emits;
        app->url_entry[app->url_entry_len] = '\0';
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
