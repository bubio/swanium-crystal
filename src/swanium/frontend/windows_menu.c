#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>
#include <commctrl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL.h>

enum { OPEN_ROM = 1, PAUSE = 4, RESET = 5, SCALE_1 = 11, FULLSCREEN = 20,
       RENDER_NEAREST = 31, RENDER_LINEAR = 32, ABOUT = 41, SETTINGS = 42,
       QUIT = 43, SAVE_STATE_BASE = 100, LOAD_STATE_BASE = 200,
       RECENT_BASE = 300, CLEAR_RECENT = 310 };

static HWND window_handle;
static HMENU menu_bar, recent_menu, save_menu, load_menu, emulation_menu, view_menu;
static int action, current_volume = 100;
static int last_taken_action;
static char *opened_path;
static char *recent_paths[10];
static char *keyboard_names[11], *button_names[3];
static int direction_values[3] = {1, 1, 2};
static HWND settings_window, settings_tabs, keyboard_page, controller_page;
static HWND keyboard_buttons[11], controller_buttons[3], direction_boxes[3];
static HWND status_bar, volume_label, volume_slider;
static int current_status_height;
static int status_layout_pending;
static int last_client_width = -1, last_client_height = -1;
static HFONT volume_icon_font;
static int native_keyboard_capture = -1;
static int last_paused = -1, last_scale = -1, last_fullscreen = -1, last_renderer = -1;
static char last_status_title[512], last_status_fps[64];

void swanium_windows_menu_state(int paused, int scale, int fullscreen, int renderer);

static wchar_t *utf8_to_wide(const char *value) {
  if (!value) return NULL;
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
  if (!count) return NULL;
  wchar_t *result = (wchar_t *)calloc((size_t)count, sizeof(wchar_t));
  if (result) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, count);
  return result;
}

static char *wide_to_utf8(const wchar_t *value) {
  int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (!count) return NULL;
  char *result = (char *)calloc((size_t)count, 1);
  if (result) WideCharToMultiByte(CP_UTF8, 0, value, -1, result, count, NULL, NULL);
  return result;
}

static char *copy_text(const char *value) {
  size_t length = value ? strlen(value) : 0;
  char *result = (char *)malloc(length + 1);
  if (result) memcpy(result, value ? value : "", length + 1);
  return result;
}

static void append(HMENU menu, UINT flags, UINT_PTR id, const wchar_t *label) {
  AppendMenuW(menu, flags, id, label);
}

static void restore_game_focus(void) {
  if (!window_handle || !IsWindow(window_handle)) return;
  SetActiveWindow(window_handle);
  SetFocus(window_handle);
}

static void handle_command(UINT id) {
  if (id == OPEN_ROM) {
    wchar_t path[32768] = L"";
    OPENFILENAMEW dialog;
    ZeroMemory(&dialog, sizeof(dialog));
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = window_handle;
    dialog.lpstrFilter = L"WonderSwan ROM (*.ws;*.wsc)\0*.ws;*.wsc\0All files (*.*)\0*.*\0\0";
    dialog.lpstrFile = path;
    dialog.nMaxFile = (DWORD)(sizeof(path) / sizeof(path[0]));
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (GetOpenFileNameW(&dialog)) {
      free(opened_path);
      opened_path = wide_to_utf8(path);
      action = OPEN_ROM;
    }
    restore_game_focus();
    return;
  }
  action = (int)id;
}

