#include <stdio.h>
#include "system.h"
#include "altera_avalon_pio_regs.h"

/*
 * Active-low 7-segment encoding for digits 0-9.
 * Bits: 6=middle  5=top-left  4=bot-left  3=bottom  2=bot-right  1=top-right  0=top
 * 0 = segment ON, 1 = segment OFF
*/
static const int seg7[] = {
    0b1000000, /* 0 */
    0b1111001, /* 1 */
    0b0100100, /* 2 */
    0b0110000, /* 3 */
    0b0011001, /* 4 */
    0b0010010, /* 5 */
    0b0000010, /* 6 */
    0b1111000, /* 7 */
    0b0000000, /* 8 */
    0b0010000  /* 9 */
};

int main()
{
    int i, count = 0;
    int delay = 300000;

    IOWR_ALTERA_AVALON_PIO_DATA(HEX3_PIO_BASE, seg7[7]); /* HEX5 on board */
    IOWR_ALTERA_AVALON_PIO_DATA(HEX2_PIO_BASE, seg7[6]); /* HEX4 on board */

    printf("Binary counter 00-99 on LEDs and seven-segment displays.\n");

    while (1) {
        // Binary value on Red LEDs
        IOWR_ALTERA_AVALON_PIO_DATA(LED_PIO_BASE, count);

        // Decimal count: ones on HEX0, tens on HEX1
        IOWR_ALTERA_AVALON_PIO_DATA(HEX0_PIO_BASE, seg7[count % 10]);
        IOWR_ALTERA_AVALON_PIO_DATA(HEX1_PIO_BASE, seg7[count / 10]);

        for (i = 0; i < delay; i++) {
            ;
        }

        count++;
        if (count > 99) count = 0;
    }

    return 0;
}
