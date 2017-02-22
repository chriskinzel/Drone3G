//
//  drone3g_installer.c
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-26.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#include "drone3g_installer.h"

#include <errno.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <fcntl.h>
#include <syslog.h>
#include <pthread.h>
#include <poll.h>

#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netinet/ip.h>
#include <arpa/inet.h>

#include <CommonCrypto/CommonCrypto.h>

extern const char* application_bundle_path();

// INSTALL + UNINSTALL CALLBACKS
void(*current_completetion_handler)(int);
void(*current_progress_updater)(int);

// INSTALLER VARIABLES
pthread_t install_thread;
int is_installing = 0;

// UNINSTALLER VARIABLES
pthread_t uninstall_thread;
int is_uninstalling = 0;

// NETWORK VARIABLES
int telnet_socket;
int has_connection = 0;

// CONNECTION VARIABLES
void(*current_connect_callback)(void);

int connect_thread_running = 0;
pthread_t connect_thread;

#pragma mark Status function
#pragma mark -

drone3g_installer_status drone3g_installer_get_status() {
    return (has_connection*32 | connect_thread_running*16 | is_installing*4 | is_uninstalling*8);
}

#pragma mark -
#pragma mark Helper Functions
#pragma mark -

static int send_telnet_command(const char* cmd, size_t cmd_len) {
    size_t wrote = 0;
    
    while(wrote < cmd_len) {
        ssize_t actual = write(telnet_socket, cmd+wrote, cmd_len-wrote);
        if(actual <= 0) {
            syslog(LOG_ERR, "Installer: communication error. %s.\n", strerror(errno));
            return -1;
        }
        
        wrote += actual;
    }
    
    return 0;
}

// Reads on the telnet socket until the #  sequence is detected indicating the shell has processed previous commands and is
// now ready for further instruction
static int read_telnet_response(char* buffer, size_t buf_size) {
    size_t stream_loc = 0;
    
    while(1) {
        size_t len = read(telnet_socket, buffer+stream_loc, buf_size-stream_loc);
        if(len <= 0) {
            syslog(LOG_ERR, "Installer: communication error. %s.\n", strerror(errno));
            return -1;
        }
        
        char* eot = strstr(buffer+stream_loc, "# ");
        if(eot != NULL) {
            return 0;
        }
        
        stream_loc += len;
        if(stream_loc >= buf_size) {
            return -1;
        }
    }
}

#pragma mark -
#pragma mark Connection
#pragma mark -

static int connect_helper_socket(int port) {
    struct sockaddr_in drone_addr;
    bzero(&drone_addr, sizeof(drone_addr));
    
    drone_addr.sin_family = AF_INET;
    drone_addr.sin_port = htons(port);
    drone_addr.sin_addr.s_addr = inet_addr("192.168.1.1");
    
    while(1) {
        int helper_socket = socket(AF_INET, SOCK_STREAM, 0);
        if(helper_socket < 0) {
            syslog(LOG_ERR, "Installer: Could not create socket. %s.\n", strerror(errno));
            return -2;
        }
        
        // Set non-blocking (this handles the case where the user is connected the ARDrone's network but needs to disconnect from another network)
        long arg = fcntl(helper_socket, F_GETFL, NULL);
        arg |= O_NONBLOCK;
        fcntl(helper_socket, F_SETFL, arg);
        
        int ret;
        int try_count = 2;
        
    check_connect:
        ret = connect(helper_socket, (struct sockaddr*)&drone_addr, sizeof(struct sockaddr));
        
        if(ret >= 0 || errno == EISCONN) {
            // Go back to blocking mode
            arg &= (~O_NONBLOCK);
            fcntl(helper_socket, F_SETFL, arg);
            
            return helper_socket;
        }
        if(errno == EINPROGRESS && try_count > 0) {
            try_count--;
            
            struct pollfd fds;
            bzero(&fds, sizeof(fds));
            fds.fd = helper_socket;
            fds.events = POLL_OUT | POLL_IN;
            
            int status = poll(&fds, 1, 5000);
            
            if(status < 0) {
                syslog(LOG_ERR, "Installer: IO error!");
                
                close(helper_socket);
                return -2;
            }
            if(status > 0 || status == 0) {
                goto check_connect;
            }
        }
        
        close(helper_socket);
        
        return -1;
    }
}

