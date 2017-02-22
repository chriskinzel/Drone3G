//
//  drone_main.c
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GAppDelegate.h"
#import <QuartzCore/QuartzCore.h>

#include "drone_main.h"
#include "drone_com.h"

#include <errno.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>

#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>

#include <SDL2/SDL.h>
#include <OpenGL/gl.h>

#define GET_BIT(n,x) ((n & (1 << x)) > 0)
#define FILTER 0.3f

// float drone3g_sensitivities[4] = {0.25f,0.23f,0.50f,0.35f};

#pragma mark SHORT TERM
#pragma mark -
// TODO: Testing (Watch out for the GPS code on the drone causing a segfault especially before lock (looks fixed now) )

// TODO: Try using UDP

// TODO: Preferences for HUD and any other preferences

// TODO: iPhone as controller

// TODO: 3 modes when lost connection LAND after x minutes also avoiding water if the GPS is available, FLY STRAIGHT HOME @ 60ft requires GPS, BACKTRACK requires GPS
// TODO: Rewrite in C++ or C with cleaner code
#pragma mark -

#pragma mark LONG TERM
#pragma mark -
// TODO: Installer
// TODO: Disclaimers
// TODO: Use syslog instead of printf

// TODO: Encrypted data transmission (SSL ?)

// TODO: Could add support for any generic controller by letting the user set it up
// TODO: Could have "multiple" loadable controller preferences
// TODO: Allow control of multiple drones
#pragma mark -

pthread_mutex_t joystick_lock;

Drone3GAppDelegate* appDelegate;
SDL_Joystick* joystick = NULL;

AVFormatContext* formatCtx = NULL;

uint64_t last_sent_bytes = 0;
uint64_t last_recv_bytes = 0;

uint32_t last_ctrl_state = 1;

int had_battery_warning = 0;
int had_battery_emergency = 0;
int battery_halfway_point;

int stream_bit_count = 0;
int frame_count = 0;

#pragma mark -
#pragma mark Cleanup
#pragma mark -

void drone3g_cleanup(int signum) {
    drone3g_got_connection = 0;
    drone3g_close_sockets();
    
    if(formatCtx != NULL) {
        avformat_close_input(&formatCtx);
        avformat_network_deinit();
    }
    
    SDL_Quit();
    
    if(signum == SIGTERM) {
        exit(0);
    }
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
        printf("[NOTICE] Estimated bitrate %iKbps\n", avg_bitrate);
        
        NSSlider* slider = [[[appDelegate bitrateSlider] subviews] objectAtIndex:0];
        if(abs([slider intValue] - avg_bitrate) > 250) {
            avg_bitrate = (int)(500.0f * floorf(avg_bitrate/500.0f + 0.5f));
            avg_bitrate = (avg_bitrate < 250) ? 250 : avg_bitrate;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[appDelegate bitrateLabel] setStringValue:[NSString stringWithFormat:@"                Bitrate: %iKbps", avg_bitrate]];
                [slider setIntValue:avg_bitrate];
            });
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[[appDelegate bitrateSlider] subviews] objectAtIndex:0] setEnabled:YES];
            [[appDelegate bitrateLabel] setTextColor:[NSColor controlTextColor]];
        });
        
        stream_bit_count = 0;
    }
}

#pragma mark -
#pragma mark Work Loops
#pragma mark -

static void* joystick_connect_loop(void* arg) {
    while(1) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            SDL_PollEvent(NULL); // This is the function that must be called on the main thread that checks for joystick reconnect
           
            if(joystick == NULL && SDL_NumJoysticks() > 0) {
                for(int i=0;i<SDL_NumJoysticks();i++) {
                    const char* joystick_name = SDL_JoystickNameForIndex(i);
                    
                    if(strstr(joystick_name, "PLAYSTATION") != NULL) {
                        pthread_mutex_lock(&joystick_lock);
                        joystick = SDL_JoystickOpen(i);
                        pthread_mutex_unlock(&joystick_lock);
                        
                        printf("[NOTICE] Joystick Connected! %s\n", joystick_name);
                        
                        [appDelegate stopFlashingControllerIcon];
                        [[appDelegate controllerImageView] setHidden:NO];
                        
                        break;
                    }
                }
            }
            if(joystick != NULL && SDL_JoystickGetAttached(joystick) == SDL_FALSE) {
                printf("[NOTICE] Joystick Disconnected!\n");
                
                if(drone3g_get_navdata().ctrl_state == DRONE3G_STATE_FLYING) { // When flying we animate the controller icon on disconnection
                    [appDelegate flashControllerIcon];
                } else {
                    [[appDelegate controllerImageView] setHidden:YES];
                }
                
                pthread_mutex_lock(&joystick_lock);
                
                SDL_JoystickClose(joystick);
                joystick = NULL;
                
                pthread_mutex_unlock(&joystick_lock);
            }
        });
        
        sleep(1);
    }
    
    return NULL;
}

