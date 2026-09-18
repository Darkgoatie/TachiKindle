#ifndef CI_SIGNALS_H
#define CI_SIGNALS_H

/* Installs handlers for SIGSEGV/SIGBUS/SIGTERM that call fb_shutdown()
   and log the crash before re-raising the default handler, so a fault
   inside the binary doesn't leave the framebuffer in a half-drawn state
   any longer than necessary -- the launcher scriptlet's own trap is the
   primary safety net (it always restarts lab126_gui regardless of how
   the binary exits), this is a second layer for the framebuffer state
   specifically. */
void signals_install(void);

#endif
