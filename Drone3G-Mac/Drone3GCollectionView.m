//
//  Drone3GCollectionView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GCollectionView.h"
#import "Drone3GPhotosWindowController.h"
#import "Drone3GWindowMover.h"
#import "Drone3GPREFWindowController.h"

@interface Drone3GCollectionView ()
- (void)startDragging;
@end

@implementation Drone3GCollectionView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {

    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

// Animates new images
- (void)addSubview:(NSView *)aView {
    // If the visible check isn't present for some reason the initial images are all on the first spot
    if([self window].isVisible) {
        [NSAnimationContext beginGrouping];
        [[NSAnimationContext currentContext] setDuration:0.5f];
        
        [super addSubview:aView];
        [aView setFrameOrigin:NSMakePoint(self.bounds.size.width/2 - aView.frame.size.width/2, -100)];
        [[aView animator] setFrameOrigin:NSMakePoint(0, 0)];
        
        [NSAnimationContext endGrouping];
        
        return;
    }
    
    [super addSubview:aView];
}

// Called when image(s) need to be deleted
- (void)deleteButtonPushed:(NSCollectionViewItem*)sender {
    if([[self selectionIndexes] count] > 1 && ![[Drone3GPREFWindowController sharedPreferencesController] shouldSuppressMediaRemovalWarning]) {
        NSAlert* alert = [NSAlert alertWithMessageText:@"Are you sure you want to delete all selected items ?" defaultButton:@"Yes, delete all items" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"When you click one of the delete buttons in a selection with multiple items, the entire selection will be deleted."];
        
        [alert setShowsSuppressionButton:YES];
        
        NSModalResponse response = [alert runModal];
        
        BOOL alertSupression = [[alert suppressionButton] state];
        [[Drone3GPREFWindowController sharedPreferencesController] setMediaRemovalWarning:alertSupression];
        
        if(response != NSModalResponseOK) {
            return;
        }
    }
    
    // Delete all selected items
    float delay = 0.0f;
    for(int i=0;i<[[self content] count];i++) {
        NSCollectionViewItem* item = [self itemAtIndex:i];
        if([item isSelected] || [item isEqualTo:sender]) {
            [[Drone3GPhotosWindowController sharedPhotoWindowController] removeObjectFromPhotosArrayAtIndex:i];
            i = -1;
            
            [[NSSound soundNamed:@"Pop"] performSelector:@selector(play) withObject:nil afterDelay:delay];
            delay += 0.03f;
        }
    }
}

- (void)startDragging {
    if([[self selectionIndexes] count] == 0) {
        return;
    }
    
    lastSelectedIndexNoMods = -1;
    
    NSEvent* theEvent = [[NSApplication sharedApplication] currentEvent];
    initalDragEvent = theEvent;
    
    //[[NSPasteboard pasteboardWithName:NSDragPboard] declareTypes:[NSArray arrayWithObject:NSURLPboardType] owner:nil];
    //[[self delegate] collectionView:self writeItemsAtIndexes:[self selectionIndexes] toPasteboard:[NSPasteboard pasteboardWithName:NSDragPboard]];
    
    // Find origin (smallest x of visible selected, greatest y of visible selected)
    __block NSPoint origin = NSMakePoint(100000, 0);
    [[self selectionIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop){
        NSRect frameRect = [[self itemAtIndex:idx].view frame];
        NSPoint frameOrigin = frameRect.origin;
        frameRect = [[[self window] contentView] convertRect:frameRect fromView:self];
        
        if(NSIntersectsRect([[[self window] contentView] frame], frameRect)) {
            if(frameOrigin.x < origin.x) {
                origin.x = frameOrigin.x;
            }
            if(frameOrigin.y > origin.y) {
                origin.y = frameOrigin.y;
            }
        }
    }];
    
    NSImage* image = [self draggingImageForItemsAtIndexes:[self selectionIndexes] withEvent:theEvent offset:nil];
    dragImageSize = image.size;
    
    dragBackFlag = NO;
    gettimeofday(&startDragTimestamp, NULL);
    
    [[NSSound soundNamed:@"pop2.mp3"] play];
    
    currentDraggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:[(Drone3GPhotosWindowController*)[self delegate] calculateDragURLForItems:[self selectionIndexes]]];
    [currentDraggingItem setDraggingFrame:NSMakeRect(origin.x, origin.y, dragImageSize.width, dragImageSize.height) contents:image];
    
    // The first dragImage does all the work, I want the image to snap back if the drag was rejected and since the windows move out of the way
    // this is tricky because this method returns the images to the origin even though the windows aren't back yet which looks awful. After
    // trying a lot of different things this simple trick appearead to work the best, just call dragImage a second time and set slideBack to YES if the drag was rejected
    [[self beginDraggingSessionWithItems:[NSArray arrayWithObject:currentDraggingItem] event:theEvent source:self] setAnimatesToStartingPositionsOnCancelOrFail:NO];
}

