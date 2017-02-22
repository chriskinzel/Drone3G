//
//  drone_main.c
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#include "drone_main.h"
#include "drone_com.h"
#include "drone3g_installer.h"

#import "NSDateComponents+Additions.h"
#import "NSFileManager+Additions.h"

#import "Drone3GAppDelegate.h"
#import "Drone3GMDCalculator.h"

#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#include <errno.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <sched.h>
#include <syslog.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>

#include "libavformat/avformat.h"
#include "libavformat/avio.h"
#include "libavcodec/avcodec.h"
#include "libswscale/swscale.h"

#include <SDL2/SDL.h>
#include <OpenGL/gl.h>

#define JOYSTICK_COND_LAND       0
#define JOYSTICK_COND_HOVER      1
#define JOYSTICK_COND_TAKEOFF    2
#define JOYSTICK_COND_FTRIM      3
#define JOYSTICK_COND_EMERGENCY  4
#define JOYSTICK_COND_SWITCH_CAM 5
#define JOYSTICK_COND_CALIB      6
#define JOYSTICK_COND_FLYHOME    7
#define JOYSTICK_COND_READ_BAT   8
#define JOYSTICK_COND_SETHOME    9
#define JOYSTICK_COND_PICTURE    10
#define JOYSTICK_COND_RECORD     11
#define JOYSTICK_COND_READ_PING  12

#define GET_BIT(n,x) ((n & (1 << x)) > 0)
#define FILTER 0.3f

#pragma mark TODO: NOW
#pragma mark -

// TODO: iPhone as controller (Build the iphone app first but then add support for using it as a bluetooth controller)

// TODO: EULA needs website when ready

#pragma mark -

#pragma mark TODO: FUTURE
#pragma mark -

// TODO: SWITCH TO MAPKIT

// TODO: When in loiter state drone could transistion back into translate state if AT*SETHOME was received
// FIXME: Compass might not show home angle sometimes (south?)
// TODO: Guess baud rate

// TODO: Could add support for any generic controller by letting the user set it up
// TODO: Rewrite this code is an absolute platform dependent mess. Even the photo viewer (which was never designed for video) is a complete mess now.

// TODO: Encrypted data transmission (SSL ?)

// TODO: Could store controller preferences on drone
// TODO: Could have "multiple" loadable controller preferences

#pragma mark -

// THREAD VARIABLES
pthread_t drone3g_thread;
pthread_t date_thread;
pthread_t joystick_thread;

pthread_mutex_t joystick_lock;

// CONTROL VARIABLES
drone3g_button_map button_mapping[DRONE3G_NUM_FUNCTIONS];
float sens_array[4] = {0.25, 0.23f, 0.60f, 0.45f};
int stick_layout = DRONE3G_STICK_LAYOUT_RH;

// MISC GENERAL VARIABLES
Drone3GAppDelegate* appDelegate = NULL;
SDL_Joystick* joystick = NULL;

int drone3g_inited = 0;

AVFormatContext* formatCtx = NULL;
int ffmpeg_inited = 0;

int is_flying = 0;
int is_transcoding = 0;

int flat_trimming = 0;
struct timeval flat_trim_timestamp;

// TEMPORAL STATE VARIABLES
uint64_t last_sent_bytes = 0;
uint64_t last_recv_bytes = 0;

uint32_t last_ctrl_state = 1;
uint32_t last_drone_state = 0;

// BATTERY VARIABLES
int had_battery_warning = 0;
int had_battery_emergency = 0;
int battery_halfway_point;

// VIDEO VARIABLES
int stream_bit_count = 0;
int frame_count = 0;

// GPS VARIABLES
double takeoff_lat = -1000.0;
double takeoff_lon = -1000.0;
float magnetic_declination = 0.0f;
float return_angle = 180.0f;
float return_distance = 0.0f;
char last_fix_state = 1;

// VARIABLES FOR PICTURE DOWNLOADING
FILE* current_image_fp = NULL;
char current_image_name[28];
size_t current_image_size;
size_t current_image_total_size = 0;

// RECORDING VARIABLES
FILE* current_video_fp = NULL;
char current_video_name[28] = {0};

int record_state = 0;
int record_to_usb = 0;
int previous_bitrate = 250;

int get_thumbnail = 0;

// PING VARIABLES
void(*current_ping_callback)(int);

int pong_count = 0;
int accm_latency = 0;

struct timeval ping_timestamp;

static void magnetic_declination_callback(float md);
extern void drone3g_set_ffmpeg_port(int port);

#pragma mark -
#pragma mark Cleanup
#pragma mark -

void drone3g_exit(int signum) {
    // If application exits close the telnet connection
    drone3g_send_command("AT*TELCLOSE\r");
    drone3g_close_sockets();
    
    /*if(formatCtx != NULL) {
        avformat_close_input(&formatCtx);
        avformat_network_deinit();
    }
    
    // Shutdown SDL, we have to make sure all threads accessing the joystick are either blocked or terminated
    pthread_mutex_lock(&joystick_lock);
    pthread_cancel(joystick_thread);
    pthread_join(joystick_thread, NULL);
    SDL_Quit();
    
    //closelog(); Why does this stall?
    
    if(signum == SIGTERM) {
        exit(0);
    }*/
}

#pragma mark -
#pragma mark Getters
#pragma mark -

drone3g_button_map* drone3g_get_button_mapping() {
    return button_mapping;
}

float* drone3g_get_sensitivities_array() {
    return sens_array;
}

int drone3g_get_stick_layout() {
    return stick_layout;
}

drone3g_termination_status_info drone3g_allow_termination() {
    return ( is_transcoding*2 | is_flying | ((drone3g_installer_get_status() & 3) << 2) );
}

#pragma mark -
#pragma mark Setters
#pragma mark -

pthread_mutex_t button_map_mutex;
void drone3g_lock_button_map() {
    static int once = 0;
    if(once == 0) {
        once = 1;
        pthread_mutex_init(&button_map_mutex, NULL);
    }
    
    pthread_mutex_lock(&button_map_mutex);
}

void drone3g_unlock_button_map() {
    pthread_mutex_unlock(&button_map_mutex);
}

pthread_mutex_t sensitivities_mutex;
void drone3g_lock_sensitivities_array() {
    static int once = 0;
    if(once == 0) {
        once = 1;
        pthread_mutex_init(&sensitivities_mutex, NULL);
    }
    
    pthread_mutex_lock(&sensitivities_mutex);
}

void drone3g_unlock_sensitivities_array() {
    pthread_mutex_unlock(&sensitivities_mutex);
}

void drone3g_set_stick_layout(drone3g_stick_layout mode) {
    stick_layout = mode;
}

void drone3g_set_recording_mode(drone3g_recording_mode mode) {
    record_to_usb = mode;
}

#pragma mark -
#pragma mark Misc
#pragma mark -

static void render_time_string(int minutes, int seconds) {
    NSString* timeString;
    
    if(minutes < 10) {
        if(seconds < 10) {
            timeString = [NSString stringWithFormat:@"0%i:0%i", minutes, seconds];
        } else {
            timeString = [NSString stringWithFormat:@"0%i:%i", minutes, seconds];
        }
    } else {
        if(seconds < 10) {
            timeString = [NSString stringWithFormat:@"%i:0%i", minutes, seconds];
        } else {
            timeString = [NSString stringWithFormat:@"%i:%i", minutes, seconds];
        }
    }
    
    [[appDelegate timeFlyingLabel] setStringValue:timeString];
}

static void calculate_bitrate(AVPacket* packet) {
    if(frame_count <= 30*10) {
        stream_bit_count += packet->size*8;
        frame_count++;
    }
    
    if(frame_count == 30*10) {
        int avg_bitrate = stream_bit_count/1024/10;
        syslog(LOG_NOTICE, "Estimated bitrate %iKbps\n", avg_bitrate);
        
        NSSlider* slider = [[appDelegate bitrateSlider] viewWithTag:1];
        avg_bitrate = (avg_bitrate < 250) ? 250 : avg_bitrate;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[appDelegate bitrateLabel] setStringValue:[NSString stringWithFormat:@"                Bitrate: %iKbps", avg_bitrate]];
            [slider setIntValue:avg_bitrate];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [slider setEnabled:YES];
            [[appDelegate bitrateLabel] setTextColor:[NSColor controlTextColor]];
        });
        
        stream_bit_count = 0;
    }
}

static void internal_ping_read_callback(int latency) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[appDelegate alertSpeaker] startSpeakingString:[NSString stringWithFormat:@"Current latency is %i milliseconds.", latency]];
    });
}

// Does 3 pings and averages
void drone3g_test_latency(void(*callback)(int)) {
    current_ping_callback = callback;
    pong_count = 0;
    accm_latency = 0;
    
    drone3g_send_command("AT*PING\r");
    gettimeofday(&ping_timestamp, NULL);
}

#pragma mark -
#pragma mark Work Loops
#pragma mark -

