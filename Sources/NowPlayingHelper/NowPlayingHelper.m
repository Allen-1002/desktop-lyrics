// 读取系统“正在播放”信息（控制中心里那张卡片）。
//
// macOS 15.4 起，普通应用直接调用 MediaRemote 私有框架会拿不到数据，
// 只有带权限的系统程序可以。这里的做法参考 ungive/mediaremote-adapter
// （BSD 3-Clause, Copyright (c) 2025 Jonas van den Berg）：
// 由系统自带的 /usr/bin/perl 加载本动态库，再在它的进程里调用 MediaRemote。

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <stdio.h>

#import "NowPlayingHelper.h"

typedef void (*MRGetNowPlayingInfo_t)(dispatch_queue_t queue, void (^completion)(NSDictionary *info));
typedef void (*MRGetIsPlaying_t)(dispatch_queue_t queue, void (^completion)(bool isPlaying));
typedef void (*MRGetPID_t)(dispatch_queue_t queue, void (^completion)(int pid));

static NSString *const kTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const kArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const kAlbum = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString *const kDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const kElapsed = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const kTimestamp = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const kRate = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";

static NSString *stringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static double numberValue(id value) {
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
}

static void emit(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) {
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

void dl_now_playing_loop(void) {
    NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)url);
    if (!bundle) {
        fprintf(stderr, "MediaRemote framework not found\n");
        return;
    }
    MRGetNowPlayingInfo_t getInfo =
        (MRGetNowPlayingInfo_t)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingInfo"));
    MRGetIsPlaying_t getIsPlaying = (MRGetIsPlaying_t)CFBundleGetFunctionPointerForName(
        bundle, CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying"));
    MRGetPID_t getPID =
        (MRGetPID_t)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingApplicationPID"));
    if (!getInfo || !getIsPlaying || !getPID) {
        fprintf(stderr, "MediaRemote functions not found\n");
        return;
    }

    // 回调和等待不能在同一个串行队列上，否则会互相卡住
    dispatch_queue_t timerQueue = dispatch_queue_create("desktoplyrics.nowplaying.timer", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t callbackQueue = dispatch_queue_create("desktoplyrics.nowplaying.callback", DISPATCH_QUEUE_SERIAL);

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 500 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
      @autoreleasepool {
          __block NSDictionary *info = nil;
          __block bool playing = false;
          __block int pid = 0;

          dispatch_group_t group = dispatch_group_create();
          dispatch_group_enter(group);
          getInfo(callbackQueue, ^(NSDictionary *value) {
            info = value;
            dispatch_group_leave(group);
          });
          dispatch_group_enter(group);
          getIsPlaying(callbackQueue, ^(bool value) {
            playing = value;
            dispatch_group_leave(group);
          });
          dispatch_group_enter(group);
          getPID(callbackQueue, ^(int value) {
            pid = value;
            dispatch_group_leave(group);
          });
          if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0) {
              return;
          }

          NSString *bundleID = @"";
          if (pid > 0) {
              NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
              bundleID = app.bundleIdentifier ?: @"";
          }

          NSString *title = stringValue(info[kTitle]);
          if (title.length == 0) {
              emit(@{@"bundle" : bundleID, @"playing" : @NO});
              return;
          }

          // elapsedTime 是 timestamp 那一刻的位置，换算成现在的位置
          double position = numberValue(info[kElapsed]);
          id timestamp = info[kTimestamp];
          double rate = info[kRate] ? numberValue(info[kRate]) : (playing ? 1 : 0);
          if (playing && [timestamp isKindOfClass:[NSDate class]]) {
              position += -[(NSDate *)timestamp timeIntervalSinceNow] * (rate > 0 ? rate : 1);
          }

          emit(@{
              @"bundle" : bundleID,
              @"title" : title,
              @"artist" : stringValue(info[kArtist]),
              @"album" : stringValue(info[kAlbum]),
              @"duration" : @(numberValue(info[kDuration])),
              @"position" : @(position),
              @"playing" : @(playing),
          });
      }
    });
    dispatch_resume(timer);
    dispatch_main();
}