static LRESULT CALLBACK settings_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_KEYDOWN && native_keyboard_capture >= 0) {
    SDL_Scancode scancode = SDL_SCANCODE_UNKNOWN;
    UINT key = (UINT)wparam;
    switch (key) {
      case VK_UP: scancode = SDL_SCANCODE_UP; break; case VK_RIGHT: scancode = SDL_SCANCODE_RIGHT; break;
      case VK_DOWN: scancode = SDL_SCANCODE_DOWN; break; case VK_LEFT: scancode = SDL_SCANCODE_LEFT; break;
      case VK_RETURN: scancode = SDL_SCANCODE_RETURN; break; case VK_ESCAPE: scancode = SDL_SCANCODE_ESCAPE; break;
      case VK_SPACE: scancode = SDL_SCANCODE_SPACE; break; case VK_PRIOR: scancode = SDL_SCANCODE_PAGEUP; break;
      case VK_NEXT: scancode = SDL_SCANCODE_PAGEDOWN; break;
      default:
        if (key >= 'A' && key <= 'Z') scancode = (SDL_Scancode)(SDL_SCANCODE_A + key - 'A');
        else if (key >= '1' && key <= '9') scancode = (SDL_Scancode)(SDL_SCANCODE_1 + key - '1');
        else if (key == '0') scancode = SDL_SCANCODE_0;
        else if (key >= VK_F1 && key <= VK_F12) scancode = (SDL_Scancode)(SDL_SCANCODE_F1 + key - VK_F1);
        break;
    }
    if (scancode != SDL_SCANCODE_UNKNOWN) {
      action = 7000 + (int)scancode;
      native_keyboard_capture = -1;
      return 0;
    }
  }
  if (message == WM_COMMAND) {
    int id = LOWORD(wparam), notification = HIWORD(wparam);
    if (id >= 600 && id <= 602 && notification == CBN_SELCHANGE) {
      int index = id - 600;
      action = 6000 + index * 10 + (int)SendMessageW(direction_boxes[index], CB_GETCURSEL, 0, 0);
      return 0;
    }
    if ((id >= 400 && id <= 410) || (id >= 500 && id <= 502) || id == 420 || id == 520) {
      action = id;
      if (id >= 400 && id <= 410) { native_keyboard_capture = id - 400; SetWindowTextW(keyboard_buttons[id - 400], L"Press a key..."); SetFocus(hwnd); }
      if (id >= 500 && id <= 502) SetWindowTextW(controller_buttons[id - 500], L"Press a button...");
      return 0;
    }
    if (id == 530 || id == 531) {
      action = id; DestroyWindow(settings_window); restore_game_focus(); return 0;
    }
  } else if (message == WM_NOTIFY && (HWND)((NMHDR *)lparam)->hwndFrom == settings_tabs &&
             ((NMHDR *)lparam)->code == TCN_SELCHANGE) {
    int selected = TabCtrl_GetCurSel(settings_tabs);
    ShowWindow(keyboard_page, selected == 0 ? SW_SHOW : SW_HIDE);
    ShowWindow(controller_page, selected == 1 ? SW_SHOW : SW_HIDE);
    return 0;
  } else if (message == WM_CLOSE) {
    action = 531; DestroyWindow(hwnd); restore_game_focus(); return 0;
  } else if (message == WM_DESTROY) {
    settings_window = NULL; return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static HWND add_control(HWND parent, const wchar_t *klass, const wchar_t *text, DWORD style,
                        int x, int y, int width, int height, int id) {
  return CreateWindowExW(0, klass, text, WS_CHILD | WS_VISIBLE | style, x, y, width, height,
                         parent, (HMENU)(INT_PTR)id, GetModuleHandleW(NULL), NULL);
}

static void layout_status(int width, int height) {
  if (!window_handle || !status_bar) return;
  last_client_width = width; last_client_height = height;
  MoveWindow(status_bar, 0, height - 24, width, 24, TRUE);
  SendMessageW(status_bar, WM_SIZE, 0, 0);
  RECT status_window; GetWindowRect(status_bar, &status_window);
  current_status_height = status_window.bottom - status_window.top;
  RECT status_client; GetClientRect(status_bar, &status_client);
  int inner_width = status_client.right - status_client.left;
  int title_end = inner_width > 300 ? inner_width - 230 : inner_width / 2;
  int fps_end = inner_width > 180 ? inner_width - 140 : title_end;
  int parts[3] = {title_end, fps_end, -1};
  SendMessageW(status_bar, SB_SETPARTS, 3, (LPARAM)parts);
  RECT volume_part;
  if (SendMessageW(status_bar, SB_GETRECT, 2, (LPARAM)&volume_part)) {
    int part_height = volume_part.bottom - volume_part.top;
    if (volume_label) MoveWindow(volume_label, volume_part.left + 4, volume_part.top + 2, 28, part_height - 4, TRUE);
    if (volume_slider) MoveWindow(volume_slider, volume_part.left + 34, volume_part.top + 1,
                                  volume_part.right - volume_part.left - 38, part_height - 2, TRUE);
  }
}

static int shortcut_action(UINT message, UINT key) {
  int control = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
  if (message == WM_KEYDOWN && control) {
    switch (key) {
      case 'O': return OPEN_ROM; case 'S': return SAVE_STATE_BASE; case 'L': return LOAD_STATE_BASE;
      case VK_OEM_COMMA: return SETTINGS; case 'Q': return QUIT; case 'P': return PAUSE;
      case 'R': return RESET; case '1': return SCALE_1; case '2': return SCALE_1 + 1;
      case '3': return SCALE_1 + 2; case '4': return SCALE_1 + 3;
    }
  }
  if (message == WM_KEYDOWN && key == VK_F11) return FULLSCREEN;
  return 0;
}

static void SDLCALL message_hook(void *userdata, void *hwnd, unsigned int message,
                                  Uint64 wparam, Sint64 lparam) {
  (void)userdata; (void)hwnd; (void)lparam;
  if (message == WM_COMMAND) handle_command(LOWORD((DWORD_PTR)wparam));
  else if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) {
    int shortcut = shortcut_action(message, (UINT)wparam);
    if (shortcut) handle_command((UINT)shortcut);
  }
  else if (message == WM_SIZE && (HWND)hwnd == window_handle)
    status_layout_pending = 1;
  else if (message == WM_EXITMENULOOP || message == WM_CANCELMODE)
    restore_game_focus();
  else if (message == WM_CLOSE) action = QUIT;
}

