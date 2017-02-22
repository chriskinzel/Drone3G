//
//  Drone3GGLView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/7/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GGLView.h"

#import <OpenGL/gl.h>
#import <pthread.h>

@implementation Drone3GGLView

@synthesize pixel_buffer_mutx;
@synthesize pixelBuffer;
@synthesize videoHeight;
@synthesize videoWidth;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
    }
    return self;
}

- (void)awakeFromNib {
    localPixelBuffer = NULL;
    pixelBuffer = NULL;
    
    pthread_mutex_t tmp;
    pthread_mutex_init(&tmp, NULL);
    pixel_buffer_mutx = &tmp;
}

- (void)allocatePixelBuffer {
    if(localPixelBuffer == NULL) {
        localPixelBuffer = malloc(videoHeight*videoWidth*3);
    } else {
        localPixelBuffer = realloc(localPixelBuffer, videoHeight*videoWidth*3);
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    static bool once = false;
    if(once == false) {
        glClearColor(0, 0, 0, 1);
        once = true;
    }

    glPixelZoom(self.frame.size.width / videoWidth, -self.frame.size.height / videoHeight);
    glWindowPos2d(0, self.frame.size.height);
    
    if(pixelBuffer != NULL) {
        pthread_mutex_lock(pixel_buffer_mutx);
        memcpy(localPixelBuffer, pixelBuffer, videoWidth*videoHeight*3);
        pthread_mutex_unlock(pixel_buffer_mutx);
        
        glDrawPixels(videoWidth, videoHeight, GL_RGB, GL_UNSIGNED_BYTE, localPixelBuffer);
    } else {
        glClear(GL_COLOR_BUFFER_BIT);
    }
}

@end