static int check_condition(int index) {
    int condition = 0;
    for(int i=0;i<drone3g_button_mapping[index].num_of_buttons;i++) {
        condition |= SDL_JoystickGetButton(joystick, drone3g_button_mapping[index].buttons[i]);
    }
    
    return condition;
}

static void* control_loop(void* arg) {
    int hover = 0;
    struct timeval hover_time_ref;
    
    __block int old_E_state = 0;
    __block int cam_state = 0;
    __block int old_Square_state = 0;
    __block int old_sel_state = 0;
    
    // SDL has to be run in main thread for joystick reconnection to work
    dispatch_sync(dispatch_get_main_queue(), ^{
        // Setup SDL for joystick
        if (SDL_Init(SDL_INIT_JOYSTICK) < 0) {
            fprintf(stderr, "[FATAL ERROR] Unable to init SDL: %s\n", SDL_GetError());
            exit(1);
        }
    });
    
    while(1) {
        __block int pitch = 0;
        __block int roll = 0;
        __block int climb = 0;
        __block int yaw = 0;
        __block int fly = 0;
        __block int reset_emergency = 0;
        __block int flat_trim = 0;
        __block int switch_cam = 0;
        __block int calib = 0;
        __block int lock_hover = 0;
        
        char cmd_buffer[1024];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            pthread_mutex_lock(&joystick_lock);
            
            if(SDL_JoystickGetAttached(joystick) == SDL_TRUE) { // Proccess joystick data
                SDL_JoystickUpdate();
                
                float l_stick_x =  (float)SDL_JoystickGetAxis(joystick, (drone3g_stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 0 : 2) / 32768;
                float l_stick_y =  (float)SDL_JoystickGetAxis(joystick, (drone3g_stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 1 : 3) / 32768;
                float r_stick_x =  (float)SDL_JoystickGetAxis(joystick, (drone3g_stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 2 : 0) / 32768;
                float r_stick_y = -(float)SDL_JoystickGetAxis(joystick, (drone3g_stick_layout == DRONE3G_STICK_LAYOUT_RH) ? 3 : 1) / 32768;
                
                if(l_stick_x < FILTER && l_stick_x > -FILTER) {
                    l_stick_x = 0.0f;
                }
                if(l_stick_y < FILTER && l_stick_y > -FILTER) {
                    l_stick_y = 0.0f;
                }
                if(r_stick_x < FILTER && r_stick_x > -FILTER) {
                    r_stick_x = 0.0f;
                }
                if(r_stick_y < FILTER && r_stick_y > -FILTER) {
                    r_stick_y = 0.0f;
                }
                
                l_stick_x *= drone3g_sensitivities[0];
                l_stick_y *= drone3g_sensitivities[0];
                r_stick_x *= drone3g_sensitivities[1];
                if(r_stick_y > 0.0f) {
                    r_stick_y *= drone3g_sensitivities[2];
                } else {
                    r_stick_y *= drone3g_sensitivities[3];
                }
                
            
                if(check_condition(2) == 1) {
                    fly = 1; // Takeoff
                }
                if(check_condition(0) == 1) {
                    fly = -1; // Land
                }
                if(check_condition(3) == 1) {
                    flat_trim = 1; // Trim
                }
                if(check_condition(1) == 1) {
                    lock_hover = 1;
                }
                /*if(SDL_JoystickGetButton(joystick, 0) == 1) {
                    if(old_sel_state == 0) {
                        calib = 1;
                    }
                    
                    old_sel_state = 1;
                } else {
                    old_sel_state = 0;
                }*/
                
                if(check_condition(4) == 1) {
                    if(old_E_state == 0) {
                        reset_emergency = 1;
                    }
                    
                    old_E_state = 1;
                } else {
                    old_E_state = 0;
                }
                
                if(check_condition(5) == 1) {
                    if(old_Square_state == 0) {
                        cam_state = (cam_state == 0) ? 1 : 0;
                        switch_cam = 1;
                    }
                    
                    old_Square_state = 1;
                } else {
                    old_Square_state = 0;
                }

               /* for(int i=0;i<SDL_JoystickNumButtons(joystick);i++) { // This prints out which buttons are pushed
                    if(SDL_JoystickGetButton(joystick, i) == 1) {
                        printf("Button #%i Pushed %i\n", i, arc4random() % 1000);
                    }
                }*/
               // printf("LX:%f LY:%f RX:%f RY:%f\n", l_stick_x, l_stick_y, r_stick_x, r_stick_y);
                
                memcpy(&pitch, &l_stick_y, sizeof(int));
                memcpy(&roll, &l_stick_x, sizeof(int));
                memcpy(&climb, &r_stick_y, sizeof(int));
                memcpy(&yaw, &r_stick_x, sizeof(int));
            }
            
            pthread_mutex_unlock(&joystick_lock);
        });
        
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
        }
        
        if(roll == 0 && pitch == 0 && climb == 0 && yaw == 0) {
            if(hover == 0) {
                gettimeofday(&hover_time_ref, NULL);
                hover = 1;
            }
            
            struct timeval current_time;
            gettimeofday(&current_time, NULL);
            
            if(current_time.tv_sec - hover_time_ref.tv_sec >= 3 || lock_hover == 1) {
                drone3g_send_command("AT*PCMD= ,0,0,0,0,0\r"); // Hover and maintain position
                hover_time_ref.tv_sec = 0; // This is done so that hover stays locked after lock_hover = 0
            } else {
                drone3g_send_command("AT*PCMD= ,1,0,0,0,0\r"); // Hover and coast
            }
        } else {
            sprintf(cmd_buffer, "AT*PCMD= ,1,%i,%i,%i,%i\r", roll, pitch, climb, yaw);
            drone3g_send_command(cmd_buffer);
            
            hover = 0;
        }
        
        usleep(15000);
    }
}

