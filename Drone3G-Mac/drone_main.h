//
//  drone_main.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#ifndef Drone3G_Mac_drone_main_h
#define Drone3G_Mac_drone_main_h

#define DRONE3G_NUM_FUNCTIONS 13

typedef enum {
    DRONE3G_STICK_LAYOUT_RH = 0,
    DRONE3G_STICK_LAYOUT_LH
}drone3g_stick_layout;

typedef enum {
    DRONE3G_TERMINATION_EXIT = 0,
    DRONE3G_TERMINATION_FLYING,
    DRONE3G_TERMINATION_TRANSCODING,
    DRONE3G_TERMINATION_INSTALLING = 4,
    DRONE3G_TERMINATION_UNINSTALLING = 8
}drone3g_termination_status_info;

typedef enum {
    DRONE3G_RECORDING_MODE_LOCAL = 0,
    DRONE3G_RECORDING_MODE_USB
}drone3g_recording_mode;

typedef struct {
    int buttons[16];
    int num_of_buttons;
}drone3g_button_map;

#pragma mark -
#pragma mark Getters
#pragma mark -

// Returns DRONE3G_STICK_LAYOUT_RH for right handed mode and DRONE3G_STICK_LAYOUT_LH for left handed mode
int drone3g_get_stick_layout();

// Returns pointer to current button mapping, use drone3g_lock_button_map() before modifying contents and for thread safety
drone3g_button_map* drone3g_get_button_mapping();

// Returns pointer to array of sensitivities one for pitch and roll, then one for yaw, then one each for climb and descend as floating point
// numbers 0.0-1.0. Use drone3g_lock_sensitivities_array() before modifying contents and for thread safety
float* drone3g_get_sensitivities_array(); // Default sensitivities are 0.25, 0.23f, 0.60f, 0.45f

#pragma mark -
#pragma mark Setters
#pragma mark -

// Thread safe access of button mapping, must be called before changing the button map
void drone3g_lock_button_map();
void drone3g_unlock_button_map();

// Call these before setting anything and for thread safety in the sensitivites array
void drone3g_lock_sensitivities_array();
void drone3g_unlock_sensitivities_array();

// The setters below should be treated as if they are not thread safe
void drone3g_set_stick_layout(drone3g_stick_layout mode); // Set right handed or left handed mode, default is right handed

void drone3g_set_recording_mode(drone3g_recording_mode mode); // Switch between recording to MicroSD and local

#pragma mark -
#pragma mark Termination Status
#pragma mark -

drone3g_termination_status_info drone3g_allow_termination(); // Returns a bitmask that the application can use when deciding wiether or not to terminate

#pragma mark -
#pragma mark Global Callbacks
#pragma mark -

void drone3g_home_location_changed_callback(double lat, double lon);
void drone3g_flyhome_settings_changed_callback(unsigned int mode, unsigned int land_timeout, unsigned int flyhome_timeout, unsigned int flyhome_alt);

#pragma mark -
#pragma mark Misc
#pragma mark -

// Test connection latency with drone, calls callback when latency has been calculated and sets the argument to the latency
// in milliseconds.
void drone3g_test_latency(void(*)(int));

#pragma mark -
#pragma mark Transcoding Function
#pragma mark -

// NOTE: drone3g_transcode_video()
//
//       progress_updater() if non NULL will be called with floating point percentages ( (0.0)-(+1.0) ) indicating progress
//       -1.0 indicates indeterminate progress (e.g. recording). Use the void* ident to identify the caller of the callback.
//       Upon completion will return 0 for success and < 0 for an error during transcoding.
int drone3g_transcode_video(const char* src, const char* dst, void(*progress_updater_callback)(float, void*), void* ident);

#pragma mark -
#pragma mark Entry and Exit Functions
#pragma mark -

void drone3g_init(); // Prepares Drone3G without starting (useful for transcoding and installing)
void drone3g_start(); // Starts Drone3G in a new thread, calls drone3g_init() if not already initialized
void drone3g_exit(int arg); // take a signal as an argument in the event that this function is to be used as a signal handler

#endif