static void* connect_drone(void* arg) {
    connect_thread_running = 1;
    
    drone3g_connect_type type = *(drone3g_connect_type*)arg;
    
    struct sockaddr_in drone_addr;
    bzero(&drone_addr, sizeof(drone_addr));
    
    drone_addr.sin_family = AF_INET;
    drone_addr.sin_port = htons( (type == DRONE3G_CONNECT_TYPE_INSTALL) ? 23 : 6450);
    drone_addr.sin_addr.s_addr = inet_addr("192.168.1.1");
    
    uint8_t buffer[64000];
    
    while(1) {
        telnet_socket = socket(AF_INET, SOCK_STREAM, 0);
        if(telnet_socket < 0) {
            syslog(LOG_ERR, "Could not create socket for installer connection. %s.\n", strerror(errno));
            
            connect_thread_running = 0;
            return NULL;
        }
        
        // Set non-blocking (this handles the case where the user is connected the ARDrone's network but needs to disconnect from another network)
        long arg = fcntl(telnet_socket, F_GETFL, NULL);
        arg |= O_NONBLOCK;
        fcntl(telnet_socket, F_SETFL, arg);
        
        int ret;
        
    try_connect:
        ret = connect(telnet_socket, (struct sockaddr*)&drone_addr, sizeof(struct sockaddr));
        if(ret >= 0 || errno == EISCONN) {
            has_connection = 1;
            syslog(LOG_NOTICE, "Installer: testing potential drone...\n");
            
            // Go back to blocking mode
            arg &= (~O_NONBLOCK);
            fcntl(telnet_socket, F_SETFL, arg);
            
            // Negotiate options
            char negotations[9] = {0xFF, 0xFC, 0x01, 0xFF, 0xFC, 0x1F, 0xFF, 0xFD, 0x03};
            if(send_telnet_command(negotations, 9) != 0) {
                goto retry;
            }
            
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                goto retry;
            }
            if(send_telnet_command("ls /bin\r\n", strlen("ls /bin\r\n")+1) != 0) {
                goto retry;
            }
            
            usleep(500000);
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                goto retry;
            }
            
            // Looks for parrotauthdaemon in /bin to check for Parrot ARDrone 2.0
            if(strstr((char*)buffer, "parrotauthdaemon") != NULL) {
                // Parrot ARDrone 2.0 found
                syslog(LOG_NOTICE, "Installer: connection to drone established!\n");
                
                current_connect_callback();
                
                connect_thread_running = 0;
                
                return NULL;
            } else { // Not a Parrot ARDrone 2.0, keep searching
                syslog(LOG_NOTICE, "Installer: Device was not a Parrot ARDrone 2.0\n");
            }
        }
        
        if(errno == EINPROGRESS) {
            usleep(500000);
            goto try_connect;
        }
        
    retry:
        close(telnet_socket);
        has_connection = 0;
        
        sleep(1);
    }
    
    return NULL;
}

void drone3g_installer_connect(drone3g_connect_type type, void(*callback)(void)) {
    if(connect_thread_running == 1 || has_connection == 1) { // Already trying to connect or connected
        return;
    }
    
    //openlog("Drone3G", LOG_PERROR, 0);
    
    current_connect_callback = callback;
    
    if(pthread_create(&connect_thread, NULL, &connect_drone, &type) != 0) {
        syslog(LOG_ERR, "Could not create new thread for installer connection. %s.\n", strerror(errno));
        return;
    }
    
    pthread_detach(connect_thread);
}

void drone3g_installer_stop_connecting() {
    if(connect_thread_running == 1) {
        pthread_cancel(connect_thread);
        connect_thread_running = 0;
    }
    if(has_connection == 1) {
        close(telnet_socket);
        has_connection = 0;
    }
}

#pragma mark -
#pragma mark Uninstaller
#pragma mark -

