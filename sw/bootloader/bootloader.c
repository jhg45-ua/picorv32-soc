#include "../common/io.h"

#define APP_BASE 0x00000800

static void self_test(void) {
    puts("\r\n[BOOT] PicoRV32 SoC Initialized\r\n");

    // Test LEDs
    REG_LEDS = 0x00FF;
    delay(100);
    REG_LEDS = 0x7F00;
    delay(100);

    // Test RAM
    volatile uint32_t *ram_test = (volatile uint32_t *)APP_BASE;
    *ram_test = 0xA5A55A5A;
    if (*ram_test == 0xA5A55A5A) {
        puts("[BOOT] RAM test passed\r\n");
    } else {
        puts("[BOOT] RAM test failed\r\n");
    }

    // Leave LEDs on to indicate bootloader is ready
    REG_LEDS = 0x5555;
}

void main(void) {
    REG_UART_CLKDIV = 868;
    REG_LEDS = 0x5555;
    
    // Run self-test to ensure the bootloader is functioning correctly
    self_test();

    puts("READY\n");
    
    uint32_t size = 0;
    for (int i = 0; i < 32; i += 8)
        size |= (uint32_t)uart_getc() << i;
    
    volatile uint8_t *ram = (volatile uint8_t *)APP_BASE;
    for (uint32_t i = 0; i < size; i++)
        ram[i] = uart_getc();
    
    ((void (*)(void))APP_BASE)();   // salta a la app
}