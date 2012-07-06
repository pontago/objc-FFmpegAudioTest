//
//  ViewController.m
//  FFmpegAudioTest
//
//  Created by Pontago on 12/06/17.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"


void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer);
void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID);

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer) {

    ViewController *viewController = (__bridge ViewController*)inClientData;
    [viewController audioQueueOutputCallback:inAQ inBuffer:inBuffer];
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID) {

    ViewController *viewController = (__bridge ViewController*)inClientData;
    [viewController audioQueueIsRunningCallback];
}

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.

    [self removeAudioQueue];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

- (IBAction)playAudio:(UIButton*)sender {
    [self startAudio_];
}

- (IBAction)pauseAudio:(UIButton*)sender {
    if (started_) {
      state_ = AUDIO_STATE_PAUSE;

      AudioQueuePause(audioQueue_);
      AudioQueueReset(audioQueue_);
    }
}

- (IBAction)stopAudio:(UIButton*)sender {
    [self stopAudio_];
}

- (IBAction)updateSeekSlider:(UISlider*)sender {
    if (started_) {
      state_ = AUDIO_STATE_SEEKING;

      AudioQueueStop(audioQueue_, YES);
      [ffmpegDecoder_ seekTime:seekSlider_.value];
      startedTime_ = seekSlider_.value;

      [self startAudio_];
    }
}

- (void)updatePlaybackTime:(NSTimer*)timer {
    AudioTimeStamp timeStamp;
    OSStatus status = AudioQueueGetCurrentTime(audioQueue_, NULL, &timeStamp, NULL);

    if (status == noErr) {
      SInt64 time = floor(durationTime_);
      NSTimeInterval currentTimeInterval = timeStamp.mSampleTime / audioStreamBasicDesc_.mSampleRate;
      SInt64 currentTime = floor(startedTime_ + currentTimeInterval);
      seekLabel_.text = [NSString stringWithFormat:@"%02llu:%02llu:%02llu / %02llu:%02llu:%02llu",
        ((currentTime / 60) / 60), (currentTime / 60), (currentTime % 60),
        ((time / 60) / 60), (time / 60), (time % 60)];

      seekSlider_.value = startedTime_ + currentTimeInterval;
    }
}


- (void)startAudio_ {
    if (started_) {
      AudioQueueStart(audioQueue_, NULL);
    }
    else {
      playingFilePath_ = [[NSBundle mainBundle] pathForResource:@"sample" ofType:@"flv"];
      fileNameLabel_.text = [playingFilePath_ lastPathComponent];

      if (![self createAudioQueue]) {
        abort();
      }
      [self startQueue];

      seekTimer_ = [NSTimer scheduledTimerWithTimeInterval:1.0
        target:self selector:@selector(updatePlaybackTime:) userInfo:nil repeats:YES];
    }

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      [self enqueueBuffer:audioQueueBuffer_[i]];
    }

    state_ = AUDIO_STATE_PLAYING;
}

- (void)stopAudio_ {
    if (started_) {
      AudioQueueStop(audioQueue_, YES);
      seekSlider_.value = 0.0;
      startedTime_ = 0.0;

      SInt64 time = floor(durationTime_);
      seekLabel_.text = [NSString stringWithFormat:@"0 / %02llu:%02llu:%02llu",
        ((time / 60) / 60), (time / 60), (time % 60)];

      [ffmpegDecoder_ seekTime:0.0];

      state_ = AUDIO_STATE_STOP;
      finished_ = NO;
    }
}

