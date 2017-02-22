//
//  drone_com.c
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#include "drone_com.h"

#include <errno.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>

#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

drone3g_navdata_t navdata;
drone3g_gpsdata_t gpsdata;

int nav_lock_inited = 0;
pthread_mutex_t nav_lock;

int gps_lock_inited = 0;
pthread_mutex_t gps_lock;

int send_lock_inited = 0;
pthread_mutex_t send_lock;

pthread_t data_thread = 0;

struct sockaddr_in server_in;
struct sockaddr_in drone;
socklen_t socksize = sizeof(struct sockaddr_in);

int server_socket;
int drone_socket;
int video_socket;
int ffmpeg_socket = -1;

int goodbye;

void drone3g_close_sockets() {
    printf("[NOTICE] Closing connections...\n");
    
    pthread_cancel(data_thread);
    pthread_join(data_thread, NULL);
    
    goodbye = 1;
    
    close(drone_socket);
    close(server_socket);
    close(video_socket);
    close(ffmpeg_socket);
}

void drone3g_send_command(const char* command) {
    if(drone3g_got_connection != 1 || send_lock_inited != 1) {
        return;
    }
    
    size_t wrote = 0;
    size_t len = strlen(command);
    
    pthread_mutex_lock(&send_lock);
    
    while(wrote < len) {
        ssize_t actual = write(drone_socket, command+wrote, len-wrote);
        if(actual < 0) {
            pthread_mutex_unlock(&send_lock);
            
            fprintf(stderr, "[ERROR] Write drone socket failure! %s\n", strerror(errno));
            return;
        }
        
        wrote += (size_t)actual;
    }
    
    pthread_mutex_unlock(&send_lock);
}

drone3g_navdata_t drone3g_get_navdata() {
    if(nav_lock_inited == 0) {
        drone3g_navdata_t blank;
        bzero(&blank, sizeof(drone3g_navdata_t));
        return blank;
    }
    
    pthread_mutex_lock(&nav_lock);
    
    drone3g_navdata_t navdata_copy;
    memcpy(&navdata_copy, &navdata, sizeof(drone3g_navdata_t));
    
    pthread_mutex_unlock(&nav_lock);
    
    return navdata_copy;
}

drone3g_gpsdata_t drone3g_get_gpsdata() {
    if(gps_lock_inited == 0) {
        drone3g_gpsdata_t blank;
        bzero(&blank, sizeof(drone3g_gpsdata_t));
        return blank;
    }
    
    pthread_mutex_lock(&gps_lock);
    
    drone3g_gpsdata_t gpsdata_copy;
    memcpy(&gpsdata_copy, &gpsdata, sizeof(drone3g_gpsdata_t));
    
    pthread_mutex_unlock(&gps_lock);
    
    return gpsdata_copy;
}