#pragma mark -
#pragma mark Custom Event Handling

#pragma mark -
#pragma mark Dragging Session
#pragma mark -

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
    // Check for fullscreen
    for(NSWindow* currentWindow in [[NSApplication sharedApplication] windows]) {
        if( (([currentWindow styleMask] & NSFullScreenWindowMask) != 0 && [currentWindow isOnActiveSpace]) || ![[self window] isOnActiveSpace]) {
            return;
        }
    }
    
    // Move windows out of the way once drag point moves enough
    NSPoint startPoint = [[self window] convertRectToScreen:NSMakeRect(startDragPoint.x, startDragPoint.y, 1, 1)].origin;
    
    float dx = startPoint.x - screenPoint.x;
    float dy = startPoint.y - screenPoint.y;
    
    float drag_width  = [self itemPrototype].view.frame.size.width/2;
    float drag_height = [self itemPrototype].view.frame.size.height/2;
    
    if( ( fabsf(dx) > drag_width || fabsf(dy) > drag_height ) && !restoreWindows) {
        [[Drone3GWindowMover sharedWindowMover] moveAllWindows];
        restoreWindows = YES;
    }
    
    // Don't allow slide back until window movement animation is done
    if(![[Drone3GWindowMover sharedWindowMover] windowsMoved]) {
        return;
    }
    
    struct timeval current_timestamp;
    gettimeofday(&current_timestamp, NULL);
    
    if( (current_timestamp.tv_sec*1000000 + current_timestamp.tv_usec) - (startDragTimestamp.tv_usec + startDragTimestamp.tv_sec*1000000) >= 1000000) {
        NSRect dragRect = NSMakeRect(screenPoint.x - dragImageSize.width/2, screenPoint.y - dragImageSize.height/2, dragImageSize.width, dragImageSize.height);
        if(NSIntersectsRect(dragRect, [self window].frame) && !dragBackFlag) {
            NSRect windowFrame = [self window].frame;
            windowFrame.origin.x += [NSScreen mainScreen].frame.size.width/4 * ( (windowFrame.origin.x < [NSScreen mainScreen].frame.size.width/2) ? 1 : -1);
            [[self window] setFrame:windowFrame display:YES animate:YES];
            
            dragBackFlag = YES;
        } else {
            if(!NSIntersectsRect(dragRect, [self window].frame) && dragBackFlag) {
                NSRect windowFrame = [self window].frame;
                windowFrame.origin.x -= [NSScreen mainScreen].frame.size.width/4 * ( (windowFrame.origin.x < [NSScreen mainScreen].frame.size.width/2) ? 1 : -1);
                [[self window] setFrame:windowFrame display:YES animate:YES];
                
                dragBackFlag = NO;
                
                /*gettimeofday(&startDragTimestamp, NULL);
                startDragTimestamp.tv_usec += 200000;
                if(startDragTimestamp.tv_usec > 999999) {
                    startDragTimestamp.tv_sec += 1;
                    startDragTimestamp.tv_usec = startDragTimestamp.tv_usec % 1000000;
                }*/
            }
        }
    }
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    // Move windows back
    [[self window] makeKeyAndOrderFront:nil];
    
    if(restoreWindows) {
        [[Drone3GWindowMover sharedWindowMover] restoreAllWindows:[[self window] isOnActiveSpace]];
        restoreWindows = NO;
    }
}

#pragma mark -
#pragma mark Mouse Events
#pragma mark -

