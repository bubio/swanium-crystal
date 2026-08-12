#import <Cocoa/Cocoa.h>

static int pending_action = 0;
static NSTextField *status_label = nil;
static NSSlider *status_volume = nil;

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
  NSMenu *bar = NSApp.mainMenu;
  if (bar == nil || [bar itemWithTitle:@"Emulation"] != nil) return;

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

void swanium_macos_menu_hide(void) {
  NSMenu *bar = NSApp.mainMenu;
  NSMenuItem *host = [bar itemWithTitle:@"Swanium Crystal"];
  if (host != nil) host.hidden = YES;
}

void swanium_macos_status_attach(void *native_window) {
  NSWindow *window = (__bridge NSWindow *)native_window;
  NSView *content = window.contentView;
  if (content == nil || status_label != nil) return;
  NSView *sdl_view = content.subviews.firstObject;
  const CGFloat height = 26.0;
  NSRect frame = content.bounds;
  // SDL's Cocoa backend normally installs a child view. Older SDL builds
  // may make that view the content view itself; in that case the footer is
  // still a native overlay rather than silently disappearing.
  if (sdl_view != nil) {
    sdl_view.frame = NSMakeRect(0, height, frame.size.width, frame.size.height - height);
    sdl_view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  NSVisualEffectView *footer = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, height)];
  footer.material = NSVisualEffectMaterialSidebar;
  footer.blendingMode = NSVisualEffectBlendingModeWithinWindow;
  footer.state = NSVisualEffectStateActive;
  footer.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  status_label = [NSTextField labelWithString:@"Starting…"];
  status_label.frame = NSMakeRect(10, 5, frame.size.width - 145, 17);
  status_label.font = [NSFont systemFontOfSize:12];
  status_label.lineBreakMode = NSLineBreakByTruncatingMiddle;
  status_label.autoresizingMask = NSViewWidthSizable;
  [footer addSubview:status_label];
  NSTextField *volume_label = [NSTextField labelWithString:@"Volume"];
  volume_label.frame = NSMakeRect(frame.size.width - 130, 5, 48, 17);
  volume_label.font = [NSFont systemFontOfSize:12];
  volume_label.autoresizingMask = NSViewMinXMargin;
  [footer addSubview:volume_label];
  status_volume = [[NSSlider alloc] initWithFrame:NSMakeRect(frame.size.width - 78, 4, 68, 18)];
  status_volume.minValue = 0;
  status_volume.maxValue = 100;
  status_volume.integerValue = 100;
  status_volume.autoresizingMask = NSViewMinXMargin;
  [footer addSubview:status_volume];
  [content addSubview:footer];
}

void swanium_macos_status_update(const char *text) {
  if (status_label != nil) status_label.stringValue = [NSString stringWithUTF8String:text];
}

int swanium_macos_status_volume(void) {
  return status_volume == nil ? 100 : (int)status_volume.integerValue;
}
