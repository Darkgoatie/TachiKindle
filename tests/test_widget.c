/* tests/test_widget.c -- widget_list_hit_test correctness, since the
   whole app's tap-to-select behavior depends on it agreeing exactly
   with widget_draw_list's layout math (row height, scroll window). */
#include "minunit.h"
#include "../src/widget.h"
#include <string.h>

static void test_hit_first_row_no_scroll(void) {
    /* 5 items, selected=0 (no scroll needed), list at (20,20,400,300) */
    int hit = widget_list_hit_test(30, 30, 5, 0, 20, 20, 400, 300);
    mu_assert("tap in row 0 lands on item 0", hit == 0);
}

static void test_hit_second_row(void) {
    /* ROW_HEIGHT is 56 (widget.c internal) -- tap at y=20+56+10=86
       should land on the second row (item index 1). */
    int hit = widget_list_hit_test(30, 86, 5, 0, 20, 20, 400, 300);
    mu_assert("tap in row 1 lands on item 1", hit == 1);
}

static void test_hit_outside_list_bounds_returns_miss(void) {
    int hit_left = widget_list_hit_test(5, 30, 5, 0, 20, 20, 400, 300);
    mu_assert("tap left of list misses", hit_left == -1);

    int hit_above = widget_list_hit_test(30, 5, 5, 0, 20, 20, 400, 300);
    mu_assert("tap above list misses", hit_above == -1);

    int hit_right = widget_list_hit_test(500, 30, 5, 0, 20, 20, 400, 300);
    mu_assert("tap right of list bounds misses", hit_right == -1);
}

static void test_hit_below_last_item_in_short_list_returns_miss(void) {
    /* Only 2 items but the list area is tall enough for many rows --
       tapping in row 4 (no such item) must miss, not wrap/crash. */
    int hit = widget_list_hit_test(30, 20 + 56 * 4 + 10, 2, 0, 20, 20, 400, 300);
    mu_assert("tap past last item misses", hit == -1);
}

static void test_hit_accounts_for_scroll_window(void) {
    /* 10 items, visible_rows = 300/56 = 5, selected=9 (last item) ->
       scroll window starts at first = 9 - 5 + 1 = 5. A tap on the
       first visible row (top of the list) should now hit item 5,
       not item 0, since the list has scrolled to keep item 9 visible. */
    int hit = widget_list_hit_test(30, 30, 10, 9, 20, 20, 400, 300);
    mu_assert("tap on top visible row after scroll hits item 5", hit == 5);
}

MU_MAIN_BEGIN
    mu_run(test_hit_first_row_no_scroll);
    mu_run(test_hit_second_row);
    mu_run(test_hit_outside_list_bounds_returns_miss);
    mu_run(test_hit_below_last_item_in_short_list_returns_miss);
    mu_run(test_hit_accounts_for_scroll_window);
MU_MAIN_END