#pragma mark -
#pragma mark Callbacks
#pragma mark -

static void date_callback(int month, int day) {
    if(day > 31 || month > 12 || month < 1 || day < 1) { // Invalid date
        printf("[WARNING] Received inavlid date format from drone!. Asking again...\n");
        drone3g_send_command("AT*GETDATE\r");
        
        return;
    }
    
    NSDateComponents* dateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:[NSDate date]];
    [dateComponents setDay:day];
    [dateComponents setMonth:month];
    NSDate* date = [[NSCalendar currentCalendar] dateFromComponents:dateComponents];
    
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    
    dateFormatter.dateFormat = @"MMMM";
    NSString* monthString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:3];
    
    dateFormatter.dateFormat=@"EEEE";
    NSString* dayString = [[[dateFormatter stringFromDate:date] capitalizedString] substringToIndex:3];
    
    NSString* suffix_string = @"|st|nd|rd|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|th|st|nd|rd|th|th|th|th|th|th|th|st";
    NSArray* suffixes = [suffix_string componentsSeparatedByString: @"|"];
    
    NSString* dateString = [NSString stringWithFormat:@"%@ %@ %d%@", dayString, monthString, day, [suffixes objectAtIndex:day-1]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[appDelegate drone3GDatWindowController] setDateString:dateString];
        [[appDelegate dataUsageMenuItem] setEnabled:YES];
    });
}

