//
//  Drone3GPhotoController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GPhoto.h"
#import "Drone3GPhotoController.h"
#import "Drone3GCollectionView.h"

#import <QuartzCore/QuartzCore.h>

@interface Drone3GPhotoController ()

@end

@implementation Drone3GPhotoController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    if([(Drone3GPhoto*)[self representedObject] isVideoAndTranscoding]) {
        [super setSelected:NO];
        return;
    }
    
    [super setSelected:selected];
    
    // Disable shadow when item is selected
    [[[self.view viewWithTag:1] layer] setShadowOpacity:(selected) ? 0.0f : 1.0f];
    
    if(selected) {
        [[[self.view viewWithTag:2] animator] setHidden:NO];
    } else {
        [[self.view viewWithTag:2] setHidden:YES];
    }
}

- (IBAction)trashImage:(id)sender {
    [(Drone3GCollectionView*)[self collectionView] deleteButtonPushed:self];
}

- (IBAction)playVideo:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:[(Drone3GPhoto*)[self representedObject] mediaPath]];
}

@end
