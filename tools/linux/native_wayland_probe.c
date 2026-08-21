#include <SDL3/SDL.h>
#include <gdk/gdkwayland.h>
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

static void fail(const char *operation) {
  fprintf(stderr, "wayland-probe: %s failed: %s\n", operation, SDL_GetError());
}

int main(void) {
  g_setenv("GDK_BACKEND", "wayland", TRUE);
  g_setenv("SDL_VIDEODRIVER", "wayland", TRUE);
  if (!gtk_init_check(NULL, NULL)) {
    fputs("wayland-probe: GTK3 could not initialize a native Wayland display\n", stderr);
    return 1;
  }
  GdkDisplay *gdk_display = gdk_display_get_default();
  if (!GDK_IS_WAYLAND_DISPLAY(gdk_display)) {
    fputs("wayland-probe: GTK3 did not select its native Wayland backend\n", stderr);
    return 1;
  }

  struct wl_display *display = gdk_wayland_display_get_wl_display(gdk_display);
  SDL_PropertiesID globals = SDL_GetGlobalProperties();
  if (!globals || !SDL_SetPointerProperty(globals, SDL_PROP_GLOBAL_VIDEO_WAYLAND_WL_DISPLAY_POINTER, display)) {
    fail("sharing GTK's wl_display");
    return 1;
  }
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    fail("SDL_Init");
    return 1;
  }

  GtkWidget *top = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *area = gtk_drawing_area_new();
  gtk_window_set_title(GTK_WINDOW(top), "GTK3 + SDL3 native Wayland probe");
  gtk_widget_set_size_request(area, 448, 288);
  gtk_container_add(GTK_CONTAINER(top), area);
  g_signal_connect(top, "delete-event", G_CALLBACK(close_window), NULL);
  gtk_widget_show_all(top);
  while (gtk_events_pending()) gtk_main_iteration();

  GdkWindow *gdk_window = gtk_widget_get_window(area);
  struct wl_surface *surface = gdk_window ? gdk_wayland_window_get_wl_surface(gdk_window) : NULL;
  if (!surface) {
    fputs("wayland-probe: GtkDrawingArea did not realize a wl_surface\n", stderr);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  GdkMonitor *monitor = gdk_display_get_monitor_at_window(gdk_display, gdk_window);
  GdkRectangle monitor_geometry = {0};
  if (monitor) gdk_monitor_get_geometry(monitor, &monitor_geometry);

  SDL_PropertiesID props = SDL_CreateProperties();
  if (!props ||
      !SDL_SetPointerProperty(props, SDL_PROP_WINDOW_CREATE_WAYLAND_WL_SURFACE_POINTER, surface) ||
      !SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, 448) ||
      !SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, 288) ||
      !SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN, true)) {
    fail("configuring imported wl_surface");
    if (props) SDL_DestroyProperties(props);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  SDL_Window *wrapper = SDL_CreateWindowWithProperties(props);
  SDL_DestroyProperties(props);
  if (!wrapper) {
    fail("SDL_CreateWindowWithProperties");
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  SDL_Renderer *renderer = SDL_CreateRenderer(wrapper, NULL);
  if (!renderer) {
    fail("SDL_CreateRenderer");
    SDL_DestroyWindow(wrapper);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }
  SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
                                           SDL_TEXTUREACCESS_STREAMING, 64, 64);
  if (!texture) {
    fail("SDL_CreateTexture");
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(wrapper);
    gtk_widget_destroy(top);
    SDL_Quit();
    return 1;
  }

  uint32_t pixels[64 * 64];
  for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
    pixels[y * 64 + x] = 0xff000000u | ((uint32_t)(x * 4) << 16) | ((uint32_t)(y * 4) << 8) | 0x40u;

  int initial_width = 0, initial_height = 0;
  int rotated_width = 0, rotated_height = 0;
  int expanded_width = 0, expanded_height = 0;
  int restored_width = 0, restored_height = 0;
  for (int frame = 0; frame < 240 && !closed; frame++) {
    while (gtk_events_pending()) gtk_main_iteration();
    SDL_Event event;
    while (SDL_PollEvent(&event)) if (event.type == SDL_EVENT_QUIT) closed = 1;
    if (frame == 30) {
      initial_width = gtk_widget_get_allocated_width(area);
      initial_height = gtk_widget_get_allocated_height(area);
    }
    if (frame == 60) {
      gtk_widget_set_size_request(area, 672, 432);
      gtk_window_resize(GTK_WINDOW(top), 672, 432);
    }
    if (frame == 90) {
      expanded_width = gtk_widget_get_allocated_width(area);
      expanded_height = gtk_widget_get_allocated_height(area);
    }
    if (frame == 120) {
      gtk_widget_set_size_request(area, 288, 448);
      gtk_window_resize(GTK_WINDOW(top), 288, 448);
    }
    if (frame == 150) {
      rotated_width = gtk_widget_get_allocated_width(area);
      rotated_height = gtk_widget_get_allocated_height(area);
    }
    if (frame == 180) {
      gtk_widget_set_size_request(area, 448, 288);
      gtk_window_resize(GTK_WINDOW(top), 448, 288);
    }
    if (frame == 210) {
      restored_width = gtk_widget_get_allocated_width(area);
      restored_height = gtk_widget_get_allocated_height(area);
    }
    GtkAllocation allocation;
    gtk_widget_get_allocation(area, &allocation);
    if (!SDL_SetWindowSize(wrapper, allocation.width, allocation.height) ||
        !SDL_UpdateTexture(texture, NULL, pixels, 64 * 4) ||
        !SDL_RenderClear(renderer) ||
        !SDL_RenderTexture(renderer, texture, NULL, NULL) ||
        !SDL_RenderPresent(renderer)) {
      fail("resize/render loop");
      closed = 1;
    }
    SDL_Delay(16);
  }

  int pixel_width = 0, pixel_height = 0;
  int logical_width = gtk_widget_get_allocated_width(area);
  int logical_height = gtk_widget_get_allocated_height(area);
  int scale = gtk_widget_get_scale_factor(area);
  if (!SDL_GetWindowSizeInPixels(wrapper, &pixel_width, &pixel_height)) {
    fail("SDL_GetWindowSizeInPixels");
    closed = 1;
  }
  fprintf(stderr, "wayland-probe: monitor=%dx%d, resize/rotate=%dx%d -> %dx%d -> %dx%d -> %dx%d, logical=%dx%d scale=%d pixels=%dx%d\n",
          monitor_geometry.width, monitor_geometry.height,
          initial_width, initial_height, expanded_width, expanded_height,
          rotated_width, rotated_height,
          restored_width, restored_height, logical_width, logical_height, scale, pixel_width, pixel_height);
  if (rotated_width != initial_height || rotated_height != initial_width ||
      expanded_width <= initial_width || expanded_height <= initial_height ||
      restored_width != initial_width || restored_height != initial_height ||
      pixel_width != logical_width * scale || pixel_height != logical_height * scale) {
    fputs("wayland-probe: resize or HiDPI dimensions did not match\n", stderr);
    closed = 1;
  }
  SDL_DestroyTexture(texture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(wrapper);
  gtk_widget_destroy(top);
  while (gtk_events_pending()) gtk_main_iteration();
  SDL_Quit();
  if (!closed) {
    fputs("wayland-probe: shared display, resize, rotation, render, input polling, HiDPI, and shutdown passed\n", stderr);
    return 0;
  }
  return 1;
}
