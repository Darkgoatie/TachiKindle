#include "minunit.h"
#include "../src/font.h"
#include <string.h>
#include <stdlib.h>

#define TEST_TTF "assets/fonts/NotoSans-Regular.ttf"

static void test_init_missing_file_fails(void) {
    mu_assert("missing file fails", font_init("/no/such/font.ttf") != 0);
}

static void test_init_real_font_succeeds(void) {
    mu_assert("real font loads", font_init(TEST_TTF) == 0);
    font_shutdown();
}

static void test_measure_width_nonzero_for_text(void) {
    font_init(TEST_TTF);
    int w = font_measure_width("Hello", 24);
    mu_assert("nonzero width", w > 0);
    font_shutdown();
}

static void test_measure_width_zero_for_empty_string(void) {
    font_init(TEST_TTF);
    int w = font_measure_width("", 24);
    mu_assert("empty string zero width", w == 0);
    font_shutdown();
}

static void test_draw_actually_darkens_pixels(void) {
    font_init(TEST_TTF);
    int w = 200, h = 60;
    uint8_t *buf = malloc((size_t)w * h);
    memset(buf, 255, (size_t)w * h); /* all white background */

    int drawn_w = font_draw(buf, w, h, 10, 10, "Test", 28);
    mu_assert("draw reports nonzero width", drawn_w > 0);

    int found_dark_pixel = 0;
    for (int i = 0; i < w * h; i++) {
        if (buf[i] < 250) { found_dark_pixel = 1; break; }
    }
    mu_assert("some pixel got darkened by real glyph ink", found_dark_pixel);

    free(buf);
    font_shutdown();
}

static void test_draw_clips_safely_at_buffer_edge(void) {
    font_init(TEST_TTF);
    int w = 20, h = 20;
    uint8_t *buf = malloc((size_t)w * h);
    memset(buf, 255, (size_t)w * h);

    /* Text origin far outside the buffer -- must not crash or
       corrupt memory, per blend_glyph's bounds checks. */
    font_draw(buf, w, h, 500, 500, "Offscreen", 24);
    font_draw(buf, w, h, -500, -500, "Offscreen", 24);

    free(buf);
    font_shutdown();
}

MU_MAIN_BEGIN
    mu_run(test_init_missing_file_fails);
    mu_run(test_init_real_font_succeeds);
    mu_run(test_measure_width_nonzero_for_text);
    mu_run(test_measure_width_zero_for_empty_string);
    mu_run(test_draw_actually_darkens_pixels);
    mu_run(test_draw_clips_safely_at_buffer_edge);
MU_MAIN_END
