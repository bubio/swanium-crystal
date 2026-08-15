#import <Cocoa/Cocoa.h>
#import <SDL.h>
#import <SDL_syswm.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static int pending_action = 0;
static NSTextField *status_label = nil;
static NSSlider *status_volume = nil;
static NSVisualEffectView *status_footer = nil;
static __weak NSWindow *main_window = nil;
static NSPanel *settings_panel = nil;
static NSButton *keyboard_buttons[11] = {nil};
static NSButton *controller_buttons[3] = {nil};
static NSPopUpButton *direction_popups[3] = {nil};
static NSInteger keyboard_capture_tag = -1;

static const CGFloat settings_outer_inset = 16.0;
static const CGFloat settings_content_inset = 20.0;
static const CGFloat settings_row_spacing = 8.0;
static const CGFloat settings_group_spacing = 24.0;
static const CGFloat settings_label_width = 172.0;
static const CGFloat settings_control_width = 200.0;
static const CGFloat settings_control_height = 26.0;
static const CGFloat settings_width = 480.0;
static const CGFloat settings_tab_width = 448.0;
static const CGFloat settings_initial_height = 520.0;
static const CGFloat settings_window_chrome_height = 32.0;
static const CGFloat settings_minimum_height = 260.0;
static const CGFloat settings_document_height = 480.0;

// Slint's Cupertino theme in Swanium renders its dark-mode accent as this
// blue. Keep the AppKit controls in the Crystal frontend visually consistent.
static NSColor *swanium_tint_color(void) {
  return [NSColor colorWithSRGBRed:(89.0 / 255.0)
                             green:(189.0 / 255.0)
                              blue:(255.0 / 255.0)
                             alpha:1.0];
}

static int sdl_scancode_for_macos_keycode(unsigned short keycode) {
  switch (keycode) {
    case 0: return 4; case 1: return 22; case 2: return 7; case 3: return 9;
    case 4: return 11; case 5: return 10; case 6: return 29; case 7: return 27;
    case 8: return 6; case 9: return 25; case 11: return 5; case 12: return 20;
    case 13: return 26; case 14: return 8; case 15: return 21; case 16: return 28;
    case 17: return 23; case 18: return 30; case 19: return 31; case 20: return 32;
    case 21: return 33; case 22: return 35; case 23: return 34; case 24: return 46;
    case 25: return 38; case 26: return 36; case 27: return 45; case 28: return 37;
    case 29: return 39; case 30: return 48; case 31: return 18; case 32: return 24;
    case 33: return 47; case 34: return 12; case 35: return 19; case 36: return 40;
    case 37: return 15; case 38: return 13; case 39: return 52; case 40: return 14;
    case 41: return 51; case 42: return 49; case 43: return 54; case 44: return 56;
    case 45: return 17; case 46: return 16; case 47: return 55; case 48: return 43;
    case 49: return 44; case 50: return 53; case 51: return 42; case 53: return 41;
    case 123: return 80; case 124: return 79; case 125: return 81; case 126: return 82;
    default: return -1;
  }
}
static NSString *opened_rom_path = nil;
static NSMutableArray<NSString *> *recent_rom_paths = nil;
static NSMenu *recent_menu = nil;
static NSMenuItem *pause_item = nil;
static NSMenuItem *fullscreen_item = nil;
static NSMenuItem *scale_items[4] = {nil};
static NSMenuItem *renderer_items[2] = {nil};
static NSMenuItem *load_state_items[10] = {nil};
static NSMenuItem *save_state_items[10] = {nil};
static NSMenuItem *load_state_root = nil;

@interface SwaniumMenuTarget : NSObject
+ (instancetype)sharedTarget;
- (void)activate:(id)sender;
@end

@implementation SwaniumMenuTarget
+ (instancetype)sharedTarget {
  static SwaniumMenuTarget *target;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ target = [[self alloc] init]; });
  return target;
}
- (void)activate:(id)sender {
  if ([sender isKindOfClass:[NSPopUpButton class]]) {
    pending_action = (int)[sender tag] * 10 + (int)[sender indexOfSelectedItem];
  } else {
    pending_action = (int)[sender tag];
    if ([sender tag] >= 400 && [sender tag] <= 410) {
      keyboard_capture_tag = [sender tag];
      [(NSButton *)sender setTitle:@"Press a key…"];
    }
  }
}
@end