static void* joystick_connect_loop(void* arg) {
    while(1) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            pthread_mutex_lock(&joystick_lock);
            
            SDL_PollEvent(NULL); // This is the function that must be called on the main thread that checks for joystick reconnect
            
            if(joystick == NULL && SDL_NumJoysticks() > 0) {
                for(int i=0;i<SDL_NumJoysticks();i++) {
                    const char* joystick_name = SDL_JoystickNameForIndex(i);
                    
                    if(strstr(joystick_name, "PLAYSTATION") != NULL) {
                        joystick = SDL_JoystickOpen(i);
                        
                        syslog(LOG_NOTICE, "Joystick Connected! %s\n", joystick_name);
                        
                        [appDelegate stopFlashingControllerIcon];
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                            [[appDelegate controllerImageView] setHidden:NO];
                        });
                        
                        [[[appDelegate gpsLabel] animator] setFrameOrigin:NSMakePoint([appDelegate controllerImageView].frame.origin.x + [appDelegate controllerImageView].frame.size.width+2, [appDelegate controllerImageView].frame.origin.y+1)];
                        
                        [appDelegate setJoystickDidConnect:YES];
                        [[[appDelegate helpButton] animator] setHidden:YES];
                        
                        break;
                    }
                }
            }
            if(joystick != NULL && SDL_JoystickGetAttached(joystick) == SDL_FALSE) {
                syslog(LOG_NOTICE, "Joystick Disconnected!\n");
                
                if(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_FLYING) { // When flying we animate the controller icon on disconnection
                    [appDelegate flashControllerIcon];
                } else {
                    [[appDelegate controllerImageView] setHidden:YES];
                    [[[appDelegate gpsLabel] animator] setFrameOrigin:NSMakePoint([appDelegate signalLevelImageView].frame.origin.x + [appDelegate signalLevelImageView].frame.size.width, [appDelegate signalLevelImageView].frame.origin.y)];
                }
                
                
                SDL_JoystickClose(joystick);
                joystick = NULL;
            }
            
            pthread_mutex_unlock(&joystick_lock);
        });
        
        sleep(1);
    }
    
    return NULL;
}

static int check_joystick_condition(int index) {
    drone3g_lock_button_map();
    
    int condition = 0;
    for(int i=0;i<button_mapping[index].num_of_buttons;i++) {
        condition |= SDL_JoystickGetButton(joystick, button_mapping[index].buttons[i]);
    }
    
    drone3g_unlock_button_map();
    
    return condition;
}