static HMENU state_submenu(int base) {
  HMENU result = CreatePopupMenu();
  for (int slot = 0; slot < 10; ++slot) {
    wchar_t label[32];
    swprintf(label, 32, L"Slot %d", slot);
    append(result, MF_STRING, (UINT_PTR)(base + slot), label);
  }
  return result;
}

int swanium_windows_menu_attach(const char *title, int volume, int scale) {
  (void)title;
  window_handle = GetActiveWindow();
  if (!window_handle) window_handle = GetForegroundWindow();
  if (!window_handle) return 0;
  current_volume = volume < 0 ? 0 : volume > 100 ? 100 : volume;
  INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_BAR_CLASSES | ICC_TAB_CLASSES};
  InitCommonControlsEx(&controls);

  HMENU file_menu = CreatePopupMenu();
  recent_menu = CreatePopupMenu();
  save_menu = state_submenu(SAVE_STATE_BASE);
  load_menu = state_submenu(LOAD_STATE_BASE);
  emulation_menu = CreatePopupMenu();
  view_menu = CreatePopupMenu();
  HMENU help_menu = CreatePopupMenu();
  menu_bar = CreateMenu();
  if (!file_menu || !recent_menu || !save_menu || !load_menu || !emulation_menu ||
      !view_menu || !help_menu || !menu_bar) return 0;

  append(file_menu, MF_STRING, OPEN_ROM, L"&Open ROM...\tCtrl+O");
  append(file_menu, MF_POPUP, (UINT_PTR)recent_menu, L"Open Recent");
  append(file_menu, MF_SEPARATOR, 0, NULL);
  append(file_menu, MF_POPUP, (UINT_PTR)save_menu, L"Save State\tCtrl+S");
  append(file_menu, MF_POPUP, (UINT_PTR)load_menu, L"Load State\tCtrl+L");
  append(file_menu, MF_SEPARATOR, 0, NULL);
  append(file_menu, MF_STRING, SETTINGS, L"&Settings...\tCtrl+,");
  append(file_menu, MF_SEPARATOR, 0, NULL);
  append(file_menu, MF_STRING, QUIT, L"E&xit\tCtrl+Q");

  append(emulation_menu, MF_STRING, PAUSE, L"&Pause\tCtrl+P");
  append(emulation_menu, MF_STRING, RESET, L"&Reset\tCtrl+R");

  HMENU scale_menu = CreatePopupMenu();
  for (int index = 0; index < 4; ++index) {
    wchar_t label[16]; swprintf(label, 16, L"%dx", index + 1);
    wchar_t shortcut_label[24]; swprintf(shortcut_label, 24, L"%s\tCtrl+%d", label, index + 1);
    append(scale_menu, MF_STRING, (UINT_PTR)(SCALE_1 + index), shortcut_label);
  }
  HMENU renderer_menu = CreatePopupMenu();
  append(renderer_menu, MF_STRING, RENDER_NEAREST, L"Nearest");
  append(renderer_menu, MF_STRING, RENDER_LINEAR, L"Linear");
  append(view_menu, MF_POPUP, (UINT_PTR)scale_menu, L"Scale");
  append(view_menu, MF_STRING, FULLSCREEN, L"Fullscreen\tF11");
  append(view_menu, MF_POPUP, (UINT_PTR)renderer_menu, L"Renderer");
  append(help_menu, MF_STRING, ABOUT, L"About Swanium Crystal...");

  append(menu_bar, MF_POPUP, (UINT_PTR)file_menu, L"&File");
  append(menu_bar, MF_POPUP, (UINT_PTR)emulation_menu, L"&Emulation");
  append(menu_bar, MF_POPUP, (UINT_PTR)view_menu, L"&View");
  append(menu_bar, MF_POPUP, (UINT_PTR)help_menu, L"&Help");
  SetMenu(window_handle, menu_bar);
  DrawMenuBar(window_handle);
  SDL_SetWindowsMessageHook(message_hook, NULL);
  swanium_windows_menu_state(0, scale, 0, 0);
  return 1;
}

