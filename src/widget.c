#include "widget.h"
#include "fb.h"
#include <stdlib.h>
#include <string.h>

#define BORDER_PX   3
#define ROW_HEIGHT  56
#define TEXT_SIZE   3   /* fontmult passed to fb_text */

/* Shared scroll-window math: which item index is the first visible
   row, given a top-anchored scroll-to-keep-selected-in-view policy.
   Both widget_draw_list and widget_list_hit_test must agree on this
   or a tap can hit a different row than what's actually drawn there. */
static int list_first_visible_row(int count, int selected, int visible_rows) {
    (void)count;
    int first = 0;
    if (selected >= visible_rows) first = selected - visible_rows + 1;
    return first;
}

static uint8_t *solid_buf(int w, int h, uint8_t value) {
    uint8_t *buf = malloc((size_t)w * (size_t)h);
    if (buf) memset(buf, value, (size_t)w * (size_t)h);
    return buf;
}

static void draw_box_border(int x, int y, int w, int h) {
    uint8_t *top = solid_buf(w, BORDER_PX, 0x00);
    if (top) { fb_blit_gray(top, w, BORDER_PX, x, y); free(top); }

    uint8_t *bottom = solid_buf(w, BORDER_PX, 0x00);
    if (bottom) { fb_blit_gray(bottom, w, BORDER_PX, x, y + h - BORDER_PX); free(bottom); }

    uint8_t *left = solid_buf(BORDER_PX, h, 0x00);
    if (left) { fb_blit_gray(left, BORDER_PX, h, x, y); free(left); }

    uint8_t *right = solid_buf(BORDER_PX, h, 0x00);
    if (right) { fb_blit_gray(right, BORDER_PX, h, x + w - BORDER_PX, y); free(right); }
}

void widget_draw_button(const widget_button_t *btn, int selected) {
    uint8_t fill_value = selected ? 0x40 : 0xFF;
    uint8_t *fill = solid_buf(btn->w, btn->h, fill_value);
    if (fill) {
        fb_blit_gray(fill, btn->w, btn->h, btn->x, btn->y);
        free(fill);
    }
    draw_box_border(btn->x, btn->y, btn->w, btn->h);
    fb_text_on_bg(btn->x + 12, btn->y + btn->h / 2 - 12, btn->label, TEXT_SIZE, fill_value);
}

void widget_draw_list(const char **labels, int count, int selected,
                       int x, int y, int w, int h) {
    int visible_rows = h / ROW_HEIGHT;
    if (visible_rows < 1) visible_rows = 1;
    int first = list_first_visible_row(count, selected, visible_rows);

    for (int row = 0; row < visible_rows; row++) {
        int i = first + row;
        if (i >= count) break;
        widget_button_t btn = {
            .label = labels[i],
            .x = x,
            .y = y + row * ROW_HEIGHT,
            .w = w,
            .h = ROW_HEIGHT,
        };
        widget_draw_button(&btn, i == selected);
    }
}

int widget_list_hit_test(int tap_x, int tap_y, int count, int selected,
                          int x, int y, int w, int h) {
    if (tap_x < x || tap_x >= x + w || tap_y < y) return -1;

    int visible_rows = h / ROW_HEIGHT;
    if (visible_rows < 1) visible_rows = 1;
    int first = list_first_visible_row(count, selected, visible_rows);

    int row = (tap_y - y) / ROW_HEIGHT;
    if (row < 0 || row >= visible_rows) return -1;

    int i = first + row;
    if (i >= count) return -1;
    return i;
}

void widget_toast(const char *message) {
    int w = fb_width();
    widget_button_t btn = {
        .label = message,
        .x = w / 8,
        .y = 40,
        .w = w - (w / 4),
        .h = ROW_HEIGHT,
    };
    widget_draw_button(&btn, 0);
}
