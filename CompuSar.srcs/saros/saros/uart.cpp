#include "uart.h"

#include <saros/sync/event.h>
#include <saros/saros.h>

#include "irq.h"
#include "p1c1.h"
#include "reg.h"

#include <cstdint>

static constexpr uint32_t DeviceNum = 0;
static constexpr uint32_t RegUartData = 0x0000;
static constexpr uint32_t RegUartStatus = 0x0004;

static constexpr uint32_t UartStatus__TxReady = 0x00000001;
static constexpr uint32_t UartStatus__RxReady = 0x00000002;


static volatile unsigned long *uart = reinterpret_cast<unsigned long *>(0xc000'0000);

void uart_send_raw(char c) {
    reg_write_32( DeviceNum, RegUartData, static_cast<unsigned long>(c) & 0xff );
}

static bool uart_tx_ready() {
    return (reg_read_32( DeviceNum, RegUartStatus ) & UartStatus__TxReady) != 0;
}

static bool uart_rx_ready() {
    return (reg_read_32( DeviceNum, RegUartStatus ) & UartStatus__RxReady) != 0;
}

static P1C1<char, 4096> uartTxBuffer, uartRxBuffer;
static Saros::Sync::Event uartTxReady, uartRxReady;

void handle_uart_tx_ready_irq() {
    while( uart_tx_ready() && !uartTxBuffer.isEmpty() )
        uart_send_raw( uartTxBuffer.consume() );

    if( uartTxBuffer.isEmpty() ) {
        irq_external_mask( IrqExt__UartTxReady ); 
    }
}

void handle_uart_rx_ready_irq() {
    while( uart_rx_ready() && !uartRxBuffer.isFull() )
        uartRxBuffer.produce( reg_read_32( DeviceNum, RegUartData ) );

    uartRxReady.set();

    if( uartRxBuffer.isFull() ) {
        irq_external_mask( IrqExt__UartRxReady ); 
    }
}

void uart_sync_flush_buffer() {
    while( !uartTxBuffer.isEmpty() )
        uart_send_raw( uartTxBuffer.consume() );
}

void uart_sync_message( const char *message ) {
    while( *message ) {
        uart_send_raw(*message);
        message++;
    }
}

void uart_send(char c) {
    if( saros.isRunning() ) {
        while( uartTxBuffer.isFull() )
            wfi();

        uartTxBuffer.produce(c);

        wwb();

        irq_external_unmask( IrqExt__UartTxReady );
    } else {
        uart_send_raw(c);
    }
}

void uart_send(const char *str) {
    while( *str != '\0' ) {
        uart_send(*str);
        ++str;
    }
}

uint32_t uart_recv_char() {
    while( uartRxBuffer.isEmpty() ) {
        uartRxReady.clear();
        uartRxReady.wait();
    }

    uint32_t ret = uartRxBuffer.consume();
    irq_external_unmask( IrqExt__UartRxReady );

    return ret;
}

void uartInit() {
    uartTxReady.set();
    uartRxReady.set();
    irq_external_unmask( IrqExt__UartRxReady );
}
