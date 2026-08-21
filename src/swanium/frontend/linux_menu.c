#include <gtk/gtk.h>
#include <gdk/gdkx.h>
#include <SDL2/SDL.h>
#include <stdint.h>

static GtkWidget *window, *status_label, *volume_slider, *game_area, *recent_menu, *load_root;
static GtkWidget *save_items[10], *load_items[10];
static GtkWidget *pause_item, *scale_items[4], *fullscreen_item, *renderer_items[2];
static GtkWidget *settings_window, *keyboard_buttons[11], *controller_buttons[3], *direction_boxes[3];
static int action, syncing_menu, keyboard_capture = -1;
static char *opened_path;
static char *present_title;
static char *recent_paths[10];
static char error_text[256];
static int frame_width = 224, frame_height = 144, display_scale = 3;
static Uint8 key_state[SDL_NUM_SCANCODES];

enum { OPEN_ROM = 1, PAUSE = 4, RESET = 5, SCALE_1 = 11, FULLSCREEN = 20,
       RENDER_NEAREST = 31, RENDER_LINEAR = 32, ABOUT = 41, SETTINGS = 42,
       QUIT = 43, SAVE_STATE_BASE = 100, LOAD_STATE_BASE = 200, RECENT_BASE = 300, CLEAR_RECENT = 310 };

static void activate(GtkWidget *item, gpointer data) {
  if (syncing_menu) return;
  action = GPOINTER_TO_INT(data);
  if (action >= 400 && action <= 410) {
    keyboard_capture = action - 400;
    gtk_button_set_label(GTK_BUTTON(item), "Press a key…");
  }
}
static gboolean close_window(GtkWidget *widget, GdkEvent *event, gpointer data) {
  (void)widget; (void)event; (void)data;
  action = QUIT;
  return TRUE;
}
static void direction_changed(GtkComboBox *box, gpointer data) { if (!syncing_menu) action = 6000 + GPOINTER_TO_INT(data) * 10 + gtk_combo_box_get_active(box); }

static void resize_for_frame(void) {
  if (!window || !game_area || frame_width <= 0 || frame_height <= 0) return;
  int width = frame_width * display_scale;
  int height = frame_height * display_scale;
  GtkAllocation window_allocation, game_allocation;
  gtk_widget_get_allocation(window, &window_allocation);
  gtk_widget_get_allocation(game_area, &game_allocation);
  int chrome_height = MAX(0, window_allocation.height - game_allocation.height);
  gtk_widget_set_size_request(game_area, width, height);
  gtk_window_resize(GTK_WINDOW(window), width, height + chrome_height);
}

static GtkWidget *menu_item(GtkWidget *menu, const char *title, int id) {
  GtkWidget *item = gtk_menu_item_new_with_label(title);
  g_signal_connect(item, "activate", G_CALLBACK(activate), GINT_TO_POINTER(id));
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  return item;
}

static void add_accelerator(GtkWidget *item, GtkAccelGroup *group, guint key, GdkModifierType modifiers) {
  gtk_widget_add_accelerator(item, "activate", group, key, modifiers, GTK_ACCEL_VISIBLE);
}

static SDL_Keycode sdl_keycode_from_gdk(guint keyval) {
  switch (keyval) {
    case GDK_KEY_Up: return SDLK_UP; case GDK_KEY_Right: return SDLK_RIGHT;
    case GDK_KEY_Down: return SDLK_DOWN; case GDK_KEY_Left: return SDLK_LEFT;
    case GDK_KEY_Return: return SDLK_RETURN; case GDK_KEY_Escape: return SDLK_ESCAPE;
    case GDK_KEY_space: return SDLK_SPACE; case GDK_KEY_Page_Up: return SDLK_PAGEUP;
    case GDK_KEY_Page_Down: return SDLK_PAGEDOWN;
    case GDK_KEY_F1: return SDLK_F1; case GDK_KEY_F2: return SDLK_F2; case GDK_KEY_F3: return SDLK_F3;
    case GDK_KEY_F4: return SDLK_F4; case GDK_KEY_F5: return SDLK_F5; case GDK_KEY_F6: return SDLK_F6;
    case GDK_KEY_F7: return SDLK_F7; case GDK_KEY_F8: return SDLK_F8; case GDK_KEY_F9: return SDLK_F9;
    case GDK_KEY_F10: return SDLK_F10; case GDK_KEY_F11: return SDLK_F11; case GDK_KEY_F12: return SDLK_F12;
    default: {
      gunichar unicode = gdk_keyval_to_unicode(keyval);
      return unicode > 0 && unicode <= 0x7f ? (SDL_Keycode)g_ascii_tolower((gchar)unicode) : SDLK_UNKNOWN;
    }
  }
}