static NSMenuItem *item(NSString *title, NSInteger tag) {
  NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:title action:@selector(activate:) keyEquivalent:@""];
  entry.target = [SwaniumMenuTarget sharedTarget];
  entry.tag = tag;
  return entry;
}

static NSMenu *submenu(NSString *title) {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
  return menu;
}

static NSTextField *settings_label(NSString *text) {
  NSTextField *label = [NSTextField labelWithString:text];
  label.font = [NSFont systemFontOfSize:13];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [[label widthAnchor] constraintEqualToConstant:settings_label_width].active = YES;
  return label;
}

static NSButton *settings_capture_button(NSInteger tag) {
  NSButton *button = [NSButton buttonWithTitle:@"Press a key…" target:[SwaniumMenuTarget sharedTarget] action:@selector(activate:)];
  button.tag = tag;
  button.contentTintColor = swanium_tint_color();
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [[button widthAnchor] constraintEqualToConstant:settings_control_width].active = YES;
  [[button heightAnchor] constraintEqualToConstant:settings_control_height].active = YES;
  return button;
}

static NSStackView *settings_row(NSString *label_text, NSView *control) {
  NSStackView *row = [NSStackView stackViewWithViews:@[settings_label(label_text), control]];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeCenterY;
  row.spacing = 16.0;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  return row;
}

static NSStackView *settings_stack(void) {
  NSStackView *stack = [NSStackView new];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = settings_row_spacing;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  return stack;
}

static void install_settings_stack(NSStackView *stack, NSView *content) {
  [content addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:settings_content_inset],
    [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-settings_content_inset],
    [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:settings_content_inset],
  ]];
}

static NSView *settings_scroll_content(NSView *content) {
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:content.bounds];
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  scroll.borderType = NSNoBorder;
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = NO;
  scroll.autohidesScrollers = YES;
  scroll.documentView = content;
  return scroll;
}

static void add_top_level(NSMenu *bar, NSString *title, NSMenu *menu) {
  NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
  root.submenu = menu;
  [bar addItem:root];
}

