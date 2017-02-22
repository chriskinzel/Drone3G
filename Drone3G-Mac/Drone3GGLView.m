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

@synthesize pixelBuffer;
@synthesize videoHeight;
@synthesize videoWidth;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        flash = -0.1f;
        flashTimer = NULL;
        
        gettimeofday(&current_timestamp, NULL);
        last_timestamp = current_timestamp;
    }
    return self;
}

- (void)awakeFromNib {    
    pixelBuffer = NULL;
}

- (void)reshape {
    CGLLockContext([[self openGLContext] CGLContextObj]);
    [super reshape];
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

// Makes sure flash is smooth
- (void)animateFlash {
    struct timeval timestamps[2];
    CGLLockContext([[self openGLContext] CGLContextObj]);
    timestamps[0] = current_timestamp;
    timestamps[1] = last_timestamp;
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
    
    if( (timestamps[0].tv_sec*1000000 + timestamps[0].tv_usec) - (timestamps[1].tv_usec + timestamps[1].tv_sec*1000000) > 33333) {
        [self setNeedsDisplay:YES];
    }
}

- (void)flash {
    flash = 1.0f;
    flashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/30.0f target:self selector:@selector(animateFlash) userInfo:nil repeats:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGLLockContext([[self openGLContext] CGLContextObj]);
    
    [super drawRect:dirtyRect];
    
    static bool once = false;
    if(once == false) {
        glClearColor(0, 0, 0, 1);
        once = true;
    }
    
    glPixelZoom(self.frame.size.width / videoWidth, -self.frame.size.height / videoHeight);
    glWindowPos2d(0, self.frame.size.height);
    
    if(pixelBuffer != NULL) {
        last_timestamp = current_timestamp;
        gettimeofday(&current_timestamp, NULL);
        
        glDrawPixels(videoWidth, videoHeight, GL_RGB, GL_UNSIGNED_BYTE, pixelBuffer);
        
        if(flash >= 0.0f) {
            glPixelTransferf(GL_RED_BIAS, flash);
            glPixelTransferf(GL_GREEN_BIAS, flash);
            glPixelTransferf(GL_BLUE_BIAS, flash);
            
            float delta = (float)( (current_timestamp.tv_sec*1000000 + current_timestamp.tv_usec) - (last_timestamp.tv_usec + last_timestamp.tv_sec*1000000) ) / 1000000.0f;
            flash -= 4.0f*delta;
            
            if(flash < 0.0f) {
                glPixelTransferf(GL_RED_BIAS, 0.0f);
                glPixelTransferf(GL_GREEN_BIAS, 0.0f);
                glPixelTransferf(GL_BLUE_BIAS, 0.0f);
            }
        } else {
            if(flashTimer != NULL) {
                [flashTimer invalidate];
                flashTimer = NULL;
            }
        }
    } else {
        glClear(GL_COLOR_BUFFER_BIT);
    }
    
    glFlush();
    
    CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

@end