static void* control_loop(void* arg) {
    int hover = 0;
    struct timeval hover_time_ref;
    hover_time_ref.tv_sec = -1;
    
    int cam_state = 0;
    
    int old_E_state = 0;
    int old_Square_state = 0;
    int old_sel_state = 0;
    int old_ps_state = 0;
    int old_bat_state = 0;
    int old_sethome_state = 0;
    int old_picture_state = 0;
    int old_record_state = 0;
    int old_rping_state = 0;
    
    // Flag so gps alert only shows once
    int gps_fix_waiting = 0;
    __block int gps_fix_waited = 0;
    
    struct timeval takeoff_time; // Time struct so that takeoff only happens after 2 seconds of holding takeoff button(s)
    takeoff_time.tv_sec = -1;
    
    // SDL has to be run in main thread for joystick reconnection to work
    dispatch_sync(dispatch_get_main_queue(), ^{
        // Setup SDL for joystick
        if (SDL_Init(SDL_INIT_JOYSTICK) < 0) {
            syslog(LOG_CRIT, "Unable to init SDL: %s\n", SDL_GetError());
            exit(1);
        }
    });
    
    while(1) {
        int pitch = 0;
        int roll = 0;
        int climb = 0;
        int yaw = 0;
        
        int fly = 0;
        int reset_emergency = 0;
        int flat_trim = 0;
        int switch_cam = 0;
        int calib = 0;
        int lock_hover = 0;
        
        int home = 0;
        
        char cmd_buffer[1024];
        
        pthread_mutex_lock(&joystick_lock);
        
        if(SDL_JoystickGetAttached(joystick) == SDL_TRUE) { // Proccess joystick data
            SDL_JoystickUpdate();
            
            float l_stick_x =  (float)SDL_JoystickGetAxis(joystick, (stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 0 : 2) / 32768;
            float l_stick_y =  (float)SDL_JoystickGetAxis(joystick, (stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 1 : 3) / 32768;
            float r_stick_x =  (float)SDL_JoystickGetAxis(joystick, (stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 2 : 0) / 32768;
            float r_stick_y = -(float)SDL_JoystickGetAxis(joystick, (stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 3 : 1) / 32768;
            
            if(l_stick_x < FILTER && l_stick_x > -FILTER) {
                l_stick_x = 0.0f;
            }
            if(l_stick_y < FILTER && l_stick_y > -FILTER) {
                l_stick_y = 0.0f;
            }
            if(r_stick_x < (FILTER+0.08) && r_stick_x > -(FILTER+0.08)) {
                r_stick_x = 0.0f;
            }
            if(r_stick_y < FILTER && r_stick_y > -FILTER) {
                r_stick_y = 0.0f;
            }
            
            drone3g_lock_sensitivities_array();
            l_stick_x *= sens_array[0];
            l_stick_y *= sens_array[0];
            r_stick_x *= sens_array[1];
            if(r_stick_y > 0.0f) {
                r_stick_y *= sens_array[2];
            } else {
                r_stick_y *= sens_array[3];
            }
            drone3g_unlock_sensitivities_array();
            
            if(check_joystick_condition(JOYSTICK_COND_TAKEOFF) == 1) {
                if(gps_fix_waiting == 0 && GET_BIT(drone3g_get_navdata().ardrone_state, 0) != 1 && [[Drone3GPREFWindowController sharedPreferencesController] connectionLostMode] == DRONE3G_CLMODE_FLYHOME && drone3g_get_gpsdata().fix_status == 0 && drone3g_got_connection() == 1) { // Notify user that GPS not locked yet
                    gps_fix_waiting = 1;
                    gps_fix_waited = 0;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [appDelegate performSelectorInBackground:@selector(playGPSAlertSound) withObject:nil];
                        NSAlert* alert = [NSAlert alertWithMessageText:@"The GPS doesn't have a lock." defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"The GPS does not have a lock yet and you have selected the \"Return Home\" option in the connection lost preferences. If the drone does not have a GPS lock when attempting to fly home it will hold position until the GPS has acquired a lock, potentially until the battery runs out.\n\nAs a result the home location will not be set automatically when the drone takes off.\nYOU MUST SET IT MANUALLY WITH THE CONTROLLER OR IN THE FLIGHT MAP.\n\nWhen the GPS has a lock the GPS indicator in the HUD turns green.\n\nIf you still want to takeoff now, click Ok then push the takeoff button again."];
                        
                        [alert runModal];
                        
                        gps_fix_waited = 1;
                    });
                } else if(gps_fix_waited == 1 || drone3g_get_gpsdata().fix_status > 0 || [[Drone3GPREFWindowController sharedPreferencesController] connectionLostMode] == DRONE3G_CLMODE_LAND) {
                    if(takeoff_time.tv_sec == -1) {
                        gettimeofday(&takeoff_time, NULL);
                        
                        // Send drone fly home preferences
                        uint32_t mode = [[Drone3GPREFWindowController sharedPreferencesController] connectionLostMode];
                        uint32_t land_timeout = [[Drone3GPREFWindowController sharedPreferencesController] landTimeout];
                        uint32_t flyhome_timeout = [[Drone3GPREFWindowController sharedPreferencesController] flyHomeTimeout];
                        uint32_t flyhome_altitude = [[Drone3GPREFWindowController sharedPreferencesController] flyHomeAltitude];
                        
                        char cmd[1024];
                        sprintf(cmd, "AT*SETVAR(%i,%i,%i,%i)\r", mode, land_timeout, flyhome_timeout, flyhome_altitude);
                        
                        drone3g_send_command(cmd);
                    } else {
                        struct timeval current_time;
                        gettimeofday(&current_time, NULL);
                        
                        if(current_time.tv_sec - takeoff_time.tv_sec >= 1) {
                            fly = 1; // Takeoff
                        }
                    }
                }
            } else {
                takeoff_time.tv_sec = -1;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_LAND) == 1) {
                fly = -1; // Land
            }
            if(check_joystick_condition(JOYSTICK_COND_FTRIM) == 1) {
                flat_trim = 1; // Trim
            }
            if(check_joystick_condition(JOYSTICK_COND_HOVER) == 1) {
                lock_hover = 1;
            }
            if(check_joystick_condition(JOYSTICK_COND_EMERGENCY) == 1) {
                if(old_E_state == 0) {
                    reset_emergency = 1;
                }
                
                old_E_state = 1;
            } else {
                old_E_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_SWITCH_CAM) == 1) {
                if(old_Square_state == 0) {
                    cam_state = (cam_state == 0) ? 1 : 0;
                    switch_cam = 1;
                }
                
                old_Square_state = 1;
            } else {
                old_Square_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_CALIB) == 1) {
                if(old_sel_state == 0) {
                    calib = 1;
                }
                
                old_sel_state = 1;
            } else {
                old_sel_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_FLYHOME) == 1) {
                if(old_ps_state == 0) {
                    // Use current altitude when flying home
                    uint32_t mode = [[Drone3GPREFWindowController sharedPreferencesController] connectionLostMode];
                    uint32_t land_timeout = [[Drone3GPREFWindowController sharedPreferencesController] landTimeout];
                    uint32_t flyhome_timeout = [[Drone3GPREFWindowController sharedPreferencesController] flyHomeTimeout];
                    
                    char cmd[1024];
                    sprintf(cmd, "AT*SETVAR(%i,%i,%i,%i)\r", mode, land_timeout, flyhome_timeout, drone3g_get_navdata().altitude);
                    
                    drone3g_send_command(cmd);
                    
                    home = 1;
                }
                
                old_ps_state = 1;
                
            } else {
                old_ps_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_READ_BAT) == 1) {
                if(old_bat_state == 0 && drone3g_got_connection() == 1) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[appDelegate alertSpeaker] startSpeakingString:[NSString stringWithFormat:@"Battery @ %i percent.", drone3g_get_navdata().battery_percentage]];
                    });
                }
                
                old_bat_state = 1;
            } else {
                old_bat_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_READ_PING) == 1) {
                if(old_rping_state == 0 && drone3g_got_connection() == 1) {
                    drone3g_test_latency(&internal_ping_read_callback);
                }
                
                old_rping_state = 1;
            } else {
                old_rping_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_SETHOME) == 1) {
                if(old_sethome_state == 0) {
                    drone3g_gpsdata_t gpsdata = drone3g_get_gpsdata();
                    
                    if(gpsdata.fix_status > 0) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[Drone3GPLANWindowController sharedFlightMap] setHomeLocation:gpsdata.latitude longitude:gpsdata.longitude];
                        });
                        
                        drone3g_home_location_changed_callback(gpsdata.latitude, gpsdata.longitude);
                    }
                }
                
                old_sethome_state = 1;
            } else {
                old_sethome_state = 0;
            }
            
            if(check_joystick_condition(JOYSTICK_COND_PICTURE) == 1) {
                // Pictures cannot be taken if the no lock GPS warning is popped since the main thread is stalled and commands will just be queued
                // and stacked until the user dissmisses the warning which will subsequently dump all the picture commands to the drone at once
                if(old_picture_state == 0 && (gps_fix_waiting == 0 || gps_fix_waited == 1) && drone3g_got_connection() == 1) {
                    if(cam_state == 0) {
                        [[appDelegate drone3GGLView] flash];
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [(NSSound*)[NSSound soundNamed:@"Grab.aif"] play];
                        
                        char cmd[1024];
                        sprintf(cmd, "AT*CONFIG= ,\"userbox:userbox_cmd\",\"2,0,1,%s\"\r", [[NSDateComponents getDateStringFormatYYYYMMDD_hhmmssForDate:[NSDate date]] cStringUsingEncoding:NSUTF8StringEncoding]);
                        
                        drone3g_send_command("AT*CONFIG_IDS= ,\"ad1efdac\",\"992f7f4f\",\"510acf97\"\r");
                        drone3g_send_command(cmd);
                    });
                }

                old_picture_state = 1;
            } else {
                old_picture_state = 0;
            }

            if(check_joystick_condition(JOYSTICK_COND_RECORD) == 1) {
                if(old_record_state == 0) {
                    if(record_state == 0 && drone3g_got_connection() == 1) { // Will start recording
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSSlider* bitrateSlider = (NSSlider*)[[appDelegate bitrateSlider] viewWithTag:1];
                            
                            if(record_to_usb == 1) {
                                record_state = 1;
                                drone3g_send_command("AT*RECORD\r");
                                
                                [appDelegate flashRecordingIndicator];
                                
                                previous_bitrate = [bitrateSlider intValue];
                                [bitrateSlider setMaxValue:1000];
                                [[appDelegate bitrateLabel] setStringValue:[NSString stringWithFormat:@"                Bitrate: %liKbps", (long)[bitrateSlider integerValue]]];
                                
                                char cmd[1024];
                                sprintf(cmd, "AT*CONFIG_IDS= ,\"ad1efdac\",\"992f7f4f\",\"510acf97\"\rAT*CONFIG= ,\"video:max_bitrate\",\"%i\"\r", [bitrateSlider intValue]);
                                drone3g_send_command(cmd);
                                
                                [[appDelegate hdMenuItem] setEnabled:NO];
                                [[appDelegate sdMenuItem] setEnabled:NO];
                                [[appDelegate recordMenuItem] setEnabled:NO];
                            } else {
                                sprintf(current_video_name, "video_%s.tmp", [[NSDateComponents getDateStringFormatYYYYMMDD_hhmmssForDate:[NSDate date]] UTF8String]);
                                NSString* path = [[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"] stringByAppendingPathComponent:[NSString stringWithCString:current_video_name encoding:NSUTF8StringEncoding]];
                                
                                current_video_fp = fopen([path UTF8String], "w");
                                if(current_video_fp == NULL) {
                                    syslog(LOG_ERR, "Could not open tmp file for video recording!\n");
                                } else {
                                    record_state = 1;
                                    get_thumbnail = 1;
                                    
                                    [appDelegate flashRecordingIndicator];
                                    
                                    [bitrateSlider setEnabled:NO];
                                    [[appDelegate bitrateLabel] setTextColor:[NSColor disabledControlTextColor]];
                                    [[appDelegate hdMenuItem] setEnabled:NO];
                                    [[appDelegate sdMenuItem] setEnabled:NO];
                                    [[appDelegate recordMenuItem] setEnabled:NO];
                                }
                            }
                        });
                    } else { // Will end recording
                        record_state = 0;
                        if(record_to_usb == 1) {
                            drone3g_send_command("AT*STOPRECORD\r");
                        } else {
                            fclose(current_video_fp);
                            current_video_fp = NULL;
                            current_video_name[0] = 0;
                            
                            const char* full_path = [[[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"] stringByAppendingPathComponent:[NSString stringWithUTF8String:current_video_name]] UTF8String];
                            
                            // File has to be at least 100KB
                            struct stat st;
                            stat(full_path, &st);
                            
                            if(st.st_size < 100*1024) {
                                unlink(full_path);
                            }
                        }
  
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [appDelegate stopFlashingRecordIndicator];
                            
                            NSSlider* bitrateSlider = (NSSlider*)[[appDelegate bitrateSlider] viewWithTag:1];
                            
                            if(drone3g_got_connection() == 1) {
                                [bitrateSlider setEnabled:YES];
                                [[appDelegate bitrateLabel] setTextColor:[NSColor controlTextColor]];
                                
                                [[appDelegate hdMenuItem] setEnabled:YES];
                                [[appDelegate sdMenuItem] setEnabled:YES];
                                [[appDelegate recordMenuItem] setEnabled:YES];
                            }
                            
                            if(record_to_usb == 1) {
                                [bitrateSlider setMaxValue:4000];
                                [bitrateSlider setIntValue:previous_bitrate];
                                
                                [[appDelegate bitrateLabel] setStringValue:[NSString stringWithFormat:@"                Bitrate: %liKbps", (long)[bitrateSlider integerValue]]];
                                
                                char cmd[1024];
                                sprintf(cmd, "AT*CONFIG_IDS= ,\"ad1efdac\",\"992f7f4f\",\"510acf97\"\rAT*CONFIG= ,\"video:max_bitrate\",\"%i\"\r", [bitrateSlider intValue]);
                                drone3g_send_command(cmd);
                            }
                        });
                        
                    }
                }
                
                old_record_state = 1;
            } else {
                old_record_state = 0;
            }
            
            /*for(int i=0;i<SDL_JoystickNumButtons(joystick);i++) { // This prints out which buttons are pushed
                if(SDL_JoystickGetButton(joystick, i) == 1) {
                    printf("Button #%i Pushed %i\n", i, arc4random() % 1000);
                }
            }*/
            //printf("LX:%f LY:%f RX:%f RY:%f\n", l_stick_x, l_stick_y, r_stick_x, r_stick_y);
            
            memcpy(&pitch, &l_stick_y, sizeof(int));
            memcpy(&roll, &l_stick_x, sizeof(int));
            memcpy(&climb, &r_stick_y, sizeof(int));
            memcpy(&yaw, &r_stick_x, sizeof(int));
        }
        
        pthread_mutex_unlock(&joystick_lock);
        
        if(reset_emergency == 1) {
            struct timeval ref, current;
            gettimeofday(&ref, NULL);
            
            while(1) {
                if(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_EMERGENCY) {
                    break;
                }
                
                sprintf(cmd_buffer, "AT*REF= ,%i\r", 290717696);
                drone3g_send_command(cmd_buffer);
                
                sprintf(cmd_buffer, "AT*REF= ,%i\r", 290717952);
                drone3g_send_command(cmd_buffer);
                
                sprintf(cmd_buffer, "AT*REF= ,%i\r", 290717696);
                drone3g_send_command(cmd_buffer);
                
                gettimeofday(&current, NULL);
                if(current.tv_sec - ref.tv_sec >= 1) {
                    break;
                }
                
                usleep(1000);
            }
        }
        
        if(fly == 1) {
            // Make sure we are not in emergency state and if so reset
            if(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_EMERGENCY) {
                sprintf(cmd_buffer, "AT*REF= ,%i\r", 290717952);
                drone3g_send_command(cmd_buffer);
                
                struct timeval ref, current;
                gettimeofday(&ref, NULL);
                
                while(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_EMERGENCY) {
                    gettimeofday(&current, NULL);
                    if(current.tv_sec - ref.tv_sec >= 2) {
                        break;
                    }
                    
                    drone3g_send_command("AT*PCMD= ,0,0,0,0,0\r");
                    usleep(1000);
                }
            }
            
            sprintf(cmd_buffer, "AT*REF= ,%i\r", 290718208);
            drone3g_send_command(cmd_buffer);
        } else if(fly == -1) {
            sprintf(cmd_buffer, "AT*REF= ,%i\r", 290717696);
            drone3g_send_command(cmd_buffer);
        }
        
        if(flat_trim == 1) {
            // Only flat trim when landed otherwise it would be disastrous
            if(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_EMERGENCY || drone3g_get_navdata().ctrl_state == DRONE3G_STATE_LANDED) {
                flat_trimming = 1;
                drone3g_send_command("AT*FTRIM= \r");
            }
        }
        
        if(switch_cam == 1) {
            drone3g_send_command("AT*CONFIG_IDS= ,\"ad1efdac\",\"992f7f4f\",\"510acf97\"\r"); // We have to send this dumb command before AT*CONFIG
            
            if(cam_state == 0) {
                drone3g_send_command("AT*CONFIG= ,\"video:video_channel\",\"2\"\r");
            } else {
                drone3g_send_command("AT*CONFIG= ,\"video:video_channel\",\"1\"\r");
            }
        }
        
        if(calib == 1) { // Tells drone to calibrate magnometer
            drone3g_send_command("AT*CALIB= ,0\r");
            
            // Must be in a hover state to calibrate
            lock_hover = 1;
        }
        
        if(home == 1) {
            sprintf(cmd_buffer, "AT*FLYHOME\r");
            drone3g_send_command(cmd_buffer);
        }
        
        if(roll == 0 && pitch == 0 && climb == 0 && yaw == 0) {
            if(hover == 0) {
                gettimeofday(&hover_time_ref, NULL);
                hover = 1;
            }
            
            struct timeval current_time;
            gettimeofday(&current_time, NULL);
            
            if( (current_time.tv_sec*1000000 + current_time.tv_usec) - (hover_time_ref.tv_sec*1000000 + hover_time_ref.tv_usec) >= 5000000 || lock_hover == 1) {
                drone3g_send_command("AT*PCMD= ,0,0,0,0,0\r"); // Hover and maintain position
                hover_time_ref.tv_sec = 0; // This is done so that hover stays locked after lock_hover = 0
            } else {
                drone3g_send_command("AT*PCMD= ,1,0,0,0,0\r"); // Hover and coast
            }
        } else {
            if(hover_time_ref.tv_sec == 0 && hover == 1 && roll == 0 && pitch == 0) { // Stabilization works for climb and yaw
                sprintf(cmd_buffer, "AT*PCMD= ,0,0,0,%i,%i\r", climb, yaw);
                drone3g_send_command(cmd_buffer);
            } else {
                sprintf(cmd_buffer, "AT*PCMD= ,1,%i,%i,%i,%i\r", roll, pitch, climb, yaw);
                drone3g_send_command(cmd_buffer);
                
                hover = 0;
            }
        }
        
        usleep(33333);
    }
}

