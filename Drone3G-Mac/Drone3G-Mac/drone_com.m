//
//  drone_com.c
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "AppDelegate.h"

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
#include <arpa/inet.h>

AppDelegate* appDelegate;

drone3g_navdata_t navdata;

int nav_lock_inited = 0;
pthread_mutex_t nav_lock;

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

void drone3g_send_command(char* command) {
    if(drone3g_got_connection != 1 || send_lock_inited != 1) {
        return;
    }
    
    size_t wrote = 0;
    size_t len = strlen(command);
    
    pthread_mutex_lock(&send_lock);
    
    while(wrote < len) {
        ssize_t actual = write(drone_socket, command+wrote, len-wrote);
        if(actual < 0) {
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

void* drone3g_data_loop(void* arg) {
    // Setting up streaming to ffmpeg
    struct sockaddr_in ffmpeg_server;
    bzero(&ffmpeg_server, sizeof(ffmpeg_server));
    
    ffmpeg_server.sin_family = AF_INET;
    ffmpeg_server.sin_addr.s_addr = htonl(INADDR_ANY);
    ffmpeg_server.sin_port = htons(drone3g_ffmpeg_port);
    
    video_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(video_socket < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not create TCP socket for ffmpeg. Aborting.\n");
        exit(2);
    }
    
    if(bind(video_socket, (struct sockaddr*)&ffmpeg_server, sizeof(struct sockaddr)) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not bind TCP socket for ffmpeg. %s Aborting.\n", strerror(errno));
        exit(2);
    }
    
    if(listen(video_socket, 1) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not listen on TCP socket port 2014. Aborting.\n");
        exit(2);
    }
    
    ffmpeg_socket = accept(video_socket, NULL, 0);
    if(ffmpeg_socket >= 0) {
        printf("[NOTICE] Internal TCP connection to ffmpeg etasblished!\n");
    } else {
        fprintf(stderr, "[ERROR] Could not establish connection to ffmpeg.\n");
    }
    
    uint8_t drone_buffer[64000];
    uint8_t split_buffer[1024];
    int left_over_bytes = 0;
    
    pthread_mutex_init(&nav_lock, NULL);
    nav_lock_inited = 1;

    while(1) {
        // Handle left over split data
        if(left_over_bytes > 0) {
            memcpy(drone_buffer, split_buffer, left_over_bytes);
        }
        
        // Read data from drone
        ssize_t len = read(drone_socket, drone_buffer+left_over_bytes, 64000-left_over_bytes);
        
        len += left_over_bytes;
        left_over_bytes = 0;
        
        if(len <= 0 && (errno == EWOULDBLOCK || errno == ECONNRESET || errno == ETIMEDOUT || errno == 0)) {
            printf("[WARNING] Connection to ARDrone appears to have been lost. Awaiting reconnection...\n");
            errno = 0;
            
            [appDelegate performSelectorOnMainThread:@selector(showConnectionLabel) withObject:nil waitUntilDone:NO];
            
            drone3g_got_connection = 0;
            drone3g_connect_ardrone();
            
            continue;
        } else if(len < 0) {
            fprintf(stderr, "[ERROR] Read on ARDrone TCP socket failed! %s\n", strerror(errno));
            
            usleep(1000);
            continue;
        }
        
        // Handle split navtag
        char* tag = "NAVDATA";
        for(int i=0;i<6;i++) {
            if(memmem(drone_buffer+len-i-1, i+1, tag, i+1) != NULL) {
                memcpy(split_buffer, drone_buffer+len-i-1, i+1);
                left_over_bytes = i+1;
                len -= i+1;
                
                break;
            }
        }
        
        // Check to see if stream contains navdata and grab latest navdata
        uint8_t* navtag = memmem(drone_buffer, len, "NAVDATA", 7);
        int navtags[1000];
        int index = 0;
        
        while(navtag != NULL) {
            navtags[index++] = (int)(navtag-drone_buffer);
            
            navtag += sizeof(drone3g_navdata_t)+7;
            navtag = memmem(navtag, drone_buffer+len - navtag, "NAVDATA", 7);
        }
        
    process_navdata:
        if(index > 0) {
            index--;
            
            // Handle split data
            if(len - navtags[index] < sizeof(drone3g_navdata_t)+7) {
                memcpy(split_buffer, drone_buffer + navtags[index], len - navtags[index]);
                
                left_over_bytes = (int)len - navtags[index];
                len = navtags[index];
                index--;
                
                if(index < 0) {
                    goto process_navdata;
                }
            }
            
            pthread_mutex_lock(&nav_lock);
            memcpy(&navdata, drone_buffer+navtags[index]+7, sizeof(drone3g_navdata_t));
            pthread_mutex_unlock(&nav_lock);
            
            drone3g_navdata_callback(navdata);
            
            // Clean navdata from stream
            int offset = navtags[0];
            for(int i=0;i<index;i++) {
                int end = navtags[i]+sizeof(drone3g_navdata_t)+7;
                int block_size = navtags[i+1]-end;
                
                memmove(drone_buffer + offset, drone_buffer + end, block_size);
                
                offset += block_size;
            }
            
            int end = navtags[index]+sizeof(drone3g_navdata_t)+7;
            memmove(drone_buffer + navtags[index], drone_buffer + end, len-end);
            
            len -= (sizeof(drone3g_navdata_t)+7) * (index+1);
        }
        
        // Write to pipe for ffmpeg
        ssize_t wrote = 0;
        while(wrote < len) {
            ssize_t actual = write(ffmpeg_socket, drone_buffer+wrote, len-wrote);
            if(actual < 0) {
                fprintf(stderr, "[ERROR] Pipe failure! %s\n", strerror(errno));
                continue;
            }
            
            wrote += actual;
        }
    }
    
    return NULL;
}

void drone3g_connect_ardrone() {
    drone3g_got_connection = 0;
    
    //close(drone_socket); // If the server thinks there is a disconnect first, it can make the ARDrone think the socket is closed see
                           // drone3g source for explanation as to why this is bad
    
    while(1) {
        drone_socket = accept(server_socket, (struct sockaddr*)&drone, &socksize);
        if(drone_socket >= 0) {
            printf("[NOTICE] TCP connection to ARDrone etasblished IP address %s\n", inet_ntoa(drone.sin_addr));
            
            struct timeval timeout;
            timeout.tv_sec = 5;
            timeout.tv_usec = 0;
            
            // This allows detection of a lost connection very fast
            if(setsockopt(drone_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
                fprintf(stderr, "[ERROR] Could not set timeout period for drone socket, Drone3g will require restarting to reinitate a dropped connection!\n");
                fprintf(stderr, "[WARNING] Recommended restart of Drone3g.\n");
            }
            
            drone3g_got_connection = 1;
            [appDelegate performSelectorOnMainThread:@selector(hideConnectionLabel) withObject:nil waitUntilDone:NO];
            
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

void drone3g_setup_ardrone() {
    appDelegate = (AppDelegate*)[[NSApplication sharedApplication] delegate];
    
    pthread_mutex_init(&send_lock, NULL);
    send_lock_inited = 1;
    
    bzero(&server_in, sizeof(server_in));
    
    // Setting up server
    server_in.sin_family = AF_INET;
    server_in.sin_addr.s_addr = htonl(INADDR_ANY);
    server_in.sin_port = htons(2013);
    
    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(server_socket < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not create TCP socket for ARDrone. Aborting.\n");
        exit(2);
    }
    
    if(bind(server_socket, (struct sockaddr*)&server_in, sizeof(struct sockaddr)) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not bind TCP socket for ARDrone. %s Aborting.\n", strerror(errno));
        exit(2);
    }
    
    if(listen(server_socket, 1) < 0) {
        fprintf(stderr, "[FATAL ERROR] Could not listen on TCP socket port 2013. Aborting.\n");
        exit(2);
    }
    
    goodbye = 0;
    drone3g_connect_ardrone();
}
