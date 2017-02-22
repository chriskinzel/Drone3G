//
//  Drone3GMenuButton.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-24.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GMenuButton.h"
#import "Drone3GAppDelegate.h"

@implementation Drone3GMenuButton


- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        buttonColor = [NSColor whiteColor];
        
        vibrateTimer = NULL;
        
        initialFrameSize = self.frame.size;
        initialFontSize = 28;
        
        state = 0;
    }
    return self;
}

- (void)awakeFromNib {
    // Fix initial font sizes
    if([[self identifier] intValue] == 5) {
        initialFontSize = 19;
    }
    if([[self identifier] intValue] == 4) {
        initialFontSize = 26;
    }
    
    if( [[[NSUserDefaults standardUserDefaults] objectForKey:@"initial_launch"] boolValue] && [[[self viewWithTag:1] stringValue] isEqualToString:@"Install"]) {
        vibrateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/5.0 target:self selector:@selector(vibrate) userInfo:nil repeats:YES];
    }
    
    [self setNeedsDisplay:YES];
}

- (void)vibrate {
    static int counter = -20;
    
    counter++;
    if(counter > 2) {
        counter = -30;
    }
    if(counter < 0) {
        counter++;
        return;
    }
    
    NSRect currentFrame = self.frame;
    
    NSPoint oldCenter = NSMakePoint(currentFrame.origin.x + currentFrame.size.width/2, currentFrame.origin.y + currentFrame.size.height/2);
    
    currentFrame.size.width *= 1.2f;
    currentFrame.size.height *= 1.2f;
    
    currentFrame.origin.x = oldCenter.x - currentFrame.size.width/2;
    currentFrame.origin.y = oldCenter.y - currentFrame.size.height/2;
    
    [self setFrame:currentFrame];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSRect currentFrame = self.frame;
        
        NSPoint oldCenter = NSMakePoint(currentFrame.origin.x + currentFrame.size.width/2, currentFrame.origin.y + currentFrame.size.height/2);
        
        currentFrame.size.width /= 1.2f;
        currentFrame.size.height /= 1.2f;
        
        currentFrame.origin.x = oldCenter.x - currentFrame.size.width/2;
        currentFrame.origin.y = oldCenter.y - currentFrame.size.height/2;
        
        [self setFrame:currentFrame];
    });
}

- (void)mouseDown:(NSEvent *)theEvent {
    if(vibrateTimer != NULL && [vibrateTimer isValid]) {
        [vibrateTimer invalidate];
    }
    
    if(state != 0) {
        return;
    }
    state = 1;
    
    [[NSSound soundNamed:@"clickf.mp3"] play];
    
    NSRect currentFrame = self.frame;
    
    NSPoint oldCenter = NSMakePoint(currentFrame.origin.x + currentFrame.size.width/2, currentFrame.origin.y + currentFrame.size.height/2);
    
    currentFrame.size.width *= 1.2f;
    currentFrame.size.height *= 1.2f;
    
    currentFrame.origin.x = oldCenter.x - currentFrame.size.width/2;
    currentFrame.origin.y = oldCenter.y - currentFrame.size.height/2;
    
    [self setFrame:currentFrame];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSRect currentFrame = self.frame;
        
        NSPoint oldCenter = NSMakePoint(currentFrame.origin.x + currentFrame.size.width/2, currentFrame.origin.y + currentFrame.size.height/2);
        
        currentFrame.size.width /= 1.2f;
        currentFrame.size.height /= 1.2f;
        
        currentFrame.origin.x = oldCenter.x - currentFrame.size.width/2;
        currentFrame.origin.y = oldCenter.y - currentFrame.size.height/2;
        
        [self setFrame:currentFrame];
        
        [(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] menuButtonPushed:[[self identifier] intValue]];
        
        state = 0;
    });
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
        
    // Calculate scale
    float scaleX = self.frame.size.width / initialFrameSize.width;
    float scaleY = self.frame.size.height / initialFrameSize.height;
    float scale = (scaleX < scaleY) ? scaleX : scaleY;
    
    // Scale font
    [[self viewWithTag:1] setFont:[NSFont systemFontOfSize:initialFontSize*scale]];
    
    // Draw border
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetStrokeColorWithColor(ctx, [buttonColor CGColor]);
    CGContextSetLineWidth(ctx, 5*scale);
    CGContextStrokeRect(ctx, CGRectMake(0, 0, self.frame.size.width, self.frame.size.height));
}

- (void)setButtonColor:(NSColor *)color {
    buttonColor = color;
    
    [[self viewWithTag:1] setTextColor:buttonColor];
    [self setNeedsDisplay:YES];
}

@end
