//
//  Drone3GPhotosWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GPhotosWindowController : NSWindowController <NSCollectionViewDelegate, NSFileManagerDelegate> {
    NSMutableArray* photosArray;
}

@property (assign) IBOutlet NSCollectionView* photoView;
@property (assign) IBOutlet NSTextField* emptyLabel;

@property (strong) NSMutableArray* photosArray;

+ (id)sharedPhotoWindowController;

- (void)insertObject:(id)p inPhotosArrayAtIndex:(NSUInteger)index;
- (void)removeObjectFromPhotosArrayAtIndex:(NSUInteger)index;

- (NSURL*)calculateDragURLForItems:(NSIndexSet*)indexes;

@end