static gboolean game_key_event(GtkWidget *widget, GdkEventKey *event, gpointer data) {
  (void)widget; (void)data;
  SDL_Keycode keycode = sdl_keycode_from_gdk(event->keyval);
  SDL_Scancode scancode = SDL_GetScancodeFromKey(keycode);
  if (scancode == SDL_SCANCODE_UNKNOWN || scancode >= SDL_NUM_SCANCODES) return FALSE;
  gboolean pressed = event->type == GDK_KEY_PRESS;
  gboolean shortcut = (event->state & (GDK_CONTROL_MASK | GDK_MOD1_MASK | GDK_SUPER_MASK)) != 0;
  Uint8 repeat = pressed && key_state[scancode];
  key_state[scancode] = pressed && !shortcut;
  if (!shortcut && SDL_WasInit(SDL_INIT_VIDEO)) {
    SDL_Event pushed;
    SDL_zero(pushed);
    pushed.type = pressed ? SDL_KEYDOWN : SDL_KEYUP;
    pushed.key.state = pressed ? SDL_PRESSED : SDL_RELEASED;
    pushed.key.repeat = repeat;
    pushed.key.keysym.scancode = scancode;
    pushed.key.keysym.sym = keycode;
    SDL_PushEvent(&pushed);
  }
  return FALSE;
}

static gboolean clear_keys(GtkWidget *widget, GdkEventFocus *event, gpointer data) {
  (void)widget; (void)event; (void)data;
  SDL_memset(key_state, 0, sizeof key_state);
  return FALSE;
}

