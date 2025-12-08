#pragma once

#include <cstdint>

void uart_send(char c);
void uart_send(const char *str);

#ifdef SAROS
void uart_send_raw(char c);
void uart_sync_flush_buffer();
void uart_sync_message( const char *message );

static constexpr uint32_t UART_RX_ERROR = 0x80000000, UART_RX_BREAK = 0x100, UART_RX_SPECIAL_MASK = 0xffffff00;
uint32_t uart_recv_char();

void handle_uart_tx_ready_irq();
void handle_uart_rx_ready_irq();

void uartInit();
#endif
