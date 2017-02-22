//
//  Drone3GCollectionView.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <sys/time.h>

@interface Drone3GCollectionView : NSCollectionView {
    BOOL mouseIgnoreUp;
    
    NSDraggingItem* currentDraggingItem;
    NSEvent* initalDragEvent;
    
    NSInteger lastSelectedIndexNoMods;
    NSInteger lastSelectedIndex;
    
    NSPoint startDragPoint;
    NSSize dragImageSize;
        
    NSTimer* dragTimer;
    BOOL mouseDragging;
    BOOL restoreWindows;
    
    BOOL dragBackFlag;
    struct timeval startDragTimestamp;
}

- (void)deleteButtonPushed:(NSCollectionViewItem*)sender;

@end