void *swanium_linux_menu_build(const char *title, int volume, int initial_scale, int width, int height) {
  if (window && game_area) {
    GdkWindow *native = gtk_widget_get_window(game_area);
    return native ? (void *)(uintptr_t)gdk_x11_window_get_xid(native) : NULL;
  }
  error_text[0] = '\0';
  display_scale = CLAMP(initial_scale, 1, 4);
  frame_width = MAX(1, width);
  frame_height = MAX(1, height);
  if (!gtk_init_check(NULL, NULL)) {
    g_strlcpy(error_text, "GTK3 could not initialize an X11 display; use an X11 session or XWayland", sizeof error_text);
    return NULL;
  }
  if (!GDK_IS_X11_DISPLAY(gdk_display_get_default())) {
    g_strlcpy(error_text, "GTK3 is not using its X11 backend; native Wayland is not supported yet", sizeof error_text);
    return NULL;
  }
  window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_window_set_wmclass(GTK_WINDOW(window), "swanium-crystal", "Swanium-crystal");
  G_GNUC_END_IGNORE_DEPRECATIONS
  g_free(present_title);
  present_title = g_strdup(title);
  gtk_window_set_title(GTK_WINDOW(window), "Swanium Crystal — Starting");
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window), NULL);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(clear_keys), NULL);
  GtkAccelGroup *accelerators = gtk_accel_group_new();
  gtk_window_add_accel_group(GTK_WINDOW(window), accelerators);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(GTK_CONTAINER(window), box);
  GtkWidget *bar = gtk_menu_bar_new(); gtk_box_pack_start(GTK_BOX(box), bar, FALSE, FALSE, 0);
  GtkWidget *file = gtk_menu_new(), *file_root = gtk_menu_item_new_with_label("File");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(file_root), file); gtk_menu_shell_append(GTK_MENU_SHELL(bar), file_root);
  GtkWidget *open_item = menu_item(file, "Open ROM…", OPEN_ROM); add_accelerator(open_item, accelerators, GDK_KEY_o, GDK_CONTROL_MASK);
  recent_menu = gtk_menu_new(); GtkWidget *recent_root = gtk_menu_item_new_with_label("Open Recent"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(recent_root), recent_menu); gtk_menu_shell_append(GTK_MENU_SHELL(file), recent_root);
  GtkWidget *save = gtk_menu_new(), *save_root = gtk_menu_item_new_with_label("Save State"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(save_root), save); gtk_menu_shell_append(GTK_MENU_SHELL(file), save_root);
  GtkWidget *load = gtk_menu_new(); load_root = gtk_menu_item_new_with_label("Load State"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(load_root), load); gtk_menu_shell_append(GTK_MENU_SHELL(file), load_root);
  for (int i = 0; i < 10; i++) { char save_label[24], load_label[24]; g_snprintf(save_label, sizeof save_label, "Slot %d", i); g_snprintf(load_label, sizeof load_label, "Slot %d", i); save_items[i] = menu_item(save, save_label, SAVE_STATE_BASE + i); load_items[i] = menu_item(load, load_label, LOAD_STATE_BASE + i); gtk_widget_set_sensitive(load_items[i], FALSE); }
  add_accelerator(save_items[0], accelerators, GDK_KEY_s, GDK_CONTROL_MASK);
  add_accelerator(load_items[0], accelerators, GDK_KEY_l, GDK_CONTROL_MASK);
  GtkWidget *settings_item = menu_item(file, "Settings…", SETTINGS); add_accelerator(settings_item, accelerators, GDK_KEY_comma, GDK_CONTROL_MASK);
  GtkWidget *quit_item = menu_item(file, "Quit", QUIT); add_accelerator(quit_item, accelerators, GDK_KEY_q, GDK_CONTROL_MASK);
  GtkWidget *emu = gtk_menu_new(), *emu_root = gtk_menu_item_new_with_label("Emulation");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(emu_root), emu); gtk_menu_shell_append(GTK_MENU_SHELL(bar), emu_root);
  pause_item = menu_item(emu, "Pause", PAUSE); add_accelerator(pause_item, accelerators, GDK_KEY_p, GDK_CONTROL_MASK);
  GtkWidget *reset_item = menu_item(emu, "Reset", RESET); add_accelerator(reset_item, accelerators, GDK_KEY_r, GDK_CONTROL_MASK);
  GtkWidget *view = gtk_menu_new(), *view_root = gtk_menu_item_new_with_label("View");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(view_root), view); gtk_menu_shell_append(GTK_MENU_SHELL(bar), view_root);
  GtkWidget *scale = gtk_menu_new(), *scale_root = gtk_menu_item_new_with_label("Scale"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(scale_root), scale); gtk_menu_shell_append(GTK_MENU_SHELL(view), scale_root);
  GSList *scale_group = NULL;
  for (int i = 0; i < 4; i++) { char label[16]; g_snprintf(label, sizeof label, "%dx", i + 1); scale_items[i] = gtk_radio_menu_item_new_with_label(scale_group, label); scale_group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(scale_items[i])); g_signal_connect(scale_items[i], "activate", G_CALLBACK(activate), GINT_TO_POINTER(SCALE_1 + i)); gtk_menu_shell_append(GTK_MENU_SHELL(scale), scale_items[i]); add_accelerator(scale_items[i], accelerators, GDK_KEY_1 + i, GDK_CONTROL_MASK); }
  fullscreen_item = gtk_check_menu_item_new_with_label("Fullscreen"); g_signal_connect(fullscreen_item, "activate", G_CALLBACK(activate), GINT_TO_POINTER(FULLSCREEN)); gtk_menu_shell_append(GTK_MENU_SHELL(view), fullscreen_item);
  add_accelerator(fullscreen_item, accelerators, GDK_KEY_F11, 0);
  GtkWidget *renderer = gtk_menu_new(), *renderer_root = gtk_menu_item_new_with_label("Renderer"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(renderer_root), renderer); gtk_menu_shell_append(GTK_MENU_SHELL(view), renderer_root);
  GSList *renderer_group = NULL;
  renderer_items[0] = gtk_radio_menu_item_new_with_label(renderer_group, "Nearest Neighbor"); renderer_group = gtk_radio_menu_item_get_group(GTK_RADIO_MENU_ITEM(renderer_items[0]));
  renderer_items[1] = gtk_radio_menu_item_new_with_label(renderer_group, "Bilinear");
  for (int i = 0; i < 2; i++) { g_signal_connect(renderer_items[i], "activate", G_CALLBACK(activate), GINT_TO_POINTER(RENDER_NEAREST + i)); gtk_menu_shell_append(GTK_MENU_SHELL(renderer), renderer_items[i]); }
  GtkWidget *help = gtk_menu_new(), *help_root = gtk_menu_item_new_with_label("Help");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(help_root), help); gtk_menu_shell_append(GTK_MENU_SHELL(bar), help_root);
  menu_item(help, "About Swanium Crystal", ABOUT);
  game_area = gtk_drawing_area_new();
  gtk_widget_set_size_request(game_area, frame_width * display_scale, frame_height * display_scale);
  gtk_widget_set_can_focus(game_area, TRUE);
  g_signal_connect(game_area, "key-press-event", G_CALLBACK(game_key_event), NULL);
  g_signal_connect(game_area, "key-release-event", G_CALLBACK(game_key_event), NULL);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_widget_set_double_buffered(game_area, FALSE);
  G_GNUC_END_IGNORE_DEPRECATIONS
  gtk_box_pack_start(GTK_BOX(box), game_area, TRUE, TRUE, 0);

  GtkWidget *separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_box_pack_start(GTK_BOX(box), separator, FALSE, FALSE, 0);
  GtkWidget *status_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  GtkStyleContext *status_style = gtk_widget_get_style_context(status_bar);
  gtk_style_context_add_class(status_style, GTK_STYLE_CLASS_STATUSBAR);
  gtk_widget_set_margin_start(status_bar, 8);
  gtk_widget_set_margin_end(status_bar, 8);
  gtk_widget_set_margin_top(status_bar, 4);
  gtk_widget_set_margin_bottom(status_bar, 4);
  status_label = gtk_label_new("Starting…");
  gtk_widget_set_halign(status_label, GTK_ALIGN_START);
  gtk_label_set_ellipsize(GTK_LABEL(status_label), PANGO_ELLIPSIZE_MIDDLE);
  gtk_box_pack_start(GTK_BOX(status_bar), status_label, TRUE, TRUE, 0);
  volume_slider = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
  gtk_scale_set_draw_value(GTK_SCALE(volume_slider), FALSE);
  gtk_widget_set_size_request(volume_slider, 96, -1);
  gtk_range_set_value(GTK_RANGE(volume_slider), volume);
  gtk_box_pack_end(GTK_BOX(status_bar), volume_slider, FALSE, FALSE, 0);
  GtkWidget *speaker = gtk_image_new_from_icon_name("audio-volume-high-symbolic", GTK_ICON_SIZE_MENU);
  gtk_box_pack_end(GTK_BOX(status_bar), speaker, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), status_bar, FALSE, FALSE, 0);
  gtk_widget_show_all(window);
  while (gtk_events_pending()) gtk_main_iteration();
  if (!gtk_widget_get_realized(game_area) || !gtk_widget_get_window(game_area)) {
    g_strlcpy(error_text, "GTK3 did not realize the game drawing area", sizeof error_text);
    gtk_widget_destroy(window); window = game_area = NULL;
    return NULL;
  }
  gtk_widget_grab_focus(game_area);
  syncing_menu = TRUE;
  gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(scale_items[display_scale - 1]), TRUE);
  gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(renderer_items[0]), TRUE);
  syncing_menu = FALSE;
  return (void *)(uintptr_t)gdk_x11_window_get_xid(gtk_widget_get_window(game_area));
}
const char *swanium_linux_menu_error_text(void) { return error_text; }
void swanium_linux_menu_present(void) {
  if (!window) return;
  gtk_window_set_title(GTK_WINDOW(window), present_title ? present_title : "Swanium Crystal");
  gtk_window_present(GTK_WINDOW(window));
  if (game_area) gtk_widget_grab_focus(game_area);
  while (gtk_events_pending()) gtk_main_iteration();
  gdk_display_flush(gdk_display_get_default());
}
void swanium_linux_menu_pump(void) { while (gtk_events_pending()) gtk_main_iteration(); }
int swanium_linux_menu_take_action(void) { int result = action; action = 0; return result; }
char *swanium_linux_menu_open_rom(void) { GtkWidget *dialog = gtk_file_chooser_dialog_new("Open ROM", GTK_WINDOW(window), GTK_FILE_CHOOSER_ACTION_OPEN, "Cancel", GTK_RESPONSE_CANCEL, "Open", GTK_RESPONSE_ACCEPT, NULL); if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) { g_free(opened_path); opened_path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog)); } gtk_widget_destroy(dialog); if (game_area) gtk_widget_grab_focus(game_area); return opened_path; }
void swanium_linux_menu_status(const char *text) { if (status_label) gtk_label_set_text(GTK_LABEL(status_label), text); }
void swanium_linux_menu_state_slots(const char **labels, const int *available) { gboolean any = FALSE; for (int i = 0; i < 10; i++) { gtk_menu_item_set_label(GTK_MENU_ITEM(save_items[i]), labels[i]); gtk_menu_item_set_label(GTK_MENU_ITEM(load_items[i]), labels[i]); gtk_widget_set_sensitive(load_items[i], available[i]); any |= available[i]; } gtk_widget_set_sensitive(load_root, any); }
void swanium_linux_menu_recent(const char **paths) { GList *children = gtk_container_get_children(GTK_CONTAINER(recent_menu)); for (GList *item = children; item; item = item->next) gtk_widget_destroy(GTK_WIDGET(item->data)); g_list_free(children); for (int i = 0; i < 10; i++) { g_free(recent_paths[i]); recent_paths[i] = NULL; } int count = 0; for (; paths && paths[count] && count < 10; count++) { recent_paths[count] = g_strdup(paths[count]); char *name = g_path_get_basename(paths[count]); menu_item(recent_menu, name, RECENT_BASE + count); g_free(name); } if (!count) { GtkWidget *empty = gtk_menu_item_new_with_label("No Recent ROMs"); gtk_widget_set_sensitive(empty, FALSE); gtk_menu_shell_append(GTK_MENU_SHELL(recent_menu), empty); } else menu_item(recent_menu, "Clear History", CLEAR_RECENT); gtk_widget_show_all(recent_menu); }
const char *swanium_linux_menu_recent_path(int index) { return index >= 0 && index < 10 ? recent_paths[index] : NULL; }
void swanium_linux_menu_resize_game(int width, int height, int scale) { frame_width = MAX(1, width); frame_height = MAX(1, height); display_scale = CLAMP(scale, 1, 4); resize_for_frame(); }
void swanium_linux_menu_fullscreen(int enabled) { if (enabled) gtk_window_fullscreen(GTK_WINDOW(window)); else gtk_window_unfullscreen(GTK_WINDOW(window)); }
void swanium_linux_menu_state(int paused, int scale, int fullscreen, int renderer) { syncing_menu = TRUE; gtk_menu_item_set_label(GTK_MENU_ITEM(pause_item), paused ? "Resume" : "Pause"); gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(scale_items[CLAMP(scale, 1, 4) - 1]), TRUE); gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(fullscreen_item), fullscreen != 0); gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(renderer_items[CLAMP(renderer, 0, 1)]), TRUE); syncing_menu = FALSE; }
int swanium_linux_menu_volume(void) { return volume_slider ? (int)gtk_range_get_value(GTK_RANGE(volume_slider)) : 100; }
int swanium_linux_menu_key_state(int scancode) { return scancode >= 0 && scancode < SDL_NUM_SCANCODES ? key_state[scancode] : 0; }
void swanium_linux_menu_error(const char *text) { GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", text); gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog); }
void swanium_linux_menu_about(void) { GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "Swanium Crystal\nWonderSwan and WonderSwan Color emulator.\n\nVersion 1.0.0\nLicensed under the MIT License."); gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog); }
static gboolean settings_key_pressed(GtkWidget *widget, GdkEventKey *event, gpointer data) {
  (void)widget; (void)data;
  if (keyboard_capture < 0) return FALSE;
  SDL_Keycode keycode;
  switch (event->keyval) {
    case GDK_KEY_Up: keycode = SDLK_UP; break; case GDK_KEY_Right: keycode = SDLK_RIGHT; break;
    case GDK_KEY_Down: keycode = SDLK_DOWN; break; case GDK_KEY_Left: keycode = SDLK_LEFT; break;
    case GDK_KEY_Return: keycode = SDLK_RETURN; break; case GDK_KEY_Escape: keycode = SDLK_ESCAPE; break;
    case GDK_KEY_space: keycode = SDLK_SPACE; break;
    default: {
      gunichar unicode = gdk_keyval_to_unicode(event->keyval);
      if (!unicode) return FALSE;
      keycode = (SDL_Keycode)g_unichar_tolower(unicode);
    }
  }
  SDL_Scancode scancode = SDL_GetScancodeFromKey(keycode);
  if (scancode == SDL_SCANCODE_UNKNOWN) return FALSE;
  action = 7000 + (int)scancode;
  keyboard_capture = -1;
  return TRUE;
}

