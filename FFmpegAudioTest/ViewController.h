//
//  ViewController.h
//  FFmpegAudioTest
//
//  Created by Pontago on 12/06/17.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "FFmpegDecoder.h"

#define kNumAQBufs 3
#define kAudioBufferSeconds 3

typedef enum _AUDIO_STATE {
  AUDIO_STATE_READY           = 0,
  AUDIO_STATE_STOP            = 1,
  AUDIO_STATE_PLAYING         = 2,
  AUDIO_STATE_PAUSE           = 3,
  AUDIO_STATE_SEEKING         = 4
} AUDIO_STATE;

@interface ViewController : UIViewController {
  NSString *playingFilePath_;
  AudioStreamBasicDescription audioStreamBasicDesc_;
  AudioQueueRef audioQueue_;
  AudioQueueBufferRef audioQueueBuffer_[kNumAQBufs];
  BOOL started_, finished_;
  NSTimeInterval durationTime_, startedTime_;
  NSInteger state_;
  NSTimer *seekTimer_;
  NSLock *decodeLock_;

  FFmpegDecoder *ffmpegDecoder_;

  IBOutlet UILabel *fileNameLabel_, *seekLabel_;
  IBOutlet UISlider *seekSlider_;
  IBOutlet UIButton *playButton_, *stopButton_, *pauseButton_;
}

- (IBAction)playAudio:(UIButton*)sender;
- (IBAction)stopAudio:(UIButton*)sender;
- (IBAction)pauseAudio:(UIButton*)sender;
- (IBAction)updateSeekSlider:(UISlider*)sender;
- (void)updatePlaybackTime:(NSTimer*)timer;

- (void)startAudio_;
- (void)stopAudio_;
- (BOOL)createAudioQueue;
- (void)removeAudioQueue;
- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer;
- (void)audioQueueIsRunningCallback;
- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer;
- (OSStatus)startQueue;

@end
