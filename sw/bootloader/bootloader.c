#include <stdint.h>

#define REG_LEDS 		(*(volatile uint32_t*)0x10000000)
#define REG_UART_CLKDIV (*(volatile uint32_t*)0x20000004)
#define REG_UART_DATA 	(*(volatile uint32_t*)0x20000008)

#define APP_BASE 0x00000800 // User program memory address

// Non-blocking UART read function
int32_t uart_getc_nonblock(void) {
    return (int32_t)REG_UART_DATA;
}

// Blocking UART read function
uint8_t uart_getc(void) {
    int32_t c;
    while ((c = (int32_t)REG_UART_DATA) == -1);
    return (uint8_t)c;
}

void main(void) {
    REG_UART_CLKDIV = 868;
    REG_LEDS = 0x5555;

    puts("\r\nPicoRV32-SoC Bootloader. Press 'u' to upload a program...\r\n");

    // Wait ~2s wating 'u'
    int upload_mode = 0;
    for (int i = 0; i < 2000000; i++) {
        if (uart_getc_nonblock() == 'u') {
            upload_mode = 1;
            break;
        }
    }

    if (upload_mode) {
        puts("READY\n");

        // First read binary size
        uint32_t size = 0;
        size |= ((uint32_t)uart_getc()) << 0;
        size |= ((uint32_t)uart_getc()) << 8;
        size |= ((uint32_t)uart_getc()) << 16;
        size |= ((uint32_t)uart_getc()) << 24;

        // Write bytes to BRAM starting from APP_BASE address
        volatile uint8_t *ram = (volatile uint8_t*)APP_BASE;
        for (uint32_t i = 0; i < size; i++) {
            ram[i] = uart_getc();
            // Show progress on LEDs
            if ((i & 0xFF) == 0) REG_LEDS = (i >> 8);
        }

        puts("OK\r\nRunning program...\r\n\r\n");
    }

    // Finally, call APP_BASE address as a C function
    void (*app_entry)(void) = (void (*)(void))APP_BASE;
    app_entry();
}