static gboolean close_settings(GtkWidget *widget, GdkEvent *event, gpointer data) {
  (void)widget; (void)event; (void)data;
  action = 531;
  keyboard_capture = -1;
  return FALSE;
}

static void finish_settings(GtkWidget *widget, gpointer data) {
  (void)widget;
  action = GPOINTER_TO_INT(data);
  keyboard_capture = -1;
  if (settings_window) gtk_widget_destroy(settings_window);
}

static void settings_destroyed(GtkWidget *widget, gpointer data) {
  (void)widget; (void)data;
  settings_window = NULL;
  if (game_area) gtk_widget_grab_focus(game_area);
}

static GtkWidget *settings_grid(void) {
  GtkWidget *grid = gtk_grid_new();
  gtk_grid_set_column_spacing(GTK_GRID(grid), 16);
  gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
  gtk_widget_set_margin_start(grid, 20);
  gtk_widget_set_margin_end(grid, 20);
  gtk_widget_set_margin_top(grid, 20);
  gtk_widget_set_margin_bottom(grid, 20);
  return grid;
}

static GtkWidget *settings_label(const char *text) {
  GtkWidget *label = gtk_label_new(text);
  gtk_widget_set_halign(label, GTK_ALIGN_END);
  gtk_widget_set_valign(label, GTK_ALIGN_CENTER);
  return label;
}

