#ifndef CI_UI_READER_H
#define CI_UI_READER_H
#include "app.h"
#include "input.h"

/* Opens cur_archive for app->sel_series/sel_chapter and jumps to the
   saved progress page, if any. Call when entering SCREEN_READER. */
void ui_reader_enter(app_t *app);

void ui_reader_draw(app_t *app);
void ui_reader_handle(app_t *app, const ci_event_t *ev);

#endif
