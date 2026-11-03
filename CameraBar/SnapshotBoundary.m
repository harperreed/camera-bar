// ABOUTME: Serializes synchronous VLC shutdown off the main thread and guards snapshots.
// ABOUTME: Keeps media observers alive until their backend has stopped.
#import "SnapshotBoundary.h"
#import <VLCKit/vlc/vlc.h>

BOOL CBTakeSnapshot(VLCMediaPlayer *player, NSString *path, int width, int height) {
  @try {
    [player saveVideoSnapshotAt:path withWidth:width andHeight:height];
    return YES;
  } @catch (NSException *exception) {
    return NO;
  }
}

@implementation CBPlaybackSession {
  libvlc_media_player_t *_instance;
  dispatch_queue_t _queue;
  BOOL _stopped;
}

- (instancetype)initWithLibrary:(VLCLibrary *)library {
  if ((self = [super init])) {
    _stopped = YES;
    _instance = libvlc_media_player_new(library.instance);
    NSAssert(_instance != NULL, @"Could not allocate the media player");
    // The documented advanced initializer takes ownership of this instance.
    _player = [[VLCMediaPlayer alloc] initWithLibVLCInstance:_instance andLibrary:library];
    _queue = dispatch_queue_create("com.harper.camera-bar.playback-stop", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (BOOL)stopped {
  return _stopped;
}

- (void)snapshotAtPath:(NSString *)path completionHandler:(void (^)(BOOL))completionHandler {
  dispatch_async(_queue, ^{
    BOOL requested = CBTakeSnapshot(self.player, path, 1280, 0);
    BOOL saved = requested && [[NSFileManager defaultManager] fileExistsAtPath:path];
    dispatch_async(dispatch_get_main_queue(), ^{
      completionHandler(saved);
    });
  });
}

- (void)stopWithCompletionHandler:(void (^)(void))completionHandler {
  _stopped = NO;
  dispatch_async(_queue, ^{
    libvlc_media_player_stop(self->_instance);
    dispatch_async(dispatch_get_main_queue(), ^{
      // Keep self alive through the main-thread completion and release observers first.
      self.player.media = nil;
      self.player.drawable = nil;
      self->_stopped = YES;
      completionHandler();
    });
  });
}
@end