#pragma mark -
#pragma mark Callbacks
#pragma mark -

void drone3g_home_location_changed_callback(double lat, double lon) {
    takeoff_lat = lat;
    takeoff_lon = lon;
    
    char cmd_buffer[1024];
    
    int64_t _lat, _lon;
    memcpy(&_lat, &lat, 8);
    memcpy(&_lon, &lon, 8);
    
    sprintf(cmd_buffer, "AT*SETHOME(%lli,%lli)\r", _lat, _lon);
    drone3g_send_command(cmd_buffer);
}

void drone3g_flyhome_settings_changed_callback(unsigned int mode, unsigned int land_timeout, unsigned int flyhome_timeout, unsigned int flyhome_alt) {
    char cmd[1024];
    sprintf(cmd, "AT*SETVAR(%i,%i,%i,%i)\r", mode, land_timeout, flyhome_timeout, flyhome_alt);
    drone3g_send_command(cmd);
}

static void magnetic_declination_callback(float md) {
    magnetic_declination = md;
    
    int32_t _md;
    memcpy(&_md, &md, 4);
    
    char cmd[1024];
    sprintf(cmd, "AT*SETMAGD(%i)\r", _md);
    
    drone3g_send_command(cmd);
}

static void start_image_transfer_callback(uint8_t* data, size_t data_len, size_t total_size) {
    if(current_image_total_size > 0) { // This means that the last picture was re-sent due to interruption from connection loss
        fclose(current_image_fp);
        current_image_fp = NULL;
        
        // Delete corrupt image
        unlink(current_image_name);
        
       // syslog(LOG_NOTICE, "Re-downloading picture...\n");
    } else {
       // syslog(LOG_NOTICE, "Downloading picture...\n");
    }
    
    current_image_total_size = total_size-27;
    current_image_size = 0;
    
    memset(current_image_name, 0, 28);
    
    // Check to see if we have the file name yet or not
    if(data_len < 27) {
        memcpy(current_image_name, data, data_len);
        return;
    }
    
    memcpy(current_image_name, data, 27);
    data_len -= 27;
    data += 27;
    
    // The .tmp is added so that the photo viewer will not try to read this
    char path[1024];
    sprintf(path, "%s/Photos/%s.tmp", [[NSFileManager applicationStoragePath] cStringUsingEncoding:NSUTF8StringEncoding], current_image_name);
    
    current_image_fp = fopen(path, "w");
    if(current_image_fp == NULL) {
        current_image_total_size = 0;
        syslog(LOG_ERR, "Could not create image file %s. %s.\n", path, strerror(errno));
        return;
    }
    
    if(data_len > 0) {
        size_t wrote = fwrite(data, 1, data_len, current_image_fp);
        if(wrote < data_len) {
            syslog(LOG_ERR, "Writing picture data for %s failed! %s.\n", current_image_name, strerror(errno));
            
            fclose(current_image_fp);
            current_image_fp = NULL;
            
            current_image_total_size = 0;
            
            return;
        }
        
        current_image_size = data_len;
        
        // All data was read without the need for subsequent transfers
        if(data_len == total_size) {
            fclose(current_image_fp);
            current_image_fp = NULL;
            current_image_total_size = 0;
            
            // Remove the .tmp extension so it will be recognizied by the photo viewer
            char new_path[1024];
            sprintf(new_path, "%s/Photos/%s", [[NSFileManager applicationStoragePath] cStringUsingEncoding:NSUTF8StringEncoding], current_image_name);
            rename(path, new_path);
            
           // syslog(LOG_NOTICE, "Download of picture %s complete!\n", current_image_name);
        }
    }
}

static void transfer_image_data_callback(uint8_t* data, size_t data_len) {
    // This means that the file could not be successfully opened or written to and we will have to abort the operation
    if(current_image_total_size == 0) {
        return;
    }
    
    // Check if we have the name or not (if we do file will already be open)
    if(current_image_fp != NULL) {
        size_t wrote = fwrite(data, 1, data_len, current_image_fp);
        if(wrote < data_len) {
            syslog(LOG_ERR, "Writing picture data for %s failed! %s.\n", current_image_name, strerror(errno));
            
            fclose(current_image_fp);
            current_image_fp = NULL;
            
            current_image_total_size = 0;
            
            return;
        }
        
        current_image_size += data_len;
        
        if(current_image_size >= current_image_total_size) {
            fclose(current_image_fp);
            current_image_fp = NULL;
            current_image_total_size = 0;
            
            // Remove the .tmp extension so it will be recognizied by the photo viewer
            char old_path[1024], new_path[1024];
            sprintf(old_path, "%s/Photos/%s.tmp", [[NSFileManager applicationStoragePath] cStringUsingEncoding:NSUTF8StringEncoding], current_image_name);
            sprintf(new_path, "%s/Photos/%s", [[NSFileManager applicationStoragePath] cStringUsingEncoding:NSUTF8StringEncoding], current_image_name);
            rename(old_path, new_path);
            
            //syslog(LOG_NOTICE, "Download of picture %s complete!\n", current_image_name);
        }
    } else {
        size_t needed_bytes = 27-strlen(current_image_name);
        if(data_len < needed_bytes) {
            memcpy(current_image_name+strlen(current_image_name), data, data_len);
            return;
        }
        
        memcpy(current_image_name+strlen(current_image_name), data, needed_bytes);
        data_len -= needed_bytes;
        data += needed_bytes;
        
        // Now we have file name, the .tmp is added so that the photo viewer will not try to read this
        char path[1024];
        sprintf(path, "%s/Photos/%s.tmp", [[NSFileManager applicationStoragePath] cStringUsingEncoding:NSUTF8StringEncoding], current_image_name);
        
        current_image_fp = fopen(path, "w");
        if(current_image_fp == NULL) {
            current_image_total_size = 0;
            syslog(LOG_ERR, "Could not create image file %s. %s.\n", path, strerror(errno));
            return;
        }
        
        if(data_len > 0) {
            size_t wrote = fwrite(data, 1, data_len, current_image_fp);
            if(wrote < data_len) {
                syslog(LOG_ERR, "Writing picture data for %s failed! %s.\n", current_image_name, strerror(errno));
                
                fclose(current_image_fp);
                current_image_fp = NULL;
                
                current_image_total_size = 0;
                
                return;
            }
            
            current_image_size = data_len;
        }
    }
}

static void date_callback(int month, int day) {
    if(month == 255 && day == 255) { // Reset date not yet set
        dispatch_async(dispatch_get_main_queue(), ^{
            [[Drone3GDATWindowController sharedDataUsageWindowController] setDateString:@"No reset yet"];
            [[appDelegate dataUsageMenuItem] setEnabled:YES];
        });
        
        return;
    }
    
    if(day > 31 || month > 12 || month < 1 || day < 1) { // Invalid date
        syslog(LOG_WARNING, "Received inavlid date format from drone!. Asking again...\n");
        drone3g_send_command("AT*GETDATE\r");
        
        return;
    }
    
    pthread_cancel(date_thread);
    
    NSDateComponents* dateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:[NSDate date]];
    [dateComponents setDay:day];
    [dateComponents setMonth:month];
    NSDate* date = [[NSCalendar currentCalendar] dateFromComponents:dateComponents];
    
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    
    dateFormatter.dateFormat = @"MMMM";
    NSString* monthString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:3];
    
    dateFormatter.dateFormat=@"EEEE";
    NSString* dayString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:3];
    
    NSString* suffix_string = @"st|nd|rd|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|st|nd|rd|th|th|th|th|th|th|th|st";
    NSArray* suffixes = [suffix_string componentsSeparatedByString: @"|"];
    
    NSString* dateString = [NSString stringWithFormat:@"%@ %@ %d%@", dayString, monthString, day, [suffixes objectAtIndex:day-1]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[Drone3GDATWindowController sharedDataUsageWindowController] setDateString:dateString];
        [[appDelegate dataUsageMenuItem] setEnabled:YES];
    });
}

