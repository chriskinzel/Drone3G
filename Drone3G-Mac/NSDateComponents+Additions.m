//
//  NSDateComponents+Additions.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-16.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSDateComponents+Additions.h"

@implementation NSDateComponents (Additions)

+ (NSString*)getDateStringFormatYYYYMMDD_hhmmssForDate:(NSDate *)date {
    NSDateComponents* dateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:date];
    return [NSString stringWithFormat:@"%li%li%li%li%li_%li%li%li%li%li%li", [dateComponents year], [dateComponents month] / 10, [dateComponents month] % 10, [dateComponents day] / 10, [dateComponents day] % 10, [dateComponents hour] / 10, [dateComponents hour] % 10, [dateComponents minute] / 10, [dateComponents minute] % 10, [dateComponents second] / 10, [dateComponents second] % 10];
}

@end