void swanium_macos_menu_build(void) {
  [NSApplication sharedApplication];
  static id key_monitor = nil;
  if (key_monitor == nil) {
    key_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
      if (keyboard_capture_tag < 0) return event;
      int scancode = sdl_scancode_for_macos_keycode(event.keyCode);
      if (scancode >= 0) {
        pending_action = 7000 + scancode;
        keyboard_capture_tag = -1;
        return nil;
      }
      return event;
    }];
  }
  NSMenu *bar = NSApp.mainMenu;
  if (bar == nil) {
    bar = [[NSMenu alloc] initWithTitle:@"Swanium Crystal"];
    [NSApp setMainMenu:bar];
  }
  if ([bar itemWithTitle:@"Emulation"] != nil) return;

  NSMenuItem *application_root = [bar itemAtIndex:0];
  if (application_root == nil) {
    application_root = [[NSMenuItem alloc] initWithTitle:@"Swanium Crystal" action:nil keyEquivalent:@""];
    [bar insertItem:application_root atIndex:0];
  }
  application_root.title = @"Swanium Crystal";
  NSMenu *application = submenu(application_root.title);
  application_root.submenu = application;
  [application addItem:item(@"About Swanium Crystal", 41)];
  [application addItem:[NSMenuItem separatorItem]];
  NSMenuItem *settings = item(@"Settings…", 42);
  settings.keyEquivalent = @",";
  [application addItem:settings];
  [application addItem:[NSMenuItem separatorItem]];
  NSMenuItem *quit = item(@"Quit Swanium Crystal", 43);
  quit.keyEquivalent = @"q";
  [application addItem:quit];
  NSMenu *emulation = submenu(@"Emulation");
  NSMenuItem *open_rom = item(@"Open ROM…", 1);
  open_rom.keyEquivalent = @"o";
  [emulation addItem:open_rom];
  recent_menu = submenu(@"Open Recent");
  NSMenuItem *recent_root = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
  recent_root.submenu = recent_menu;
  [emulation addItem:recent_root];
  [emulation addItem:[NSMenuItem separatorItem]];
  NSMenu *save_state = submenu(@"Save State");
  NSMenu *load_state = submenu(@"Load State");
  for (NSInteger slot = 0; slot < 10; slot++) {
    NSString *title = [NSString stringWithFormat:@"Slot %ld", (long)slot];
    save_state_items[slot] = item(title, 100 + slot);
    if (slot == 0) save_state_items[slot].keyEquivalent = @"s";
    [save_state addItem:save_state_items[slot]];
    load_state_items[slot] = item(title, 200 + slot);
    if (slot == 0) load_state_items[slot].keyEquivalent = @"l";
    [load_state addItem:load_state_items[slot]];
  }
  NSMenuItem *save_root = [[NSMenuItem alloc] initWithTitle:@"Save State" action:nil keyEquivalent:@""];
  save_root.submenu = save_state;
  [emulation addItem:save_root];
  load_state_root = [[NSMenuItem alloc] initWithTitle:@"Load State" action:nil keyEquivalent:@""];
  load_state_root.submenu = load_state;
  [emulation addItem:load_state_root];
  [emulation addItem:[NSMenuItem separatorItem]];
  pause_item = item(@"Pause", 4);
  pause_item.keyEquivalent = @"p";
  [emulation addItem:pause_item];
  NSMenuItem *reset = item(@"Reset", 5);
  reset.keyEquivalent = @"r";
  [emulation addItem:reset];
  add_top_level(bar, @"Emulation", emulation);

  NSMenu *view = submenu(@"View");
  NSMenu *scale = submenu(@"Scale");
  scale_items[0] = item(@"1x", 11);
  scale_items[1] = item(@"2x", 12);
  scale_items[2] = item(@"3x", 13);
  scale_items[3] = item(@"4x", 14);
  scale_items[0].keyEquivalent = @"1";
  scale_items[1].keyEquivalent = @"2";
  scale_items[2].keyEquivalent = @"3";
  scale_items[3].keyEquivalent = @"4";
  [scale addItem:scale_items[0]];
  [scale addItem:scale_items[1]];
  [scale addItem:scale_items[2]];
  [scale addItem:scale_items[3]];
  NSMenuItem *scale_root = [[NSMenuItem alloc] initWithTitle:@"Scale" action:nil keyEquivalent:@""];
  scale_root.submenu = scale;
  [view addItem:scale_root];
  fullscreen_item = item(@"Fullscreen", 20);
  fullscreen_item.keyEquivalent = [NSString stringWithFormat:@"%C", (unichar)NSF11FunctionKey];
  fullscreen_item.keyEquivalentModifierMask = 0;
  [view addItem:fullscreen_item];
  [view addItem:[NSMenuItem separatorItem]];
  NSMenu *renderer = submenu(@"Renderer");
  renderer_items[0] = item(@"Nearest Neighbor", 31);
  renderer_items[1] = item(@"Bilinear", 32);
  [renderer addItem:renderer_items[0]];
  [renderer addItem:renderer_items[1]];
  NSMenuItem *renderer_root = [[NSMenuItem alloc] initWithTitle:@"Renderer" action:nil keyEquivalent:@""];
  renderer_root.submenu = renderer;
  [view addItem:renderer_root];
  add_top_level(bar, @"View", view);
}

void swanium_macos_menu_set_state_slots(const char **labels, const int *slots) {
  BOOL any_loadable = NO;
  for (NSInteger slot = 0; slot < 10; slot++) {
    save_state_items[slot].title = [NSString stringWithUTF8String:labels[slot]];
    load_state_items[slot].title = [NSString stringWithUTF8String:labels[slot]];
    load_state_items[slot].enabled = slots[slot] != 0;
    any_loadable |= slots[slot] != 0;
  }
  load_state_root.enabled = any_loadable;
}

