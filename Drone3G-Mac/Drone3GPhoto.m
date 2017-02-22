//
//  Drone3GPhoto.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "Drone3GPhoto.h"

@implementation Drone3GPhoto

@synthesize image;
@synthesize dateString;
@synthesize mediaPath;
@synthesize isPhoto;
@synthesize isVideoAndReadyForPlayback;
@synthesize isVideoAndTranscoding;
@synthesize videoDurationString;

- (id)initWithMediaNamed:(NSString*)path {
    if(self = [super init]) {
        videoDurationString = @"";
        mediaPath = path;
        
        NSString* mediaTypeString = @"picture_";
        NSString* mediaExtString = @".jpg";
        
        if([[path pathExtension] rangeOfString:@"mp4"].location != NSNotFound) {
            mediaTypeString = @"video_";
            mediaExtString = @".mp4";
            
            isPhoto = NO;
            isVideoAndReadyForPlayback = YES;
            isVideoAndTranscoding = NO;
            
            [self getVideoThumbnail];
            [self updateDuration];
        } else if([[path pathExtension] rangeOfString:@"tcv"].location != NSNotFound) {
            mediaTypeString = @"video_";
            mediaExtString = @".tcv";
            
            isPhoto = NO;
            isVideoAndReadyForPlayback = NO;
            isVideoAndTranscoding = YES;
            
            NSString* thumbnailPath = [[[mediaPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"] stringByReplacingOccurrencesOfString:mediaTypeString withString:@"thumbnail_"];
            image = [[NSImage alloc] initWithContentsOfFile:thumbnailPath];
            if(!image) {
                image = [[NSWorkspace sharedWorkspace] iconForFileType:@"mp4"];
            }
        } else {
            isPhoto = YES;
            isVideoAndReadyForPlayback = NO;
            isVideoAndTranscoding = NO;
            
            image = [[NSImage alloc] initWithContentsOfFile:[path stringByExpandingTildeInPath]];
        }
        
        if(!image) {
            return nil;
        }
        
        NSString* shortDate = [[[path lastPathComponent] stringByReplacingOccurrencesOfString:mediaTypeString withString:@""] stringByReplacingOccurrencesOfString:mediaExtString withString:@""];
        if([shortDate length] < 14) {
            return nil;
        }
        
        int year = [[shortDate substringToIndex:4] intValue];
        int monthNum = [[shortDate substringWithRange:NSMakeRange(4, 2)] intValue];
        int dayNum = [[shortDate substringWithRange:NSMakeRange(6, 2)] intValue];
        
        int hour24format = [[shortDate substringWithRange:NSMakeRange(9, 2)] intValue];
        int minute = [[shortDate substringWithRange:NSMakeRange(11, 2)] intValue];
        
        NSDateComponents* dateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:[NSDate date]];
        [dateComponents setDay:dayNum];
        [dateComponents setMonth:monthNum];
        NSDate* date = [[NSCalendar currentCalendar] dateFromComponents:dateComponents];
        
        NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
        
        int lengths[12] = {3,3,3,5,3,4,4,3,4,3,3,3};
        
        dateFormatter.dateFormat = @"MMMM";
        NSString* monthString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:lengths[monthNum-1]];
        
        dateFormatter.dateFormat=@"EEEE";
        NSString* dayString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:3];
        
        NSString* suffix_string = @"st|nd|rd|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|st|nd|rd|th|th|th|th|th|th|th|st";
        NSArray* suffixes = [suffix_string componentsSeparatedByString: @"|"];
        
        dateString = [NSString stringWithFormat:@"%d:%d%d%@ - %@ %@ %d%@ %d", (hour24format > 12) ? hour24format-12 : ( (hour24format == 0) ? 12 : hour24format), minute / 10, minute % 10, (hour24format >= 12) ? @"PM" : @"AM", dayString, monthString, dayNum, [suffixes objectAtIndex:dayNum-1], year];
    }
    
    return self;
}

- (void)getVideoThumbnail {
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:mediaPath] options:nil];
    if(asset == nil) {
        return;
    }
    
    AVAssetImageGenerator* generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;

    CGSize maxSize = CGSizeMake(223, 125);
    
    generator.maximumSize = maxSize;
    CGImageRef cgImage = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(0,30) actualTime:nil error:nil];
    
    if(cgImage == NULL) {
        NSLog(@"Error could not get video thumbnail for '%@' .\n", [[mediaPath lastPathComponent] stringByDeletingPathExtension]);
        
        image = [[NSWorkspace sharedWorkspace] iconForFileType:@"mp4"];
        return;
    }
    
    image = [[NSImage alloc] initWithCGImage:cgImage size:maxSize];
    CGImageRelease(cgImage);
}

- (void)updateDuration {
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:mediaPath] options:nil];
    if(asset == nil) {
        return;
    }
    
    int videoDuration = (int)CMTimeGetSeconds(asset.duration);
    
    int minutes = videoDuration / 60;
    int seconds = videoDuration % 60;
    
    if(minutes < 10) {
        if(seconds < 10) {
            videoDurationString = [NSString stringWithFormat:@"0%i:0%i", minutes, seconds];
        } else {
            videoDurationString = [NSString stringWithFormat:@"0%i:%i", minutes, seconds];
        }
    } else {
        if(seconds < 10) {
            videoDurationString = [NSString stringWithFormat:@"%i:0%i", minutes, seconds];
        } else {
            videoDurationString = [NSString stringWithFormat:@"%i:%i", minutes, seconds];
        }
    }
    
    [self setVideoDurationString:videoDurationString];
}

@end
