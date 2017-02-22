//
//  Drone3GGLView.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/7/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <sys/time.h>

@interface Drone3GGLView : NSOpenGLView {
    uint8_t* pixelBuffer;
    int videoWidth;
    int videoHeight;
    
    struct timeval current_timestamp;
    struct timeval last_timestamp;
    
    NSTimer* flashTimer;
    float flash;
}

@property (assign) uint8_t* pixelBuffer;
@property (assign) int videoWidth;
@property (assign) int videoHeight;

- (void)flash; // Simple flash animation for taking pictures 

@end