static void navdata_callback(drone3g_navdata_t navdata) {
    if(navdata.ctrl_state == DRONE3G_STATE_EMERGENCY || navdata.ctrl_state == DRONE3G_STATE_LANDED) {
        drone3g_allow_terminate = 1;
    } else {
        drone3g_allow_terminate = 0;
    }
    
    printf("Fix Status:%i\n", navdata.gps_navdata.fix_status);
    printf("Lat:%f Lon:%f\n", navdata.gps_navdata.latitude, navdata.gps_navdata.longitude);
    printf("Altitude Above Mean Sea Level:%fft\n", navdata.gps_navdata.altitude_msl*3.28084);
    printf("Speed:%f km/h\n", navdata.gps_navdata.ground_speed);
        
    int altitude = (int)((float)navdata.altitude*0.00328084f);
    float velocity = sqrtf(navdata.vx*navdata.vx + navdata.vy*navdata.vy + navdata.vz*navdata.vz)*0.0036f;
    
    if(navdata.ctrl_state == DRONE3G_STATE_FLYING && (last_ctrl_state == DRONE3G_STATE_LANDED || last_ctrl_state == DRONE3G_STATE_EMERGENCY || last_ctrl_state == DRONE3G_STATE_TAKEOFF) ) { // Drone took off
        had_battery_emergency = 0;
        had_battery_warning = 0;
        
        battery_halfway_point = -1;
        if(navdata.battery_percentage > 20) {
            battery_halfway_point = navdata.battery_percentage/2 + 10;
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
            if(navdata.battery_percentage < battery_halfway_point && navdata.battery_percentage > 20 && had_battery_warning == 0 && !appDelegate.batteryAnimationsAreRunning) {
                [appDelegate batteryWarning];
                had_battery_warning = 1;
            }
            if(navdata.battery_percentage <= 20 && had_battery_emergency == 0) {
                if(appDelegate.batteryAnimationsAreRunning) { // Stop warning animation if it is playing
                    [appDelegate stopbatteryAnimations];
                }
                
                [appDelegate batteryEmergency];
                had_battery_emergency = 1;
            }
        } else if(appDelegate.batteryAnimationsAreRunning) { // If we aren't flying make sure no animations are running
            [appDelegate stopbatteryAnimations];
        }
        
        [[appDelegate batteryLabel] setStringValue:[NSString stringWithFormat:@"%i%%", navdata.battery_percentage]];
        [[appDelegate altitudeLabel] setStringValue:[NSString stringWithFormat:@"%i ft", altitude]];
        [[appDelegate velocityLabel] setStringValue:[NSString stringWithFormat:@"%.1f km/h", velocity]];
        
        // Set compass angle
        float angle;
        if(navdata.time_flying > 0) { // If the drone has been flying the compass flips 180˚
            angle = fmodf(navdata.psi/1000.0f+360.0f, 360.0f);
        } else {
            angle = fmodf(navdata.psi/1000.0f+180.0f, 360.0f);
        }
        [appDelegate setCompassAngle:angle];
        //printf("%.2f %.2f\n", angle, navdata.psi/1000.0f);
        
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
        if(navdata.total_sent_bytes + navdata.total_recv_bytes > 1024*1024*1000) { // GB
            [[[appDelegate drone3GDatWindowController] dataUsedLabel] setStringValue:[NSString stringWithFormat:@"%.2fGB", (navdata.total_recv_bytes + navdata.total_sent_bytes) / 1024.0f / 1024.0f / 1000.0f]];
        } else { // MB
            [[[appDelegate drone3GDatWindowController] dataUsedLabel] setStringValue:[NSString stringWithFormat:@"%lluMB", (navdata.total_recv_bytes + navdata.total_sent_bytes) / 1024 / 1024]];
        }
        
        if(navdata.total_sent_bytes > last_sent_bytes) {
            [[[appDelegate drone3GDatWindowController] bandwidthUpLabel] setStringValue:[NSString stringWithFormat:@"%uKB/s", (unsigned int)(navdata.total_sent_bytes - last_sent_bytes) / 1024]];
        }
        if(navdata.total_recv_bytes > last_recv_bytes) {
            if(navdata.total_recv_bytes - last_recv_bytes > 1024*1024) {
                [[[appDelegate drone3GDatWindowController] bandwidthDownLabel] setStringValue:[NSString stringWithFormat:@"%.2fMB/s", (unsigned int)(navdata.total_recv_bytes - last_recv_bytes) / 1024.0f / 1024.0f]];
            } else {
                [[[appDelegate drone3GDatWindowController] bandwidthDownLabel] setStringValue:[NSString stringWithFormat:@"%uKB/s", (unsigned int)(navdata.total_recv_bytes - last_recv_bytes) / 1024]];
            }
        }
        
        last_recv_bytes = navdata.total_recv_bytes;
        last_sent_bytes = navdata.total_sent_bytes;
        
        // Show time flying
        render_time_string(navdata.time_flying / 60, navdata.time_flying % 60);
    });
}

static void connection_established_callback() {
    frame_count = 0;
    stream_bit_count = 0;
    
    drone3g_send_command("AT*GETDATE\r"); // Tells the drone to put the last data usage reset date into the incoming data stream
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if([[appDelegate drone3GGLView] pixelBuffer] != NULL) {
            [[[[appDelegate bitrateSlider] subviews] objectAtIndex:0] setEnabled:YES];
            [[appDelegate bitrateLabel] setTextColor:[NSColor controlTextColor]];
        }
        
        [[appDelegate hdMenuItem] setEnabled:YES];
        [[appDelegate sdMenuItem] setEnabled:YES];
        [appDelegate hideConnectionLabel];
    });
}

static void connection_lost_callback() {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[[appDelegate bitrateSlider] subviews] objectAtIndex:0] setEnabled:NO];
        [[appDelegate dataUsageMenuItem] setEnabled:NO];
        [[appDelegate hdMenuItem] setEnabled:NO];
        [[appDelegate sdMenuItem] setEnabled:NO];
        [[appDelegate bitrateLabel] setTextColor:[NSColor disabledControlTextColor]];
        
        [appDelegate showConnectionLabel];
    });
}

#pragma mark -
#pragma mark Entry Point
#pragma mark -

