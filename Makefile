CROSS   ?= arm-kindlehf-linux-gnueabihf-
CC       = $(CROSS)gcc
FBINK    = third_party/FBInk
CFLAGS   = -std=gnu11 -O2 -Wall -Wextra -I$(FBINK)
LDFLAGS  = -static
LDLIBS   = $(FBINK)/Release/libfbink.a -lm

tachikindle: src/main.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS) $(LDFLAGS)

clean:
	rm -f tachikindle
