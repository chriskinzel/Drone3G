//
//  drone3g_installer.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-26.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#ifndef Drone3G_Mac_drone3g_installer_h
#define Drone3G_Mac_drone3g_installer_h

typedef enum {
    DRONE3G_INSTALLER_STATUS_IDLE = 0,
    DRONE3G_INSTALLER_STATUS_INSTALLING,
    DRONE3G_INSTALLER_STATUS_UNINSTALLING,
    DRONE3G_INSTALLER_STATUS_CONNECTING = 4,
    DRONE3G_INSTALLER_STATUS_CONNECTED = 8
}drone3g_installer_status;

typedef enum {
    DRONE3G_CONNECT_TYPE_INSTALL = 0,
    DRONE3G_CONNECT_TYPE_UNINSTALL
}drone3g_connect_type;

enum {
    DRONE3G_INSTALL_SUCCESS = 0,
    DRONE3G_INSTALL_DRONE_FAILED,
    DRONE3G_INSTALL_ALREADY,
    DRONE3G_INSTALL_LOST_CONNECTION
};

enum {
    DRONE3G_UNINSTALL_SUCCESS = 0,
    DRONE3G_UNINSTALL_FAILED,
    DRONE3G_UNINSTALL_ALREADY,
    DRONE3G_UNINSTALL_LOST_CONNECTION
};

// THIS BITMASK HAS TO BE SHIFTED 2 TO THE RIGHT >> 2 (IT WAS REALLY MEANT FOR COMPUTING TERMINATION STATUS)
drone3g_installer_status drone3g_installer_get_status(); // Returns a bitmask indicating the current state of the installer

// Tries to connect to the ARDrone in a seperate thread, if successful the callback function is called
void drone3g_installer_connect(drone3g_connect_type type, void(*callback)(void));

// Aborts drone3g_installer_connect, callback will not be called, closes connection if one already exists.
void drone3g_installer_stop_connecting();

// Attempts to install drone3g on the currently connected drone, drone3g_installer_connect() must be
// called first and successfully connect. Upon completetion of the install, the complete_callback function
// will be called with an integer argument indicating the completetion status of the install. This function
// cannot be aborted and the running application should not allow termination until the callback is called.
// The progress_update callback allows rendering of UI that reflects the current progress of the install,
// the argument is simply an integer equal to the completetion percent of the install.
void drone3g_installer_install(void(*complete_callback)(int), void(*progress_update)(int));

void drone3g_installer_uninstall(void(*complete_callback)(int), void(*progress_update)(int));


// Sync's carrier settings to drone
// Returns -1 on connection loss, otherwise returns 0
int drone3g_set_carrier_settings(const char* apn, const char* username, const char* password);

// Set drone3g carrier settings to automatic mode and read the settings into the buffers provided, respective sizes in bytes as follows 64,32,32
// Returns -1 on failure (connection loss), otherwise returns 0
int drone3g_get_carrier_settings(char* apn, char* username, char* password);


// Sync's login information to drone
// Returns -1 on connection loss, otherwise returns 0
int drone3g_set_credentials(const char* username, const char* password, const char* dname);

// Sync's login information to drone  ---- USE WHEN DRONE3G IS ABOUT TO BE INSTALLED
// Returns -1 on connection loss, otherwise returns 0
int drone3g_set_credentials_pre_install(const char* username, const char* password, const char* dname);

#endif
