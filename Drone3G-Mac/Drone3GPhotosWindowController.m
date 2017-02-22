//
//  Drone3GPhotosWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSFileManager+Additions.h"

#import "Drone3GPhotosWindowController.h"
#import "Drone3GPhotoController.h"
#import "Drone3GPhoto.h"

#import "drone_main.h"

#import <CoreServices/CoreServices.h>
#import <pthread.h>

@implementation Drone3GPhotosWindowController

@synthesize photosArray;
@synthesize photoView;
@synthesize emptyLabel;

id cself;
NSMutableArray* processedImages = NULL;
NSMutableArray* processedVideos = NULL;

static void* process_video(void* _filename) {
    const char* filename = (const char*)_filename;
    
    NSString* videoDirectory = [[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"];
    
    char raw_path[1024];
    char final_path[1024];
    char thumb_path[1024];
    char* tmp_path = malloc(1024);
    
    sprintf(raw_path, "%s/%s", [videoDirectory UTF8String], filename);
    sprintf(thumb_path, "%s/thumbnail_%s.jpg", [videoDirectory UTF8String], [[[NSString stringWithUTF8String:filename+6] stringByDeletingPathExtension] UTF8String]);
    sprintf(tmp_path, "%s/%s", [videoDirectory UTF8String], [[[[NSString stringWithUTF8String:filename] stringByDeletingPathExtension] stringByAppendingPathExtension:@"tcv"] UTF8String]);
    sprintf(final_path, "%s/%s", [videoDirectory UTF8String], [[[[NSString stringWithUTF8String:filename] stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"] UTF8String]);
    
    free(_filename);
    
    int ret = drone3g_transcode_video(raw_path, tmp_path, &transcoding_progress_update, (void*)tmp_path);
    if(ret < 0) {
        unlink(raw_path);
        unlink(tmp_path);
        unlink(thumb_path);
        
        if(ret == -2) { // File was deleted
            free(tmp_path);
            return NULL;
        }
        
        // Remove from collection view
        dispatch_async(dispatch_get_main_queue(), ^{
            [[cself photosArray] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
                if([[(Drone3GPhoto*)obj mediaPath] isEqualToString:[NSString stringWithUTF8String:tmp_path]]) {
                    [cself removeObjectFromPhotosArrayAtIndex:idx];
                    *stop = YES;
                }
            }];
            
            free(tmp_path);
        });
        
        return NULL;
    }
    
    // Rename tmp transcoding file to mp4
    rename(tmp_path, final_path);
    
    // Delete raw file
    unlink(raw_path);
    
    // Delete thumbnail
    unlink(thumb_path);
    
    // Change item status in collection view
    dispatch_async(dispatch_get_main_queue(), ^{
        [[cself photosArray] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
            Drone3GPhoto* media = (Drone3GPhoto*)obj;
            if([[media mediaPath] isEqualToString:[NSString stringWithUTF8String:tmp_path]]) {
                [media setMediaPath:[[[media mediaPath] stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"]];
                
                [media getVideoThumbnail];
                [media updateDuration];
                
                [[[[[cself photoView] itemAtIndex:idx] view] viewWithTag:1] setImage:[media image]];
                
                [media setIsVideoAndTranscoding:NO];
                [media setIsVideoAndReadyForPlayback:YES];
                
                *stop = YES;
            }
        }];
        
        free(tmp_path);
    });
        
    return NULL;
}

static void transcoding_progress_update(float progress, void* ident) {
    if(progress < 0.0f) {
        return;
    }
        
    dispatch_async(dispatch_get_main_queue(), ^{
        char* tmp_path = (char*)ident;
        
        [[cself photosArray] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
            Drone3GPhoto* media = (Drone3GPhoto*)obj;
            if([[media mediaPath] isEqualToString:[NSString stringWithUTF8String:tmp_path]]) {
                Drone3GPhotoController* pc = (Drone3GPhotoController*)[[cself photoView] itemAtIndex:idx];
                
                NSProgressIndicator* progressBar = nil;
                for(NSView* subview in [[pc view] subviews]) {
                    if([[subview identifier] isEqualToString:@"progressBar"]) {
                        progressBar = (NSProgressIndicator*)subview;
                    }
                }
                
                if(progressBar != nil) {
                    [progressBar setIndeterminate:NO];
                    [progressBar setDoubleValue:progress];
                }
                                
                *stop = YES;
            }
        }];
    });
}

static void videos_directory_changed_callback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    NSString* videoDirectory = [[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"];
    
    NSArray* files = [defaultManager contentsOfDirectoryAtPath:videoDirectory error:nil];
    for(NSString* filename in files) {
        if([processedVideos containsObject:filename] || (![[filename pathExtension] isEqualToString:@"tmp"] && ![[filename pathExtension] isEqualToString:@"mp4"] && ![[filename pathExtension] isEqualToString:@"tcv"]) ) {
            continue;
        }
        
        if([[filename pathExtension] isEqualToString:@"tmp"]) {
            char* cname = malloc(28);
            strcpy(cname, [filename UTF8String]);
            
            pthread_t work_thread;
            pthread_create(&work_thread, NULL, &process_video, (void*)cname);
            
            [processedVideos addObject:filename];
            
            continue;
        }
        if(![processedVideos containsObject:[[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"tcv"]]) {
            NSMutableArray* pArray = [cself photosArray];
            
            Drone3GPhoto* photo = [[Drone3GPhoto alloc] initWithMediaNamed:[videoDirectory stringByAppendingPathComponent:filename]];
            [pArray addObject:photo];
            
            [cself setPhotosArray:pArray];
        }
        
        [processedVideos addObject:filename];
    }
}

static void photos_directory_changed_callback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    NSString* photoDirectory = [[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Photos"];
    
    NSArray* files = [defaultManager contentsOfDirectoryAtPath:photoDirectory error:nil];
    for(NSString* filename in files) {
        if([processedImages containsObject:filename] || ![[filename pathExtension] isEqualToString:@"jpg"]) {
            continue;
        }
        
        [processedImages addObject:filename];
        
        NSMutableArray* pArray = [cself photosArray];
        
        Drone3GPhoto* photo = [[Drone3GPhoto alloc] initWithMediaNamed:[photoDirectory stringByAppendingPathComponent:filename]];
        [pArray addObject:photo];
        
        [cself setPhotosArray:pArray];
    }
}

static void cleanup_photos_directory() {
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    NSString* photoDirectory = [[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Photos"];
    
    NSArray* files = [defaultManager contentsOfDirectoryAtPath:photoDirectory error:nil];
    for(NSString* filename in files) {
        if([[filename pathExtension] isEqualToString:@"tmp"]) {
            [defaultManager removeItemAtPath:[photoDirectory stringByAppendingPathComponent:filename] error:nil];
        }
    }
}

static void cleanup_videos_directory() {
    NSFileManager* defaultManager = [NSFileManager defaultManager];
    NSString* videoDirectory = [[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"];
    
    NSArray* files = [defaultManager contentsOfDirectoryAtPath:videoDirectory error:nil];
    for(NSString* filename in files) {
        if([[filename pathExtension] isEqualToString:@"tcv"]) {
            [defaultManager removeItemAtPath:[videoDirectory stringByAppendingPathComponent:filename] error:nil];
            continue;
        }
        if([[filename pathExtension] isEqualToString:@"jpg"]) { // Remove abandoned thumbnails
            NSString* rawPath = [[[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"tmp"] stringByReplacingOccurrencesOfString:@"thumbnail" withString:@"video"];
            if(![defaultManager fileExistsAtPath:[videoDirectory stringByAppendingPathComponent:rawPath]]) {
                [defaultManager removeItemAtPath:[videoDirectory stringByAppendingPathComponent:filename] error:nil];
            }
            
            continue;
        }
        
        // FFmpeg needs to enough bytes to scan the stream so any tmp files less than 100KB are useless
        if([[filename pathExtension] isEqualToString:@"tmp"]) {
            NSString* fullPath = [videoDirectory stringByAppendingPathComponent:filename];
            
            NSDictionary* fileAttributes = [defaultManager attributesOfItemAtPath:fullPath error:nil];
            unsigned long long size = [[fileAttributes objectForKey:NSFileSize] unsignedLongLongValue];
            if(size < 100*1024) {
                [defaultManager removeItemAtPath:fullPath error:nil];
                continue;
            }
        }
    }
}

+ (id)sharedPhotoWindowController {
    static Drone3GPhotosWindowController* sharedController = nil;
    static dispatch_once_t once_token;
    dispatch_once(&once_token, ^{
        sharedController = [[self alloc] init];
    });
    
    return sharedController;
}

- (id)init {
    self = [super initWithWindowNibName:@"PhotoViewerWindow"];
    if(self) {
        cleanup_photos_directory();
        cleanup_videos_directory();
        
        if(processedImages == NULL) {
            processedImages = [NSMutableArray array];
        }
        if(processedVideos == NULL) {
            processedVideos = [NSMutableArray array];
        }
        
        photosArray = [NSMutableArray array];
        cself = self;
        
        // Loads the photo view at application startup (needed so that photos can be scanned immediately)
        [[self window] setIsVisible:NO];
    }
    
    return self;
}

- (void)awakeFromNib {
    // Load previously saved photos
    photos_directory_changed_callback(0, NULL, 0, NULL, NULL, NULL);
    videos_directory_changed_callback(0, NULL, 0, NULL, NULL, NULL);
    
    [photoView setBackgroundColors:@[[NSColor clearColor]]];
    
    // Register FSEvent to look for new images
    CFStringRef watchPath = (__bridge CFStringRef)[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Photos"];
    CFArrayRef pathsArray = CFArrayCreate(NULL, (const void**)&watchPath, 1, NULL);
    
    FSEventStreamRef stream = FSEventStreamCreate(NULL, &photos_directory_changed_callback, NULL, pathsArray, kFSEventStreamEventIdSinceNow, 0.1, kFSEventStreamCreateFlagNone);
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    FSEventStreamStart(stream);
    
    CFRelease(pathsArray);
    
    // Register FSEvent to look for new videos
    watchPath = (__bridge CFStringRef)[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"];
    pathsArray = CFArrayCreate(NULL, (const void**)&watchPath, 1, NULL);
    
    stream = FSEventStreamCreate(NULL, &videos_directory_changed_callback, NULL, pathsArray, kFSEventStreamEventIdSinceNow, 0.1, kFSEventStreamCreateFlagNone);
    FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    FSEventStreamStart(stream);
    
    CFRelease(pathsArray);
    
    [photoView setDelegate:self];
    [photoView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
    
    [[NSFileManager defaultManager] setDelegate:self];
}

/*- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}*/

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)showWindow:(id)sender {
    if([[self window] isVisible] && ([[NSApplication sharedApplication] currentEvent].modifierFlags & NSCommandKeyMask) ) { // Alternates visibillity for hot keys
        [[self window] performClose:nil];
        return;
    }
    
    // Deselect all photos
    [photoView setSelectionIndexes:[NSIndexSet indexSet]];
    
    [[self window] center];
    [super showWindow:sender];
}

#pragma mark -
#pragma mark NSFileManager Delegate Methods
#pragma mark -

- (BOOL)fileManager:(NSFileManager *)fileManager shouldProceedAfterError:(NSError *)error copyingItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath {
    if([error code] == NSFileWriteFileExistsError) { // Overwrite copies in the temporary directory
        if([dstPath rangeOfString:NSTemporaryDirectory()].location != NSNotFound) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark -
#pragma mark Collection View Delegate Methods
#pragma mark -

- (NSURL*)calculateDragURLForItems:(NSIndexSet*)indexes {
    // If more than one image create a folder for the set
    if([indexes count] > 1) {
        // Find common demoniator among dragged images to calculate folder name
        NSString* folderName = @"ARDrone "; // Worst case scenario fall back to this
        
        __block BOOL hasVideo = NO;
        __block BOOL hasPhotos = NO;
        
        __block int commonDay, commonYear=0;
        __block char* commonMonth = alloca(6);
        
        [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            Drone3GPhoto* photo = [photosArray objectAtIndex:idx];
            if(photo.isPhoto) {
                hasPhotos = YES;
            }
            if(photo.isVideoAndReadyForPlayback) {
                hasVideo = YES;
            }
            
            int hour;
            int minute;
            char halfDay[3];
            char dayName[4];
            char monthName[6];
            int day;
            char suffix[3];
            int year;
            
            sscanf([photo.dateString UTF8String], "%d:%d%s - %s %s %d%s %d", &hour, &minute, halfDay, dayName, monthName, &day, suffix, &year);
            
            if(commonYear == 0) {
                commonDay = day;
                commonYear = year;
                strcpy(commonMonth, monthName);
            } else {
                if(commonDay != day) {
                    commonDay = -1;
                }
                if(commonMonth != NULL) {
                    if(strcmp(commonMonth, monthName) != 0) {
                        commonDay = -1;
                        commonMonth = NULL;
                    }
                }
                if(commonYear != year) {
                    commonDay = -1;
                    commonMonth = NULL;
                    year = -1;
                    
                    *stop = YES;
                }
            }
        }];
        
        if(hasVideo && hasPhotos) {
            folderName = [folderName stringByAppendingString:@"Media"];
        } else if(hasPhotos) {
            folderName = [folderName stringByAppendingString:@"Photos"];
        } else {
            folderName = [folderName stringByAppendingString:@"Videos"];
        }
        
        if(commonDay != -1) { // Items had day in common
            NSString* suffix_string = @"st|nd|rd|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|st|nd|rd|th|th|th|th|th|th|th|st";
            NSArray* suffixes = [suffix_string componentsSeparatedByString: @"|"];
            
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %s %d%@ %d", commonMonth, commonDay, [suffixes objectAtIndex:commonDay-1], commonYear]];
        } else if(commonMonth != NULL) {
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %s %d", commonMonth, commonYear]];
        } else if(commonYear != -1) {
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %d", commonYear]];
        }
        
        NSString* tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:folderName];
        
        // Remove folder if it already exists
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        
        // Create folder
        NSError* error;
        if(![[NSFileManager defaultManager] createDirectoryAtPath:tmpPath withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Error file manager could not create temporary media directory! %@\n", [error localizedDescription]);
        }
        
        if(hasPhotos && hasVideo) {
            [[NSFileManager defaultManager] removeItemAtPath:[tmpPath stringByAppendingPathComponent:@"Photos"] error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[tmpPath stringByAppendingPathComponent:@"Videos"] error:nil];
            
            if(![[NSFileManager defaultManager] createDirectoryAtPath:[tmpPath stringByAppendingPathComponent:@"Videos"] withIntermediateDirectories:NO attributes:nil error:&error]) {
                NSLog(@"Error file manager could not create temporary media video directory! %@\n", [error localizedDescription]);
            }
            if(![[NSFileManager defaultManager] createDirectoryAtPath:[tmpPath stringByAppendingPathComponent:@"Photos"] withIntermediateDirectories:NO attributes:nil error:&error]) {
                NSLog(@"Error file manager could not create temporary media photo directory! %@\n", [error localizedDescription]);
            }
        }
        
        NSURL* temporaryDirectoryURL = [NSURL fileURLWithPath:tmpPath isDirectory:YES];
        [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            Drone3GPhoto* photo = [photosArray objectAtIndex:idx];
            
            NSString* photoName = [[[photo mediaPath] lastPathComponent] stringByReplacingOccurrencesOfString:@"picture" withString:@"ARDrone"];
            photoName = [photoName stringByReplacingOccurrencesOfString:@"video" withString:@"ARDrone"];
            
            NSURL* folderURL;
            if(hasVideo && hasPhotos) {
                folderURL = [[temporaryDirectoryURL URLByAppendingPathComponent:(photo.isPhoto) ? @"Photos" : @"Videos"] URLByAppendingPathComponent:photoName];
            } else {
                folderURL = [temporaryDirectoryURL URLByAppendingPathComponent:photoName];
            }
            
            NSError* error;
            if(![[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:[photo mediaPath]] toURL:folderURL error:&error]) {
                NSLog(@"Error file manager could not copy file \"%@\". %@\n", [[photo mediaPath] lastPathComponent], [error localizedDescription]);
            }
        }];
        
        return temporaryDirectoryURL;
    } else {
        NSURL* temporaryDirectoryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
        
        Drone3GPhoto* photo = [photosArray objectAtIndex:[indexes firstIndex]];
        if([photo isVideoAndTranscoding]) {
            return NO;
        }
        
        NSString* photoName = [[[photo mediaPath] lastPathComponent] stringByReplacingOccurrencesOfString:@"picture" withString:@"ARDrone"];
        photoName = [photoName stringByReplacingOccurrencesOfString:@"video" withString:@"ARDrone"];
        NSURL* url = [temporaryDirectoryURL URLByAppendingPathComponent:photoName];
        
        NSError* error;
        if(![[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:[photo mediaPath]] toURL:url error:&error]) {
            NSLog(@"Error file manager could not copy file \"%@\". %@\n", [[photo mediaPath] lastPathComponent], [error localizedDescription]);
        }
        
        return url;
    }
}

// Drag and drop
- (BOOL)collectionView:(NSCollectionView *)collectionView writeItemsAtIndexes:(NSIndexSet *)indexes toPasteboard:(NSPasteboard *)pasteboard {
    // If more than one image create a folder for the set
    if([indexes count] > 1) {
        // Find common demoniator among dragged images to calculate folder name
        NSString* folderName = @"ARDrone "; // Worst case scenario fall back to this
        
        __block BOOL hasVideo = NO;
        __block BOOL hasPhotos = NO;
        
        __block int commonDay, commonYear=0;
        __block char* commonMonth = alloca(6);

        [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            Drone3GPhoto* photo = [photosArray objectAtIndex:idx];
            if(photo.isPhoto) {
                hasPhotos = YES;
            }
            if(photo.isVideoAndReadyForPlayback) {
                hasVideo = YES;
            }
            
            int hour;
            int minute;
            char halfDay[3];
            char dayName[4];
            char monthName[6];
            int day;
            char suffix[3];
            int year;
            
            sscanf([photo.dateString UTF8String], "%d:%d%s - %s %s %d%s %d", &hour, &minute, halfDay, dayName, monthName, &day, suffix, &year);
            
            if(commonYear == 0) {
                commonDay = day;
                commonYear = year;
                strcpy(commonMonth, monthName);
            } else {
                if(commonDay != day) {
                    commonDay = -1;
                }
                if(commonMonth != NULL) {
                    if(strcmp(commonMonth, monthName) != 0) {
                        commonDay = -1;
                        commonMonth = NULL;
                    }
                }
                if(commonYear != year) {
                    commonDay = -1;
                    commonMonth = NULL;
                    year = -1;
                    
                    *stop = YES;
                }
            }
        }];
        
        if(hasVideo && hasPhotos) {
            folderName = [folderName stringByAppendingString:@"Media"];
        } else if(hasPhotos) {
            folderName = [folderName stringByAppendingString:@"Photos"];
        } else {
            folderName = [folderName stringByAppendingString:@"Videos"];
        }
        
        if(commonDay != -1) { // Items had day in common
            NSString* suffix_string = @"st|nd|rd|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|st|nd|rd|th|th|th|th|th|th|th|st";
            NSArray* suffixes = [suffix_string componentsSeparatedByString: @"|"];
            
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %s %d%@ %d", commonMonth, commonDay, [suffixes objectAtIndex:commonDay-1], commonYear]];
        } else if(commonMonth != NULL) {
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %s %d", commonMonth, commonYear]];
        } else if(commonYear != -1) {
            folderName = [folderName stringByAppendingString:[NSString stringWithFormat:@" %d", commonYear]];
        }
        
        NSString* tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:folderName];
        
        // Remove folder if it already exists
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        
        // Create folder
        NSError* error;
        if(![[NSFileManager defaultManager] createDirectoryAtPath:tmpPath withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Error file manager could not create temporary media directory! %@\n", [error localizedDescription]);
        }
        
        if(hasPhotos && hasVideo) {
            [[NSFileManager defaultManager] removeItemAtPath:[tmpPath stringByAppendingPathComponent:@"Photos"] error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[tmpPath stringByAppendingPathComponent:@"Videos"] error:nil];
            
            if(![[NSFileManager defaultManager] createDirectoryAtPath:[tmpPath stringByAppendingPathComponent:@"Videos"] withIntermediateDirectories:NO attributes:nil error:&error]) {
                NSLog(@"Error file manager could not create temporary media video directory! %@\n", [error localizedDescription]);
            }
            if(![[NSFileManager defaultManager] createDirectoryAtPath:[tmpPath stringByAppendingPathComponent:@"Photos"] withIntermediateDirectories:NO attributes:nil error:&error]) {
                NSLog(@"Error file manager could not create temporary media photo directory! %@\n", [error localizedDescription]);
            }
        }
        
        NSURL* temporaryDirectoryURL = [NSURL fileURLWithPath:tmpPath isDirectory:YES];
        [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            Drone3GPhoto* photo = [photosArray objectAtIndex:idx];
            
            NSString* photoName = [[[photo mediaPath] lastPathComponent] stringByReplacingOccurrencesOfString:@"picture" withString:@"ARDrone"];
            photoName = [photoName stringByReplacingOccurrencesOfString:@"video" withString:@"ARDrone"];
            
            NSURL* folderURL;
            if(hasVideo && hasPhotos) {
                folderURL = [[temporaryDirectoryURL URLByAppendingPathComponent:(photo.isPhoto) ? @"Photos" : @"Videos"] URLByAppendingPathComponent:photoName];
            } else {
                folderURL = [temporaryDirectoryURL URLByAppendingPathComponent:photoName];
            }
            
            NSError* error;
            if(![[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:[photo mediaPath]] toURL:folderURL error:&error]) {
                NSLog(@"Error file manager could not copy file \"%@\". %@\n", [[photo mediaPath] lastPathComponent], [error localizedDescription]);
            }
        }];
        
        [pasteboard clearContents];
        return [pasteboard writeObjects:@[temporaryDirectoryURL]];
    } else {
        NSURL* temporaryDirectoryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];

        Drone3GPhoto* photo = [photosArray objectAtIndex:[indexes firstIndex]];
        if([photo isVideoAndTranscoding]) {
            return NO;
        }
        
        NSString* photoName = [[[photo mediaPath] lastPathComponent] stringByReplacingOccurrencesOfString:@"picture" withString:@"ARDrone"];
        photoName = [photoName stringByReplacingOccurrencesOfString:@"video" withString:@"ARDrone"];
        NSURL* url = [temporaryDirectoryURL URLByAppendingPathComponent:photoName];
        
        NSError* error;
        if(![[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:[photo mediaPath]] toURL:url error:&error]) {
            NSLog(@"Error file manager could not copy file \"%@\". %@\n", [[photo mediaPath] lastPathComponent], [error localizedDescription]);
        }
        
        [pasteboard clearContents];
        return [pasteboard writeObjects:@[url]];
    }
}

#pragma mark -
#pragma mark KVC functions
#pragma mark -

- (void)insertObject:(id)p inPhotosArrayAtIndex:(NSUInteger)index {
    [photosArray insertObject:p atIndex:index];
}

- (void)removeObjectFromPhotosArrayAtIndex:(NSUInteger)index {
    NSString* photoPath = [[photosArray objectAtIndex:index] mediaPath];
    
    // Delete image file
    NSError* error;
    if(![[NSFileManager defaultManager] removeItemAtPath:photoPath error:&error]) {
        NSLog(@"Error file manager could not delete file \"%@\". %@\n", [photoPath lastPathComponent], [error localizedDescription]);
    }
    
    // If this is a transcoding video remove the raw h264 as well
    if([[photoPath pathExtension] isEqualToString:@"tcv"]) {
        if(![[NSFileManager defaultManager] removeItemAtPath:[[photoPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"tmp"] error:&error]) {
            NSLog(@"Error file manager could not delete file \"%@\". %@\n", [photoPath lastPathComponent], [error localizedDescription]);
        }
    }
    
    [photosArray removeObjectAtIndex:index];
    
    if([photosArray count] == 0) {
        [[emptyLabel animator] setHidden:NO];
    }
}

- (void)setPhotosArray:(NSMutableArray *)a {
    // Have images in the collection view so hide the empty message
    [emptyLabel setHidden:YES];
    
    photosArray = a;
}

- (NSArray*)photosArray {
    return photosArray;
}

@end
