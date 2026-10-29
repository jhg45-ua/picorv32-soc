#include "../common/io.h"

#define APP_BASE 0x00000800

void main(void) {
    REG_UART_CLKDIV = 868;
    REG_LEDS = 0x5555;
    
    puts("READY\n");
    
    uint32_t size = 0;
    for (int i = 0; i < 32; i += 8)
        size |= (uint32_t)uart_getc() << i;
    
    volatile uint8_t *ram = (volatile uint8_t *)APP_BASE;
    for (uint32_t i = 0; i < size; i++)
        ram[i] = uart_getc();
    
    ((void (*)(void))APP_BASE)();   // salta a la app
}