static void gpsdata_callback(drone3g_gpsdata_t gpsdata) {
    /*printf("Fix:%i\n", gpsdata.fix_status);
    printf("Lat:%f Lon:%f\n", gpsdata.latitude, gpsdata.longitude);
    printf("Altitude Above Mean Sea Level:%fft\n", gpsdata.altitude_msl*3.28084);
    printf("Speed:%f km/h\n\n", gpsdata.ground_speed);*/
    
    // Convert degrees to radians
    double rad_takeoff_lat = M_PI/180 * takeoff_lat;
    double rad_takeoff_lon = M_PI/180 * takeoff_lon;
    double rad_lat = M_PI/180 * gpsdata.latitude;
    double rad_lon = M_PI/180 * gpsdata.longitude;
    
    double dlon = rad_lon - rad_takeoff_lon;
    
    double cos_lat = cos(rad_lat);
    double y = sin(dlon) * cos_lat;
    double x = cos(rad_takeoff_lat) * sin(rad_lat) - sin(rad_takeoff_lat) * cos_lat * cos(dlon);
    
    double bearing = atan2(y, x);
    bearing *= 180/M_PI;
    bearing = fmod(bearing - magnetic_declination + 540, 360);
    
    double distance = sqrt(x*x+y*y)*6371000;
    float distance_f = (float)distance;
    return_distance = distance_f;
    if(return_distance > 10000) {
        return_distance = 0.0;
    }
    
    float bearing_f = (float)bearing;
    return_angle = bearing_f;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if(gpsdata.fix_status != DRONE3G_GPS_FIX_STATUS_NO_GPS) {
            [[appDelegate gpsLabel] setHidden:NO];
            [[Drone3GPREFWindowController sharedPreferencesController] enableFlyHome];
            
            if(gpsdata.fix_status == DRONE3G_GPS_FIX_STATUS_NO_LOCK) {
                [[appDelegate gpsLabel] setTextColor:[NSColor redColor]];
                
                [[appDelegate distanceLabel] setHidden:YES];
                [[appDelegate homeImage] setHidden:YES];
                [[appDelegate homeAngleLabel] setHidden:YES];
            } else {
                [[appDelegate gpsLabel] setTextColor:[NSColor greenColor]];
                
                if(takeoff_lon > - 1000 && takeoff_lat > -1000) {
                   [appDelegate positionHomeImage:return_angle];
                }
                
                if(last_fix_state == DRONE3G_GPS_FIX_STATUS_NO_LOCK) {
                    [(NSSound*)[NSSound soundNamed:@"Tink"] play];
                    [[appDelegate alertSpeaker] startSpeakingString:@"GPS lock acquired."];
                }
            }
            
            if(gpsdata.fix_status == DRONE3G_GPS_FIX_STATUS_DIFFGPS) {
                [[appDelegate gpsLabel] setStringValue:@"DGPS"];
            } else {
                [[appDelegate gpsLabel] setStringValue:@"GPS"];
            }
            
            if(gpsdata.fix_status != DRONE3G_GPS_FIX_STATUS_NO_LOCK) {
                [[Drone3GPLANWindowController sharedFlightMap] updateDroneLocation:gpsdata.latitude longitude:gpsdata.longitude];
                [[Drone3GMDCalculator sharedCalculator] getMagneticDeclinationForCoordinates:gpsdata.latitude longitude:gpsdata.longitude callback:&magnetic_declination_callback];
                
                [[appDelegate distanceLabel] setStringValue:[NSString stringWithFormat:@"Distance: %.0f%@", return_distance * ( ([[[Drone3GPREFWindowController sharedPreferencesController] distanceUnits] isEqualToString:@"m"]) ? 1.0f : 3.28084f), [[Drone3GPREFWindowController sharedPreferencesController] distanceUnits]]];
                [[appDelegate distanceLabel] setHidden:NO];
            }
            
            last_fix_state = gpsdata.fix_status;
        } else {
            [[Drone3GPREFWindowController sharedPreferencesController] disableFlyHome];
            
            [[appDelegate gpsLabel] setHidden:YES];
            [[appDelegate distanceLabel] setHidden:YES];
            
            [[appDelegate homeImage] setHidden:YES];
            [[appDelegate homeAngleLabel] setHidden:YES];
        }
    });
}