void swanium_windows_menu_pump(void) {
  if (window_handle && status_bar) {
    RECT client; GetClientRect(window_handle, &client);
    int width = client.right - client.left, height = client.bottom - client.top;
    if (status_layout_pending || width != last_client_width || height != last_client_height)
      layout_status(width, height);
    status_layout_pending = 0;
  }
}
int swanium_windows_menu_take_action(void) { int result = action; action = 0; last_taken_action = result; return result; }
char *swanium_windows_menu_open_rom(void) { return opened_path; }

void swanium_windows_menu_recent(const char **paths) {
  while (GetMenuItemCount(recent_menu) > 0) DeleteMenu(recent_menu, 0, MF_BYPOSITION);
  int count = 0;
  for (; paths && paths[count] && count < 10; ++count) {
    free(recent_paths[count]); recent_paths[count] = copy_text(paths[count]);
    const char *base = strrchr(paths[count], '\\');
    if (!base) base = strrchr(paths[count], '/');
    wchar_t *label = utf8_to_wide(base ? base + 1 : paths[count]);
    append(recent_menu, MF_STRING, (UINT_PTR)(RECENT_BASE + count), label ? label : L"ROM");
    free(label);
  }
  for (int index = count; index < 10; ++index) { free(recent_paths[index]); recent_paths[index] = NULL; }
  if (!count) append(recent_menu, MF_STRING | MF_GRAYED, 0, L"No Recent ROMs");
  else { append(recent_menu, MF_SEPARATOR, 0, NULL); append(recent_menu, MF_STRING, CLEAR_RECENT, L"Clear History"); }
  DrawMenuBar(window_handle);
}

const char *swanium_windows_menu_recent_path(int index) {
  return index >= 0 && index < 10 ? recent_paths[index] : NULL;
}

