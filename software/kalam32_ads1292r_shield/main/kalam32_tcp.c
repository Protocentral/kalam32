#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "esp_wifi.h"
#include "esp_system.h"
#include "esp_event.h"
#include "esp_event_loop.h"
#include "nvs_flash.h"
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "driver/ledc.h"
#include "driver/i2c.h"
#include "driver/uart.h"
#include <sys/socket.h>

#include "esp_log.h"
#include "kalam32_config.h"
#include "ads1292r.h"

/*********************** START TCP Server Code *****************/

int connectedflag = 0;
int total_data = 0;


/*socket*/
static int server_socket = 0;
static struct sockaddr_in server_addr;
static struct sockaddr_in client_addr;
static unsigned int socklen = sizeof(client_addr);
static int connect_socket = 0;

#define PACK_BYTE_IS 100
#define TAG "kalam32:"

extern bool ads1292dataReceived;
extern char DataPacketHeader[16];

//send data
void send_data(void *pvParameters)
{
    int len = 0;
    uint8_t* db;
    char databuff[DEFAULT_PKTSIZE];
    memset(databuff, PACK_BYTE_IS, DEFAULT_PKTSIZE);
    db=&databuff;
    vTaskDelay(100/portTICK_RATE_MS);
    ESP_LOGI(TAG, "start sending...");

    while(1)
    {
        ads1292r_read_into_buffer();

        if(true==ads1292dataReceived)
        {
        	  len = send(connect_socket, DataPacketHeader, 15, 0);
            //vTaskDelay(1/portTICK_RATE_MS);
            ads1292dataReceived = false;
        }
    }
}

char* tcpip_get_reason(int err)
{
    switch (err) {
	case 0:
	    return "reason: other reason";
	case ENOMEM:
	    return "reason: out of memory";
	case ENOBUFS:
	    return "reason: buffer error";
	case EWOULDBLOCK:
	    return "reason: timeout, try again";
	case EHOSTUNREACH:
	    return "reason: routing problem";
	case EINPROGRESS:
	    return "reason: operation in progress";
	case EINVAL:
	    return "reason: invalid value";
	case EADDRINUSE:
	    return "reason: address in use";
	case EALREADY:
	    return "reason: conn already connected";
	case EISCONN:
	    return "reason: conn already established";
	case ECONNABORTED:
	    return "reason: connection aborted";
	case ECONNRESET:
	    return "reason: connection is reset";
	case ENOTCONN:
	    return "reason: connection closed";
	case EIO:
	    return "reason: invalid argument";
	case -1:
	    return "reason: low level netif error";
	default:
	    return "reason not found";
    }
}

int show_socket_error_code(int socket)
{
    int result;
    u32_t optlen = sizeof(int);
    getsockopt(socket, SOL_SOCKET, SO_ERROR, &result, &optlen);
    ESP_LOGI(TAG, "socket error %d reason: %s", result, tcpip_get_reason(result));
    return result;
}

int check_socket_error_code()
{
    int ret;
#if ESP_TCP_MODE_SERVER
    ESP_LOGI(TAG, "check server_socket");
    ret = show_socket_error_code(server_socket);
    if(ret == ECONNRESET)
	return ret;
#endif
    ESP_LOGI(TAG, "check connect_socket");
    ret = show_socket_error_code(connect_socket);
    if(ret == ECONNRESET)
	return ret;
    return 0;
}

void close_socket()
{
    close(connect_socket);
    close(server_socket);
}

//use this esp32 as a tcp server. return ESP_OK:success ESP_FAIL:error
esp_err_t create_tcp_server()
{
    ESP_LOGI(TAG, "server socket....port=%d\n", DEFAULT_PORT);
    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket < 0)
    {
    	 show_socket_error_code(server_socket);
	     return ESP_FAIL;
    }
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(DEFAULT_PORT);
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(server_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0)
    {
    	 show_socket_error_code(server_socket);
	     close(server_socket);
	      return ESP_FAIL;
    }
    if (listen(server_socket, 5) < 0)
    {
    	  show_socket_error_code(server_socket);
	      close(server_socket);
	      return ESP_FAIL;
    }

    connect_socket = accept(server_socket, (struct sockaddr*)&client_addr, &socklen);
    if (connect_socket<0)
    {
    	  show_socket_error_code(connect_socket);
	      close(server_socket);
	      return ESP_FAIL;
    }
    /*connection established，now can send/recv*/
    ESP_LOGI(TAG, "tcp connection established!");
    return ESP_OK;
}

//this task establish a TCP connection and receive data from TCP
static void tcp_conn(void *pvParameters)
{
    ESP_LOGI(TAG, "task tcp_conn start.");

    /*create tcp socket*/
    int socket_ret;

    vTaskDelay(3000 / portTICK_RATE_MS);

    ESP_LOGI(TAG, "create_tcp_server.");
    socket_ret=create_tcp_server();
    if(ESP_FAIL == socket_ret)
    {
    	ESP_LOGI(TAG, "create tcp socket error,stop.");
    	vTaskDelete(NULL);
    }

    /*create a task to tx/rx data*/
    TaskHandle_t tx_rx_task;

    xTaskCreate(&send_data, "send_data", 4096, NULL, 4, &tx_rx_task);

    while (1)
    {
      	vTaskDelay(3000 / portTICK_RATE_MS);//every 3s
  	    int err_ret = check_socket_error_code();
  	    if (err_ret == ECONNRESET)
        {
      		ESP_LOGI(TAG, "disconnected... stop.");
          close_socket();
          socket_ret=create_tcp_server();
          //break;
  	    }
    }

    close_socket();
    vTaskDelete(tx_rx_task);
    vTaskDelete(NULL);
}

void kalam32_tcp_server_start(void)
{
    xTaskCreate(&tcp_conn, "tcp_conn", 4096, NULL, 5, NULL);
}