static void navdata_callback(drone3g_navdata_t navdata) {
    is_flying = !((navdata.ctrl_state == DRONE3G_STATE_EMERGENCY) || (navdata.ctrl_state == DRONE3G_STATE_LANDED));
    
    // Sync record state with drone
    if(record_to_usb == 1) {
        if(navdata.video_record_state == 1 && record_state == 0) {
            drone3g_send_command("AT*STOPRECORD\r");
        } else if(navdata.video_record_state == 0 && record_state == 1) {
            drone3g_send_command("AT*RECORD\r");
        }
    } else {
        if(navdata.video_record_state == 1) {
            drone3g_send_command("AT*STOPRECORD\r");
        }
    }
    
    if(GET_BIT(navdata.ardrone_state, 0) == 1 && GET_BIT(last_drone_state, 0) == 0) { // Drone took off
        had_battery_emergency = 0;
        had_battery_warning = 0;
        
        battery_halfway_point = -1;
        if(navdata.battery_percentage > 30) {
            battery_halfway_point = navdata.battery_percentage/2 + 10;
        }

        if(takeoff_lat < -500 && takeoff_lon < -500 && drone3g_get_gpsdata().fix_status > 0) {
            // Set home location in map
            dispatch_async(dispatch_get_main_queue(), ^{
                drone3g_gpsdata_t gpsdata = drone3g_get_gpsdata();
                [[Drone3GPLANWindowController sharedFlightMap] setHomeLocation:gpsdata.latitude longitude:gpsdata.longitude];
                //[[Drone3GPLANWindowController sharedFlightMap] setHomeLocation:50.88899 longitude:-114.0824];
            });
            
            drone3g_gpsdata_t gpsdata = drone3g_get_gpsdata();
            takeoff_lat = gpsdata.latitude;
            takeoff_lon = gpsdata.longitude;
        }
    }
    
    last_ctrl_state = navdata.ctrl_state;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CIColor* color;
        if(navdata.battery_percentage > 50) {
            float red = (1.0f - navdata.battery_percentage/100.0f) * 2.0f;
            color = [CIColor colorWithRed:red green:1.0f blue:0.0f];
        } else {
            float green = navdata.battery_percentage/100.0f * 10.0f/3.0f - 2.0f/3.0f;
            color = [CIColor colorWithRed:1.0f green:(green < 0.0f) ? 0.0f : green blue:0.0f];
        }
        
        CIFilter* filter = [CIFilter filterWithName:@"CIFalseColor"];
        [filter setDefaults];
        [filter setValue:color forKey:@"inputColor0"];
        [filter setValue:color forKey:@"inputColor1"];
        [[appDelegate.batteryImageView layer] setFilters:@[filter]];
        [appDelegate.batteryLabel setTextColor:[NSColor colorWithCIColor:color]];
        
        if(navdata.ctrl_state != DRONE3G_STATE_LANDED && navdata.ctrl_state != DRONE3G_STATE_EMERGENCY) { // Only do battery animations when flying
            if(navdata.battery_percentage < battery_halfway_point && navdata.battery_percentage > 30 && had_battery_warning == 0 && !appDelegate.batteryAnimationsAreRunning) {
                [appDelegate batteryWarning];
                had_battery_warning = 1;
            }
            if(navdata.battery_percentage <= 30 && had_battery_emergency == 0) {
                if(appDelegate.batteryAnimationsAreRunning) { // Stop warning animation if it is playing
                    [appDelegate stopBatteryAnimations];
                }
                
                [appDelegate batteryEmergency];
                had_battery_emergency = 1;
            }
        } else if(appDelegate.batteryAnimationsAreRunning) { // If we aren't flying make sure no animations are running
            [appDelegate stopBatteryAnimations];
        }
        
        // Setting wind in HUD
        float wind_angle = fmodf(navdata.wind_vector.wind_direction * 180.0f / M_1_PI / 1000.0f + 540.0f, 360.0f);
        char wind_string[3] = {0};
        if(navdata.wind_vector.wind_speed > 0.28f) {
            if(wind_angle < 45.0f || wind_angle > 315.0f) {
                wind_string[0] = 'N';
            } else if(wind_angle < 225.0f && wind_angle > 135.0f) {
                wind_string[0] = 'S';
            }
            if(wind_angle > 22.5f && wind_angle < 157.5f) {
                strcat(wind_string, "E");
            } else if(wind_angle > 202.5f && wind_angle < 337.5f) {
                strcat(wind_string, "W");
            }
        }
        
        [[appDelegate windSpeedLabel] setStringValue:[NSString stringWithFormat:@"Wind: %.1f %@ %s", navdata.wind_vector.wind_speed * ( ([[[Drone3GPREFWindowController sharedPreferencesController] speedUnits] isEqualToString:@"km/h"]) ? 3.6f : 2.23693629f), [[Drone3GPREFWindowController sharedPreferencesController] speedUnits], wind_string]];
        
        float altitude = (float)navdata.altitude * ( ([[[Drone3GPREFWindowController sharedPreferencesController] altitudeUnits] isEqualToString:@"ft"]) ? 0.00328084f : 0.001f);
        float velocity = sqrtf(navdata.vx*navdata.vx + navdata.vy*navdata.vy) * ( ([[[Drone3GPREFWindowController sharedPreferencesController] speedUnits] isEqualToString:@"km/h"]) ? 0.0036f : 0.00223693629f);

        [[appDelegate batteryLabel] setStringValue:[NSString stringWithFormat:@"%i%%", navdata.battery_percentage]];
        [[appDelegate altitudeLabel] setStringValue:[NSString stringWithFormat:@"%.0f %@", altitude, [[Drone3GPREFWindowController sharedPreferencesController] altitudeUnits] ]];
        [[appDelegate velocityLabel] setStringValue:[NSString stringWithFormat:@"%.1f %@", velocity, [[Drone3GPREFWindowController sharedPreferencesController] speedUnits] ]];
        
        // Set compass angle
        float angle;
        if(navdata.time_flying > 0) { // If the drone has been flying the compass flips 180˚
            angle = fmodf(navdata.psi/1000.0f+360.0f, 360.0f);
        } else {
            angle = fmodf(navdata.psi/1000.0f+180.0f, 360.0f);
        }
        [appDelegate setCompassAngle:angle];
        [[Drone3GPLANWindowController sharedFlightMap] updateDroneHeading:fmodf(angle + magnetic_declination, 360.0f)];
        //printf("%.2f %.2f\n", angle, navdata.psi/1000.0f);
        
        // Update inclinometer
        [appDelegate updateInclinometer:navdata.theta/1000 roll:navdata.phi/1000];
        
        if(navdata.signal_strength < 8) {
            [[appDelegate signalLevelImageView] setImage:[NSImage imageNamed:@"3g1.png"]];
        } else if(navdata.signal_strength >= 8 && navdata.signal_strength < 16) {
            [[appDelegate signalLevelImageView] setImage:[NSImage imageNamed:@"3g2.png"]];
        } else if(navdata.signal_strength >= 16 && navdata.signal_strength < 24) {
            [[appDelegate signalLevelImageView] setImage:[NSImage imageNamed:@"3g3.png"]];
        } else {
            [[appDelegate signalLevelImageView] setImage:[NSImage imageNamed:@"3g4.png"]];
        }
        
        // Data usage UI
        if(drone3g_got_connection() == 1) {
            if(navdata.total_sent_bytes + navdata.total_recv_bytes > 1024*1024*1000) { // GB
                [[[Drone3GDATWindowController sharedDataUsageWindowController] dataUsedLabel] setStringValue:[NSString stringWithFormat:@"%.2fGB", (navdata.total_recv_bytes + navdata.total_sent_bytes) / 1024.0f / 1024.0f / 1000.0f]];
            } else { // MB
                [[[Drone3GDATWindowController sharedDataUsageWindowController] dataUsedLabel] setStringValue:[NSString stringWithFormat:@"%lluMB", (navdata.total_recv_bytes + navdata.total_sent_bytes) / 1024 / 1024]];
            }
            
            if(navdata.total_sent_bytes > last_sent_bytes) {
                [[[Drone3GDATWindowController sharedDataUsageWindowController] bandwidthUpLabel] setStringValue:[NSString stringWithFormat:@"%uKB/s", (unsigned int)(navdata.total_sent_bytes - last_sent_bytes) / 1024]];
            }
            if(navdata.total_recv_bytes > last_recv_bytes) {
                if(navdata.total_recv_bytes - last_recv_bytes > 1024*1024) {
                    [[[Drone3GDATWindowController sharedDataUsageWindowController] bandwidthDownLabel] setStringValue:[NSString stringWithFormat:@"%.2fMB/s", (unsigned int)(navdata.total_recv_bytes - last_recv_bytes) / 1024.0f / 1024.0f]];
                } else {
                    [[[Drone3GDATWindowController sharedDataUsageWindowController] bandwidthDownLabel] setStringValue:[NSString stringWithFormat:@"%uKB/s", (unsigned int)(navdata.total_recv_bytes - last_recv_bytes) / 1024]];
                }
            }
            
            last_recv_bytes = navdata.total_recv_bytes;
            last_sent_bytes = navdata.total_sent_bytes;
        }
        
        if(flat_trimming == 1) {
            flat_trimming = 0;
            gettimeofday(&flat_trim_timestamp, NULL);
        }
        
        // Check emergency conditions
        struct timeval current_timestamp;
        gettimeofday(&current_timestamp, NULL);
        
        if( (current_timestamp.tv_sec*1000000 + current_timestamp.tv_usec) - (flat_trim_timestamp.tv_usec + flat_trim_timestamp.tv_sec*1000000) < 4000000 ) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"FLAT TRIM OK"]) {
                [[appDelegate warningLabel] setStringValue:@"FLAT TRIM OK"];
                [appDelegate flashWarningLabel];
            }
        } else if(GET_BIT(navdata.ardrone_state, 14) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"SOFTWARE ERROR"]) {
                [[appDelegate warningLabel] setStringValue:@"SOFTWARE ERROR"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 14) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:[NSString stringWithFormat:@"warning! software error. %@", (is_flying == 1) ? @"recommend immediate landing" : @"reboot your drone before flying"]];
                }
            }
        } else if(GET_BIT(navdata.ardrone_state, 19) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"UNSAFE ANGLE EMERGENCY"]) {
                [[appDelegate warningLabel] setStringValue:@"UNSAFE ANGLE EMERGENCY"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 19) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:@"warning! unsafe angle emergency"];
                }
            }
        } else if(GET_BIT(navdata.ardrone_state, 22) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"MOTOR CUTOUT"]) {
                [[appDelegate warningLabel] setStringValue:@"MOTOR CUTOUT"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 22) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:@"warning! motor cutout"];
                }
            }
        } else if(GET_BIT(navdata.ardrone_state, 12) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"MOTOR ERROR"]) {
                [[appDelegate warningLabel] setStringValue:@"MOTOR ERROR"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 12) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:@"warning! one or more motors is not working correctly"];
                }
            }
        } else if(GET_BIT(navdata.ardrone_state, 21) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"ULTRASOUND ERROR"]) {
                [[appDelegate warningLabel] setStringValue:@"ULTRASOUND ERROR"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 21) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:@"warning! ultrasound sensor error"];
                }
            }
        } else if(GET_BIT(navdata.ardrone_state, 20) == 1) {
            if(![appDelegate warningLabelIsAnimating] || ![[[appDelegate warningLabel] stringValue] isEqualToString:@"HIGH WIND SPEED"]) {
                [[appDelegate warningLabel] setStringValue:@"HIGH WIND SPEED"];
                [appDelegate flashWarningLabel];
                
                if(GET_BIT(last_drone_state, 20) == 0) {
                    [[appDelegate alertSpeaker] startSpeakingString:@"caution! high wind speed"];
                }
            }
        } else {
            [appDelegate stopFlashingWarningLabel];
        }
        
        last_drone_state = navdata.ardrone_state;
        
        // Show time flying
        render_time_string(navdata.time_flying / 60, navdata.time_flying % 60);
    });
}

// Asks the drone for the latest data usage reset date once per second until it is recieved
void* get_date_loop(void* arg) {
    while(1) {
        drone3g_send_command("AT*GETDATE\r");
        sleep(1);
    }
    
    return NULL;
}

static void pong_callback(struct timeval timestamp, int residual_ms) {
    accm_latency += ( (timestamp.tv_sec*1000000 + timestamp.tv_usec) - (ping_timestamp.tv_usec + ping_timestamp.tv_sec*1000000) )/1000 - residual_ms;

    pong_count++;
    if(pong_count < 3) {
        drone3g_send_command("AT*PING\r");
        gettimeofday(&ping_timestamp, NULL);
        
        return;
    }
    
    current_ping_callback(accm_latency/3);
}

static void connection_established_callback() {
    frame_count = 0;
    stream_bit_count = 0;
    
     // Tells the drone to put the last data usage reset date into the incoming data stream
    pthread_create(&date_thread, NULL, get_date_loop, NULL);
    pthread_detach(date_thread);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Make sure userbox is running for pictures
        char cmd[1024];
        sprintf(cmd, "AT*START_USERBOX(%s)\r", [[NSDateComponents getDateStringFormatYYYYMMDD_hhmmssForDate:[NSDate date]] cStringUsingEncoding:NSUTF8StringEncoding]); // Date must be formatted as YYYYMMDD_hhmmss
        drone3g_send_command(cmd);
        
        if([[appDelegate drone3GGLView] pixelBuffer] != NULL && (record_state == 0 || record_to_usb == 1) ) {
            [[[appDelegate bitrateSlider] viewWithTag:1] setEnabled:YES];
            [[appDelegate bitrateLabel] setTextColor:[NSColor controlTextColor]];
        }
        
        if(record_state == 0) {
            [[appDelegate hdMenuItem] setEnabled:YES];
            [[appDelegate sdMenuItem] setEnabled:YES];
            [[appDelegate recordMenuItem] setEnabled:YES];
        }
        
        [appDelegate hideConnectionLabel];
    });
}

