#include "uart.h"
#include "irq.h"
#include "format.h"

#include <saros/kernel/timer.h>
#include <saros/kernel/thread_stack.h>
#include <saros/fs/filesystem.h>

#include "assets/logo.hpp"
#include "display.h"
#include "gpio.h"
#include "sd.h"

#include <saros/csr.h>
#include <saros/saros.h>
#include <8bit_hook.h>

extern void startup_function(void *) noexcept;
extern "C" void (*__init_array_start[])();
extern "C" void (*__init_array_end)();

extern "C"
int saros_main() {
    // Run "pre main" functions
    for( auto ptr = __init_array_start; ptr != &__init_array_end; ++ptr )
        (*ptr)();

    uart_send("Second stage!\n");

    saros.init(std::span<Saros::Kernel::ThreadStack>( Saros::Kernel::__thread_stacks_start, &Saros::Kernel::__thread_stacks_end ));
    saros.run( startup_function, nullptr, "Startup thread"_fs );
    uart_send("Saros exit\n");

    halt();
}

void logoCrawl(void *) noexcept {
    static constexpr uint16_t WIDTH = 640, HEIGHT = 480;
    uint16_t x=120, y=17;
    int dirx = 1, diry = 1;

    Display::setDisplay(Bitmaps::logo, x, y);
    reset_gpio_bits(0, GPO0__DISPLAY32_RESET | GPO0__DDR_RESET);

    irq_external_unmask( IrqExt__Vsync );

    while(true) {
        x+=dirx;
        y+=diry;

        if( x==WIDTH - Bitmaps::logo.width )
            dirx = -1;
        if( x==0 )
            dirx = 1;
        if( y==HEIGHT - Bitmaps::logo.height )
            diry = -1;
        if( y==0 )
            diry = 1;

        Display::vsyncSignal.wait();

        Display::setDisplay(Bitmaps::logo, x, y);
    }
}

void startup_function(void *) noexcept {
    uart_send("Point 1\n");
    SD::init();
    uart_send("Point 2\n");

    saros.createThread( logoCrawl, nullptr, "Logo crawl"_fs );
    uart_send("Point 3\n");
    start_8bit();
}

void  __attribute__((weak)) start_8bit() {
    uart_send("8bit 1\n");
    while( !fs ) {
        fsChanged.wait();
    }
    uart_send("8bit 2\n");
    auto rootDir = fs->getRootDir();
    uart_send("8bit 3\n");
    for( auto dirEntry : rootDir ) {
        if( dirEntry.dirAttr == FAT::Directory::DirEntry::AttributeLongName )
            continue;

        if( dirEntry.dirName[8]=='T' && dirEntry.dirName[9]=='X' && dirEntry.dirName[10]=='T' ) {
            uart_send("Dumping content of ");
            for(unsigned i = 0; i<8; ++i) {
                uart_send(static_cast<char>(dirEntry.dirName[i]));
            }
            uart_send('.');
            for(unsigned i = 8; i<11; ++i) {
                uart_send(static_cast<char>(dirEntry.dirName[i]));
            }
            uart_send(":\n");

            FAT::File textFile( dirEntry, *fs );
            SD::BlockPtr data;
            size_t blockFill = textFile.readBlock(data);
            while( blockFill!=0 ) {
                for( unsigned i=0; i<blockFill; ++i ) {
                    uart_send( static_cast<char>( data->data[i] ) );
                }

                blockFill = textFile.readBlock(data);
            }

            uart_send("\n\n");
        }
    }
}
