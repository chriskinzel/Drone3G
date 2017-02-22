//
//  Drone3GGLView.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/7/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GGLView : NSOpenGLView {
    uint8_t* pixelBuffer;
    uint8_t* localPixelBuffer;
    
    int videoWidth;
    int videoHeight;
    
    pthread_mutex_t* pixel_buffer_mutx;
}

@property (readonly) pthread_mutex_t* pixel_buffer_mutx;

@property (assign) uint8_t* pixelBuffer;
@property (assign) int videoWidth;
@property (assign) int videoHeight;

- (void)allocatePixelBuffer;

@end