void swanium_windows_menu_state_slots(const char **labels, const int *available) {
  for (int slot = 0; slot < 10; ++slot) {
    wchar_t *label = utf8_to_wide(labels[slot]);
    ModifyMenuW(save_menu, (UINT)slot, MF_BYPOSITION | MF_STRING, SAVE_STATE_BASE + slot, label);
    ModifyMenuW(load_menu, (UINT)slot, MF_BYPOSITION | MF_STRING | (available[slot] ? MF_ENABLED : MF_GRAYED), LOAD_STATE_BASE + slot, label);
    free(label);
  }
}

void swanium_windows_menu_status(const char *title, const char *fps) {
  if (!status_bar) return;
  if (strcmp(last_status_title, title) != 0) {
    strncpy_s(last_status_title, sizeof(last_status_title), title, _TRUNCATE);
    wchar_t *wide = utf8_to_wide(title); if (wide) { SendMessageW(status_bar, SB_SETTEXTW, 0, (LPARAM)wide); free(wide); }
  }
  if (strcmp(last_status_fps, fps) != 0) {
    strncpy_s(last_status_fps, sizeof(last_status_fps), fps, _TRUNCATE);
    wchar_t *wide = utf8_to_wide(fps); if (wide) { SendMessageW(status_bar, SB_SETTEXTW, 1, (LPARAM)wide); free(wide); }
  }
}

