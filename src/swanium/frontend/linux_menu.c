#include <gtk/gtk.h>

static GtkWidget *window, *status_label, *volume_slider, *game_area, *recent_menu, *load_root;
static GtkWidget *save_items[10], *load_items[10];
static GtkWidget *settings_window, *keyboard_buttons[11], *controller_buttons[3], *direction_boxes[3];
static int action;
static char *opened_path;
static char *recent_paths[10];
static guint8 *frame; static int frame_width, frame_height, display_scale = 3;

enum { OPEN_ROM = 1, PAUSE = 4, RESET = 5, SCALE_1 = 11, FULLSCREEN = 20,
       RENDER_NEAREST = 31, RENDER_LINEAR = 32, ABOUT = 41, SETTINGS = 42,
       QUIT = 43, SAVE_STATE_BASE = 100, LOAD_STATE_BASE = 200, RECENT_BASE = 300, CLEAR_RECENT = 310 };

static void activate(GtkWidget *item, gpointer data) { action = GPOINTER_TO_INT(data); }
static gboolean close_window(GtkWidget *widget, GdkEvent *event, gpointer data) { action = QUIT; return TRUE; }
static void set_volume(GtkRange *range, gpointer data) { (void)data; }
static void direction_changed(GtkComboBox *box, gpointer data) { action = 6000 + GPOINTER_TO_INT(data) * 10 + gtk_combo_box_get_active(box); }

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

static gboolean draw_game(GtkWidget *widget, cairo_t *cr, gpointer data) {
  (void)widget; (void)data;
  if (!frame) return FALSE;
  cairo_surface_t *surface = cairo_image_surface_create_for_data(frame, CAIRO_FORMAT_RGB24, frame_width, frame_height, frame_width * 4);
  GtkAllocation allocation; gtk_widget_get_allocation(widget, &allocation);
  int scale = MAX(1, MIN(allocation.width / frame_width, allocation.height / frame_height));
  double x = (allocation.width - frame_width * scale) / 2.0, y = (allocation.height - frame_height * scale) / 2.0;
  cairo_translate(cr, x, y); cairo_scale(cr, scale, scale);
  cairo_set_source_surface(cr, surface, 0, 0); cairo_paint(cr); cairo_surface_destroy(surface);
  return FALSE;
}

static GtkWidget *menu_item(GtkWidget *menu, const char *title, int id) {
  GtkWidget *item = gtk_menu_item_new_with_label(title);
  g_signal_connect(item, "activate", G_CALLBACK(activate), GINT_TO_POINTER(id));
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  return item;
}