void swanium_macos_menu_update_state(BOOL paused, int scale, BOOL fullscreen, int renderer) {
  pause_item.state = paused ? NSControlStateValueOn : NSControlStateValueOff;
  fullscreen_item.state = fullscreen ? NSControlStateValueOn : NSControlStateValueOff;
  for (NSInteger index = 0; index < 4; index++) {
    scale_items[index].state = scale_items[index].tag == scale + 10 ? NSControlStateValueOn : NSControlStateValueOff;
  }
  for (NSInteger index = 0; index < 2; index++) {
    renderer_items[index].state = index == renderer ? NSControlStateValueOn : NSControlStateValueOff;
  }
}

void swanium_macos_menu_set_recent_roms(const char **paths) {
  if (recent_menu == nil) return;
  [recent_menu removeAllItems];
  recent_rom_paths = [[NSMutableArray alloc] init];
  for (NSInteger index = 0; paths[index] != NULL && index < 10; index++) {
    NSString *path = [NSString stringWithUTF8String:paths[index]];
    [recent_rom_paths addObject:path];
    [recent_menu addItem:item(path.lastPathComponent, 300 + index)];
  }
  if (recent_rom_paths.count == 0) {
    NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Recent ROMs" action:nil keyEquivalent:@""];
    empty.enabled = NO;
    [recent_menu addItem:empty];
  } else {
    [recent_menu addItem:[NSMenuItem separatorItem]];
    [recent_menu addItem:item(@"Clear History", 310)];
  }
}

const char *swanium_macos_menu_recent_rom(int index) {
  if (index < 0 || index >= recent_rom_paths.count) return NULL;
  opened_rom_path = recent_rom_paths[index];
  return opened_rom_path.UTF8String;
}

int swanium_macos_menu_take_action(void) {
  int action = pending_action;
  pending_action = 0;
  return action;
}

const char *swanium_macos_menu_open_rom(void) {
  // The initial ROM picker runs before SDL creates its first window. Make the
  // process a foreground Cocoa app so a Finder launch can present the panel.
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp activateIgnoringOtherApps:YES];
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.allowedContentTypes = @[
    [UTType typeWithFilenameExtension:@"ws"],
    [UTType typeWithFilenameExtension:@"wsc"],
  ];
  panel.allowsMultipleSelection = NO;
  panel.canChooseDirectories = NO;
  if ([panel runModal] != NSModalResponseOK) return NULL;
  opened_rom_path = panel.URL.path;
  return opened_rom_path.UTF8String;
}

void swanium_macos_menu_show_about(void) {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Swanium Crystal";
  alert.informativeText = @"WonderSwan and WonderSwan Color emulator.";
  [alert runModal];
}

void swanium_macos_menu_show_error(const char *message) {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleWarning;
  alert.messageText = @"Could not load save state";
  alert.informativeText = [NSString stringWithUTF8String:message];
  [alert runModal];
}

