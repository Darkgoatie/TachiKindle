#ifndef CI_APP_H
#define CI_APP_H

#include "library.h"
#include "progress.h"
#include "archive.h"
#include "repo.h"

#define APP_MAX_REPOS 16
#define APP_URL_ENTRY_MAX 256

typedef enum {
    SCREEN_LIBRARY,
    SCREEN_CHAPTERS,
    SCREEN_READER,
    SCREEN_REPO_LIST,
    SCREEN_REPO_ADD,
    SCREEN_EXT_LIST,
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

    /* Repo browsing state. repos[] is persisted to
       /mnt/us/tachikindle/repos.json (name = url, one per saved
       repo). sel_repo indexes repos[]; cur_repo_index holds the
       parsed index.json of whichever repo was last opened, freed and
       re-fetched each time the user (re-)enters SCREEN_EXT_LIST.
       url_entry/url_entry_len back the on-screen keyboard for adding
       a new repo URL. download_status holds a short human-readable
       result ("Downloaded", "Failed: ...") shown after a download
       attempt, cleared on next screen change. */
    char repo_urls[APP_MAX_REPOS][512];
    int  n_repos;
    int  sel_repo;

    repo_index cur_repo_index;
    int         cur_repo_index_loaded;
    int         sel_ext;

    char url_entry[APP_URL_ENTRY_MAX];
    int  url_entry_len;

    char download_status[128];
} app_t;

void app_init(app_t *app, const char *library_root, const char *progress_path);
void app_shutdown(app_t *app);

/* Runs one iteration: polls for input, dispatches to the current
   screen's handler, redraws only if something changed. Returns 0 to
   keep running, non-zero when SCREEN_EXIT has been reached. */
int app_step(app_t *app);

/* Draws the top-left quit-zone marker; called by app_step after each
   screen redraw so it's visible on every screen. Exposed in the
   header only so screens that do partial in-place redraws (skipping
   app_step's normal post-switch draw) can call it themselves. */
void app_draw_quit_zone(void);

#endif
