#ifndef CI_WIDGET_H
#define CI_WIDGET_H

/* Boring-by-design e-ink UI primitives: thick borders, big text, no
   anti-aliasing tricks that vanish after 16-level dithering. Built only
   on top of fb.h so the same calls work whether fb.c is backed by the
   real Kindle framebuffer or (later) an SDL host preview -- see the
   plan's Phase 5 Task 5.3 for that swap. */

typedef struct {
    const char *label;
    int x, y, w, h;
} widget_button_t;

/* Draws a filled box with a border and centered label. */
void widget_draw_button(const widget_button_t *btn, int selected);

/* Draws a scrollable list of labels; `selected` highlights that row. */
void widget_draw_list(const char **labels, int count, int selected,
                       int x, int y, int w, int h);

/* Draws a short-lived status message centered near the top; caller is
   responsible for triggering the actual screen refresh afterward. */
void widget_toast(const char *message);

#endif
