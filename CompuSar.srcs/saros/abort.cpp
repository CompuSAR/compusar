#include <abort.h>

#include <saros/csr.h>

#include <irq.h>
#include <uart.h>
#include <format.h>

using namespace Saros;

void _abortWithMessage( const char *message, const char *file, int line ) {
    // Disable interrupts
    csr_read_clr_bits<CSR::mstatus>(MSTATUS__MIE);

    uart_sync_flush_buffer();

    uart_sync_message("ABORT: ");
    uart_sync_message(file);
    uart_sync_message(":");
    print_dec(line, true);
    uart_sync_message(" ");
    uart_sync_message(message);
    uart_sync_message("\n");

    asm("ebreak");
    halt();
}

void _assertWithMessage( bool condition, const char *message, const char *file, int line ) {
    if( !condition )
        _abortWithMessage(message, file, line);
}

void _checkWithMessage( bool condition, const char *message, const char *file, int line  ) {
    if( !condition )
        _abortWithMessage(message, file, line);
}