void swanium_macos_settings_show(void) {
  if (main_window == nil) return;
  if (settings_panel == nil) {
    settings_panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, settings_width, settings_initial_height)
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    settings_panel.title = @"Swanium Crystal Settings";
    // NSWindow minSize/maxSize use the complete frame, including title bar.
    // Keep the current initial frame as the maximum and permit half-height.
    settings_panel.minSize = NSMakeSize(settings_width, (settings_initial_height + settings_window_chrome_height) / 2.0);
    settings_panel.maxSize = NSMakeSize(settings_width, settings_initial_height + settings_window_chrome_height);
    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(settings_outer_inset, settings_outer_inset, settings_tab_width, 488)];
    tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSView *keyboard = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, settings_tab_width, settings_document_height)];
    NSStackView *keyboard_stack = settings_stack();
    NSArray<NSString *> *labels = @[@"X Pad Up", @"X Pad Right", @"X Pad Down", @"X Pad Left", @"Y Pad Up", @"Y Pad Right", @"Y Pad Down", @"Y Pad Left", @"A Button", @"B Button", @"Start"];
    NSStackView *last_keyboard_row = nil;
    for (NSInteger index = 0; index < labels.count; index++) {
      keyboard_buttons[index] = settings_capture_button(400 + index);
      last_keyboard_row = settings_row(labels[index], keyboard_buttons[index]);
      [keyboard_stack addArrangedSubview:last_keyboard_row];
    }
    NSButton *keyboard_defaults = [NSButton buttonWithTitle:@"Restore Defaults" target:[SwaniumMenuTarget sharedTarget] action:@selector(activate:)];
    keyboard_defaults.tag = 420;
    keyboard_defaults.contentTintColor = swanium_tint_color();
    keyboard_defaults.translatesAutoresizingMaskIntoConstraints = NO;
    [[keyboard_defaults widthAnchor] constraintEqualToConstant:settings_control_width].active = YES;
    [[keyboard_defaults heightAnchor] constraintEqualToConstant:settings_control_height].active = YES;
    [keyboard_stack setCustomSpacing:16.0 afterView:last_keyboard_row];
    [keyboard_stack addArrangedSubview:settings_row(@"", keyboard_defaults)];
    install_settings_stack(keyboard_stack, keyboard);
    NSTabViewItem *keyboard_tab = [[NSTabViewItem alloc] initWithIdentifier:@"keyboard"];
    keyboard_tab.label = @"Keyboard";
    keyboard_tab.view = settings_scroll_content(keyboard);
    [tabs addTabViewItem:keyboard_tab];

    NSView *controller = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, settings_tab_width, settings_document_height)];
    NSStackView *controller_stack = settings_stack();
    NSArray<NSString *> *directions = @[@"D-pad", @"Left stick", @"Right stick"];
    NSStackView *last_direction_row = nil;
    for (NSInteger index = 0; index < directions.count; index++) {
      direction_popups[index] = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
      direction_popups[index].translatesAutoresizingMaskIntoConstraints = NO;
      [[direction_popups[index] widthAnchor] constraintEqualToConstant:settings_control_width].active = YES;
      [[direction_popups[index] heightAnchor] constraintEqualToConstant:settings_control_height].active = YES;
      [direction_popups[index] addItemsWithTitles:@[@"Disabled", @"X Pad", @"Y Pad"]];
      direction_popups[index].target = [SwaniumMenuTarget sharedTarget];
      direction_popups[index].action = @selector(activate:);
      direction_popups[index].tag = 600 + index;
      direction_popups[index].contentTintColor = swanium_tint_color();
      last_direction_row = settings_row(directions[index], direction_popups[index]);
      [controller_stack addArrangedSubview:last_direction_row];
    }
    NSArray<NSString *> *button_labels = @[@"A Button", @"B Button", @"Start"];
    [controller_stack setCustomSpacing:settings_group_spacing afterView:last_direction_row];
    NSStackView *last_controller_button_row = nil;
    for (NSInteger index = 0; index < button_labels.count; index++) {
      controller_buttons[index] = settings_capture_button(500 + index);
      last_controller_button_row = settings_row(button_labels[index], controller_buttons[index]);
      [controller_stack addArrangedSubview:last_controller_button_row];
    }
    NSButton *controller_defaults = [NSButton buttonWithTitle:@"Restore Defaults" target:[SwaniumMenuTarget sharedTarget] action:@selector(activate:)];
    controller_defaults.tag = 520;
    controller_defaults.contentTintColor = swanium_tint_color();
    controller_defaults.translatesAutoresizingMaskIntoConstraints = NO;
    [[controller_defaults widthAnchor] constraintEqualToConstant:settings_control_width].active = YES;
    [[controller_defaults heightAnchor] constraintEqualToConstant:settings_control_height].active = YES;
    [controller_stack setCustomSpacing:16.0 afterView:last_controller_button_row];
    [controller_stack addArrangedSubview:settings_row(@"", controller_defaults)];
    install_settings_stack(controller_stack, controller);
    NSTabViewItem *controller_tab = [[NSTabViewItem alloc] initWithIdentifier:@"controller"];
    controller_tab.label = @"Controller";
    controller_tab.view = settings_scroll_content(controller);
    [tabs addTabViewItem:controller_tab];
    [settings_panel.contentView addSubview:tabs];
  }
  NSRect parent = main_window.frame;
  [settings_panel setFrameOrigin:NSMakePoint(NSMidX(parent) - settings_panel.frame.size.width / 2, NSMidY(parent) - settings_panel.frame.size.height / 2)];
  [main_window addChildWindow:settings_panel ordered:NSWindowAbove];
  [settings_panel makeKeyAndOrderFront:nil];
}