void swanium_linux_menu_build(const char *title, int volume, int initial_scale) {
  if (window) return;
  display_scale = CLAMP(initial_scale, 1, 4);
  gtk_init(NULL, NULL);
  window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), title);
  gtk_window_set_default_size(GTK_WINDOW(window), 672, 500);
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window), NULL);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(GTK_CONTAINER(window), box);
  GtkWidget *bar = gtk_menu_bar_new(); gtk_box_pack_start(GTK_BOX(box), bar, FALSE, FALSE, 0);
  GtkWidget *file = gtk_menu_new(), *file_root = gtk_menu_item_new_with_label("File");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(file_root), file); gtk_menu_shell_append(GTK_MENU_SHELL(bar), file_root);
  menu_item(file, "Open ROM…", OPEN_ROM);
  recent_menu = gtk_menu_new(); GtkWidget *recent_root = gtk_menu_item_new_with_label("Open Recent"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(recent_root), recent_menu); gtk_menu_shell_append(GTK_MENU_SHELL(file), recent_root);
  GtkWidget *save = gtk_menu_new(), *save_root = gtk_menu_item_new_with_label("Save State"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(save_root), save); gtk_menu_shell_append(GTK_MENU_SHELL(file), save_root);
  GtkWidget *load = gtk_menu_new(); load_root = gtk_menu_item_new_with_label("Load State"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(load_root), load); gtk_menu_shell_append(GTK_MENU_SHELL(file), load_root);
  for (int i = 0; i < 10; i++) { char save_label[24], load_label[24]; g_snprintf(save_label, sizeof save_label, "Slot %d", i); g_snprintf(load_label, sizeof load_label, "Slot %d", i); save_items[i] = menu_item(save, save_label, SAVE_STATE_BASE + i); load_items[i] = menu_item(load, load_label, LOAD_STATE_BASE + i); gtk_widget_set_sensitive(load_items[i], FALSE); }
  menu_item(file, "Settings…", SETTINGS); menu_item(file, "Quit", QUIT);
  GtkWidget *emu = gtk_menu_new(), *emu_root = gtk_menu_item_new_with_label("Emulation");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(emu_root), emu); gtk_menu_shell_append(GTK_MENU_SHELL(bar), emu_root);
  menu_item(emu, "Pause / Resume", PAUSE); menu_item(emu, "Reset", RESET);
  GtkWidget *view = gtk_menu_new(), *view_root = gtk_menu_item_new_with_label("View");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(view_root), view); gtk_menu_shell_append(GTK_MENU_SHELL(bar), view_root);
  GtkWidget *scale = gtk_menu_new(), *scale_root = gtk_menu_item_new_with_label("Scale"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(scale_root), scale); gtk_menu_shell_append(GTK_MENU_SHELL(view), scale_root);
  for (int i = 0; i < 4; i++) { char label[16]; g_snprintf(label, sizeof label, "%dx", i + 1); menu_item(scale, label, SCALE_1 + i); }
  menu_item(view, "Fullscreen", FULLSCREEN);
  GtkWidget *renderer = gtk_menu_new(), *renderer_root = gtk_menu_item_new_with_label("Renderer"); gtk_menu_item_set_submenu(GTK_MENU_ITEM(renderer_root), renderer); gtk_menu_shell_append(GTK_MENU_SHELL(view), renderer_root);
  menu_item(renderer, "Nearest Neighbor", RENDER_NEAREST); menu_item(renderer, "Bilinear", RENDER_LINEAR);
  GtkWidget *help = gtk_menu_new(), *help_root = gtk_menu_item_new_with_label("Help");
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(help_root), help); gtk_menu_shell_append(GTK_MENU_SHELL(bar), help_root);
  menu_item(help, "About Swanium Crystal", ABOUT);
  game_area = gtk_drawing_area_new();
  gtk_widget_set_size_request(game_area, 672, 432);
  g_signal_connect(game_area, "draw", G_CALLBACK(draw_game), NULL);
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
  g_signal_connect(volume_slider, "value-changed", G_CALLBACK(set_volume), NULL);
  gtk_box_pack_end(GTK_BOX(status_bar), volume_slider, FALSE, FALSE, 0);
  GtkWidget *speaker = gtk_image_new_from_icon_name("audio-volume-high-symbolic", GTK_ICON_SIZE_MENU);
  gtk_box_pack_end(GTK_BOX(status_bar), speaker, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), status_bar, FALSE, FALSE, 0);
  gtk_widget_show_all(window);
}
void swanium_linux_menu_pump(void) { while (gtk_events_pending()) gtk_main_iteration(); }
int swanium_linux_menu_take_action(void) { int result = action; action = 0; return result; }
char *swanium_linux_menu_open_rom(void) { GtkWidget *dialog = gtk_file_chooser_dialog_new("Open ROM", GTK_WINDOW(window), GTK_FILE_CHOOSER_ACTION_OPEN, "Cancel", GTK_RESPONSE_CANCEL, "Open", GTK_RESPONSE_ACCEPT, NULL); if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) { g_free(opened_path); opened_path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog)); } gtk_widget_destroy(dialog); return opened_path; }
void swanium_linux_menu_status(const char *text) { if (status_label) gtk_label_set_text(GTK_LABEL(status_label), text); }
void swanium_linux_menu_state_slots(const char **labels, const int *available) { gboolean any = FALSE; for (int i = 0; i < 10; i++) { gtk_menu_item_set_label(GTK_MENU_ITEM(save_items[i]), labels[i]); gtk_menu_item_set_label(GTK_MENU_ITEM(load_items[i]), labels[i]); gtk_widget_set_sensitive(load_items[i], available[i]); any |= available[i]; } gtk_widget_set_sensitive(load_root, any); }
void swanium_linux_menu_recent(const char **paths) { GList *children = gtk_container_get_children(GTK_CONTAINER(recent_menu)); for (GList *item = children; item; item = item->next) gtk_widget_destroy(GTK_WIDGET(item->data)); g_list_free(children); for (int i = 0; i < 10; i++) { g_free(recent_paths[i]); recent_paths[i] = NULL; } int count = 0; for (; paths && paths[count] && count < 10; count++) { recent_paths[count] = g_strdup(paths[count]); char *name = g_path_get_basename(paths[count]); menu_item(recent_menu, name, RECENT_BASE + count); g_free(name); } if (!count) { GtkWidget *empty = gtk_menu_item_new_with_label("No Recent ROMs"); gtk_widget_set_sensitive(empty, FALSE); gtk_menu_shell_append(GTK_MENU_SHELL(recent_menu), empty); } else menu_item(recent_menu, "Clear History", CLEAR_RECENT); gtk_widget_show_all(recent_menu); }
const char *swanium_linux_menu_recent_path(int index) { return index >= 0 && index < 10 ? recent_paths[index] : NULL; }
void swanium_linux_menu_present(const unsigned char *pixels, int width, int height) { if (!pixels || width <= 0 || height <= 0) return; size_t size = (size_t)width * height * 4; if (width != frame_width || height != frame_height) { g_free(frame); frame = g_malloc(size); frame_width = width; frame_height = height; resize_for_frame(); } for (size_t i = 0; i < size; i += 4) { frame[i] = pixels[i + 2]; frame[i + 1] = pixels[i + 1]; frame[i + 2] = pixels[i]; frame[i + 3] = 0; } gtk_widget_queue_draw(game_area); }
void swanium_linux_menu_scale(int scale) { display_scale = CLAMP(scale, 1, 4); resize_for_frame(); }
void swanium_linux_menu_fullscreen(int enabled) { if (enabled) gtk_window_fullscreen(GTK_WINDOW(window)); else gtk_window_unfullscreen(GTK_WINDOW(window)); }
int swanium_linux_menu_volume(void) { return volume_slider ? (int)gtk_range_get_value(GTK_RANGE(volume_slider)) : 100; }
void swanium_linux_menu_error(const char *text) { GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", text); gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog); }
void swanium_linux_menu_about(void) { GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "Swanium Crystal\nWonderSwan and WonderSwan Color emulator.\n\nVersion 1.0.0\nLicensed under the MIT License."); gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog); }
static void settings_destroyed(GtkWidget *widget, gpointer data) {
  (void)widget; (void)data;
  settings_window = NULL;
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

  GtkWidget *tabs = gtk_notebook_new();
  gtk_container_set_border_width(GTK_CONTAINER(tabs), 12);
  gtk_container_add(GTK_CONTAINER(settings_window), tabs);

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
  gtk_widget_show_all(settings_window);
}
void swanium_linux_menu_settings_sync(const char **keyboard, const char **buttons, const int *directions) { if (!settings_window) return; for(int i=0;i<11;i++) gtk_button_set_label(GTK_BUTTON(keyboard_buttons[i]), keyboard[i]); for(int i=0;i<3;i++){ gtk_button_set_label(GTK_BUTTON(controller_buttons[i]),buttons[i]); gtk_combo_box_set_active(GTK_COMBO_BOX(direction_boxes[i]),directions[i]); } }
void swanium_linux_menu_destroy(void) { if (window) gtk_widget_destroy(window); window = status_label = volume_slider = game_area = NULL; g_clear_pointer(&opened_path, g_free); g_clear_pointer(&frame, g_free); }
