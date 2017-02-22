//
//  drone_com.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#ifndef Drone3G_Mac_drone_com_h
#define Drone3G_Mac_drone_com_h

#include <stdint.h>

// GPS fix status constants
enum {
    DRONE3G_GPS_FIX_STATUS_NO_GPS = -1,
    DRONE3G_GPS_FIX_STATUS_NO_LOCK,
    DRONE3G_GPS_FIX_STATUS_LOCKED,
    DRONE3G_GPS_FIX_STATUS_DIFFGPS
};

// Navdata ctrl_state constants
enum {
    DRONE3G_STATE_EMERGENCY = 0,
    DRONE3G_STATE_FLYING = 196608,
    DRONE3G_STATE_LANDED = 131072,
    DRONE3G_STATE_TAKEOFF = 458752,
    DRONE3G_STATE_BAT_2_LOW_2_FLY = 589824
};

// GPS data structure
typedef struct {
    double latitude; /*!< Latitude in degrees, North is +*/
    double longitude; /*!< Longtiude in degrees, East is +*/
    
    float altitude_msl; /*!< Meters above mean sea level*/
    
    float ground_speed; /*!< True ground speed in km/h*/
    
    char fix_status; /*!< Status of GPS reciever constants in enum*/
}drone3g_gpsdata_t;

typedef struct {
    uint32_t ardrone_state; /*!<Bit mask indicating ARDrone state*/
    uint32_t ctrl_state; /*!<Numeric value indicating ARDrone state*/
    uint8_t battery_percentage /*!<Battery percentage as a number from 0-100*/;
    
    int32_t altitude; /*!<Altitude of the drone in centimeters*/
    uint8_t signal_strength; /*!<Number from 0-131 indicating signal quality with 131 as best*/
    
    uint64_t total_recv_bytes; /*!<Total number of bytes sent from the drone*/
    uint64_t total_sent_bytes; /*!<Total number of bytes recieved from the drone*/
    
    uint16_t time_flying; /*!<Total number of seconds since last takeoff*/
    
    float theta; /*!< Drone pitch angle in millidegrees*/
    float phi; /*!< Drone roll angle in millidegrees*/
    float psi; /*!< Magnometer reading from drone, north is 0˚, range is -180-180*/
    
    float vx; /*!< Estimated forward velocity of drone in mm/s*/
    float vy; /*!< Estimated lateral velocity of drone in mm/s*/
    float vz; /*!< Not used, always set to 0.000000 by Parrot*/
}drone3g_navdata_t;

void(*drone3g_got_date_callback)(int,int);
void(*drone3g_navdata_callback)(drone3g_navdata_t); // Gets called when navdata struct was recevied
void(*drone3g_gpsdata_callback)(drone3g_gpsdata_t); // Gets called when gps data struct was recevied
void(*drone3g_connection_lost_callback)(void); // Gets called when connection is lost
void(*drone3g_connection_established_callback)(void); // Gets called when a connection is established

drone3g_navdata_t drone3g_get_navdata(); // THREAD SAFE
drone3g_gpsdata_t drone3g_get_gpsdata(); // THREAD SAFE

int drone3g_got_connection;
int drone3g_ffmpeg_port;

void drone3g_setup_server();
void drone3g_listen_for_ardrone();

void drone3g_send_command(const char* command); // THREAD SAFE
void* drone3g_data_loop(void* arg);

void drone3g_close_sockets();

#endif
