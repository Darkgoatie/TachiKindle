#ifndef CI_INPUT_H
#define CI_INPUT_H

typedef enum {
    EV_NONE,
    EV_TAP,
    EV_SWIPE_L,
    EV_SWIPE_R,
    EV_SWIPE_U,
    EV_SWIPE_D,
    EV_KEY_BACK,
    EV_QUIT
} ev_type_t;

typedef struct {
    ev_type_t type;
    int x, y;
} ci_event_t;

/* Auto-detects the touchscreen node under /dev/input by probing for
   ABS_MT_POSITION_X support rather than hardcoding a fixed event number,
   since it differs across Kindle models. Returns 0 on success. */
int input_init(void);
void input_shutdown(void);

/* Blocks up to timeout_ms waiting for a normalized event.
   Returns 1 and fills *out on an event, 0 on timeout. */
int input_poll(ci_event_t *out, int timeout_ms);

#endif
