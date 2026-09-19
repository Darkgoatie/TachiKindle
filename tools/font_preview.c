/* tools/font_preview.c -- renders sample text to a PNG for visual
   verification of stb_truetype output quality. Not a unit test. */
#include "../src/font.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

int main(void) {
    if (font_init("assets/fonts/NotoSans-Regular.ttf") != 0) {
        fprintf(stderr, "font_init failed\n");
        return 1;
    }

    int w = 500, h = 300;
    uint8_t *buf = malloc((size_t)w * h);
    memset(buf, 255, (size_t)w * h);

    font_draw(buf, w, h, 10, 10, "Example (Madara)", 32);
    font_draw(buf, w, h, 10, 60, "Chapter 12: The Return", 24);
    font_draw(buf, w, h, 10, 100, "abcdefghijklmnopqrstuvwxyz", 18);
    font_draw(buf, w, h, 10, 130, "0123456789 !@#$%", 18);
    font_draw(buf, w, h, 10, 170, "Small: quick brown fox jumps", 14);

    stbi_write_png("font_preview.png", w, h, 1, buf, w);
    printf("wrote font_preview.png\n");

    free(buf);
    font_shutdown();
    return 0;
}
