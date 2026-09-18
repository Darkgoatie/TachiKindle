#ifndef CI_UI_LIBRARY_H
#define CI_UI_LIBRARY_H
#include "app.h"
#include "input.h"

void ui_library_draw(app_t *app);
void ui_library_handle(app_t *app, const ci_event_t *ev);

#endif
