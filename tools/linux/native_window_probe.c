#include <SDL2/SDL.h>
#include <gdk/gdkx.h>
#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>

static int closed;

static gboolean close_window(GtkWidget *widget, GdkEvent *event, gpointer data) {
  (void)widget;
  (void)event;
  (void)data;
  closed = 1;
  return TRUE;
}

static void fill_test_pattern(uint32_t *pixels, int width, int height) {
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      uint8_t red = (uint8_t)(x * 255 / (width - 1));
      uint8_t green = (uint8_t)(y * 255 / (height - 1));
      uint8_t blue = ((x / 8) ^ (y / 8)) & 1 ? 0xff : 0x30;
      pixels[y * width + x] = 0xff000000u | ((uint32_t)blue << 16) | ((uint32_t)green << 8) | red;
    }
  }
}

int main(void) {
  g_setenv("GDK_BACKEND", "x11", FALSE);
  g_setenv("SDL_VIDEODRIVER", "x11", FALSE);
  if (!gtk_init_check(NULL, NULL)) {
    fputs("probe: GTK3 could not initialize X11/XWayland\n", stderr);
    return 1;
  }
  if (!GDK_IS_X11_DISPLAY(gdk_display_get_default())) {
    fputs("probe: GTK3 did not select the X11 backend\n", stderr);
    return 1;
  }
  if (SDL_Init(SDL_INIT_VIDEO) != 0) {
    fprintf(stderr, "probe: SDL_Init failed: %s\n", SDL_GetError());
    return 1;
  }

  GtkWidget *top = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *area = gtk_drawing_area_new();
  gtk_window_set_title(GTK_WINDOW(top), "GTK3 + SDL2 native window probe");
  gtk_widget_set_size_request(area, 448, 288);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_widget_set_double_buffered(area, FALSE);
  G_GNUC_END_IGNORE_DEPRECATIONS
  gtk_container_add(GTK_CONTAINER(top), area);
  g_signal_connect(top, "delete-event", G_CALLBACK(close_window), NULL);
  gtk_widget_show_all(top);
  while (gtk_events_pending()) gtk_main_iteration();

  GdkWindow *gdk_window = gtk_widget_get_window(area);
  if (!gdk_window) {
    fputs("probe: GtkDrawingArea was not realized\n", stderr);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }

  Window xid = gdk_x11_window_get_xid(gdk_window);
  SDL_Window *wrapper = SDL_CreateWindowFrom((void *)(uintptr_t)xid);
  if (!wrapper) {
    fprintf(stderr, "probe: SDL_CreateWindowFrom failed: %s\n", SDL_GetError());
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  SDL_Renderer *renderer = SDL_CreateRenderer(wrapper, -1, SDL_RENDERER_ACCELERATED);
  if (!renderer) renderer = SDL_CreateRenderer(wrapper, -1, 0);
  if (!renderer) {
    fprintf(stderr, "probe: SDL_CreateRenderer failed: %s\n", SDL_GetError());
    SDL_DestroyWindow(wrapper);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  SDL_RendererInfo info;
  if (SDL_GetRendererInfo(renderer, &info) == 0)
    fprintf(stderr, "probe: renderer=%s flags=0x%x xid=0x%lx\n", info.name, info.flags, (unsigned long)xid);

  enum { WIDTH = 64, HEIGHT = 64 };
  uint32_t pixels[WIDTH * HEIGHT];
  fill_test_pattern(pixels, WIDTH, HEIGHT);
  SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
                                           SDL_TEXTUREACCESS_STREAMING, WIDTH, HEIGHT);
  if (!texture) {
    fprintf(stderr, "probe: SDL_CreateTexture failed: %s\n", SDL_GetError());
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(wrapper);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }

  for (int frame = 0; frame < 180 && !closed; frame++) {
    while (gtk_events_pending()) gtk_main_iteration();
    SDL_Event event;
    while (SDL_PollEvent(&event)) if (event.type == SDL_QUIT) closed = 1;
    if (frame == 60) gtk_widget_set_size_request(area, 672, 432);
    if (frame == 120) gtk_widget_set_size_request(area, 448, 288);
    SDL_UpdateTexture(texture, NULL, pixels, WIDTH * 4);
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    SDL_RenderPresent(renderer);
    SDL_Delay(16);
  }

  SDL_DestroyTexture(texture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(wrapper);
  gtk_widget_destroy(top);
  while (gtk_events_pending()) gtk_main_iteration();
  SDL_Quit();
  fputs("probe: startup, resize, render, and shutdown passed\n", stderr);
  return 0;
}
