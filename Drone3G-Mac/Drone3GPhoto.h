//
//  Drone3GPhoto.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Drone3GPhoto : NSObject {
    NSImage* image;
    NSString* dateString;
    NSString* mediaPath;
    NSString* videoDurationString;
    
    BOOL isPhoto;
    BOOL isVideoAndReadyForPlayback;
    BOOL isVideoAndTranscoding;
}

@property (strong) NSImage* image;
@property (strong) NSString* dateString;
@property (strong) NSString* mediaPath;
@property (strong) NSString* videoDurationString;

@property (readonly) BOOL isPhoto;
@property (assign) BOOL isVideoAndReadyForPlayback;
@property (assign) BOOL isVideoAndTranscoding;

- (id)initWithMediaNamed:(NSString*)path;

- (void)updateDuration;
- (void)getVideoThumbnail;

@end
