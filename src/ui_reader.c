#include "ui_reader.h"
#include "fb.h"
#include "widget.h"
#include "image.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dirent.h>
#include <ctype.h>

/* Third-thirds tap zones: left third = prev page, right third = next
   page, center third = toggle overlay. Matches how most e-ink readers
   split the screen since it needs no visible chrome to discover. */

static series_t *cur_series(app_t *app) {
    return &app->lib.series[app->sel_series];
}
static chapter_t *cur_chapter(app_t *app) {
    return &cur_series(app)->chapters[app->sel_chapter];
}

static void save_progress(app_t *app) {
    progress_set(&app->prog, cur_series(app)->name, cur_chapter(app)->name, app->page);
    progress_save(&app->prog, "/mnt/us/tachikindle/progress.tsv");
}

/* Same natural-sort semantics as archive.c/library.c. Duplicated on
   purpose for now rather than sharing a header -- three copies of a
   ~20-line static comparator is an acceptable price versus introducing
   a shared "util" module for one function this early; revisit if a
   fourth caller shows up. */
static int natcmp(const char *a, const char *b) {
    while (*a && *b) {
        if (isdigit((unsigned char)*a) && isdigit((unsigned char)*b)) {
            const char *a0 = a, *b0 = b;
            while (*a == '0') a++;
            while (*b == '0') b++;
            const char *as = a, *bs = b;
            while (isdigit((unsigned char)*a)) a++;
            while (isdigit((unsigned char)*b)) b++;
            size_t alen = (size_t)(a - as), blen = (size_t)(b - bs);
            if (alen != blen) return alen < blen ? -1 : 1;
            int cmp = strncmp(as, bs, alen);
            if (cmp != 0) return cmp;
            size_t azeros = (size_t)(as - a0), bzeros = (size_t)(bs - b0);
            if (azeros != bzeros) return azeros > bzeros ? -1 : 1;
        } else {
            if (*a != *b) return (unsigned char)*a - (unsigned char)*b;
            a++; b++;
        }
    }
    return (unsigned char)*a - (unsigned char)*b;
}

static int natcmp_qsort(const void *pa, const void *pb) {
    return natcmp(*(const char * const *)pa, *(const char * const *)pb);
}

/* Lists regular files in a loose-image chapter directory, naturally
   sorted. Caller frees the returned array and its strings. */
static char **list_dir_pages(const char *dir_path, int *out_count) {
    DIR *d = opendir(dir_path);
    if (!d) { *out_count = 0; return NULL; }

    char **names = NULL;
    int cap = 0, n = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        if (n == cap) {
            cap = cap == 0 ? 16 : cap * 2;
            names = realloc(names, (size_t)cap * sizeof(char *));
        }
        names[n++] = strdup(ent->d_name);
    }
    closedir(d);

    qsort(names, (size_t)n, sizeof(char *), natcmp_qsort);
    *out_count = n;
    return names;
}

void ui_reader_enter(app_t *app) {
    if (app->open_archive) {
        archive_close(&app->cur_archive);
        app->open_archive = 0;
    }

    chapter_t *ch = cur_chapter(app);
    if (!ch->is_dir_chapter) {
        if (archive_open(&app->cur_archive, ch->path) == 0) {
            app->open_archive = 1;
        }
    }

    int saved = progress_get_page(&app->prog, cur_series(app)->name, ch->name);
    app->page = saved > 0 ? saved : 0;
    app->overlay_visible = 0;
}

/* Returns -1 for archive chapters whose page count isn't known until
   opened (it always is, once open_archive is set) -- kept as an int
   return so callers can treat "unknown" and "directory, count it"
   uniformly without a second code path. */
static int reader_page_count(app_t *app) {
    chapter_t *ch = cur_chapter(app);
    if (ch->is_dir_chapter) {
        int count = 0;
        char **names = list_dir_pages(ch->path, &count);
        for (int i = 0; i < count; i++) free(names[i]);
        free(names);
        return count;
    }
    if (app->open_archive) return archive_page_count(&app->cur_archive);
    return 0;
}