void swanium_macos_settings_sync(const char **keyboard, const char **buttons, const int *directions) {
  for (NSInteger index = 0; index < 11; index++) keyboard_buttons[index].title = [NSString stringWithUTF8String:keyboard[index]];
  for (NSInteger index = 0; index < 3; index++) controller_buttons[index].title = [NSString stringWithUTF8String:buttons[index]];
  for (NSInteger index = 0; index < 3; index++) [direction_popups[index] selectItemAtIndex:directions[index]];
}

void swanium_macos_status_attach(void *native_window) {
  NSWindow *window = (__bridge NSWindow *)native_window;
  NSView *content = window.contentView;
  if (content == nil || status_footer != nil) return;
  const CGFloat height = 22.0;
  NSRect frame = content.bounds;
  NSVisualEffectView *footer = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, height)];
  footer.material = NSVisualEffectMaterialUnderWindowBackground;
  footer.blendingMode = NSVisualEffectBlendingModeWithinWindow;
  footer.state = NSVisualEffectStateActive;
  footer.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  status_label = [NSTextField labelWithString:@"Starting…"];
  status_label.frame = NSMakeRect(8, 3, frame.size.width - 126, 16);
  status_label.font = [NSFont systemFontOfSize:12];
  status_label.lineBreakMode = NSLineBreakByTruncatingMiddle;
  status_label.autoresizingMask = NSViewWidthSizable;
  [footer addSubview:status_label];
  NSImageView *speaker = [[NSImageView alloc] initWithFrame:NSMakeRect(frame.size.width - 116, 4, 14, 14)];
  speaker.image = [NSImage imageNamed:NSImageNameTouchBarAudioOutputVolumeHighTemplate];
  speaker.imageScaling = NSImageScaleProportionallyUpOrDown;
  speaker.autoresizingMask = NSViewMinXMargin;
  [footer addSubview:speaker];
  status_volume = [[NSSlider alloc] initWithFrame:NSMakeRect(frame.size.width - 98, 2, 90, 18)];
  status_volume.minValue = 0;
  status_volume.maxValue = 100;
  status_volume.integerValue = 100;
  status_volume.autoresizingMask = NSViewMinXMargin;
  [footer addSubview:status_volume];
  [content addSubview:footer];
  main_window = window;
  status_footer = footer;
}

void swanium_macos_status_attach_sdl_window(void *sdl_window) {
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (SDL_GetWindowWMInfo((SDL_Window *)sdl_window, &info) == SDL_FALSE) return;
  // The RGBA texture contains RGB444 values expanded into sRGB bytes. Declare
  // that source space explicitly so AppKit/ColorSync follows the same path as
  // the reference Swanium frontend instead of inheriting an SDL default.
  info.info.cocoa.window.colorSpace = NSColorSpace.sRGBColorSpace;
  swanium_macos_status_attach((__bridge void *)info.info.cocoa.window);
}

void swanium_macos_status_update(const char *text) {
  if (status_label != nil) status_label.stringValue = [NSString stringWithUTF8String:text];
}

void swanium_macos_status_detach(void) {
  [main_window removeChildWindow:settings_panel];
  [settings_panel orderOut:nil];
  [status_footer removeFromSuperview];
  status_footer = nil;
  status_label = nil;
  status_volume = nil;
}

int swanium_macos_status_volume(void) {
  return status_volume == nil ? 100 : (int)status_volume.integerValue;
}

void swanium_macos_status_set_volume(int value) {
  if (status_volume != nil) status_volume.integerValue = MAX(0, MIN(100, value));
}

int swanium_macos_status_reserved_height_pixels(void *sdl_window) {
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (SDL_GetWindowWMInfo((SDL_Window *)sdl_window, &info) == SDL_FALSE) return 0;
  return (int)lround(22.0 * info.info.cocoa.window.backingScaleFactor);
}