void swanium_windows_menu_attach_status(void) {
  if (status_bar || !window_handle) return;
  status_bar = CreateWindowExW(0, STATUSCLASSNAMEW, L"", WS_CHILD | WS_VISIBLE,
                               0, 0, 0, 0, window_handle, NULL, GetModuleHandleW(NULL), NULL);
  volume_slider = CreateWindowExW(0, TRACKBAR_CLASSW, L"", WS_CHILD | WS_VISIBLE | TBS_NOTICKS,
                                  0, 0, 0, 0, status_bar, NULL, GetModuleHandleW(NULL), NULL);
  volume_label = CreateWindowExW(0, L"STATIC", L"\xD83D\xDD0A", WS_CHILD | WS_VISIBLE | SS_CENTERIMAGE | SS_CENTER,
                                 0, 0, 0, 0, status_bar, NULL, GetModuleHandleW(NULL), NULL);
  volume_icon_font = CreateFontW(-16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Emoji");
  if (volume_icon_font) SendMessageW(volume_label, WM_SETFONT, (WPARAM)volume_icon_font, TRUE);
  SendMessageW(volume_slider, TBM_SETRANGE, TRUE, MAKELPARAM(0, 100));
  SendMessageW(volume_slider, TBM_SETPOS, TRUE, current_volume);
  RECT client; GetClientRect(window_handle, &client);
  layout_status(client.right - client.left, client.bottom - client.top);
}
int swanium_windows_menu_status_height(void) { return status_bar ? current_status_height : 0; }

void swanium_windows_menu_state(int paused, int scale, int fullscreen, int renderer) {
  if (paused != last_paused) { ModifyMenuW(emulation_menu, 0, MF_BYPOSITION | MF_STRING, PAUSE, paused ? L"&Resume\tCtrl+P" : L"&Pause\tCtrl+P"); last_paused = paused; }
  if (scale != last_scale) { for (int index = 0; index < 4; ++index) CheckMenuItem(view_menu, SCALE_1 + index, MF_BYCOMMAND | (scale == index + 1 ? MF_CHECKED : MF_UNCHECKED)); last_scale = scale; }
  if (fullscreen != last_fullscreen) { CheckMenuItem(view_menu, FULLSCREEN, MF_BYCOMMAND | (fullscreen ? MF_CHECKED : MF_UNCHECKED)); last_fullscreen = fullscreen; }
  if (renderer != last_renderer) { CheckMenuItem(view_menu, RENDER_NEAREST, MF_BYCOMMAND | (!renderer ? MF_CHECKED : MF_UNCHECKED)); CheckMenuItem(view_menu, RENDER_LINEAR, MF_BYCOMMAND | (renderer ? MF_CHECKED : MF_UNCHECKED)); last_renderer = renderer; }
}

int swanium_windows_menu_volume(void) {
  if (volume_slider) current_volume = (int)SendMessageW(volume_slider, TBM_GETPOS, 0, 0);
  if (volume_slider && GetFocus() == volume_slider && (GetKeyState(VK_LBUTTON) & 0x8000) == 0)
    restore_game_focus();
  return current_volume;
}
void swanium_windows_menu_error(const char *text) {
  wchar_t *wide = utf8_to_wide(text); MessageBoxW(window_handle, wide ? wide : L"Unknown error", L"Swanium Crystal", MB_OK | MB_ICONERROR); free(wide);
}
void swanium_windows_menu_about(void) {
  MessageBoxW(window_handle, L"Swanium Crystal\nWonderSwan and WonderSwan Color emulator.\n\nVersion 1.0.0\nLicensed under the MIT License.", L"About Swanium Crystal", MB_OK | MB_ICONINFORMATION);
}
void swanium_windows_menu_settings(void) {
  if (settings_window) { SetForegroundWindow(settings_window); return; }
  WNDCLASSW klass; ZeroMemory(&klass, sizeof(klass));
  klass.lpfnWndProc = settings_proc; klass.hInstance = GetModuleHandleW(NULL);
  klass.lpszClassName = L"SwaniumCrystalSettings"; klass.hCursor = LoadCursor(NULL, IDC_ARROW);
  klass.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); RegisterClassW(&klass);
  settings_window = CreateWindowExW(WS_EX_DLGMODALFRAME, klass.lpszClassName, L"Swanium Crystal Settings",
    WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 500, 570,
    window_handle, NULL, klass.hInstance, NULL);
  if (!settings_window) return;
  settings_tabs = add_control(settings_window, WC_TABCONTROLW, L"", WS_TABSTOP, 12, 12, 460, 475, 700);
  SendMessageW(settings_tabs, TCM_SETITEMSIZE, 0, MAKELPARAM(150, 28));
  TCITEMW tab; ZeroMemory(&tab, sizeof(tab)); tab.mask = TCIF_TEXT;
  tab.pszText = L"Keyboard"; SendMessageW(settings_tabs, TCM_INSERTITEMW, 0, (LPARAM)&tab);
  tab.pszText = L"Controller"; SendMessageW(settings_tabs, TCM_INSERTITEMW, 1, (LPARAM)&tab);
  keyboard_page = CreateWindowExW(0, klass.lpszClassName, L"", WS_CHILD | WS_VISIBLE,
                                  22, 44, 438, 430, settings_window, NULL, klass.hInstance, NULL);
  controller_page = CreateWindowExW(0, klass.lpszClassName, L"", WS_CHILD,
                                    22, 44, 438, 430, settings_window, NULL, klass.hInstance, NULL);
  const wchar_t *actions[11] = {L"X Up", L"X Right", L"X Down", L"X Left", L"Y Up", L"Y Right", L"Y Down", L"Y Left", L"A", L"B", L"Start"};
  for (int i = 0; i < 11; ++i) {
    int y = 10 + i * 34;
    add_control(keyboard_page, L"STATIC", actions[i], SS_LEFT, 14, y + 5, 145, 24, 0);
    wchar_t *name = utf8_to_wide(keyboard_names[i] ? keyboard_names[i] : "Unassigned");
    keyboard_buttons[i] = add_control(keyboard_page, L"BUTTON", name ? name : L"Unassigned", BS_PUSHBUTTON, 170, y, 235, 27, 400 + i); free(name);
  }
  add_control(keyboard_page, L"BUTTON", L"Restore Defaults", BS_PUSHBUTTON, 170, 388, 235, 30, 420);
  const wchar_t *directions[3] = {L"D-pad", L"Left stick", L"Right stick"};
  for (int i = 0; i < 3; ++i) {
    int y = 18 + i * 44; add_control(controller_page, L"STATIC", directions[i], SS_LEFT, 14, y + 5, 145, 24, 0);
    direction_boxes[i] = add_control(controller_page, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL, 170, y, 235, 120, 600 + i);
    SendMessageW(direction_boxes[i], CB_ADDSTRING, 0, (LPARAM)L"Disabled");
    SendMessageW(direction_boxes[i], CB_ADDSTRING, 0, (LPARAM)L"X Pad");
    SendMessageW(direction_boxes[i], CB_ADDSTRING, 0, (LPARAM)L"Y Pad");
    SendMessageW(direction_boxes[i], CB_SETCURSEL, direction_values[i], 0);
  }
  const wchar_t *buttons[3] = {L"A button", L"B button", L"Start button"};
  for (int i = 0; i < 3; ++i) {
    int y = 174 + i * 44; add_control(controller_page, L"STATIC", buttons[i], SS_LEFT, 14, y + 5, 145, 24, 0);
    wchar_t *name = utf8_to_wide(button_names[i] ? button_names[i] : "Unassigned");
    controller_buttons[i] = add_control(controller_page, L"BUTTON", name ? name : L"Unassigned", BS_PUSHBUTTON, 170, y, 235, 27, 500 + i); free(name);
  }
  add_control(controller_page, L"BUTTON", L"Restore Defaults", BS_PUSHBUTTON, 170, 330, 235, 30, 520);
  add_control(settings_window, L"BUTTON", L"Apply", BS_DEFPUSHBUTTON, 284, 500, 88, 30, 530);
  add_control(settings_window, L"BUTTON", L"Cancel", BS_PUSHBUTTON, 382, 500, 88, 30, 531);
  ShowWindow(settings_window, SW_SHOW); UpdateWindow(settings_window);
}
void swanium_windows_menu_settings_sync(const char **keyboard, const char **buttons, const int *directions) {
  native_keyboard_capture = -1;
  for (int i = 0; i < 11; ++i) { free(keyboard_names[i]); keyboard_names[i] = copy_text(keyboard[i]); wchar_t *wide = utf8_to_wide(keyboard[i]); if (settings_window && wide) SetWindowTextW(keyboard_buttons[i], wide); free(wide); }
  for (int i = 0; i < 3; ++i) { free(button_names[i]); button_names[i] = copy_text(buttons[i]); direction_values[i] = directions[i]; wchar_t *wide = utf8_to_wide(buttons[i]); if (settings_window && wide) SetWindowTextW(controller_buttons[i], wide); if (settings_window) SendMessageW(direction_boxes[i], CB_SETCURSEL, directions[i], 0); free(wide); }
}
void swanium_windows_menu_smoke_open_settings(void) { swanium_windows_menu_settings(); }
int swanium_windows_menu_smoke_settings_tab_count(void) { return settings_tabs ? TabCtrl_GetItemCount(settings_tabs) : 0; }
int swanium_windows_menu_smoke_settings_tabs_named(void) {
  if (!settings_tabs) return 0;
  wchar_t first[32] = L"", second[32] = L"";
  TCITEMW item; ZeroMemory(&item, sizeof(item)); item.mask = TCIF_TEXT;
  item.pszText = first; item.cchTextMax = 32;
  if (!SendMessageW(settings_tabs, TCM_GETITEMW, 0, (LPARAM)&item)) return 0;
  item.pszText = second;
  if (!SendMessageW(settings_tabs, TCM_GETITEMW, 1, (LPARAM)&item)) return 0;
  return wcscmp(first, L"Keyboard") == 0 && wcscmp(second, L"Controller") == 0;
}
int swanium_windows_menu_smoke_status_layout_valid(void) {
  if (!window_handle || !status_bar || !volume_slider) return 0;
  RECT parent, status_window, status, slider;
  GetClientRect(window_handle, &parent); GetWindowRect(status_bar, &status_window);
  POINT status_points[2] = {{status_window.left, status_window.top}, {status_window.right, status_window.bottom}};
  MapWindowPoints(NULL, window_handle, status_points, 2);
  if (status_points[0].x != parent.left || status_points[1].x != parent.right ||
      status_points[1].y != parent.bottom || status_points[0].y < parent.top) return 0;
  GetClientRect(status_bar, &status); GetWindowRect(volume_slider, &slider);
  POINT points[2] = {{slider.left, slider.top}, {slider.right, slider.bottom}};
  MapWindowPoints(NULL, status_bar, points, 2);
  return points[0].x >= status.left && points[0].y >= status.top &&
         points[1].x <= status.right && points[1].y <= status.bottom;
}
void swanium_windows_menu_smoke_begin_keyboard_capture(int index) {
  if (keyboard_page && index >= 0 && index < 11) SendMessageW(keyboard_page, WM_COMMAND, 400 + index, 0);
}
void swanium_windows_menu_smoke_send_key(int virtual_key) {
  if (keyboard_page) SendMessageW(keyboard_page, WM_KEYDOWN, (WPARAM)virtual_key, 0);
}
int swanium_windows_menu_smoke_pending_action(void) { return action; }
int swanium_windows_menu_smoke_keyboard_capture(void) { return native_keyboard_capture; }
int swanium_windows_menu_smoke_last_taken_action(void) { return last_taken_action; }
int swanium_windows_menu_smoke_select_settings_tab(int index) {
  if (!settings_tabs || index < 0 || index > 1) return 0;
  TabCtrl_SetCurSel(settings_tabs, index);
  ShowWindow(keyboard_page, index == 0 ? SW_SHOW : SW_HIDE);
  ShowWindow(controller_page, index == 1 ? SW_SHOW : SW_HIDE);
  return IsWindowVisible(index == 0 ? keyboard_page : controller_page) != 0;
}
void swanium_windows_menu_smoke_close_settings(void) {
  if (settings_window) { action = 531; DestroyWindow(settings_window); }
  restore_game_focus();
}
void swanium_windows_menu_smoke_focus_volume(void) { if (volume_slider) SetFocus(volume_slider); }
int swanium_windows_menu_smoke_game_has_focus(void) { return GetFocus() == window_handle; }
void swanium_windows_menu_smoke_post_game_key(int virtual_key) {
  if (!window_handle) return;
  LPARAM scan = (LPARAM)(MapVirtualKeyW((UINT)virtual_key, MAPVK_VK_TO_VSC) << 16);
  PostMessageW(window_handle, WM_KEYDOWN, (WPARAM)virtual_key, 1 | scan);
  PostMessageW(window_handle, WM_KEYUP, (WPARAM)virtual_key, 1 | scan | (1LL << 30) | (1LL << 31));
}
void swanium_windows_menu_destroy(void) {
  SDL_SetWindowsMessageHook(NULL, NULL);
  if (settings_window) DestroyWindow(settings_window);
  status_bar = volume_label = volume_slider = NULL; current_status_height = 0; status_layout_pending = 0;
  last_client_width = last_client_height = -1;
  if (window_handle) SetMenu(window_handle, NULL);
  if (menu_bar) DestroyMenu(menu_bar);
  if (volume_icon_font) { DeleteObject(volume_icon_font); volume_icon_font = NULL; }
  menu_bar = NULL; window_handle = NULL; action = 0;
  last_paused = last_scale = last_fullscreen = last_renderer = -1;
  last_status_title[0] = last_status_fps[0] = '\0';
  native_keyboard_capture = -1;
  free(opened_path); opened_path = NULL;
  for (int i = 0; i < 10; ++i) { free(recent_paths[i]); recent_paths[i] = NULL; }
  for (int i = 0; i < 11; ++i) { free(keyboard_names[i]); keyboard_names[i] = NULL; }
  for (int i = 0; i < 3; ++i) { free(button_names[i]); button_names[i] = NULL; }
}
