// ABOUTME: Reports whether the test host can create VLC's macOS OpenGL output context.
// ABOUTME: Matches the vendor's pixel-format flags without changing playback or skipping tests.
#import <AppKit/AppKit.h>

// This probe deliberately uses the same deprecated OpenGL API as VLCKit's output.
int main(void) __attribute__((availability(macos, deprecated=10.14)));
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSOpenGLPixelFormatAttribute attributes[] = {
      NSOpenGLPFADoubleBuffer, NSOpenGLPFAAccelerated, NSOpenGLPFANoRecovery,
      NSOpenGLPFAColorSize, 24, NSOpenGLPFAAlphaSize, 8, NSOpenGLPFADepthSize, 24,
      NSOpenGLPFAWindow, NSOpenGLPFAAllowOfflineRenderers, 0
    };
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    if (format == nil) {
      puts("Pixel format: unavailable");
      return 0;
    }
    puts("Pixel format: created");
    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    puts(context == nil ? "OpenGL context: unavailable" : "OpenGL context: created");
  }
  return 0;
}
