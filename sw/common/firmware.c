#include <stdint.h>

#define REG_LEDS 		(*(volatile uint32_t*)0x10000000)
#define REG_UART_CLKDIV (*(volatile uint32_t*)0x20000004)
#define REG_UART_DATA 	(*(volatile uint32_t*)0x20000008)

void putc(char c)
{
    if (c == '\n') {
        REG_UART_DATA = '\r';
    }
    // Hardware automatically stalls CPU via mem_ready until TX buffer accepts byte
    REG_UART_DATA = c;
}

void puts(const char *s)
{
	while (*s) putc(*s++);
}

void *memcpy(void *dest, const void *src, int n)
{
	while (n) {
		n--;
		((char*)dest)[n] = ((char*)src)[n];
	}
	return dest;
}

// Simple delay loop
void delay(volatile uint32_t count)
{
    while (count--) {
        __asm__ volatile("");
    }
}

void main(void)
{
    // Set UART baud rate: 100 MHz / 115200 baud = 868
    REG_UART_CLKDIV = 868;
    puts("\r\n");
    puts("==================================================\r\n");
    puts("  PicoRV32 RV32I Running on Digilent Nexys A7-100T\r\n");
    puts("==================================================\r\n");
    puts("CPU started successfully. Running LED counter...\r\n\r\n");
    uint32_t counter = 0;
    while (1) {
        // Output bottom 15 bits to the 15 user LEDs
        REG_LEDS = counter & 0x7FFF;
        // Print a periodic heartbeat over serial every 16 iterations
        if ((counter & 0x0F) == 0) {
            puts("[PicoRV32 Heartbeat] Counter = ");
            // Print simple hex digit
            char hex_char = "0123456789ABCDEF"[(counter >> 4) & 0x0F];
            putc(hex_char);
            puts("\r\n");
        }
        counter++;
        delay(250000); // Visual delay on real FPGA (~250ms at 100MHz)
    }
}
