#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const AudioNodeTapErrorDomain;

typedef NS_ERROR_ENUM(AudioNodeTapErrorDomain, AudioNodeTapError) {
  /// AVFAudio rejected the tap, such as for a format that doesn't match the hardware.
  AudioNodeTapErrorRejected = 1,
};

/// Installs taps on audio nodes, reporting a tap that AVFAudio rejects as an error instead of a crash.
///
/// AVFAudio raises an Objective-C exception when it rejects a tap, such as one whose sample rate no longer matches the
/// hardware because a device, like Bluetooth headphones, changed its format while the tap was being installed. Swift
/// can't catch the exception, and it mustn't unwind through Swift code, so the tap is installed here. macOS 27 reports
/// the same failures as errors through `installTapOnBus:bufferSize:format:error:block:`, which can replace this once
/// Casper requires it.
@interface AudioNodeTap : NSObject

+ (BOOL)installOnNode:(AVAudioNode *)node
                  bus:(AVAudioNodeBus)bus
           bufferSize:(AVAudioFrameCount)bufferSize
               format:(nullable AVAudioFormat *)format
                block:(AVAudioNodeTapBlock)block
                error:(NSError **)error NS_SWIFT_NAME(install(on:bus:bufferSize:format:block:));

@end

NS_ASSUME_NONNULL_END
