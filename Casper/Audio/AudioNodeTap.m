#import "AudioNodeTap.h"

NSErrorDomain const AudioNodeTapErrorDomain = @"io.jeph.Casper.AudioNodeTap";

@implementation AudioNodeTap

+ (BOOL)installOnNode:(AVAudioNode *)node
                  bus:(AVAudioNodeBus)bus
           bufferSize:(AVAudioFrameCount)bufferSize
               format:(nullable AVAudioFormat *)format
                block:(AVAudioNodeTapBlock)block
                error:(NSError **)error {
  @try {
    [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
    return YES;
  } @catch (NSException *exception) {
    if (error) {
      *error = [NSError errorWithDomain:AudioNodeTapErrorDomain
                                   code:AudioNodeTapErrorRejected
                               userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: exception.name}];
    }
    return NO;
  }
}

@end
