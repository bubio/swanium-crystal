#import <Cocoa/Cocoa.h>
#import <SDL.h>
#import <SDL_syswm.h>

static int pending_action = 0;
static NSTextField *status_label = nil;
static NSSlider *status_volume = nil;
static NSString *opened_rom_path = nil;
static NSMutableArray<NSString *> *recent_rom_paths = nil;
static NSMenu *recent_menu = nil;
static NSMenuItem *pause_item = nil;
static NSMenuItem *fullscreen_item = nil;
static NSMenuItem *scale_items[4] = {nil};
static NSMenuItem *renderer_items[2] = {nil};
static NSMenuItem *load_state_items[10] = {nil};
static NSMenuItem *save_state_items[10] = {nil};

@interface SwaniumMenuTarget : NSObject
+ (instancetype)sharedTarget;
- (void)activate:(NSMenuItem *)sender;
@end

@implementation SwaniumMenuTarget
+ (instancetype)sharedTarget {
  static SwaniumMenuTarget *target;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ target = [[self alloc] init]; });
  return target;
}
- (void)activate:(NSMenuItem *)sender { pending_action = (int)sender.tag; }
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

static void add_top_level(NSMenu *bar, NSString *title, NSMenu *menu) {
  NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
  root.submenu = menu;
  [bar addItem:root];
}

void swanium_macos_menu_build(void) {
  [NSApplication sharedApplication];
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
  [emulation addItem:item(@"Open ROM…", 1)];
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
    [save_state addItem:save_state_items[slot]];
    load_state_items[slot] = item(title, 200 + slot);
    [load_state addItem:load_state_items[slot]];
  }
  NSMenuItem *save_root = [[NSMenuItem alloc] initWithTitle:@"Save State" action:nil keyEquivalent:@""];
  save_root.submenu = save_state;
  [emulation addItem:save_root];
  NSMenuItem *load_root = [[NSMenuItem alloc] initWithTitle:@"Load State" action:nil keyEquivalent:@""];
  load_root.submenu = load_state;
  [emulation addItem:load_root];
  [emulation addItem:[NSMenuItem separatorItem]];
  pause_item = item(@"Pause", 4);
  [emulation addItem:pause_item];
  [emulation addItem:item(@"Reset", 5)];
  add_top_level(bar, @"Emulation", emulation);

  NSMenu *view = submenu(@"View");
  NSMenu *scale = submenu(@"Scale");
  scale_items[0] = item(@"1x", 11);
  scale_items[1] = item(@"2x", 12);
  scale_items[2] = item(@"3x", 13);
  scale_items[3] = item(@"4x", 14);
  [scale addItem:scale_items[0]];
  [scale addItem:scale_items[1]];
  [scale addItem:scale_items[2]];
  [scale addItem:scale_items[3]];
  NSMenuItem *scale_root = [[NSMenuItem alloc] initWithTitle:@"Scale" action:nil keyEquivalent:@""];
  scale_root.submenu = scale;
  [view addItem:scale_root];
  fullscreen_item = item(@"Fullscreen", 20);
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
  for (NSInteger slot = 0; slot < 10; slot++) {
    save_state_items[slot].title = [NSString stringWithUTF8String:labels[slot]];
    load_state_items[slot].title = [NSString stringWithUTF8String:labels[slot]];
    load_state_items[slot].enabled = slots[slot] != 0;
  }
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
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.allowedFileTypes = @[@"ws", @"wsc"];
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

void swanium_macos_status_attach(void *native_window) {
  NSWindow *window = (__bridge NSWindow *)native_window;
  NSView *content = window.contentView;
  if (content == nil || status_label != nil) return;
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
}

void swanium_macos_status_attach_sdl_window(void *sdl_window) {
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (SDL_GetWindowWMInfo((SDL_Window *)sdl_window, &info) == SDL_FALSE) return;
  swanium_macos_status_attach((__bridge void *)info.info.cocoa.window);
}

void swanium_macos_status_update(const char *text) {
  if (status_label != nil) status_label.stringValue = [NSString stringWithUTF8String:text];
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