void swanium_linux_menu_settings(void) {
  if (settings_window) {
    gtk_window_present(GTK_WINDOW(settings_window));
    return;
  }
  settings_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(settings_window), "Swanium Crystal Settings");
  gtk_window_set_default_size(GTK_WINDOW(settings_window), 480, 520);
  gtk_window_set_transient_for(GTK_WINDOW(settings_window), GTK_WINDOW(window));
  gtk_window_set_destroy_with_parent(GTK_WINDOW(settings_window), TRUE);
  gtk_window_set_position(GTK_WINDOW(settings_window), GTK_WIN_POS_CENTER_ON_PARENT);
  gtk_window_set_type_hint(GTK_WINDOW(settings_window), GDK_WINDOW_TYPE_HINT_DIALOG);
  g_signal_connect(settings_window, "destroy", G_CALLBACK(settings_destroyed), NULL);
  g_signal_connect(settings_window, "delete-event", G_CALLBACK(close_settings), NULL);
  g_signal_connect(settings_window, "key-press-event", G_CALLBACK(settings_key_pressed), NULL);

  GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(GTK_CONTAINER(settings_window), root);
  GtkWidget *tabs = gtk_notebook_new();
  gtk_container_set_border_width(GTK_CONTAINER(tabs), 12);
  gtk_box_pack_start(GTK_BOX(root), tabs, TRUE, TRUE, 0);

  GtkWidget *keyboard_scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(keyboard_scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  GtkWidget *keyboard = settings_grid();
  const char *keys[] = {"X Pad Up", "X Pad Right", "X Pad Down", "X Pad Left", "Y Pad Up", "Y Pad Right", "Y Pad Down", "Y Pad Left", "A Button", "B Button", "Start"};
  for (int i = 0; i < 11; i++) {
    gtk_grid_attach(GTK_GRID(keyboard), settings_label(keys[i]), 0, i, 1, 1);
    keyboard_buttons[i] = gtk_button_new_with_label("Press a key…");
    gtk_widget_set_size_request(keyboard_buttons[i], 200, 30);
    gtk_widget_set_hexpand(keyboard_buttons[i], TRUE);
    g_signal_connect(keyboard_buttons[i], "clicked", G_CALLBACK(activate), GINT_TO_POINTER(400 + i));
    gtk_grid_attach(GTK_GRID(keyboard), keyboard_buttons[i], 1, i, 1, 1);
  }
  GtkWidget *key_reset = gtk_button_new_with_label("Restore Defaults");
  gtk_widget_set_margin_top(key_reset, 8);
  g_signal_connect(key_reset, "clicked", G_CALLBACK(activate), GINT_TO_POINTER(420));
  gtk_grid_attach(GTK_GRID(keyboard), key_reset, 1, 11, 1, 1);
  gtk_container_add(GTK_CONTAINER(keyboard_scroll), keyboard);
  gtk_notebook_append_page(GTK_NOTEBOOK(tabs), keyboard_scroll, gtk_label_new("Keyboard"));

  GtkWidget *controller = settings_grid();
  const char *dirs[] = {"D-pad", "Left stick", "Right stick"};
  for (int i = 0; i < 3; i++) {
    gtk_grid_attach(GTK_GRID(controller), settings_label(dirs[i]), 0, i, 1, 1);
    direction_boxes[i] = gtk_combo_box_text_new();
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(direction_boxes[i]), "Disabled");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(direction_boxes[i]), "X Pad");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(direction_boxes[i]), "Y Pad");
    gtk_widget_set_size_request(direction_boxes[i], 200, 30);
    gtk_widget_set_hexpand(direction_boxes[i], TRUE);
    g_signal_connect(direction_boxes[i], "changed", G_CALLBACK(direction_changed), GINT_TO_POINTER(i));
    gtk_grid_attach(GTK_GRID(controller), direction_boxes[i], 1, i, 1, 1);
  }
  GtkWidget *group_separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_set_margin_top(group_separator, 8);
  gtk_widget_set_margin_bottom(group_separator, 8);
  gtk_grid_attach(GTK_GRID(controller), group_separator, 0, 3, 2, 1);
  const char *buttons[] = {"A Button", "B Button", "Start"};
  for (int i = 0; i < 3; i++) {
    gtk_grid_attach(GTK_GRID(controller), settings_label(buttons[i]), 0, i + 4, 1, 1);
    controller_buttons[i] = gtk_button_new_with_label("Press a button…");
    gtk_widget_set_size_request(controller_buttons[i], 200, 30);
    gtk_widget_set_hexpand(controller_buttons[i], TRUE);
    g_signal_connect(controller_buttons[i], "clicked", G_CALLBACK(activate), GINT_TO_POINTER(500 + i));
    gtk_grid_attach(GTK_GRID(controller), controller_buttons[i], 1, i + 4, 1, 1);
  }
  GtkWidget *pad_reset = gtk_button_new_with_label("Restore Defaults");
  gtk_widget_set_margin_top(pad_reset, 8);
  g_signal_connect(pad_reset, "clicked", G_CALLBACK(activate), GINT_TO_POINTER(520));
  gtk_grid_attach(GTK_GRID(controller), pad_reset, 1, 7, 1, 1);
  gtk_notebook_append_page(GTK_NOTEBOOK(tabs), controller, gtk_label_new("Controller"));
  GtkWidget *action_buttons = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_button_box_set_layout(GTK_BUTTON_BOX(action_buttons), GTK_BUTTONBOX_END);
  gtk_box_set_spacing(GTK_BOX(action_buttons), 8);
  gtk_widget_set_margin_start(action_buttons, 12); gtk_widget_set_margin_end(action_buttons, 12); gtk_widget_set_margin_bottom(action_buttons, 12);
  GtkWidget *cancel = gtk_button_new_with_label("Cancel"); g_signal_connect(cancel, "clicked", G_CALLBACK(finish_settings), GINT_TO_POINTER(531));
  GtkWidget *apply = gtk_button_new_with_label("Apply"); g_signal_connect(apply, "clicked", G_CALLBACK(finish_settings), GINT_TO_POINTER(530));
  gtk_container_add(GTK_CONTAINER(action_buttons), cancel); gtk_container_add(GTK_CONTAINER(action_buttons), apply);
  gtk_box_pack_end(GTK_BOX(root), action_buttons, FALSE, FALSE, 0);
  gtk_widget_show_all(settings_window);
}
void swanium_linux_menu_smoke_open_settings(void) { action = SETTINGS; }
int swanium_linux_menu_smoke_settings_visible(void) { return settings_window && gtk_widget_get_visible(settings_window); }
void swanium_linux_menu_smoke_finish_settings(int apply) {
  if (!settings_window) return;
  action = apply ? 530 : 531;
  keyboard_capture = -1;
  gtk_widget_destroy(settings_window);
}
int swanium_linux_menu_smoke_direction(int index) {
  return settings_window && index >= 0 && index < 3 ? gtk_combo_box_get_active(GTK_COMBO_BOX(direction_boxes[index])) : -1;
}
void swanium_linux_menu_smoke_set_direction(int index, int destination) {
  if (settings_window && index >= 0 && index < 3)
    gtk_combo_box_set_active(GTK_COMBO_BOX(direction_boxes[index]), CLAMP(destination, 0, 2));
}
void swanium_linux_menu_settings_sync(const char **keyboard, const char **buttons, const int *directions) { if (!settings_window) return; syncing_menu = TRUE; for(int i=0;i<11;i++) gtk_button_set_label(GTK_BUTTON(keyboard_buttons[i]), keyboard[i]); for(int i=0;i<3;i++){ gtk_button_set_label(GTK_BUTTON(controller_buttons[i]),buttons[i]); gtk_combo_box_set_active(GTK_COMBO_BOX(direction_boxes[i]),directions[i]); } syncing_menu = FALSE; }
void swanium_linux_menu_destroy(void) { if (window) gtk_widget_destroy(window); window = status_label = volume_slider = game_area = NULL; settings_window = NULL; SDL_memset(key_state, 0, sizeof key_state); g_clear_pointer(&opened_path, g_free); g_clear_pointer(&present_title, g_free); }
