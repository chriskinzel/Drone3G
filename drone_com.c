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
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <poll.h>
#include <fcntl.h>
#include <syslog.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netinet/ip.h>
#include <arpa/inet.h>

#include <CommonCrypto/CommonHMAC.h>

#define DNS_SERVER_IP "96.51.168.137"
#define DNS_SERVER_PORT 6449

#define VERSION_STRING "Drone3G OS X V1.0"

// TODO: This is way too messy, needs to be put in seperate files and more organized

int got_connection = 0;
int ffmpeg_port = 9600;

drone3g_proxy_mode proxy_mode = DRONE3G_PROXY_MODE_NONE;

drone3g_navdata_t navdata;
drone3g_gpsdata_t gpsdata;

int nav_lock_inited = 0;
pthread_mutex_t nav_lock;

int gps_lock_inited = 0;
pthread_mutex_t gps_lock;

int send_lock_inited = 0;
pthread_mutex_t send_lock;

pthread_t data_thread = 0;
pthread_t proxy_thread;
int proxy_thread_running = 0;

struct sockaddr_in telnet;
int telnet_client_socket = -1;
int telnet_server_socket = -1;
int telnet_connection_state = 0;

struct sockaddr_in drone;
socklen_t socksize = sizeof(struct sockaddr_in);

in_addr_t proxy_ip;

int controller_socket = -1;
int server_socket = -1;
int drone_socket = -1;
int video_socket = -1;
int ffmpeg_socket = -1;
int dns_socket = -1;

int sockets_closing;

int last_send_err = 0;

struct timeval last_connect_time;

void drone3g_listen_for_ardrone(int dns_post);

#pragma mark Disconnecting
#pragma mark -

void drone3g_close_sockets() {
    syslog(LOG_NOTICE, "Closing connections...\n");
    
    got_connection = 0;
    sockets_closing = 1;
    
    close(drone_socket);
    close(dns_socket);
    close(server_socket);
    close(controller_socket);
    close(video_socket);
    close(ffmpeg_socket);
    close(telnet_client_socket);
    close(telnet_server_socket);
}

void drone3g_disconnect() {
    if(drone_socket != -1) {
        close(drone_socket);
        drone_socket = -1;
    }
    if(dns_socket != -1) {
        close(dns_socket);
        dns_socket = -1;
    }
    if(controller_socket != -1) {
        close(controller_socket);
        controller_socket = -1;
    }
}

#pragma mark -
#pragma mark Getters and Setters
#pragma mark -

int drone3g_got_connection() {
    return got_connection;
}

void drone3g_set_ffmpeg_port(int port_num) {
    ffmpeg_port = port_num;
}