static void* uninstall_drone(void* arg) { // Since this function is used for cleanup on a failed install it does not callback unless the installer
    is_uninstalling = 1;
    
    uint8_t buffer[64000];
    
    // Connect to uninstall port
    int uninstall_socket = connect_helper_socket(6453);
    if(uninstall_socket < 0) {
        current_completetion_handler((uninstall_socket < -1) ? DRONE3G_UNINSTALL_ALREADY : DRONE3G_UNINSTALL_LOST_CONNECTION);
        is_uninstalling = 0;
        
        close(telnet_socket);
        has_connection = 0;
        
        return NULL;
    }
    
    // Send anything to continue
    if(write(uninstall_socket, "\r", 1) <= 0) {
        current_completetion_handler(DRONE3G_UNINSTALL_LOST_CONNECTION);
        is_uninstalling = 0;
        
        close(uninstall_socket);
        close(telnet_socket);
        has_connection = 0;
        
        return NULL;
    }
    
    char* last_progress = (char*)buffer;
    ssize_t offset = 0;
    
    while(1) {
        // Read progress updates
        ssize_t bytes_read = read(uninstall_socket, buffer+offset, 64000-offset-1);
        if(bytes_read <= 0) {
            current_completetion_handler(DRONE3G_UNINSTALL_LOST_CONNECTION);
            is_uninstalling = 0;
            
            close(uninstall_socket);
            close(telnet_socket);
            has_connection = 0;
            
            return NULL;
        }
        
        offset += bytes_read;
        buffer[offset] = 0;
        
        char* match;
        while( (match = strstr((char*)last_progress, "PROGRESS:")) != NULL) {
            int progress;
            if(sscanf(match, "PROGRESS:%i", &progress) == 1) {
                if(progress == 100) { // Complete
                    close(uninstall_socket);
                    close(telnet_socket);
                    has_connection = 0;
                    
                    current_progress_updater(100);
                    current_completetion_handler(DRONE3G_UNINSTALL_SUCCESS);
                    
                    is_uninstalling = 0;
                    
                    return NULL;
                }
                
                current_progress_updater(progress);
                last_progress = match+1;
            }
        }
        
    }
    
    return NULL;
}

void drone3g_installer_uninstall(void(*complete_callback)(int), void(*progress_update)(int)) {
    if(is_installing == 1 || is_uninstalling == 1) {
        return;
    }
    if(has_connection == 0 || connect_thread_running == 1) {
        complete_callback(DRONE3G_INSTALL_LOST_CONNECTION);
        return;
    }
    
    current_completetion_handler = complete_callback;
    current_progress_updater = progress_update;
    
    if(pthread_create(&uninstall_thread, NULL, &uninstall_drone, NULL) != 0) {
        syslog(LOG_ERR, "Could not create new thread for uninstaller. %s.\n", strerror(errno));
        return;
    }
    
    syslog(LOG_NOTICE, "Installer: begining uninstall!\n");
    
    pthread_detach(uninstall_thread);

}

#pragma mark -
#pragma mark Installer
#pragma mark -

static void* decrypt(void* data, size_t data_len, char* key) {
    size_t buf_size = data_len + kCCBlockSizeAES128;
    void* outBuffer = malloc(buf_size);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus result = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding, key, kCCKeySizeAES256, NULL, data, data_len, outBuffer, buf_size, &numBytesDecrypted);
    
    if(result == kCCSuccess) {
        return outBuffer;
    }
    
    free(outBuffer);
    return NULL;
}

static void install_cleanup(int stage) {
    if(stage >= 0) {
        char* cmd;
        
        // Delete drone3g directory
        cmd = "rmdir /data/drone3g\r\n";
        if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
            return;
        }
        
        if(stage == 1) { // Delete wifi_setup.sh backup
            cmd = "rm /bin/.wifi_setup.sh.backup\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                return;
            }
        } else if(stage > 1) { // Restore wifi_setup.sh backup
            cmd = "mv /bin/.wifi_setup.sh.backup /bin/wifi_setup.sh\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                return;
            }
        }
    }
    
    is_installing = 0;
    has_connection = 0;
    close(telnet_socket);
}

