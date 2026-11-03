// ABOUTME: Owns the VLC player and exposes safe stop and snapshot operations.
// ABOUTME: Serializes backend shutdown before Swift starts another camera.
#import <Foundation/Foundation.h>
#import <VLCKit/VLCKit.h>

BOOL CBTakeSnapshot(VLCMediaPlayer * _Nonnull player, NSString * _Nonnull path, int width, int height);

@interface CBPlaybackSession : NSObject
@property(nonatomic, readonly, nonnull) VLCMediaPlayer *player;
@property(nonatomic, readonly) BOOL stopped;
- (nonnull instancetype)initWithLibrary:(nonnull VLCLibrary *)library;
- (void)snapshotAtPath:(nonnull NSString *)path completionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- (void)stopWithCompletionHandler:(void (^ _Nonnull)(void))completionHandler;
@end