static void connection_lost_callback() {
    pthread_cancel(date_thread);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[appDelegate bitrateSlider] viewWithTag:1] setEnabled:NO];
        [[appDelegate hdMenuItem] setEnabled:NO];
        [[appDelegate sdMenuItem] setEnabled:NO];
        [[appDelegate recordMenuItem] setEnabled:NO];
        [[appDelegate bitrateLabel] setTextColor:[NSColor disabledControlTextColor]];
        
        [[[Drone3GDATWindowController sharedDataUsageWindowController] bandwidthUpLabel] setStringValue:@"0KB/s"];
        [[[Drone3GDATWindowController sharedDataUsageWindowController] bandwidthDownLabel] setStringValue:@"0KB/s"];
        
        [appDelegate stopFlashingWarningLabel];
        
        [appDelegate showConnectionLabel];
    });
}

#pragma mark -
#pragma mark Video Transcoding
#pragma mark -

static void write_thumnail_image_for_data(uint8_t* data, int w, int h) {
    NSString* filename = [[NSString stringWithUTF8String:current_video_name] stringByReplacingOccurrencesOfString:@"video" withString:@"thumbnail"];
    NSString* thumbPath = [[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"] stringByAppendingPathComponent:[[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"jpg"]];
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, 3*w*h, NULL);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    CGImageRef cgImage = CGImageCreate(w, h, 8, 24, 3*w, colorSpace, kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault);
    NSImage* thumbnail = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(w, h)];
    
    NSBitmapImageRep* imageRep = [NSBitmapImageRep imageRepWithData:[thumbnail TIFFRepresentation]];
    NSDictionary* imageProps = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
    NSData* imageData = [imageRep representationUsingType:NSJPEGFileType properties:imageProps];
    [imageData writeToFile:thumbPath atomically:NO];
    
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
}

int drone3g_transcode_video(const char* raw_filename, const char* out_filename, void(*progress_updater)(float,void*), void* ident) {
    is_transcoding = 1;
    
    __block BOOL done = NO;
    
    const char* record_path = [[[[NSFileManager applicationStoragePath] stringByAppendingPathComponent:@"Videos"] stringByAppendingPathComponent:[NSString stringWithUTF8String:current_video_name]] UTF8String];
    
    // Reduce thread priority
    struct sched_param sched;
    sched.sched_priority = sched_get_priority_min(SCHED_OTHER);
    pthread_setschedparam(pthread_self(), SCHED_OTHER, &sched);
    
    if(ffmpeg_inited == 0) {
        ffmpeg_inited = 1;
        
        av_register_all();
        avcodec_register_all();
        av_log_set_level(AV_LOG_QUIET);
    }
    
    // File needs to have enough data before proceeding
    struct stat st;
    do {
        sleep(1);
        
        int ret = stat(raw_filename, &st);
        if(ret < 0) { // File was deleted
            is_transcoding = 0;
            return -1;
        }
    } while(st.st_size < 100*1024);
    
    // FFmpeg decoding
    AVFormatContext* rawFmtCtx = NULL;
    AVInputFormat* inFmt = av_find_input_format("h264");
    
    int ret = avformat_open_input(&rawFmtCtx, raw_filename, inFmt, NULL);
    if(rawFmtCtx == NULL) {
        char errbuf[4096];
        av_strerror(ret, errbuf, 4096);
        
        syslog(LOG_ERR, "Transcoder: Error opening %s raw file! %s.\n", raw_filename, errbuf);
        
        is_transcoding = 0;
        
        return -1;
    }
    
    avformat_find_stream_info(rawFmtCtx, NULL);
    //av_dump_format(rawFmtCtx, 0, raw_filename, 0);
    
    // Calculate bitrate of video
    AVPacket packet;
    int bitrate = 0;
    
    for(int i=0;i<30;i++) {
        if(av_read_frame(rawFmtCtx, &packet) >= 0) {
            bitrate += packet.size;
            av_free_packet(&packet);
            
            continue;
        }
        
        av_free_packet(&packet);
        
        break;
    }
    
    // FIXME: This doesn't seem to work (start time wrong ?) it's only one second of video so it isn't really a big deal
   // av_seek_frame(rawFmtCtx, 0, 0, AVSEEK_FLAG_ANY);
    
    bitrate *= 8;
    
    AVCodecContext* codecCtx = rawFmtCtx->streams[0]->codec;
    AVCodec* codec = avcodec_find_decoder(codecCtx->codec_id);
    avcodec_open2(codecCtx, codec, NULL);
    
    AVFrame* frame_RGB = av_frame_alloc();
    uint8_t* buffer_RGB = (uint8_t*)av_malloc(avpicture_get_size(PIX_FMT_RGB24, codecCtx->width, codecCtx->height));
    avpicture_fill((AVPicture*)frame_RGB, buffer_RGB, PIX_FMT_RGB24, codecCtx->width, codecCtx->height);
    
    AVFrame* frame = av_frame_alloc();
    
    struct SwsContext* convertCtx = sws_getContext(codecCtx->width, codecCtx->height, codecCtx->pix_fmt, codecCtx->width, codecCtx->height, PIX_FMT_RGB24, SWS_SPLINE, NULL, NULL, NULL);
    
    // AVFoundation encoding
    NSError* error;

    AVAssetWriter* recorder = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:[NSString stringWithCString:out_filename encoding:NSUTF8StringEncoding]] fileType:AVFileTypeMPEG4 error:&error];
    NSDictionary* compressionSettings = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:bitrate], AVVideoAverageBitRateKey, AVVideoProfileLevelH264High41, AVVideoProfileLevelKey, nil];
    NSDictionary* recordSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey, [NSNumber numberWithInt:codecCtx->width], AVVideoWidthKey, [NSNumber numberWithInt:codecCtx->height], AVVideoHeightKey, compressionSettings, AVVideoCompressionPropertiesKey, nil];
    AVAssetWriterInput* ffmpegInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:recordSettings];
    
    NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
    [attributes setObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_24RGB] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [attributes setObject:[NSNumber numberWithUnsignedInt:codecCtx->width] forKey:(NSString*)kCVPixelBufferWidthKey];
    [attributes setObject:[NSNumber numberWithUnsignedInt:codecCtx->height] forKey:(NSString*)kCVPixelBufferHeightKey];
    
    AVAssetWriterInputPixelBufferAdaptor* adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:ffmpegInput sourcePixelBufferAttributes:attributes];
    
    [recorder addInput:ffmpegInput];
    ffmpegInput.expectsMediaDataInRealTime = YES;
    
    int status = 0;
    if(![recorder startWriting]) {
        syslog(LOG_ERR, "Transcoder: could not begin transcoding! %s.\n", [[error localizedDescription] UTF8String]);
        
        status = -1;
        goto cleanup;
    }
    
    [recorder startSessionAtSourceTime:kCMTimeZero];
    
    int transcoded_size = 0;
    int stated = 0;
    
    int frameDecoded = 0;
    int frames = 0;
    
    if(progress_updater != NULL) {
        progress_updater(-1.0f, ident); // Indefinite progress, will change when recording is done
    }
    
    while(1) {
        sleep(1);
        
        // Check if file still exists
        if(access(raw_filename, F_OK) < 0) { // File was deleted
            is_transcoding = 0;
            return -2;
        }
        
        while(av_read_frame(rawFmtCtx, &packet) >= 0) {
            // Check if file still exists
            if(access(raw_filename, F_OK) < 0) { // File was deleted
                is_transcoding = 0;
                return -2;
            }
            
            if(progress_updater != NULL) {
                transcoded_size += packet.size;
                
                if(current_video_name[0] == 0 || strcmp(record_path, raw_filename) != 0) {
                    if(stated == 0) {
                        stated = 1;
                        stat(raw_filename, &st);
                    }
                    
                    float progress = (float)transcoded_size / (float)st.st_size;
                    progress_updater((progress > 1.0f) ? 1.0f : progress, ident);
                }
            }
            
            // FIXME: Sometimes this can randomly block forever at _psynch_mutexwait (deadlock ?) it's extrememly rare though
            if(avcodec_decode_video2(codecCtx, frame, &frameDecoded, &packet) < 0) {
                av_free_packet(&packet);
                
                syslog(LOG_WARNING, "Transcoder: Could not decode frame!\n");
                continue;
            }
            
            if(frameDecoded == 1) {
                sws_scale(convertCtx, (const uint8_t* const*)frame->data, frame->linesize, 0, codecCtx->height, frame_RGB->data, frame_RGB->linesize);
                
                CVPixelBufferRef buffer = NULL;
                CVPixelBufferPoolCreatePixelBuffer(NULL, [adaptor pixelBufferPool], &buffer);
                
                CVPixelBufferLockBaseAddress(buffer, 0);
                void* data = CVPixelBufferGetBaseAddress(buffer);
                memcpy(data, frame_RGB->data[0], codecCtx->width*codecCtx->height*3);
                CVPixelBufferUnlockBaseAddress(buffer, 0);
                
                while(!adaptor.assetWriterInput.readyForMoreMediaData) {
                    usleep(10);
                }
                
                CMTime presentTime = CMTimeMake(frames++, 30);
                if(![adaptor appendPixelBuffer:buffer withPresentationTime:presentTime]) {
                    syslog(LOG_WARNING, "Transcoder: Failed to encode frame!\n");
                }
                
                frameDecoded = 0;
                
                CVBufferRelease(buffer);
            }
            
            av_free_packet(&packet);
        }
        
        if(current_video_name[0] == 0 || strcmp(record_path, raw_filename) != 0) {
            break;
        }
        
    }
 
    [ffmpegInput markAsFinished];
    
    // Annoyingly this was chagned by Apple to non-blocking during development, since it's a pain to change the entire function
    // it just spins a loop until the completion handler is done.
    [recorder finishWritingWithCompletionHandler:^{
        done = YES;
    }];
    
    // FIXME: Actually use the proper format for that completion handler rather than this ugly loop
    while(!done) {
        usleep(100000);
    }
    