static void* install_drone(void* arg) {
    is_installing = 1;
    
    uint8_t buffer[64000];
    char* cmd;
    
    cmd = "mkdir /data/drone3g\r\n";
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
        install_cleanup(-1);
        
        return NULL;
    }
    usleep(100000);
    if(read_telnet_response((char*)buffer, 64000) != 0) {
        current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
        install_cleanup(-1);
        
        return NULL;
    }
    if(strstr((char*)buffer, "mkdir:") != NULL) {
        syslog(LOG_ERR, "Installer: Drone3G is already installed on this drone.");
        
        current_completetion_handler(DRONE3G_INSTALL_ALREADY);
        install_cleanup(-1);
        
        return NULL;
    }

    // Make sure image is available first
    char install_path[1024];
    sprintf(install_path, "%s/Contents/Resources/drone3g.install", application_bundle_path());
    
    FILE* image_fp = fopen(install_path, "rb");
    if(image_fp == NULL) {
        syslog(LOG_ERR, "Installer: Access error!");
        
        current_completetion_handler(DRONE3G_INSTALL_DRONE_FAILED);
        install_cleanup(0);
        
        return NULL;
    }
    
    fseek(image_fp, 0, SEEK_END);
    long img_size = ftell(image_fp);
    fseek(image_fp, 0, SEEK_SET);
    
    void* encrypted_data = malloc(img_size);
    if(fread(encrypted_data, img_size, 1, image_fp) < 1) {
        syslog(LOG_ERR, "Installer: read error!");
        
        current_completetion_handler(DRONE3G_INSTALL_DRONE_FAILED);
        install_cleanup(0);
        
        fclose(image_fp);
        free(encrypted_data);
        
        return NULL;
    }
    
    fclose(image_fp);
    
    volatile char key[33] = "a7jbb843j6u3ms0t9s4emr8z3k5725n2f"; // "b52qw521782oo9lt9s4emr8z3k5725n2f"
    key[0]  = 98;
    key[1]  = key[0]/2 + 4;
    key[2]  = key[1] - 3;
    key[3]  = (key[2] << 1) + 13;
    key[4]  = key[3]+6;
    key[5]  = key[1];
    key[6]  = key[5] - 3;
    key[7]  = key[6] - 1;
    key[8]  = key[7]+6;
    key[9]  = key[8]+1;
    key[10] = key[2];
    key[11] = key[3] - 2;
    key[12] = key[11];
    key[13] = key[9]+1;
    key[14] = key[12] - 3;
    key[15] = key[14] + 8;
    
    void* data = decrypt(encrypted_data, img_size, (char*)key);
    img_size -= kCCBlockSizeAES128;
    free(encrypted_data);
        
    while(1) {
        // Set up connection for install transfer later and clear user boxes so that non-volatile memory isn't exhausted
        // also move credential file to the correct place
        cmd = "(rm -r /data/video/boxes/*; mv /.credentials /data/drone3g/.credentials; nc -l -p 6454 | tar -xf - -C /data; mv /data/.drone3g/drone/.drone3g /; reboot) &\r\n";
        if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
            current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
            install_cleanup(-1);
            
            free(data);
            
            return NULL;
        }
        usleep(100000);
        if(read_telnet_response((char*)buffer, 64000) != 0) {
            current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
            install_cleanup(-1);
            
            free(data);
            
            return NULL;
        }
        
        current_progress_updater(2);
        
        // Check if wifi_setup.sh already autostarts drone3g
#pragma mark Check wifi_setup.sh
        cmd = "cat /bin/wifi_setup.sh\r\n";
        if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
            current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
            install_cleanup(-1);
            
            free(data);

            return NULL;
        }
        usleep(500000);
        if(read_telnet_response((char*)buffer, 64000) != 0) {
            current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
            install_cleanup(-1);
            
            free(data);

            return NULL;
        }
        
        current_progress_updater(13);
        
        if(strstr((char*)buffer, "telnet 192.168.1.1 < /.drone3g/drone3g.sh& exit") == NULL) {
            // Backup wifi_setup.sh
#pragma mark Backup of wifi_setup.sh if needed
            cmd = "cp /bin/wifi_setup.sh /bin/.wifi_setup.sh.backup\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            usleep(100000);
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            
            current_progress_updater(15);
            
            // Make sure backup was successful
            cmd = "ls -a /bin\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);
                
                return NULL;
            }
            usleep(500000);
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            if(strstr((char*)buffer, ".wifi_setup.sh.backup") == NULL) {
                syslog(LOG_ERR, "Installer: Backup failed!\n");
                
                current_completetion_handler(DRONE3G_INSTALL_DRONE_FAILED);
                install_cleanup(1);
                
                free(data);

                return NULL;
            }
            
            current_progress_updater(27);
            
            // Add line to wifi_setup.sh to autostart drone3g.sh
#pragma mark Adding autostart line to wifi_setup.sh for drone3g.sh if not already present
            cmd = "echo $'telnet 192.168.1.1 < /.drone3g/drone3g.sh& exit\n' >> /bin/wifi_setup.sh\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            usleep(100000);
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            
            current_progress_updater(29);
            
            // Make sure line was successfully added
            cmd = "cat /bin/wifi_setup.sh\r\n";
            if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            usleep(500000);
            if(read_telnet_response((char*)buffer, 64000) != 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                free(data);

                return NULL;
            }
            if(strstr((char*)buffer, "telnet 192.168.1.1 < /.drone3g/drone3g.sh& exit") == NULL) {
                syslog(LOG_ERR, "Installer: Autorun failed!\n");
                
                current_completetion_handler(DRONE3G_INSTALL_DRONE_FAILED);
                install_cleanup(2);
                
                free(data);

                return NULL;
            }
        }
        
        current_progress_updater(38);
        
        // Transfer image
