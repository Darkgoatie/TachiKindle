#ifndef TK_UI_REPO_H
#define TK_UI_REPO_H

#include "app.h"
#include "input.h"

/* Three screens live here since they form one flow (repo list -> add
   repo -> extension list) and share little enough state to not
   justify three separate files the way library/chapters/reader do
   (those have real per-screen state: pan_y, zoom, chapter progress).
   Call ui_repo_enter_list() once when the user navigates here from
   the library screen (via a menu action -- wired in app.c) so repos
   get (re)loaded from disk. */
void ui_repo_enter_list(app_t *app);

void ui_repo_list_draw(app_t *app);
void ui_repo_list_handle(app_t *app, const ci_event_t *ev);

void ui_repo_add_draw(app_t *app);
void ui_repo_add_handle(app_t *app, const ci_event_t *ev);

void ui_ext_list_draw(app_t *app);
void ui_ext_list_handle(app_t *app, const ci_event_t *ev);

#endif