- (void)mouseDown:(NSEvent *)theEvent {
    startDragPoint = [theEvent locationInWindow];
    mouseIgnoreUp = YES;
    
    NSPoint windowLocation = [theEvent locationInWindow];
    
    for(int i=0;i<[[self content] count];i++) {
        NSCollectionViewItem* item = [self itemAtIndex:i];
        
        NSPoint viewLocation = [item.view convertPoint:windowLocation fromView:nil];
        if(NSPointInRect(viewLocation, [item.view bounds])) {
            dragTimer = [NSTimer scheduledTimerWithTimeInterval:0.25f target:self selector:@selector(startDragging) userInfo:nil repeats:NO];
            
            // Handle multi selection using shift key
            if([self selectionIndexes].count > 0) {
                if( ([theEvent modifierFlags] & NSShiftKeyMask) ) {
                    lastSelectedIndexNoMods = -1;
                    
                    BOOL direction = ![item isSelected];
                    [[self itemAtIndex:lastSelectedIndex] setSelected:direction];
                    
                    for(NSUInteger j=lastSelectedIndex;j!=i;(j > i) ? j-- : j++) {
                        NSUInteger index = (lastSelectedIndex > i) ? j-1 : j+1;
                        [[self itemAtIndex:index] setSelected:direction];
                    }
                    
                    [item setSelected:YES];
                    lastSelectedIndex = i;
                    
                    return;
                }
                
                // Handle multi selection using command key
                if( ([theEvent modifierFlags] & NSCommandKeyMask) ) {
                    lastSelectedIndexNoMods = -1;
                    
                    if([item isSelected]) {
                        [item setSelected:NO];
                        return;
                    }
                }
            }
            
            static BOOL once = NO;
            if(lastSelectedIndexNoMods == i && once) {
                mouseIgnoreUp = ![item isSelected];

            }
            once = YES;
            
            if(!([theEvent modifierFlags] & NSCommandKeyMask) ) {
                lastSelectedIndexNoMods = i;
            }
            
            [item setSelected:YES];
            lastSelectedIndex = i;
        }
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if( ([theEvent modifierFlags] & NSCommandKeyMask) || ([theEvent modifierFlags] & NSShiftKeyMask) ) {
        return;
    }
    
    [self autoscroll:theEvent];
    
    mouseIgnoreUp = YES;
    mouseDragging = YES;
    
    [dragTimer invalidate];
    
    // Drag and select
    NSPoint windowLocation = [theEvent locationInWindow];
    NSRect dragRect = NSMakeRect((windowLocation.x < startDragPoint.x) ? windowLocation.x : startDragPoint.x, (windowLocation.y < startDragPoint.y) ? windowLocation.y : startDragPoint.y, fabs(startDragPoint.x - windowLocation.x), fabs(startDragPoint.y - windowLocation.y));
    
    for(int i=0;i<[[self content] count];i++) {
        NSCollectionViewItem* item = [self itemAtIndex:i];
        
        NSRect viewRect = [item.view convertRect:dragRect fromView:nil];
        if(NSIntersectsRect(viewRect, [item.view bounds])) {
            [item setSelected:YES];
        }
    }
    
    lastSelectedIndexNoMods = -1;
}

- (void)mouseUp:(NSEvent *)theEvent {
    [dragTimer invalidate];
    
    NSPoint windowLocation = [theEvent locationInWindow];
    
    // Deselect item if it is clicked while selected
    BOOL hitTest = NO;
    for(int i=0;i<[[self content] count];i++) {
        NSCollectionViewItem* item = [self itemAtIndex:i];
        
        NSPoint viewLocation = [item.view convertPoint:windowLocation fromView:nil];
        if(NSPointInRect(viewLocation, [item.view bounds])) {
            hitTest = YES;
            
            if(!mouseIgnoreUp && !([theEvent modifierFlags] & NSCommandKeyMask) && !([theEvent modifierFlags] & NSShiftKeyMask) ) {
                [item setSelected:NO];
            }
            
            if(!([theEvent modifierFlags] & NSShiftKeyMask) && !([theEvent modifierFlags] & NSCommandKeyMask) && !mouseDragging) {
                [[self selectionIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop){
                    if(idx != i && idx < [[self content] count]) {
                        [[self itemAtIndex:idx] setSelected:NO];
                    }
                }];
            }
        }
    }
    
    // Deselect if nothing was selected
    if(!hitTest && !mouseDragging) {
        [[self selectionIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop){
            [[self itemAtIndex:idx] setSelected:NO];
        }];
    }
    
    mouseDragging = NO;
}

@end