#pragma mark Transfering image
        int transfer_socket = connect_helper_socket(6454);
        if(transfer_socket < 0) {
            current_completetion_handler((transfer_socket < -1) ? DRONE3G_INSTALL_DRONE_FAILED : DRONE3G_INSTALL_LOST_CONNECTION);
            install_cleanup(2);
            
            free(data);
            
            return NULL;
        }
        
        size_t bytes_written = 0;
        while(bytes_written < img_size) {
            ssize_t actual = write(transfer_socket, data+bytes_written, (img_size-bytes_written > 128*1024) ? 128*1024 : img_size-bytes_written);
            if(actual <= 0) {
                current_completetion_handler(DRONE3G_INSTALL_LOST_CONNECTION);
                install_cleanup(-1);
                
                close(transfer_socket);
                free(data);
                
                return NULL;
            }
            
            bytes_written += actual;
            current_progress_updater((int)(bytes_written*62 / img_size) + 38);
        }
        
        sleep(1); // Make sure data is sent
        
        close(transfer_socket);
        free(data);
        
#pragma mark Complete
        close(telnet_socket);
        has_connection = 0;
        
        current_progress_updater(100);
        current_completetion_handler(DRONE3G_INSTALL_SUCCESS);
        
        is_installing = 0;
        
        return NULL;
    }
    
    return NULL;
}

void drone3g_installer_install(void(*complete_callback)(int), void(*progress_update)(int)) {
    if(is_installing == 1 || is_uninstalling == 1) {
        return;
    }
    if(has_connection == 0 || connect_thread_running == 1) {
        complete_callback(DRONE3G_INSTALL_LOST_CONNECTION);
        return;
    }
    
    current_completetion_handler = complete_callback;
    current_progress_updater = progress_update;
    
    if(pthread_create(&install_thread, NULL, &install_drone, NULL) != 0) {
        syslog(LOG_ERR, "Could not create new thread for installer. %s.\n", strerror(errno));
        return;
    }
    
    syslog(LOG_NOTICE, "Installer: begining install!\n");
    
    pthread_detach(install_thread);
}


#pragma mark -
#pragma mark Carrier Settings
#pragma mark -

int drone3g_set_carrier_settings(const char* apn, const char* username, const char* password) {
    if(has_connection != 1) {
        return -1;
    }
    
    char _apn[64];
    char _username[32];
    char _password[32];
    
    strncpy(_apn, apn, 64);
    strncpy(_username, username, 32);
    strncpy(_password, password, 32);
    
    uint8_t buffer[64000];
    char cmd[1024];
    
    // Create manual carrier settings file
    sprintf(cmd, "echo $'APN:%s\nUsername:%s\nPassword:%s\n' > /data/drone3g/.carrier-settings\r\n", _apn, _username, _password);
    
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        return -1;
    }
    usleep(100000);
    if(read_telnet_response((char*)buffer, 64000) != 0) {
        return -1;
    }
    
    return 0;
}

int drone3g_get_carrier_settings(char* apn, char* username, char* password) {
    if(has_connection != 1) {
        return -1;
    }
    
    uint8_t buffer[64000];
    char* cmd;
    
    cmd = "rm /data/drone3g/.carrier-settings\r\n";
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        return -1;
    }
    usleep(100000);
    if(read_telnet_response((char*)buffer, 64000) != 0) {
        return -1;
    }
    
    cmd = "cat /data/drone3g/.carrier-settings-auto\r\n";
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        return -1;
    }
    usleep(500000);
    if(read_telnet_response((char*)buffer, 64000) != 0) {
        return -1;
    }
    
    // Read the APN
    char* apn_tag = strstr((char*)buffer, "APN:");
    if(apn_tag == NULL) {
        return -1;
    }
    apn_tag += 4;
    
    char* nl = strchr(apn_tag, '\n');
    char* cr = strchr(apn_tag, '\r');
    char* eol;
    
    if(nl == NULL && cr == NULL) {
        return -1;
    }
    if(nl != NULL && cr != NULL) {
        eol = (nl < cr) ? nl : cr;
    } else {
        eol = (nl == NULL) ? cr : nl;
    }
    
    eol[0] = 0;
    strncpy(apn, apn_tag, 64);
    eol[0] = '\n';
    
    // Read the Username
    char* user_tag = strstr((char*)buffer, "Username:");
    if(user_tag == NULL) {
        return -1;
    }
    user_tag += 9;
    
    nl = strchr(user_tag, '\n');
    cr = strchr(user_tag, '\r');
    
    if(nl == NULL && cr == NULL) {
        return -1;
    }
    if(nl != NULL && cr != NULL) {
        eol = (nl < cr) ? nl : cr;
    } else {
        eol = (nl == NULL) ? cr : nl;
    }
    
    eol[0] = 0;
    strncpy(username, user_tag, 32);
    eol[0] = '\n';
    
    // Read the Password
    char* pass_tag = strstr((char*)buffer, "Password:");
    if(pass_tag == NULL) {
        return -1;
    }
    pass_tag += 9;
    
    nl = strchr(pass_tag, '\n');
    cr = strchr(pass_tag, '\r');
    
    if(nl == NULL && cr == NULL) {
        return -1;
    }
    if(nl != NULL && cr != NULL) {
        eol = (nl < cr) ? nl : cr;
    } else {
        eol = (nl == NULL) ? cr : nl;
    }
    
    eol[0] = 0;
    strncpy(password, pass_tag, 32);
    
    return 0;
}

