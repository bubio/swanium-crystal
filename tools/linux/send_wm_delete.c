#include <X11/Xlib.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s WINDOW_ID\n", argv[0]);
    return 2;
  }

  errno = 0;
  char *end = NULL;
  unsigned long parsed = strtoul(argv[1], &end, 0);
  if (errno || !end || *end != '\0' || parsed == 0) {
    fprintf(stderr, "invalid X11 window id: %s\n", argv[1]);
    return 2;
  }

  Display *display = XOpenDisplay(NULL);
  if (!display) {
    fputs("could not open the X11 display\n", stderr);
    return 1;
  }

  Atom protocols = XInternAtom(display, "WM_PROTOCOLS", False);
  Atom delete_window = XInternAtom(display, "WM_DELETE_WINDOW", False);
  XEvent event = {0};
  event.xclient.type = ClientMessage;
  event.xclient.display = display;
  event.xclient.window = (Window)parsed;
  event.xclient.message_type = protocols;
  event.xclient.format = 32;
  event.xclient.data.l[0] = (long)delete_window;
  event.xclient.data.l[1] = CurrentTime;

  int sent = XSendEvent(display, (Window)parsed, False, NoEventMask, &event);
  XSync(display, False);
  XCloseDisplay(display);
  if (!sent) {
    fputs("could not send WM_DELETE_WINDOW\n", stderr);
    return 1;
  }
  return 0;
}