int drone3g_get_ffmpeg_port() {
    return ffmpeg_port;
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

void drone3g_set_proxy_mode(drone3g_proxy_mode mode) {
    proxy_mode = mode;
}

#pragma mark -
#pragma mark Custom Mutex Lock Function
#pragma mark -

// Implementation of pthread_mutex_timedlock for systems that don't have it
int drone3g_mutex_timedlock(pthread_mutex_t *mutex, struct timespec *timeout) {
    struct timeval timenow;
    int retcode;
    
    while ((retcode = pthread_mutex_trylock (mutex)) == EBUSY) {
        gettimeofday (&timenow, NULL);
        
        if (timenow.tv_sec >= timeout->tv_sec && (timenow.tv_usec * 1000) >= timeout->tv_nsec) {
            return ETIMEDOUT;
        }
        
        usleep(100);
    }
    
    return retcode;
}

#pragma mark -
#pragma mark Telnet Proxy
#pragma mark -

// Drone3G supports remote telnet via 3G into the ARDrone this function proxies the connection, to connect simply telnet via localhost port 6452
// e.g. "telnet 127.0.0.1 6452"
static void telnet_loop() {
    while(1) {
        // Application is closing
        if(sockets_closing == 1) {
            pthread_exit(NULL);
        }
        
        telnet_client_socket = accept(telnet_server_socket, (struct sockaddr*)&telnet, &socksize);
        if(telnet_client_socket >= 0) {
            int nodelay = 1;
            setsockopt(telnet_client_socket, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(int));
            
            syslog(LOG_NOTICE, "Telnet connection etasblished to client.\n");
            
            telnet_connection_state = 1;
            drone3g_send_command("AT*TELCON\r");
            
            uint8_t recv_buffer[1023-13];
            while(1) {
                ssize_t len = read(telnet_client_socket, recv_buffer, 1023-13);
                if(len <= 0) {
                    if(len == 0) {
                        syslog(LOG_NOTICE, "Telnet connection closed by client.\n");
                    } else {
                        if(errno == EBADF) {
                            syslog(LOG_NOTICE, "Telnet connection closed by foreign host.\n");
                        } else {
                            syslog(LOG_ERR, "Read on telnet socket failed! %s\n", strerror(errno));
                        }
                    }
                    
                    if(telnet_connection_state == 1) {
                        telnet_connection_state = 0;
                        drone3g_send_command("AT*TELCLOSE\r");
                        
                        close(telnet_client_socket);
                    }
                    
                    break;
                }
                
                if(send_lock_inited == 1 && got_connection == 1) {
                    size_t wrote = 0;
                    
                    struct timeval current_time;
                    gettimeofday(&current_time, NULL);
                    
                    struct timespec timeout;
                    timeout.tv_sec = current_time.tv_sec+1;
                    timeout.tv_nsec = 0;
                    
                    int retcode = drone3g_mutex_timedlock(&send_lock, &timeout);
                    if(retcode == ETIMEDOUT) {
                        printf("\n\n[ATTENTION] SEND LOCK ACQUISTION TIMED OUT! REINITIALIZING MUTEX LOCK.\n\n");
                        
                        pthread_mutex_destroy(&send_lock);
                        pthread_mutex_init(&send_lock, NULL);
                        
                        return;
                    }
                    
                    int32_t size = (int32_t)len;
                    send(drone_socket, "[TELNET]", 8, MSG_HAVEMORE);
                    send(drone_socket, &size, 4, MSG_HAVEMORE);
                    
                    while(wrote < len && got_connection == 1) {
                        ssize_t actual = write(drone_socket, recv_buffer+wrote, len-wrote);
                        if(actual <= 0) {
                            syslog(LOG_CRIT, "Write drone socket failure! %s\n", strerror(errno));
                            break;
                        }
                        
                        wrote += (size_t)actual;
                    }
                    
                    pthread_mutex_unlock(&send_lock);
                }
            }
            
            continue;
        }
        
        if(sockets_closing != 1) {
            syslog(LOG_ERR, "Could not accept telnet connection. %s Trying again...\n", strerror(errno));
        }
    }
}

static void* start_telnet_proxy(void* arg) {
    struct sockaddr_in server_in;
    bzero(&server_in, sizeof(server_in));
    
    // Setting up server
    server_in.sin_family = AF_INET;
    server_in.sin_addr.s_addr = htonl(INADDR_ANY);
    server_in.sin_port = htons(6452);
    
    telnet_server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(telnet_server_socket < 0) {
        syslog(LOG_ERR, "Could not create TCP socket for telnet. Aborting.\n");
    }
    
    int reuse = 1;
    if(setsockopt(telnet_server_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
        syslog(LOG_ERR, "Could not set socket option SO_REUSEADDR for telnet. %s\n", strerror(errno));
    }
    
    if(bind(telnet_server_socket, (struct sockaddr*)&server_in, sizeof(struct sockaddr)) < 0) {
        syslog(LOG_ERR, "Could not bind TCP socket for telnet. %s.\n", strerror(errno));
    }
    
    if(listen(telnet_server_socket, 1) < 0) {
        syslog(LOG_ERR, "Could not listen on TCP socket port 6452.\n");
    }
    
    telnet_loop();
    
    return NULL;
}

#pragma mark -
#pragma mark Sending commands
#pragma mark -

void drone3g_send_command(const char* command) {
    if(send_lock_inited != 1 || got_connection != 1) {
        return;
    }
    
    size_t wrote = 0;
    size_t len = strlen(command);
    
    struct timeval current_time;
    gettimeofday(&current_time, NULL);
    
    struct timespec timeout;
    timeout.tv_sec = current_time.tv_sec+1;
    timeout.tv_nsec = 0;
    
    int retcode = drone3g_mutex_timedlock(&send_lock, &timeout);
    if(retcode == ETIMEDOUT) {
        printf("\n\n[ATTENTION] SEND LOCK ACQUISTION TIMED OUT! REINITIALIZING MUTEX LOCK.\n\n");
        
        pthread_mutex_destroy(&send_lock);
        pthread_mutex_init(&send_lock, NULL);
        
        return;
    }
    
    while(wrote < len && got_connection == 1) {
        ssize_t actual = write(drone_socket, command+wrote, len-wrote);
        if(actual <= 0) {
            if(last_send_err != errno) {
                last_send_err = errno;
                syslog(LOG_WARNING, "Write drone socket failure! %s\n", strerror(errno));
            }
            
            break;
        }
        
        wrote += (size_t)actual;
    }
    
    pthread_mutex_unlock(&send_lock);
}

#pragma mark -
#pragma mark Read loop
#pragma mark -

// Does everything except for navdata but is capable of handling navdata
static void* data_loop(void* arg) {
    // Setting up streaming to ffmpeg
    struct sockaddr_in ffmpeg_server;
    bzero(&ffmpeg_server, sizeof(ffmpeg_server));
    
    ffmpeg_server.sin_family = AF_INET;
    ffmpeg_server.sin_addr.s_addr = htonl(INADDR_ANY);
    ffmpeg_server.sin_port = htons(ffmpeg_port);
    
    video_socket = socket(AF_INET, SOCK_STREAM, 0);
    if(video_socket < 0) {
        syslog(LOG_CRIT, "Could not create TCP socket for ffmpeg. Aborting.\n");
        exit(2);
    }
    
    int reuse = 1;
    if(setsockopt(video_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
        syslog(LOG_CRIT, "Could not set SO_REUSEADDR for ffmpeg socket. %s\n", strerror(errno));
    }
    
    while(bind(video_socket, (struct sockaddr*)&ffmpeg_server, sizeof(struct sockaddr)) < 0) {
        syslog(LOG_CRIT, "Could not bind TCP socket for ffmpeg. %s trying different port...\n", strerror(errno));
        
        ffmpeg_port = 9600 + arc4random_uniform(100);
        ffmpeg_server.sin_port = htons(ffmpeg_port);
    }
    
    if(listen(video_socket, 1) < 0) {
        syslog(LOG_CRIT, "Could not listen on ffmpeg port. Aborting\n");
        exit(2);
    }
    
    ffmpeg_socket = accept(video_socket, NULL, 0);
    if(ffmpeg_socket >= 0) {
        syslog(LOG_NOTICE, "Internal TCP connection to ffmpeg etasblished!\n");
    } else {
        syslog(LOG_CRIT, "Could not establish connection to ffmpeg.\n");
    }
    
    pthread_mutex_init(&nav_lock, NULL);
    nav_lock_inited = 1;
    
    int last_error = 0;
    
    uint8_t recv_buffer[64000];
    uint8_t carry_buffer[64000];
    int carry_bytes = 0;
    
    int remaining_vbytes = 0;
    int remaining_tbytes = 0;
    int remaining_pbytes = 0;
    
    while(1) {
        struct timeval current_time;
        gettimeofday(&current_time, NULL);
        
        struct pollfd pfd;
        bzero(&pfd, sizeof(pfd));
        
        pfd.fd = drone_socket;
        pfd.events = POLL_IN;
        
        int timedout = poll(&pfd, 1, 1500);
        if(timedout < 0) {
            syslog(LOG_ERR, "Polling error: %s.\n", strerror(errno));
            continue;
        }
        
        errno = 0;
        ssize_t len = recv(drone_socket, recv_buffer+carry_bytes, 64000-carry_bytes, MSG_DONTWAIT);
        
        if(timedout == 0 || len == 0 || (len < 0 && (errno == EWOULDBLOCK || errno == ECONNRESET || errno == EAGAIN || errno == ETIMEDOUT || errno == EPIPE || errno == EBADF || errno == 0)) ) {
            syslog(LOG_WARNING, "Connection to ARDrone appears to have been lost: %s. Awaiting reconnection...\n", (errno == 0) ? "Drone closed connnection" : strerror(errno));
            
            remaining_pbytes = 0; // Picture transfers that were interrupted by connection loss are re-sent
            
            if(proxy_mode == DRONE3G_PROXY_MODE_CLIENT) {
                close(drone_socket);
                drone_socket = -1;
            }
            
            drone3g_connection_lost_callback();
            
            got_connection = 0;
            drone3g_listen_for_ardrone(errno != ECONNRESET);

            continue;
        } else if(len < 0) {
            if(sockets_closing == 1) {
                return NULL;
            }
            
            syslog(LOG_ERR, "Read on ARDrone TCP socket failed! %s\n", strerror(errno));
            
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
                    syslog(LOG_ERR, "ffmpeg socket failure! %s\n", strerror(errno));
                    
                    if(errno == EPIPE) {
                        // Reconnect ffmpeg
                        close(ffmpeg_socket);
                        ffmpeg_socket = accept(video_socket, NULL, 0);
                    }
                    
                    break;
                }
                
                wrote += actual;
            }
            
            remaining_vbytes -= vlen;
        }
        
        // Process expected remaining telnet data
        if(remaining_tbytes > 0) {
            int tlen = remaining_tbytes;
            
            if(remaining_tbytes > len) {
                tlen = (int)len;
            }
            
            // Proxy telnet data
            ssize_t wrote = 0;
            while(wrote < tlen) {
                ssize_t actual = write(telnet_client_socket, recv_buffer+wrote, tlen-wrote);
                if(actual < 0) {
                    if(last_error != errno && telnet_connection_state == 1) {
                        last_error = errno;
                        syslog(LOG_ERR, "Telnet socket write failure! %s\n", strerror(errno));
                    }
                    
                    break;
                }
                
                wrote += actual;
            }
            
            remaining_tbytes -= tlen;
        }
        
        // Process expected remaining photo data
        if(remaining_pbytes > 0) {
            int plen = remaining_pbytes;
            
            if(remaining_pbytes > len) {
                plen = (int)len;
            }
            
            drone3g_transfer_image_data_callback(recv_buffer, plen);
            
            remaining_pbytes -= plen;
        }
        
        uint8_t* video_tag = memmem(recv_buffer, len, "VIDEO", 5);
        while(video_tag != NULL) {
            // Check to see make sure the 4 byte length isn't cutoff
            if(video_tag+9 <= recv_buffer + len) {
                int32_t vlen;
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
                        syslog(LOG_ERR, "ffmpeg socket failure! %s\n", strerror(errno));
                        
                        if(errno == EPIPE) {
                            // Reconnect ffmpeg
                            close(ffmpeg_socket);
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
        
        uint8_t* picture_tag = memmem(recv_buffer, len, "PICTURE", 7);
        while(picture_tag != NULL) {
            // Check to see make sure the 4 byte length isn't cutoff
            if(picture_tag+11 <= recv_buffer + len) {
                int32_t plen, _plen;
                memcpy(&plen, picture_tag+7, 4);
                picture_tag += 11;
                
                _plen = plen;
                
                if(picture_tag + plen > recv_buffer + len) { // Split data
                    int tmplen = (int)( (recv_buffer + len) - picture_tag );
                    
                    // Set remaining bytes
                    remaining_pbytes = plen - tmplen;
                    plen = tmplen;
                }
                
                drone3g_start_image_transfer_callback(picture_tag, plen, _plen);
                
                picture_tag = memmem(picture_tag+plen, (recv_buffer + len) - (picture_tag + plen), "PICTURE", 7);
            } else {
                int tmplen = (int)( (recv_buffer + len) - picture_tag );
                memcpy(carry_buffer, picture_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
        
        uint8_t* telnet_tag = memmem(recv_buffer, len, "TELNET", 6);
        while(telnet_tag != NULL) {
            // Check to see make sure the 4 byte length isn't cutoff
            if(telnet_tag+10 <= recv_buffer + len) {
                int32_t tlen;
                memcpy(&tlen, telnet_tag+6, 4);
                telnet_tag += 10;
                
                if(telnet_tag + tlen > recv_buffer + len) { // Split data
                    int tmplen = (int)( (recv_buffer + len) - telnet_tag );
                    
                    // Set remaining bytes
                    remaining_tbytes = tlen - tmplen;
                    tlen = tmplen;
                }
                                
                // Proxy data to telnet socket
                ssize_t wrote = 0;
                while(wrote < tlen) {
                    ssize_t actual = send(telnet_client_socket, telnet_tag+wrote, tlen-wrote, MSG_DONTWAIT);
                    if(actual < 0) {
                        if(errno == EWOULDBLOCK || errno == EAGAIN) {
                            usleep(50);
                            continue;
                        }
                        
                        if(last_error != errno && telnet_connection_state == 1) {
                            last_error = errno;
                            syslog(LOG_ERR, "Telnet socket write failure! %s\n", strerror(errno));
                        }
                        
                        break;
                    }
                    
                    wrote += actual;
                }
                
                telnet_tag = memmem(telnet_tag+tlen, (recv_buffer + len) - (telnet_tag + tlen), "TELNET", 6);
            } else {
                int tmplen = (int)( (recv_buffer + len) - telnet_tag );
                memcpy(carry_buffer, telnet_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
        
        uint8_t* close_tag = memmem(recv_buffer, len, "TELCLOSE", 8);
        while(close_tag != NULL) {
            if(telnet_connection_state == 1) {
                telnet_connection_state = 0;
                close(telnet_client_socket);
            }
            
            close_tag = memmem(close_tag+8, (recv_buffer + len) - (close_tag+8), "TELCLOSE", 8);
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
                    
                    // FIXME: For some reason with the current gps module I have (ublox VK16U6) the speed is half of what it actually is
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
        
        uint8_t* pong_tag = memmem(recv_buffer, len, "PONG", 4);
        while(pong_tag != NULL) {
            // See if data is split
            if(pong_tag+8 <= recv_buffer + len) {
                struct timeval current_timestamp;
                gettimeofday(&current_timestamp, NULL);
                
                int32_t residual_ms;
                memcpy(&residual_ms, pong_tag+4, 4);
                
                drone3g_pong_callback(current_timestamp, (int)residual_ms);
                
                pong_tag = memmem(pong_tag+8, (recv_buffer + len) - (pong_tag+8), "PONG", 4);
            } else {
                int tmplen = (int)( (recv_buffer + len) - pong_tag );
                memcpy(carry_buffer, pong_tag, tmplen);
                carry_bytes += tmplen;
                
                break;
            }
        }
    }
    
    return NULL;
}

#pragma mark -
#pragma mark DNS Functions
#pragma mark -

static int dns_send_data(int sock, const void* data, size_t data_len, int timeout, int flags) {
    size_t sent_bytes = 0;
    while(sent_bytes < data_len) {
        ssize_t actual = send(sock, data, data_len, flags);
        if(actual <= 0) {
            syslog(LOG_ERR, "DNS ERROR: Sending error. %s.\n", (actual == 0) ? "Connection closed" : strerror(errno));
            return -2;
        }
        
        sent_bytes += (size_t)actual;
    }
    
    return 1;
}

static ssize_t dns_recv_data(int sock, void* buffer, ssize_t read_len, int timeout, int flags) {
    struct pollfd fds;
    bzero(&fds, sizeof(fds));
    fds.events = POLL_IN;
    fds.fd = sock;
    
    ssize_t recv_bytes = 0;
    while(recv_bytes < read_len) {
        int ret = poll(&fds, 1, timeout);
        if(ret == 0) {
            syslog(LOG_ERR, "DNS ERROR: Read timeout.\n");
            return 0;
        } else if(ret < 0) {
            syslog(LOG_ERR, "DNS ERROR: Polling error. %s.\n", strerror(errno));
            return -1;
        }
        
        ssize_t actual = recv(sock, buffer+recv_bytes, read_len-recv_bytes, flags | MSG_DONTWAIT);
        if(actual <= 0) {
            syslog(LOG_ERR, "DNS ERROR: Read error. %s.\n", (actual == 0) ? "Connection closed" : strerror(errno));
            return -2;
        }
        
        recv_bytes += actual;
    }
    
    if(read_len < 0) { // If read_len is < 0 then that magnitude of that value is the max length of the buffer
        size_t buffer_len = -read_len;
        
        int ret = poll(&fds, 1, timeout);
        if(ret == 0) {
            syslog(LOG_ERR, "DNS ERROR: Read timeout.\n");
            return 0;
        } else if(ret < 0) {
            syslog(LOG_ERR, "DNS ERROR: Polling error. %s.\n", strerror(errno));
            return -1;
        }
        
        recv_bytes = recv(sock, buffer, buffer_len, flags | MSG_DONTWAIT);
        if(recv_bytes <= 0) {
            syslog(LOG_ERR, "DNS ERROR: Read error. %s.\n", (recv_bytes == 0) ? "Connection closed" : strerror(errno));
            return -2;
        }
        
        return recv_bytes;
    }
    
    return 1;
}

void drone3g_dns_post() {
    while(1) {
        struct sockaddr_in dns_addr;
        bzero(&dns_addr, sizeof(dns_addr));
        
        dns_addr.sin_family = AF_INET;
        dns_addr.sin_port = htons(DNS_SERVER_PORT);
        dns_addr.sin_addr.s_addr = inet_addr(DNS_SERVER_IP);
        
        int last_error = 0;
        
        while(1) {
            if(drone3g_can_accept_callback() != 1) {
                return;
            }
            
            dns_socket = socket(AF_INET, SOCK_STREAM, 0);
            if(dns_socket < 0) {
                syslog(LOG_CRIT, "Could not create TCP socket for DNS server post! %s.\n", strerror(errno));
                return;
            }
            
            int nagle = 1;
            setsockopt(dns_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int));
            
            errno = 0;
            if(connect(dns_socket, (struct sockaddr*)&dns_addr, sizeof(dns_addr)) >= 0) {
                syslog(LOG_NOTICE, "Connection to DNS server established.");
                break;
            }
            
            if(last_error != errno) {
                last_error = errno;
                syslog(LOG_NOTICE, "Connection attempt to DNS server failed. %s. Retrying...\n", strerror(errno));
            }
            
            close(dns_socket);
            dns_socket = -1;
        }
        
        // CONNECTED TO DNS SERVER
        
        if(dns_send_data(dns_socket, "DRONE3G", 7, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        char drone3g_tag[7];
        if(dns_recv_data(dns_socket, drone3g_tag, 7, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        if(strncmp(drone3g_tag, "DRONE3G", 7) != 0) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        // HMAC Authentication
        uint16_t message_len = arc4random_uniform(65)+64;
        unsigned char* message = alloca(message_len);
        
        for(int i=0;i<message_len;i+=4) {
            uint32_t rand_quad = arc4random();
            memcpy(message+i, &rand_quad, (message_len-i > 4) ? 4 : message_len-i );
        }
        
        if(dns_send_data(dns_socket, &message_len, 2, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, message, message_len, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        char fake_key[] = "1H!<12E/GeDsD]+tD$xf5CR_cSvsW2'e+xM>oD4jVQU1p'NM9}y,0pJ@#ZxdKbS'7LnCR@Mdt6dft|QEwtYZbr(GqCVcL1uiZ[E(WBAyW]v;Al2jplb>QuKtR.f(Y3BQ7Q";
        char key[65];
        for(int i=0;i<64;i++) {
            key[i] = fake_key[i*2];
        }
        key[64] = '?';
        
        unsigned char mac[16];
        CCHmac(kCCHmacAlgMD5, key, 64, message, message_len, mac);
        
        unsigned char check_mac[16];
        if(dns_recv_data(dns_socket, check_mac, 16, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        if(memcmp(mac, check_mac, 16) != 0) { // Server was not authentic
            syslog(LOG_WARNING, "DNS ERROR: DNS Server authentication failed. Retrying...");
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        uint16_t smessage_len;
        if(dns_recv_data(dns_socket, &smessage_len, 2, 2000, 0) != 1 || smessage_len < 64 || smessage_len > 128) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        unsigned char* smessage = alloca(smessage_len);
        if(dns_recv_data(dns_socket, smessage, smessage_len, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        unsigned char smac[16];
        CCHmac(kCCHmacAlgMD5, key, 64, smessage, smessage_len, smac);
        
        if(dns_send_data(dns_socket, smac, 16, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        if(dns_recv_data(dns_socket, smac /* dummy buffer in this case */, 2, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        // CONTROLLER SPECIFIC DNS FEATURES
        
        uint8_t type = (proxy_mode == DRONE3G_PROXY_MODE_CLIENT) ? 2 : ( (proxy_mode == DRONE3G_PROXY_MODE_SERVER) ? 3 : 1);
        if(dns_send_data(dns_socket, &type, 1, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        uint8_t ver_len = sizeof(VERSION_STRING)-1;
        if(dns_send_data(dns_socket, &ver_len, 1, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, VERSION_STRING, ver_len, 2000, 0) != 1) {
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        unsigned char h_username[32], h_password[32], h_name[32];
        const char** login_info = drone3g_get_login_info();
        
        // Hash login credentials
        CC_SHA256(login_info[0], (CC_LONG)strlen(login_info[0])+1, h_username);
        CC_SHA256(login_info[1], (CC_LONG)strlen(login_info[1])+1, h_password);
        CC_SHA256(login_info[2], (CC_LONG)strlen(login_info[2])+1, h_name);
        
        uint16_t user_len = 32;
        uint16_t pass_len = 32;
        uint16_t name_len = 32;
        
        if(dns_send_data(dns_socket, &user_len, 2, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, &pass_len, 2, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, &name_len, 2, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        if(dns_send_data(dns_socket, h_username, user_len, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, h_password, pass_len, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        if(dns_send_data(dns_socket, h_name, name_len, 2000, 0) != 1) {
            free(login_info);
            
            close(dns_socket);
            dns_socket = -1;
            
            continue;
        }
        
        free(login_info);
        
        // Keep alive loop
        char buf[5] = {0};
        while(1) {
            if(drone3g_can_accept_callback() != 1) {
                close(dns_socket);
                dns_socket = -1;
                
                break;
            }
            
            if(dns_recv_data(dns_socket, buf, 4, 12000, 0) <= 0) {
                syslog(LOG_ERR, "DNS ERROR: DNS Server timeout. Retrying...");
                
                close(dns_socket);
                dns_socket = -1;
                
                break;
            }
            
            if(strcmp(buf, "PING") != 0) { // Server is resolving controller name for drone
                uint8_t tmp[4];
                if(proxy_mode == DRONE3G_PROXY_MODE_CLIENT) { // If we are connecting through a proxy its IP address will be sent at this point
                    if(dns_recv_data(dns_socket, tmp, 4, 2000, 0) <= 0) {
                        syslog(LOG_ERR, "DNS ERROR: DNS Server timeout. Retrying...");
                        
                        close(dns_socket);
                        dns_socket = -1;
                        
                        break;
                    }
                    
                    memcpy(&proxy_ip, tmp, 4);
                }
                
                dns_send_data(dns_socket, "FINE", 4, 2000, 0); // Acknowledge termination
                dns_recv_data(dns_socket, tmp, -4, 2000, 0); // Wait for transaction completion
                
                close(dns_socket);
                dns_socket = -1;
                
                syslog(LOG_NOTICE, "DNS NOTICE: Name resolution successful !");
                
                return;
            }
            
            if(dns_send_data(dns_socket, "PONG", 4, 2000, 0) != 1) {
                syslog(LOG_ERR, "DNS ERROR: DNS Server timeout. Retrying...");
                
                close(dns_socket);
                dns_socket = -1;
                
                break;
            }
        }
    }
}

#pragma mark -
#pragma mark Proxy Functions
#pragma mark -

static void connect_to_proxy(int dns_post) {
    uint8_t buffer[128];
    int should_post_dns = dns_post;
    
    while(1) {
    start_connect:
        if(drone3g_can_accept_callback() != 1) {
            usleep(500000);
            continue;
        }
        
        if(should_post_dns == 1) {
            drone3g_dns_post();
        }
        should_post_dns = 1;
        
        if(drone3g_can_accept_callback() != 1) {
            continue;
        }
        
        struct sockaddr_in proxy_addr;
        bzero(&proxy_addr, sizeof(proxy_addr));

        proxy_addr.sin_family = AF_INET;
        proxy_addr.sin_addr.s_addr = proxy_ip;
        proxy_addr.sin_port = htons(6451);
        
        drone_socket = socket(AF_INET, SOCK_STREAM, 0);
        if(drone_socket < 0) {
            syslog(LOG_CRIT, "Socket creation failed: %s. Retrying...\n", strerror(errno));
            return;
        }
        
        /*struct timeval timeout;
         timeout.tv_sec = 1;
         timeout.tv_usec = 0;
         
         // This allows detection of a lost connection very fast
         if(setsockopt(drone_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
         syslog(LOG_CRIT, "Could not set timeout period for drone socket, Drone3g will require restarting to reinitate a dropped connection! %s.\n", strerror(errno));
         syslog(LOG_WARNING, "Recommended restart of Drone3g.\n");
         }*/
        
        // This may not be helpful as I don't think I've ever had the controls lag but it may help
        int nagle = 1;
        if(setsockopt(drone_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int)) < 0) {
            syslog(LOG_CRIT, "Could not disable nagle algorithm. %s.\n", strerror(errno));
        }
        int tos = IPTOS_LOWDELAY;
        if(setsockopt(drone_socket, IPPROTO_IP, IP_TOS, &tos, sizeof(int)) < 0) {
            syslog(LOG_CRIT, "Could not set ToS byte for IP header. %s.\n", strerror(errno));
            fflush(stdout);
        }
        
        long sock_flags = fcntl(drone_socket, F_GETFL, 0);
        fcntl(drone_socket, F_SETFL, sock_flags | O_NONBLOCK);
        
        connect(drone_socket, (struct sockaddr*)&proxy_addr, sizeof(proxy_addr));
        
        int retry_count = 3;
        while(1) {
            if(drone3g_can_accept_callback() != 1) {
                goto start_connect;
            }
            
            struct pollfd fds[1];
            bzero(fds, sizeof(fds));
            
            fds[0].fd = drone_socket;
            fds[0].events = POLL_OUT | POLL_ERR;
            
            if(poll(fds, 1, 5000) == 0) {
                goto start_connect;
            }
            
            if(fds[0].revents != 0) {
                errno = 0;
                if(connect(drone_socket, (struct sockaddr*)&proxy_addr, sizeof(proxy_addr)) >= 0 || errno == EISCONN) {
                    break;
                }
                
                syslog(LOG_ERR, "Could not connect to proxy server: %s. Retrying...\n", strerror(errno));
                
                retry_count--;
                if(retry_count == 0) {
                    goto start_connect;
                }
                
                close(drone_socket);
                
                drone_socket = socket(AF_INET, SOCK_STREAM, 0);
                if(drone_socket < 0) {
                    syslog(LOG_CRIT, "Socket creation failed: %s.\n", strerror(errno));
                    return;
                }
                
                /*struct timeval timeout;
                 timeout.tv_sec = 1;
                 timeout.tv_usec = 0;
                 
                 // This allows detection of a lost connection very fast
                 if(setsockopt(drone_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
                 syslog(LOG_CRIT, "Could not set timeout period for drone socket, Drone3g will require restarting to reinitate a dropped connection! %s.\n", strerror(errno));
                 syslog(LOG_WARNING, "Recommended restart of Drone3g.\n");
                 }*/
                
                // This may not be helpful as I don't think I've ever had the controls lag but it may help
                int nagle = 1;
                if(setsockopt(drone_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int)) < 0) {
                    syslog(LOG_CRIT, "Could not disable nagle algorithm. %s.\n", strerror(errno));
                }
                int tos = IPTOS_LOWDELAY;
                if(setsockopt(drone_socket, IPPROTO_IP, IP_TOS, &tos, sizeof(int)) < 0) {
                    syslog(LOG_CRIT, "Could not set ToS byte for IP header. %s.\n", strerror(errno));
                    fflush(stdout);
                }
                
                sock_flags = fcntl(drone_socket, F_GETFL, 0);
                fcntl(drone_socket, F_SETFL, sock_flags | O_NONBLOCK);
                
                connect(drone_socket, (struct sockaddr*)&proxy_addr, sizeof(proxy_addr));
            }
        }
        
        syslog(LOG_NOTICE, "Connection to proxy server established.\n");
        
        // Turn blocking mode back on
        fcntl(drone_socket, F_SETFL, sock_flags);
        
        // Wait, since when using a proxy the drone might not actually be connected yet
        while(1) {
            struct pollfd fds[1];
            bzero(fds, sizeof(fds));
            
            fds[0].fd = drone_socket;
            fds[0].events = POLL_IN;
            
            if(poll(fds, 1, 5000) <= 0) {
                syslog(LOG_ERR, "Connection to proxy server timedout. Reconnecting...\n");
                goto start_connect;
            }
            
            errno = 0;
            ssize_t len = recv(drone_socket, buffer, 13, MSG_PEEK | MSG_DONTWAIT);
            if(len <= 0) {
                syslog(LOG_ERR, "Connection to proxy server was lost. %s. Reconnecting...\n", strerror(errno));
                goto start_connect;
            }
            
            if(len == 13) {
                if(strncmp((char*)buffer, "AT*KEEPALIVE\r", 13) != 0) {
                    break;
                }
                
                // Flush buffer
                recv(drone_socket, buffer, 13, MSG_DONTWAIT);
            }
        }
        
        syslog(LOG_NOTICE, "Proxy to drone established.\n");
        
        got_connection = 1;
        drone3g_connection_established_callback();
        
        // Send the current telnet connection state so the drone can match
        if(telnet_connection_state == 0) {
            drone3g_send_command("AT*TELCLOSE\r");
        } else {
            drone3g_send_command("AT*TELCON\r");
        }
        
        // Start data thread
        if(data_thread == 0) {
            pthread_create(&data_thread, NULL, data_loop, NULL);
        }
        
        return;
    }
}

int print_lock_flag;

static void* proxy_work_loop(void* arg) {
    uint8_t buffer[64000];
    
    int client1_socket = ((int*)arg)[0];
    int client2_socket = ((int*)arg)[1];
    int me = ((int*)arg)[2];
    
    send(controller_socket, "AT*KEEPALIVE\r", 13, MSG_DONTWAIT);
    send(drone_socket,      "AT*KEEPALIVE\r", 13, MSG_DONTWAIT);
    
    while(1) {
        struct pollfd pfd[1];
        bzero(pfd, sizeof(pfd));
        
        pfd[0].fd = client1_socket;
        pfd[0].events = POLL_IN;
        
        int status = poll(pfd, 1, 2000);
        if(status < 0) {
            syslog(LOG_CRIT, "PROXY SERVER: A polling error occured. %s.\n", strerror(errno));
            
            usleep(66666);
            continue;
        }
        if(status == 0) {
            if(print_lock_flag == 1) {
                print_lock_flag = 0;
                
                syslog(LOG_WARNING, "PROXY SERVER: Client %i timedout while reading.\n", me);
                drone3g_proxy_log_post_callback((me == 1) ? "Client 1 not responding. Retrying connection process...\n" : "Client 2 not responding. Retrying connection process...\n");
            }
            
            shutdown(client1_socket, SHUT_RDWR);
            
            return NULL;
        }
        
        errno = 0;
        ssize_t bytes_read = recv(client1_socket, buffer, 64000, MSG_DONTWAIT);
        if(bytes_read <= 0) {
            if(print_lock_flag == 1) {
                print_lock_flag = 0;
                
                syslog(LOG_ERR, "PROXY SERVER: Connection to client %i was lost. %s.\n", me, strerror(errno));
                drone3g_proxy_log_post_callback((me == 1) ? "Connection to client 1 was lost. Trying to reconnect...\n" : "Connection to client 2 was lost. Trying to reconnect...\n");
            }
            
            return NULL;
        }
        
        struct timeval watch_stamp;
        gettimeofday(&watch_stamp, NULL);
        
        ssize_t bytes_written = 0;
        while(bytes_written < bytes_read) {
            struct timeval current_stamp;
            gettimeofday(&current_stamp, NULL);
            
            if( (current_stamp.tv_sec*1000000 + current_stamp.tv_usec) - (watch_stamp.tv_usec + watch_stamp.tv_sec*1000000) >= 2000000) {
                syslog(LOG_WARNING, "PROXY SERVER: Client %i timedout while writing.\n", me);
                drone3g_proxy_log_post_callback((me == 1) ? "Connection to client 2 was lost. Trying to reconnect...\n" : "Connection to client 1 was lost. Trying to reconnect...\n");
                
                return NULL;
            }
            
            errno = 0;
            ssize_t wrote = send(client2_socket, buffer+bytes_written, bytes_read-bytes_written, MSG_DONTWAIT);
            
            if(wrote <= 0) {
                if(errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(100);
                    continue;
                }
                
                if(print_lock_flag == 1) {
                    print_lock_flag = 0;
                
                    syslog(LOG_ERR, "PROXY SERVER: Connection to client %i was lost. %s.\n", me, strerror(errno));
                    drone3g_proxy_log_post_callback((me == 1) ? "Connection to client 2 was lost. Trying to reconnect...\n" : "Connection to client 1 was lost. Trying to reconnect...\n");
                }
                
                return NULL;
            }
            
            bytes_written += wrote;
        }
    }
}

static void* start_proxy_server(void* arg) {
    proxy_thread_running = 1;
    
    drone3g_proxy_log_post_callback("Proxy server started");
    
    // Setup server
    if(server_socket < 0) {
        struct sockaddr_in server_in;
        bzero(&server_in, sizeof(server_in));
        
        server_in.sin_family = AF_INET;
        server_in.sin_addr.s_addr = htonl(INADDR_ANY);
        server_in.sin_port = htons(6451);
        
        server_socket = socket(AF_INET, SOCK_STREAM, 0);
        if(server_socket < 0) {
            syslog(LOG_CRIT, "Could not create TCP socket for ARDrone. Aborting.\n");
            exit(2);
        }
        
        int reuse = 1;
        if(setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
            syslog(LOG_CRIT, "Could not set socket option SO_REUSEADDR. %s\n", strerror(errno));
        }
        
        if(bind(server_socket, (struct sockaddr*)&server_in, sizeof(struct sockaddr)) < 0) {
            syslog(LOG_CRIT, "Could not bind TCP socket for ARDrone. %s.\n", strerror(errno));
        }
        
        if(listen(server_socket, 1) < 0) {
            syslog(LOG_CRIT, "Could not listen on TCP socket port 6451.\n");
        }
    }
    
    drone3g_proxy_log_post_callback("Waiting for clients...\n");
    
    uint8_t buffer[4096];
    
    if(drone3g_can_accept_callback() == 1) {
        drone3g_dns_post();
    }
    
    struct timeval dns_stamp;
    gettimeofday(&dns_stamp, NULL);
    
    while(1) {
        got_connection = 0;

        if(drone3g_can_accept_callback() != 1) {
            proxy_thread_running = 0;
            pthread_detach(pthread_self());
            
            return NULL;
        }
        
        struct timeval current_stamp;
        gettimeofday(&current_stamp, NULL);

        if( (current_stamp.tv_sec*1000000 + current_stamp.tv_usec) - (dns_stamp.tv_usec + dns_stamp.tv_sec*1000000) >= 5000000) {
            syslog(LOG_ERR, "PROXY SERVER: Connection timeout.");
            drone3g_proxy_log_post_callback("Clients taking too long to connect, disconnecting then trying again...\n");
            
            controller_socket = -1;
            drone_socket = -1;
            
            /*if(controller_socket >= 0) {
                close(controller_socket);
                controller_socket = -1;
            }
            if(drone_socket >= 0) {
                close(drone_socket);
                drone_socket = -1;
            }*/
            
            drone3g_dns_post();
            gettimeofday(&dns_stamp, NULL);
        }
        
        int num_fds = 1;
        
        struct pollfd pfd[3];
        bzero(pfd, sizeof(pfd));
        
        pfd[0].fd = server_socket;
        pfd[0].events = POLL_IN;
        
        if(controller_socket >= 0) {
            pfd[1].fd = controller_socket;
            pfd[1].events = POLL_IN;
            
            num_fds++;
        }
        if(drone_socket >= 0) {
            pfd[2].fd = drone_socket;
            pfd[2].events = POLL_IN;
            
            num_fds++;
        }
        
        int status = poll(pfd, num_fds, 5000);
        
        // Clear buffer
        if(controller_socket >= 0) {
            if(recv(controller_socket, buffer, 4096, MSG_DONTWAIT) == 0) {
                syslog(LOG_ERR, "PROXY SERVER: Client 1 disconnected.\n");
                drone3g_proxy_log_post_callback("Client 1 disconnected.");
                
                controller_socket = -1;
            }
            
            send(controller_socket, "AT*KEEPALIVE\r", 13, MSG_DONTWAIT);
        }
        if(drone_socket >= 0) {
            if(recv(drone_socket, buffer, 4096, MSG_DONTWAIT) == 0) {
                syslog(LOG_ERR, "PROXY SERVER: Client 2 disconnected.\n");
                drone3g_proxy_log_post_callback("Client 2 disconnected.");
                
                drone_socket = -1;
            }
            
            send(drone_socket, "AT*KEEPALIVE\r", 13, MSG_DONTWAIT);
        }
        
        if(status <= 0) {
            syslog(LOG_ERR, "PROXY_SERVER: Polling error.");
            drone3g_proxy_log_post_callback("Communication with clients has been lost, clients are not responding. Retrying connection...\n");
            
            drone_socket = -1;
            controller_socket = -1;
            
            if(drone3g_can_accept_callback() == 1) {
                drone3g_dns_post();
                gettimeofday(&dns_stamp, NULL);
            }
            
            continue;
        }
        
        if(pfd[0].revents & POLL_IN) {
            struct sockaddr_in client_addr;
            socklen_t socksize = sizeof(client_addr);
            bzero(&client_addr, sizeof(client_addr));
            
            int client_socket = accept(server_socket, (struct sockaddr*)&client_addr, &socksize);
            
            if(client_socket >= 0) {
                syslog(LOG_NOTICE, "PROXY SERVER: Connection to client %i etasblished IP address %s\n", (controller_socket < 0)  ? 1 : 2, inet_ntoa(client_addr.sin_addr));
                
                char line[512];
                sprintf(line, "Established connection to client %i IP address %s", (controller_socket < 0)  ? 1 : 2, inet_ntoa(client_addr.sin_addr));
                drone3g_proxy_log_post_callback(line);
                
                int nagle = 1;
                if(setsockopt(client_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int)) < 0) {
                    syslog(LOG_WARNING, "PROXY SERVER: Could not disable nagle algorithm.\n");
                }
                int tos = IPTOS_LOWDELAY;
                if(setsockopt(client_socket, IPPROTO_IP, IP_TOS, &tos, sizeof(int)) < 0) {
                    syslog(LOG_WARNING, "PROXY SERVER: Could not set ToS byte for IP header.\n");
                }
                
                if(controller_socket < 0) {
                    controller_socket = client_socket;
                } else if(drone_socket < 0) {
                    drone_socket = client_socket;
                }
                
                if(drone_socket >= 0 && controller_socket >= 0) {
                    // Start proxy
                    int sockets[2][3] = {{controller_socket,drone_socket,1},{drone_socket,controller_socket,2}};
                    
                    print_lock_flag = 1;
                    
                    pthread_t work_threads[2];
                    pthread_create(&work_threads[0], NULL, proxy_work_loop, sockets[0]);
                    pthread_create(&work_threads[1], NULL, proxy_work_loop, sockets[1]);
                    
                    pthread_join(work_threads[0], NULL);
                    pthread_join(work_threads[1], NULL);
                    
                    controller_socket = -1;
                    drone_socket = -1;
                    
                    if(drone3g_can_accept_callback() == 1) {
                        drone3g_dns_post();
                        gettimeofday(&dns_stamp, NULL);
                    }
                }
                
                continue;
            }
            
            syslog(LOG_ERR, "PROXY SERVER: Could not accept incoming connection. Trying again... (firewall?)\n");
            drone3g_proxy_log_post_callback("A connection attempt was in progress but was aborted. Trying again...");
        }
    }
}

void drone3g_start_proxy() {
    if(proxy_thread_running == 1) {
        pthread_cancel(proxy_thread);
        pthread_join(proxy_thread, NULL);
        
        proxy_thread_running = 0;
    }
    
    pthread_create(&proxy_thread, NULL, start_proxy_server, NULL);
}

#pragma mark -
#pragma mark Connection 
#pragma mark -

void drone3g_listen_for_ardrone(int dns_post) {
    got_connection = 0;
    
    while(1) {
        if(drone3g_can_accept_callback() == 1 && proxy_mode != DRONE3G_PROXY_MODE_SERVER) {
            break;
        }
        
        usleep(500000);
    }
    
    if(proxy_thread_running == 1) {
        pthread_cancel(proxy_thread);
        pthread_join(proxy_thread, NULL);
        
        proxy_thread_running = 0;
    }
    
    if(proxy_mode == DRONE3G_PROXY_MODE_CLIENT) {
        connect_to_proxy(dns_post);
        return;
    }
    
    while(1) {
        // Check to see if connecting is allowed
        if(drone3g_can_accept_callback() != 1 || proxy_mode == DRONE3G_PROXY_MODE_SERVER) {
            usleep(500000);
            continue;
        }
        
        drone3g_dns_post();
        
        struct pollfd pfd[1];
        bzero(pfd, sizeof(pfd));
        
        pfd[0].fd = server_socket;
        pfd[0].events = POLL_IN;
        
        if(poll(pfd, 1, 10000) == 0) {
            continue;
        }
        
        if(drone3g_can_accept_callback() != 1 || proxy_mode == DRONE3G_PROXY_MODE_SERVER) {
            continue;
        }
        
        drone_socket = accept(server_socket, (struct sockaddr*)&drone, &socksize);
        
        if(drone_socket >= 0) {
            syslog(LOG_NOTICE, "Connection to ARDrone etasblished IP address %s\n", inet_ntoa(drone.sin_addr));
            
            /*struct timeval timeout;
            timeout.tv_sec = 1;
            timeout.tv_usec = 0;
            
            // This allows detection of a lost connection very fast
            if(setsockopt(drone_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
                syslog(LOG_CRIT, "Could not set timeout period for drone socket: %s. Drone3g will require restarting to reinitate a dropped connection!\n", strerror(errno));
                syslog(LOG_WARNING, "Recommended restart of Drone3g.\n");
            }*/
            
            // This may not be helpful as I don't think I've ever had the controls lag but it may help
            int nagle = 1;
            if(setsockopt(drone_socket, IPPROTO_TCP, TCP_NODELAY, &nagle, sizeof(int)) < 0) {
                syslog(LOG_CRIT, "Could not disable nagle algorithm. %s.\n", strerror(errno));
            }
            int tos = IPTOS_LOWDELAY;
            if(setsockopt(drone_socket, IPPROTO_IP, IP_TOS, &tos, sizeof(int)) < 0) {
                syslog(LOG_CRIT, "Could not set ToS byte for IP header. %s.\n", strerror(errno));
                fflush(stdout);
            }
            
            gettimeofday(&last_connect_time, NULL);
            
            got_connection = 1;
            drone3g_connection_established_callback();
            
            // Send the current telnet connection state so the drone can match
            if(telnet_connection_state == 0) {
                drone3g_send_command("AT*TELCLOSE\r");
            } else {
                drone3g_send_command("AT*TELCON\r");
            }
            
            // Start data thread
            if(data_thread == 0) {
                pthread_create(&data_thread, NULL, data_loop, NULL);
            }
            
            return;
        }
        
        // Server socket was closed because we are exiting
        if(sockets_closing == 1) {
            pthread_exit(NULL);
        }
        
        syslog(LOG_ERR, "Could not accept ARDrone connection. Trying again... (firewall?)\n");
    }
}

void drone3g_setup_server() {
    pthread_mutex_init(&send_lock, NULL);
    send_lock_inited = 1;
    
    pthread_mutex_init(&gps_lock, NULL);
    gps_lock_inited = 1;
    
    // Setting up server
    if(server_socket < 0) {
        struct sockaddr_in server_in;
        bzero(&server_in, sizeof(server_in));
        
        server_in.sin_family = AF_INET;
        server_in.sin_addr.s_addr = htonl(INADDR_ANY);
        server_in.sin_port = htons(6451);
        
        server_socket = socket(AF_INET, SOCK_STREAM, 0);
        if(server_socket < 0) {
            syslog(LOG_CRIT, "Could not create TCP socket for ARDrone. Aborting.\n");
            exit(2);
        }
        
        int reuse = 1;
        if(setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(int)) < 0) {
            syslog(LOG_CRIT, "Could not set socket option SO_REUSEADDR. %s\n", strerror(errno));
        }
        
        if(bind(server_socket, (struct sockaddr*)&server_in, sizeof(struct sockaddr)) < 0) {
            syslog(LOG_CRIT, "Could not bind TCP socket for ARDrone. %s.\n", strerror(errno));
        }
        
        if(listen(server_socket, 1) < 0) {
            syslog(LOG_CRIT, "Could not listen on TCP socket port 6451.\n");
        }
    }
    
    sockets_closing = 0;
    
    pthread_t telnet_thr;
    pthread_create(&telnet_thr, NULL, start_telnet_proxy, NULL);
    
    drone3g_listen_for_ardrone(1);
}