- (BOOL)createAudioQueue {
    state_ = AUDIO_STATE_READY;
    finished_ = NO;

    decodeLock_ = [[NSLock alloc] init];
    ffmpegDecoder_ = [[FFmpegDecoder alloc] init];
    NSInteger retLoaded = [ffmpegDecoder_ loadFile:playingFilePath_];
    if (retLoaded) return NO;


    // 16bit PCM LE.
    audioStreamBasicDesc_.mFormatID = kAudioFormatLinearPCM;
    audioStreamBasicDesc_.mSampleRate = ffmpegDecoder_.audioCodecContext_->sample_rate;
    audioStreamBasicDesc_.mBitsPerChannel = 16;
    audioStreamBasicDesc_.mChannelsPerFrame = ffmpegDecoder_.audioCodecContext_->channels;
    audioStreamBasicDesc_.mFramesPerPacket = 1;
    audioStreamBasicDesc_.mBytesPerFrame = audioStreamBasicDesc_.mBitsPerChannel / 8 
      * audioStreamBasicDesc_.mChannelsPerFrame;
    audioStreamBasicDesc_.mBytesPerPacket = 
      audioStreamBasicDesc_.mBytesPerFrame * audioStreamBasicDesc_.mFramesPerPacket;
    audioStreamBasicDesc_.mReserved = 0;
    audioStreamBasicDesc_.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;


    durationTime_ = [ffmpegDecoder_ duration];
    dispatch_async(dispatch_get_main_queue(), ^{
      SInt64 time = floor(durationTime_);
      seekLabel_.text = [NSString stringWithFormat:@"0 / %02llu:%02llu:%02llu",
        ((time / 60) / 60), (time / 60), (time % 60)];

      seekSlider_.maximumValue = durationTime_;
    });


    OSStatus status = AudioQueueNewOutput(&audioStreamBasicDesc_, audioQueueOutputCallback, (__bridge void*)self,
      NULL, NULL, 0, &audioQueue_);
    if (status != noErr) {
      NSLog(@"Could not create new output.");
      return NO;
    }

    status = AudioQueueAddPropertyListener(audioQueue_, kAudioQueueProperty_IsRunning, 
      audioQueueIsRunningCallback, (__bridge void*)self);
    if (status != noErr) {
      NSLog(@"Could not add propery listener. (kAudioQueueProperty_IsRunning)");
      return NO;
    }


//    [ffmpegDecoder_ seekTime:10.0];

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      status = AudioQueueAllocateBufferWithPacketDescriptions(audioQueue_, 
        ffmpegDecoder_.audioCodecContext_->bit_rate * kAudioBufferSeconds / 8, 
        ffmpegDecoder_.audioCodecContext_->sample_rate * kAudioBufferSeconds / 
          ffmpegDecoder_.audioCodecContext_->frame_size + 1, 
        audioQueueBuffer_ + i);
      if (status != noErr) {
        NSLog(@"Could not allocate buffer.");
        return NO;
      }
    }

    return YES;
}

- (void)removeAudioQueue {
    [self stopAudio_];
    started_ = NO;

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      AudioQueueFreeBuffer(audioQueue_, audioQueueBuffer_[i]);
    }
    AudioQueueDispose(audioQueue_, YES);
}


- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer {
    if (state_ == AUDIO_STATE_PLAYING) {
      [self enqueueBuffer:inBuffer];
    }
}

- (void)audioQueueIsRunningCallback {
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    OSStatus status = AudioQueueGetProperty(audioQueue_, kAudioQueueProperty_IsRunning, &isRunning, &size);

    if (status == noErr && !isRunning && state_ == AUDIO_STATE_PLAYING) {
      state_ = AUDIO_STATE_STOP;

      if (finished_) {
        dispatch_async(dispatch_get_main_queue(), ^{
          SInt64 time = floor(durationTime_);
          seekLabel_.text = [NSString stringWithFormat:@"%02llu:%02llu:%02llu / %02llu:%02llu:%02llu",
            ((time / 60) / 60), (time / 60), (time % 60),
            ((time / 60) / 60), (time / 60), (time % 60)];
        });
      }
    }
}


- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer {
    OSStatus status = noErr;
    NSInteger decodedDataSize = 0;
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;

    [decodeLock_ lock];

    while (buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity) {
      decodedDataSize = [ffmpegDecoder_ decode];

      if (decodedDataSize && buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= decodedDataSize) {
        memcpy(buffer->mAudioData + buffer->mAudioDataByteSize, 
          ffmpegDecoder_.audioBuffer_, decodedDataSize);

        buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
        buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = decodedDataSize;
        buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = 
          audioStreamBasicDesc_.mFramesPerPacket;

        buffer->mAudioDataByteSize += decodedDataSize;
        buffer->mPacketDescriptionCount++;
        [ffmpegDecoder_ nextPacket];
      }
      else {
        break;
      }
    }


    if (buffer->mPacketDescriptionCount > 0) {
      status = AudioQueueEnqueueBuffer(audioQueue_, buffer, 0, NULL);
      if (status != noErr) { 
        NSLog(@"Could not enqueue buffer.");
      }
    }
    else {
      AudioQueueStop(audioQueue_, NO);
      finished_ = YES;
    }

    [decodeLock_ unlock];

    return status;
}

- (OSStatus)startQueue {
    OSStatus status = noErr;

    if (!started_) {
      status = AudioQueueStart(audioQueue_, NULL);
      if (status == noErr) {
        started_ = YES;
      }
      else {
        NSLog(@"Could not start audio queue.");
      }
    }

    return status;
}

@end