static unsigned char *load_current_page_gray(app_t *app, int *out_w, int *out_h) {
    chapter_t *ch = cur_chapter(app);
    unsigned char *raw = NULL;
    size_t raw_size = 0;
    int free_raw = 1;

    if (!ch->is_dir_chapter) {
        if (!app->open_archive) return NULL;
        raw = archive_read_page(&app->cur_archive, app->page, &raw_size);
    } else {
        int count = 0;
        char **names = list_dir_pages(ch->path, &count);
        if (app->page < 0 || app->page >= count) {
            for (int i = 0; i < count; i++) free(names[i]);
            free(names);
            return NULL;
        }

        char full_path[4096];
        snprintf(full_path, sizeof(full_path), "%s/%s", ch->path, names[app->page]);
        for (int i = 0; i < count; i++) free(names[i]);
        free(names);

        FILE *f = fopen(full_path, "rb");
        if (!f) return NULL;
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size <= 0) { fclose(f); return NULL; }
        raw = malloc((size_t)size);
        if (!raw) { fclose(f); return NULL; }
        if (fread(raw, 1, (size_t)size, f) != (size_t)size) {
            fclose(f); free(raw); return NULL;
        }
        fclose(f);
        raw_size = (size_t)size;
        free_raw = 1;
    }

    if (!raw) return NULL;

    int w, h, ch_count;
    unsigned char *decoded = image_decode(raw, raw_size, &w, &h, &ch_count);
    if (free_raw) free(raw);
    if (!decoded) return NULL;

    unsigned char *gray = malloc((size_t)w * (size_t)h);
    if (gray) image_to_grayscale(decoded, w, h, ch_count, gray);
    free(decoded);

    *out_w = w;
    *out_h = h;
    return gray;
}

void ui_reader_draw(app_t *app) {
    fb_clear();

    int src_w, src_h;
    unsigned char *gray = load_current_page_gray(app, &src_w, &src_h);
    if (!gray) {
        widget_toast("Failed to load page");
        fb_refresh_full();
        return;
    }

    int box_w = fb_width(), box_h = fb_height();

    /* Scaling the decoded buffer itself (not just picking a draw size)
       is a follow-up once stb_image_resize2 is wired in; for now this
       blits at native decode resolution clipped to the framebuffer,
       which is correct for already screen-sized scans and a known
       rough edge for oversized source images -- see plan Task 3.5. */
    int blit_w = src_w < box_w ? src_w : box_w;
    int blit_h = src_h < box_h ? src_h : box_h;
    int off_y = app->zoom == ZOOM_FIT_WIDTH ? app->pan_y : 0;
    if (off_y > src_h - blit_h) off_y = src_h - blit_h;
    if (off_y < 0) off_y = 0;

    fb_blit_gray(gray + (size_t)off_y * (size_t)src_w, blit_w, blit_h,
                 (box_w - blit_w) / 2, 0);
    free(gray);

    if (app->overlay_visible) {
        char msg[128];
        int total = reader_page_count(app);
        if (total > 0) {
            snprintf(msg, sizeof(msg), "%s - page %d/%d",
                     cur_chapter(app)->name, app->page + 1, total);
        } else {
            snprintf(msg, sizeof(msg), "%s - page %d",
                     cur_chapter(app)->name, app->page + 1);
        }
        widget_toast(msg);
    }

    fb_refresh_page_turn();
}

void ui_reader_handle(app_t *app, const ci_event_t *ev) {
    int screen_w = fb_width();

    switch (ev->type) {
        case EV_TAP:
            if (ev->x < screen_w / 3) {
                if (app->page > 0) app->page--;
                save_progress(app);
            } else if (ev->x > (screen_w * 2) / 3) {
                int total = reader_page_count(app);
                if (app->page < total - 1) {
                    app->page++;
                    save_progress(app);
                } else {
                    /* past the last page: advance chapter, or back to
                       the chapter list if this was the last chapter */
                    series_t *s = cur_series(app);
                    if (app->sel_chapter < (int)s->n_chapters - 1) {
                        app->sel_chapter++;
                        ui_reader_enter(app);
                    } else {
                        app->screen = SCREEN_CHAPTERS;
                    }
                }
            } else {
                app->overlay_visible = !app->overlay_visible;
            }
            break;
        case EV_SWIPE_L: {
            int total = reader_page_count(app);
            if (app->page < total - 1) {
                app->page++;
                save_progress(app);
            }
            break;
        }
        case EV_SWIPE_R:
            if (app->page > 0) {
                app->page--;
                save_progress(app);
            }
            break;
        case EV_SWIPE_U:
        case EV_SWIPE_D:
            if (app->zoom == ZOOM_FIT_WIDTH) {
                app->pan_y += ev->type == EV_SWIPE_U ? 200 : -200;
                if (app->pan_y < 0) app->pan_y = 0;
            }
            break;
        case EV_KEY_BACK:
            save_progress(app);
            if (app->open_archive) {
                archive_close(&app->cur_archive);
                app->open_archive = 0;
            }
            app->screen = SCREEN_CHAPTERS;
            break;
        default:
            break;
    }
}