#pragma mark -
#pragma mark Login Settings
#pragma mark -

int drone3g_set_credentials(const char* username, const char* password, const char* dname) {
    if(has_connection != 1) {
        return -1;
    }
    
    // Hash login info
    uint8_t username_hash[32], password_hash[32], name_hash[32];
    
    CC_SHA256((const unsigned char*)username, (CC_LONG)strlen(username)+1, username_hash);
    CC_SHA256((const unsigned char*)password, (CC_LONG)strlen(password)+1, password_hash);
    CC_SHA256((const unsigned char*)dname,    (CC_LONG)strlen(dname)+1,    name_hash);
    
    char cmd[1024];
    
    // Transfer hashed credentials
    sprintf(cmd, "nc -l -p 9600 > /data/drone3g/.credentials\r\n");
    
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        return -1;
    }
    usleep(100000);
    
    int transfer_socket = connect_helper_socket(9600);
    if(transfer_socket < 0) {
        return -1;
    }
    
    uint8_t* current_hash = username_hash;
    for(int i=0;i<3;i++) {
        if(i == 1) {
            current_hash = password_hash;
        } else if(i == 2) {
            current_hash = name_hash;
        }
        
        size_t bytes_written = 0;
        while(bytes_written < 32) {
            ssize_t actual = write(transfer_socket, current_hash+bytes_written, 32-bytes_written);
            if(actual <= 0) {
                syslog(LOG_ERR, "Credential syncing failed! %s.", strerror(errno));
                close(transfer_socket);
                
                return -1;
            }
            
            bytes_written += actual;
        }
    }
    
    // Give the transfer a few milliseconds to complete before closing
    usleep(5000);
    close(transfer_socket);
    
    return 0;
}

int drone3g_set_credentials_pre_install(const char* username, const char* password, const char* dname) {
    if(has_connection != 1) {
        return -1;
    }
    
    // Hash login info
    uint8_t username_hash[32], password_hash[32], name_hash[32];
    
    CC_SHA256((const unsigned char*)username, (CC_LONG)strlen(username)+1, username_hash);
    CC_SHA256((const unsigned char*)password, (CC_LONG)strlen(password)+1, password_hash);
    CC_SHA256((const unsigned char*)dname,    (CC_LONG)strlen(dname)+1,    name_hash);
    
    char cmd[1024];
    
    // Transfer hashed credentials
    sprintf(cmd, "nc -l -p 9600 > /.credentials\r\n");
    
    if(send_telnet_command(cmd, strlen(cmd)+1) != 0) {
        return -1;
    }
    usleep(100000);
    
    int transfer_socket = connect_helper_socket(9600);
    if(transfer_socket < 0) {
        return -1;
    }
    
    uint8_t* current_hash = username_hash;
    for(int i=0;i<3;i++) {
        if(i == 1) {
            current_hash = password_hash;
        } else if(i == 2) {
            current_hash = name_hash;
        }
        
        size_t bytes_written = 0;
        while(bytes_written < 32) {
            ssize_t actual = write(transfer_socket, current_hash+bytes_written, 32-bytes_written);
            if(actual <= 0) {
                syslog(LOG_ERR, "Credential syncing failed! %s.", strerror(errno));
                close(transfer_socket);
                
                return -1;
            }
            
            bytes_written += actual;
        }
    }
    
    // Give the transfer a few milliseconds to complete before closing
    usleep(5000);
    close(transfer_socket);
    
    return 0;
}
