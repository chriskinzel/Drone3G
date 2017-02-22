//
//  drone_main.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#ifndef Drone3G_Mac_drone_main_h
#define Drone3G_Mac_drone_main_h

#define DRONE3G_NUM_FUNCTIONS 7

#define DRONE3G_STICK_LAYOUT_RH 0
#define DRONE3G_STICK_LAYOUT_LH 1

typedef struct {
    int buttons[16];
    int num_of_buttons;
}drone3g_button_map;

int drone3g_stick_layout;
drone3g_button_map drone3g_button_mapping[DRONE3G_NUM_FUNCTIONS];
float drone3g_sensitivities[4]; // One sensitivity for pitch and yaw then climb has one for up and down

int drone3g_allow_terminate;

void* drone3g_start(void* arg);
void drone3g_cleanup(int arg);

#endif
