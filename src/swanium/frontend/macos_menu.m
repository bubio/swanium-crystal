#import <Cocoa/Cocoa.h>

static int pending_action = 0;

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