void* drone3g_data_loop(void* arg) {
    // Setting up streaming to ffmpeg
    struct sockaddr_in ffmpeg_server;
    bzero(&ffmpeg_server, sizeof(ffmpeg_server));
    
    ffmpeg_server.sin_family = AF_INET;
    ffmpeg_server.sin_addr.s_addr = htonl(INADDR_ANY);
    ffmpeg_server.sin_port = htons(drone3g_ffmpeg_port);
    
    video_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(video_socket < 0) {
        printf("[FATAL ERROR] Could not create TCP socket for ffmpeg. Aborting.\n");
        exit(2);
    }
    
    int reuse = 1;
    if(setsockopt(video_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
        printf("[ERROR] Could not set SO_REUSEADDR for ffmpeg socket. %s\n", strerror(errno));
    }
    
    while(bind(video_socket, (struct sockaddr*)&ffmpeg_server, sizeof(struct sockaddr)) < 0) {
        printf("[ERROR] Could not bind TCP socket for ffmpeg. %s trying different port...\n", strerror(errno));
        
        drone3g_ffmpeg_port = 6400 + (arc4random() % 100);
        ffmpeg_server.sin_port = htons(drone3g_ffmpeg_port);
    }
    
    if(listen(video_socket, 1) < 0) {
        printf("[FATAL ERROR] Could not listen on ffmpeg port. Aborting\n");
        exit(2);
    }
    
    ffmpeg_socket = accept(video_socket, NULL, 0);
    if(ffmpeg_socket >= 0) {
        printf("[NOTICE] Internal TCP connection to ffmpeg etasblished!\n");
    } else {
        printf("[ERROR] Could not establish connection to ffmpeg.\n");
    }
    
    pthread_mutex_init(&nav_lock, NULL);
    nav_lock_inited = 1;
    
    uint8_t recv_buffer[64000];
    uint8_t carry_buffer[64000];
    int remaining_vbytes = 0;
    int carry_bytes = 0;
    
    while(1) {
        ssize_t len = read(drone_socket, recv_buffer+carry_bytes, 64000-carry_bytes);
        if(len <= 0 && (errno == EWOULDBLOCK || errno == ECONNRESET || errno == EAGAIN || errno == ETIMEDOUT || errno == 0)) {
            printf("[WARNING] Connection to ARDrone appears to have been lost %s. Awaiting reconnection...\n", strerror(errno));
            errno = 0;
            
            drone3g_connection_lost_callback();
            
            drone3g_got_connection = 0;
            drone3g_listen_for_ardrone();
            
            continue;
        } else if(len < 0) {
            fprintf(stderr, "[ERROR] Read on ARDrone TCP socket failed! %s\n", strerror(errno));
            
            usleep(1000);
            continue;
        }
        
        memcpy(recv_buffer, carry_buffer, carry_bytes);
        len += carry_bytes;
        carry_bytes = 0;
        
        // Process expected remaining video data
        if(remaining_vbytes > 0) {
            int vlen = remaining_vbytes;
            
            if(remaining_vbytes > len) {
                vlen = (int)len;
            }
            
            // Write to socket for ffmpeg
            ssize_t wrote = 0;
            while(wrote < vlen) {
                ssize_t actual = write(ffmpeg_socket, recv_buffer+wrote, vlen-wrote);
                if(actual < 0) {
                    fprintf(stderr, "[ERROR] ffmpeg socket failure! %s\n", strerror(errno));
                    
                    if(errno == EPIPE) {
                        // Resetting connection corrects this problem
                        close(ffmpeg_socket);
                        drone3g_listen_for_ardrone();
                        ffmpeg_socket = accept(video_socket, NULL, 0);
                    }
                    
                    break;
                }
                
                wrote += actual;
            }
            
            remaining_vbytes -= vlen;
        }
        
        uint8_t* video_tag = memmem(recv_buffer, len, "VIDEO", 5);
        while(video_tag != NULL) {
            // Check to see make sure the 4 byte length isn't cutoff
            if(video_tag+9 <= recv_buffer + len) {
                int vlen;
                memcpy(&vlen, video_tag+5, 4);
                video_tag += 9;
                
                if(video_tag + vlen > recv_buffer + len) { // Split data
                    int tmplen = (int)( (recv_buffer + len) - video_tag );
                    
                    // Set remaining bytes
                    remaining_vbytes = vlen - tmplen;
                    vlen = tmplen;
                }
                
                // Write to socket for ffmpeg
                ssize_t wrote = 0;
                while(wrote < vlen) {
                    ssize_t actual = write(ffmpeg_socket, video_tag+wrote, vlen-wrote);
                    if(actual < 0) {
                        fprintf(stderr, "[ERROR] ffmpeg socket failure! %s\n", strerror(errno));
                        
                        if(errno == EPIPE) {
                            // Resetting connection corrects this problem
                            close(ffmpeg_socket);
                            drone3g_listen_for_ardrone();
                            ffmpeg_socket = accept(video_socket, NULL, 0);
                        }
                        
                        break;
                    }
                    
                    wrote += actual;
                }
                
                video_tag = memmem(video_tag+vlen, (recv_buffer + len) - (video_tag + vlen), "VIDEO", 5);
            } else {
                int tmplen = (int)( (recv_buffer + len) - video_tag );
                memcpy(carry_buffer, video_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
        
        uint8_t* nav_tag = memmem(recv_buffer, len, "NAVDATA", 7);
        while(nav_tag != NULL) {
            // See if data is split
            if(nav_tag+sizeof(drone3g_navdata_t)+7 <= recv_buffer + len) {
                drone3g_navdata_t navdata_tmp;
                memcpy(&navdata_tmp, nav_tag+7, sizeof(drone3g_navdata_t));
                
                nav_tag = memmem(nav_tag+sizeof(drone3g_navdata_t)+7, (recv_buffer + len) - (nav_tag+sizeof(drone3g_navdata_t)+7), "NAVDATA", 7);
                
                if(nav_tag == NULL) { // Only want latest navdata
                    pthread_mutex_lock(&nav_lock);
                    navdata = navdata_tmp;
                    pthread_mutex_unlock(&nav_lock);
                    
                    drone3g_navdata_callback(navdata);
                }
            } else {
                int tmplen = (int)( (recv_buffer + len) - nav_tag );
                memcpy(carry_buffer, nav_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
        
        uint8_t* gps_tag = memmem(recv_buffer, len, "GPSDATA", 7);
        while(gps_tag != NULL) {
            // See if data is split
            if(gps_tag+sizeof(drone3g_gpsdata_t)+7 <= recv_buffer + len) {
                drone3g_gpsdata_t gpsdata_tmp;
                memcpy(&gpsdata_tmp, gps_tag+7, sizeof(drone3g_gpsdata_t));
                
                gps_tag = memmem(gps_tag+sizeof(drone3g_gpsdata_t)+7, (recv_buffer + len) - (gps_tag+sizeof(drone3g_gpsdata_t)+7), "GPSDATA", 7);
                
                if(gps_tag == NULL) { // Get only latest gps data
                    pthread_mutex_lock(&gps_lock);
                    gpsdata = gpsdata_tmp;
                    
                    // For some reason with the current gps module I have (ublox VK16U6) the speed is half of what it actually is
                    gpsdata.ground_speed *= 2;
                    
                    pthread_mutex_unlock(&gps_lock);
                    
                    drone3g_gpsdata_callback(gpsdata);
                }
            } else {
                int tmplen = (int)( (recv_buffer + len) - gps_tag );
                memcpy(carry_buffer, gps_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
        
        uint8_t* date_tag = memmem(recv_buffer, len, "DATE", 4);
        while(date_tag != NULL) {
            // See if data is split
            if(date_tag+6 <= recv_buffer + len) {
                drone3g_got_date_callback(date_tag[4], date_tag[5]);
                date_tag = memmem(date_tag+6, (recv_buffer + len) - (date_tag+6), "DATE", 4);
            } else {
                int tmplen = (int)( (recv_buffer + len) - date_tag );
                memcpy(carry_buffer, date_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
    }
    
    return NULL;
}

void drone3g_listen_for_ardrone() {
    drone3g_got_connection = 0;
    
    close(drone_socket);
    
    while(1) {
        drone_socket = accept(server_socket, (struct sockaddr*)&drone, &socksize);
        if(drone_socket >= 0) {
            printf("[NOTICE] TCP connection to ARDrone etasblished IP address %s\n", inet_ntoa(drone.sin_addr));
            
            struct timeval timeout;
            timeout.tv_sec = 1;
            timeout.tv_usec = 0;
            
            // This allows detection of a lost connection very fast
            if(setsockopt(drone_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
                printf("[ERROR] Could not set timeout period for drone socket, Drone3g will require restarting to reinitate a dropped connection!\n");
                printf("[WARNING] Recommended restart of Drone3g.\n");
            }
            // This may not be helpful as I don't think I've ever had the controls lag but it may help
            int nagle = 1;
            if(setsockopt(drone_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int)) < 0) {
                printf("[ERROR] Could not disable nagle algorithm.\n");
            }
            
            drone3g_got_connection = 1;
            drone3g_connection_established_callback();
            
            // Start data thread
            if(data_thread == 0) {
                pthread_create(&data_thread, NULL, drone3g_data_loop, NULL);
            }
            
            return;
        }
        
        // Server socket was closed because we are exiting
        if(goodbye == 1) {
            pthread_exit(NULL);
        }
        
        fprintf(stderr, "[ERROR] Could not accept ARDrone connection. Trying again... (firewall?)\n");
    }
}

void drone3g_setup_server() {
    pthread_mutex_init(&send_lock, NULL);
    send_lock_inited = 1;
    
    pthread_mutex_init(&gps_lock, NULL);
    gps_lock_inited = 1;
    
    bzero(&server_in, sizeof(server_in));
    
    // Setting up server
    server_in.sin_family = AF_INET;
    server_in.sin_addr.s_addr = htonl(INADDR_ANY);
    server_in.sin_port = htons(6451);
    
    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(server_socket < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not create TCP socket for ARDrone. Aborting.\n");
        exit(2);
    }
    
    int reuse = 1;
    if(setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
        printf("[ERROR] Could not set socket option SO_REUSEADDR. %s\n", strerror(errno));
    }
    
    if(bind(server_socket, (struct sockaddr*)&server_in, sizeof(struct sockaddr)) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not bind TCP socket for ARDrone. %s.\n", strerror(errno));
    }
    
    if(listen(server_socket, 1) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not listen on TCP socket port 6451.\n");
    }
    
    goodbye = 0;
    drone3g_listen_for_ardrone();
}