void* drone3g_start(void* arg) {
    drone3g_allow_terminate = 1;
    drone3g_got_connection = 0;
    
    drone3g_navdata_callback = navdata_callback;
    drone3g_got_date_callback = date_callback;
    drone3g_connection_lost_callback = connection_lost_callback;
    drone3g_connection_established_callback = connection_established_callback;
    
    // Install signal handler to catch SIGTERM and exit gracefully
    struct sigaction quit;
    memset(&quit, 0, sizeof(struct sigaction));
    quit.sa_handler = drone3g_cleanup;
    sigaction(SIGTERM, &quit, NULL);
    
    // Get app delegate for UI control
    appDelegate = (Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate];
    
    // Pick last 2 numbers of random port for ffmpeg (this gives 1/100 odds of picking same port)
    drone3g_ffmpeg_port = 6400 + (arc4random() % 100);
    
    // Setup ffmpeg
    av_register_all();
    avcodec_register_all();
    avformat_network_init();

    av_log_set_level(AV_LOG_QUIET);
    
    printf("[NOTICE] Listening for ARDrone...\n");
    
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
    
    char url[1024];
    sprintf(url, "tcp://127.0.0.1:%i", drone3g_ffmpeg_port);
    do {
        avformat_open_input(&formatCtx, url, NULL, NULL);
    } while(formatCtx == NULL);
    
    avformat_find_stream_info(formatCtx, NULL);
    //av_dump_format(formatCtx, 0, url, 0);
    
    AVCodec* codec;
    
    AVCodecContext* codecCtx = formatCtx->streams[0]->codec;
    codec = avcodec_find_decoder(codecCtx->codec_id);
    avcodec_open2(codecCtx, codec, NULL);
    
setup_video:
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
    
    AVFrame* frame_RGB = avcodec_alloc_frame();
    uint8_t* buffer_RGB = (uint8_t*)av_malloc(avpicture_get_size(PIX_FMT_RGB24, codecCtx->width, codecCtx->height));
    avpicture_fill((AVPicture*)frame_RGB, buffer_RGB, PIX_FMT_RGB24, codecCtx->width, codecCtx->height);
    
    // Give OpenGL View video dimensions
    pthread_mutex_t* pixel_buf_lock = [appDelegate drone3GGLView].pixel_buffer_mutx;
    [[appDelegate drone3GGLView] setVideoWidth:codecCtx->width];
    [[appDelegate drone3GGLView] setVideoHeight:codecCtx->height];
    [[appDelegate drone3GGLView] allocatePixelBuffer];
    [[appDelegate drone3GGLView] setPixelBuffer:frame_RGB->data[0]];
    
    struct SwsContext* convertCtx = sws_getContext(codecCtx->width, codecCtx->height, codecCtx->pix_fmt, codecCtx->width, codecCtx->height, PIX_FMT_RGB24, SWS_SPLINE, NULL, NULL, NULL);
    
    int frameDecoded = 0;
    
    AVFrame* frame = avcodec_alloc_frame();
    AVPacket packet;

    // Rendering and decoding
    while(1) {
        if(drone3g_got_connection != 1) {
            usleep(5000);
            continue;
        }
        
        if(av_read_frame(formatCtx, &packet) < 0) {
            fprintf(stderr, "[WARNING] Could not read frame!\n");
            continue;
        }
        
        if(avcodec_decode_video2(codecCtx, frame, &frameDecoded, &packet) < 0) {
            fprintf(stderr, "[WARNING] Could not decode frame!\n");
            continue;
        }
        
        if(frameDecoded == 1) {
            if(frame->width != [appDelegate drone3GGLView].videoWidth) { // Resolution change
                printf("[NOTICE] Resolution change from %ix%i -> %ix%i\n", [appDelegate drone3GGLView].videoWidth, [appDelegate drone3GGLView].videoHeight, frame->width, frame->height);
                
                av_frame_free(&frame_RGB);
                free(buffer_RGB);
                av_frame_free(&frame);
                sws_freeContext(convertCtx);
                av_free_packet(&packet);
                
                goto setup_video;
            }
            
            calculate_bitrate(&packet);
            
            pthread_mutex_lock(pixel_buf_lock);
            sws_scale(convertCtx, (const uint8_t* const*)frame->data, frame->linesize, 0, codecCtx->height, frame_RGB->data, frame_RGB->linesize);
            pthread_mutex_unlock(pixel_buf_lock);

            [[appDelegate drone3GGLView] performSelectorOnMainThread:@selector(display) withObject:nil waitUntilDone:NO];
            
            frameDecoded = 0;
            
            av_free_packet(&packet);
        }
    }
    
    return NULL;
}