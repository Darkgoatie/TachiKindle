#ifndef CI_APP_H
#define CI_APP_H

#include "library.h"
#include "progress.h"
#include "archive.h"

typedef enum {
    SCREEN_LIBRARY,
    SCREEN_CHAPTERS,
    SCREEN_READER,
    SCREEN_EXIT
} screen_t;

typedef enum {
    ZOOM_FIT_PAGE,
    ZOOM_FIT_WIDTH
} zoom_mode_t;

typedef struct {
    screen_t   screen;
    library_t  lib;
    progress_t prog;

    int sel_series;
    int sel_chapter;
    int page;

    archive_t  cur_archive;
    int        open_archive; /* 1 if cur_archive is currently open */

    zoom_mode_t zoom;
    int pan_y; /* vertical scroll offset in fit-width mode */

    int overlay_visible;
    int running;
} app_t;

void app_init(app_t *app, const char *library_root, const char *progress_path);
void app_shutdown(app_t *app);

/* Runs one iteration: polls for input, dispatches to the current
   screen's handler, redraws only if something changed. Returns 0 to
   keep running, non-zero when SCREEN_EXIT has been reached. */
int app_step(app_t *app);

#endif
