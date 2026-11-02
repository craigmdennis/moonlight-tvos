//
//  StreamFrameConfigurable.h
//  Moonlight
//
//  What the SwiftUI home screen sets on StreamFrameViewController. Swift can't
//  import StreamFrameViewController.h itself, because StreamView.h imports the
//  generated Swift header.
//

#import "StreamConfiguration.h"

@protocol StreamFrameConfigurable <NSObject>

@property (nonatomic) StreamConfiguration* streamConfig;
// tvOS home screen: called instead of showing an alert when the stream fails.
// kind is "launch", "connect" or "dropped".
@property (nonatomic, copy) void (^failureHandler)(NSString* kind, NSString* message);

@end
