#import <Cocoa/Cocoa.h>
#import <SDL.h>
#import <SDL_syswm.h>

static int pending_action = 0;
static NSTextField *status_label = nil;
static NSSlider *status_volume = nil;
static NSString *opened_rom_path = nil;

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
  NSMenu *recent = submenu(@"Open Recent");
  NSMenuItem *no_recent = [[NSMenuItem alloc] initWithTitle:@"No Recent ROMs" action:nil keyEquivalent:@""];
  no_recent.enabled = NO;
  [recent addItem:no_recent];
  NSMenuItem *recent_root = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
  recent_root.submenu = recent;
  [emulation addItem:recent_root];
  [emulation addItem:[NSMenuItem separatorItem]];
  NSMenu *save_state = submenu(@"Save State");
  NSMenu *load_state = submenu(@"Load State");
  for (NSInteger slot = 0; slot < 10; slot++) {
    NSString *title = [NSString stringWithFormat:@"Slot %ld", (long)slot];
    [save_state addItem:item(title, 100 + slot)];
    [load_state addItem:item(title, 200 + slot)];
  }
  NSMenuItem *save_root = [[NSMenuItem alloc] initWithTitle:@"Save State" action:nil keyEquivalent:@""];
  save_root.submenu = save_state;
  [emulation addItem:save_root];
  NSMenuItem *load_root = [[NSMenuItem alloc] initWithTitle:@"Load State" action:nil keyEquivalent:@""];
  load_root.submenu = load_state;
  [emulation addItem:load_root];
  [emulation addItem:[NSMenuItem separatorItem]];
  [emulation addItem:item(@"Pause", 4)];
  [emulation addItem:item(@"Reset", 5)];
  add_top_level(bar, @"Emulation", emulation);

  NSMenu *view = submenu(@"View");
  NSMenu *scale = submenu(@"Scale");
  [scale addItem:item(@"1x", 11)];
  [scale addItem:item(@"2x", 12)];
  [scale addItem:item(@"3x", 13)];
  [scale addItem:item(@"4x", 14)];
  NSMenuItem *scale_root = [[NSMenuItem alloc] initWithTitle:@"Scale" action:nil keyEquivalent:@""];
  scale_root.submenu = scale;
  [view addItem:scale_root];
  [view addItem:item(@"Fullscreen", 20)];
  [view addItem:[NSMenuItem separatorItem]];
  NSMenu *renderer = submenu(@"Renderer");
  [renderer addItem:item(@"Nearest Neighbor", 31)];
  [renderer addItem:item(@"Bilinear", 32)];
  NSMenuItem *renderer_root = [[NSMenuItem alloc] initWithTitle:@"Renderer" action:nil keyEquivalent:@""];
  renderer_root.submenu = renderer;
  [view addItem:renderer_root];
  add_top_level(bar, @"View", view);
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

int swanium_macos_status_reserved_height_pixels(void *sdl_window) {
  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  if (SDL_GetWindowWMInfo((SDL_Window *)sdl_window, &info) == SDL_FALSE) return 0;
  return (int)lround(22.0 * info.info.cocoa.window.backingScaleFactor);
}