cleanup:
    av_frame_free(&frame_RGB);
    free(buffer_RGB);
    sws_freeContext(convertCtx);
    
    avcodec_close(codecCtx);
    av_free(frame);
    avformat_close_input(&rawFmtCtx);
    
    is_transcoding = 0;
    
    return status;
}

#pragma mark -
#pragma mark Entry Point
#pragma mark -

static void* drone3g_main(void* arg) {
    // Pick last 2 numbers of random port for ffmpeg (this gives 1/100 odds of picking same port)
    int ffmpeg_port = 9600 + arc4random_uniform(100);
    drone3g_set_ffmpeg_port(ffmpeg_port);
    
    // Setup ffmpeg
    if(ffmpeg_inited == 0) {
        ffmpeg_inited = 1;
        
        av_register_all();
        avcodec_register_all();
        avformat_network_init();
        
        av_log_set_level(AV_LOG_QUIET);
    }
    
    syslog(LOG_NOTICE, "Listening for ARDrone...\n");
    
    // Handles SDL Joystick connection
    pthread_mutex_init(&joystick_lock, NULL);
    pthread_t joystick_thread;
    pthread_create(&joystick_thread, NULL, joystick_connect_loop, NULL);
    
    // Control thread
    pthread_t control_thread;
    pthread_create(&control_thread, NULL, control_loop, NULL);
    
    drone3g_setup_server();
    
    [appDelegate performSelectorOnMainThread:@selector(showHUD) withObject:nil waitUntilDone:NO];
    
    // Undocumented startup commands (what do these do ?)
    drone3g_send_command("AT*PMODE= ,2\r");
    drone3g_send_command("AT*MISC= ,20,2000,3000\r");
    
    sleep(2);
    
    AVInputFormat* inFmt = NULL;
    char fmt_name[5] = "h264";
    
connect_ffmpeg:
    inFmt = av_find_input_format(fmt_name);
    
    char url[1024];
    do {
        sprintf(url, "tcp://127.0.0.1:%i", ffmpeg_port);
        avformat_open_input(&formatCtx, url, inFmt, NULL);
    } while(formatCtx == NULL);
    
    if(avformat_find_stream_info(formatCtx, NULL) < 0) {
        syslog(LOG_ERR, "Couldn't find stream info for playback!\n");
        
        avformat_close_input(&formatCtx);
        
        goto connect_ffmpeg;
    }
    //av_dump_format(formatCtx, 0, url, 0);
    
    AVCodecContext* codecCtx = formatCtx->streams[0]->codec;
    AVCodec* codec = avcodec_find_decoder(codecCtx->codec_id);
    
    if(codec == NULL) {
        syslog(LOG_ERR, "Missing video codec!\n");
        
        avcodec_close(codecCtx);
        avformat_close_input(&formatCtx);
        
        goto connect_ffmpeg;
    }
    
    if(avcodec_open2(codecCtx, codec, NULL) < 0) {
        syslog(LOG_ERR, "Failed to open codec.\n");
        
        avcodec_close(codecCtx);
        avformat_close_input(&formatCtx);
        
        goto connect_ffmpeg;
    }
    
setup_video:
    // Sometimes the video can be corrupt when switching to mpeg (size is wrong and probably a lot of other things)
    if(codecCtx->width > 1280) {
        syslog(LOG_ERR, "Invalid input format while proccessing video.\n");
        
        avcodec_close(codecCtx);
        avformat_close_input(&formatCtx);
        
        goto connect_ffmpeg;
    }
    if(codecCtx->width == 1280) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[appDelegate hdMenuItem] setState:NSOnState];
            [[appDelegate sdMenuItem] setState:NSOffState];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[appDelegate hdMenuItem] setState:NSOffState];
            [[appDelegate sdMenuItem] setState:NSOnState];
        });
    }
    
    AVFrame* frame_RGB = av_frame_alloc();
    uint8_t* buffer_RGB = (uint8_t*)av_malloc(avpicture_get_size(PIX_FMT_RGB24, codecCtx->width, codecCtx->height));
    avpicture_fill((AVPicture*)frame_RGB, buffer_RGB, PIX_FMT_RGB24, codecCtx->width, codecCtx->height);
    
    // Give OpenGL View video dimensions
    [[appDelegate drone3GGLView] setVideoWidth:codecCtx->width];
    [[appDelegate drone3GGLView] setVideoHeight:codecCtx->height];
    [[appDelegate drone3GGLView] setPixelBuffer:frame_RGB->data[0]];
    
    struct SwsContext* convertCtx = sws_getContext(codecCtx->width, codecCtx->height, codecCtx->pix_fmt, codecCtx->width, codecCtx->height, PIX_FMT_RGB24, SWS_SPLINE, NULL, NULL, NULL);
    
    int frameDecoded = 0;
    
    AVFrame* frame = av_frame_alloc();
    AVPacket packet;
    
    // Rendering and decoding
    while(1) {
        if(drone3g_got_connection() != 1) {
            usleep(5000);
            continue;
        }
        
        if(av_read_frame(formatCtx, &packet) < 0) {
            syslog(LOG_WARNING, "Could not read frame!\n");
            
            av_frame_free(&frame_RGB);
            free(buffer_RGB);
            sws_freeContext(convertCtx);
            
            //avcodec_close(codecCtx);
            av_free(frame);
            avformat_close_input(&formatCtx);
            
            goto connect_ffmpeg;
        }
        
        if(record_state == 1 && record_to_usb == 0) {
            fwrite(packet.data, 1, packet.size, current_video_fp);
        }
        if(record_to_usb == 1) {
            if(record_state == 1 && strcmp(fmt_name, "h264") == 0) {
                syslog(LOG_NOTICE, "Video codec change H264 --> MPEG4.2\n");
                
                strcpy(fmt_name, "m4v");
                
                av_frame_free(&frame_RGB);
                free(buffer_RGB);
                sws_freeContext(convertCtx);
                
                avcodec_close(codecCtx);
                av_free(frame);
                avformat_close_input(&formatCtx);
                
                av_free_packet(&packet);
                
                goto connect_ffmpeg;
            } else if(record_state == 0 && strcmp(fmt_name, "m4v") == 0) {
                syslog(LOG_NOTICE, "Video codec change MPEG4.2 --> H264\n");
                
                strcpy(fmt_name, "h264");
                
                av_frame_free(&frame_RGB);
                free(buffer_RGB);
                sws_freeContext(convertCtx);
                
                avcodec_close(codecCtx);
                av_free(frame);
                avformat_close_input(&formatCtx);
                
                av_free_packet(&packet);
                
                goto connect_ffmpeg;
            }
        }
        
        calculate_bitrate(&packet);
        
        // FIXME: This deadlocks and requires application restart for some unknown reason
        if(avcodec_decode_video2(codecCtx, frame, &frameDecoded, &packet) < 0) {
            av_free_packet(&packet);
            
            syslog(LOG_WARNING, "Could not decode frame!\n");
            continue;
        }
        
        if(frameDecoded == 1) {
            if(frame->width != [appDelegate drone3GGLView].videoWidth) { // Resolution change
                syslog(LOG_NOTICE, "Resolution change from %ix%i -> %ix%i\n", [appDelegate drone3GGLView].videoWidth, [appDelegate drone3GGLView].videoHeight, frame->width, frame->height);
                
                av_frame_free(&frame_RGB);
                free(buffer_RGB);
                av_frame_free(&frame);
                sws_freeContext(convertCtx);
                av_free_packet(&packet);
                
                goto setup_video;
            }
            
            sws_scale(convertCtx, (const uint8_t* const*)frame->data, frame->linesize, 0, codecCtx->height, frame_RGB->data, frame_RGB->linesize);
            
            if(get_thumbnail == 1) {
                write_thumnail_image_for_data(frame_RGB->data[0], codecCtx->width, codecCtx->height);
                get_thumbnail = 0;
            }
            
            [[appDelegate drone3GGLView] setNeedsDisplay:YES];
            
            frameDecoded = 0;
        }
        
        av_free_packet(&packet);
    }
    
    return NULL;
}

void drone3g_init() {
    if(drone3g_inited == 1) {
        return;
    }
    
    openlog("Drone3G", LOG_PERROR, 0);
    
    gettimeofday(&flat_trim_timestamp, NULL);
    
    drone3g_navdata_callback = navdata_callback;
    drone3g_gpsdata_callback = gpsdata_callback;
    drone3g_got_date_callback = date_callback;
    drone3g_connection_lost_callback = connection_lost_callback;
    drone3g_connection_established_callback = connection_established_callback;
    drone3g_start_image_transfer_callback = start_image_transfer_callback;
    drone3g_transfer_image_data_callback = transfer_image_data_callback;
    drone3g_pong_callback = pong_callback;
    
    // Install signal handler to catch SIGTERM and exit gracefully
    struct sigaction quit;
    memset(&quit, 0, sizeof(struct sigaction));
    quit.sa_handler = drone3g_exit;
    sigaction(SIGTERM, &quit, NULL);
    
    // Get app delegate for UI control
    appDelegate = (Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate];
    
    drone3g_inited = 1;
}

// Creates a new thread and runs drone3g_main()
void drone3g_start() {
    drone3g_init();
    
    pthread_create(&drone3g_thread, NULL, drone3g_main, NULL);
}
