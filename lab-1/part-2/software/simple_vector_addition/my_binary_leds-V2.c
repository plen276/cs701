/*
 * my_binary_leds_V2.c
 *
 *  COMPSYS 701 - March 2026
 *      Author: Morteza
 */

#include <stdio.h>
#include "system.h"
#include "altera_avalon_pio_regs.h"

// Header files added for using high resolution timer
#include "altera_avalon_timer_regs.h"
#include "sys/alt_timestamp.h"


int main()
{
	int i, k, count = 0;
	int Delay_Value = 300000; // Note: This was reduced from 3000000 (in Demo-1) to 3000000
	
	unsigned int timestamp_start_time, timestamp_end_time;
	unsigned int timestamp_overhead_time, T1, T2;
	int To_Measure = 0;

	printf("This is a simple binary counter displayed on LEDs.\n");
	printf("This program use high resolution timer for performance measurement.\n");

	if (alt_timestamp_start() < 0) {
		    printf ("No timestamp device is available.\n");
	}
	else
	{
		To_Measure = 1;
		for (k = 0; k < 25; k++) {  // counts 0 to 24
			IOWR_ALTERA_AVALON_PIO_DATA(LED_PIO_BASE, count);
			
			// Measure the number of cycles for the delay loop (only in the first iteration)
			if (To_Measure) {
				// Sample the timestamp timer (for start time)
				timestamp_start_time = alt_timestamp();
			}
			// Delay for sometime
			for (i = 0; i < Delay_Value; i++) {
				;
			}
			if (To_Measure) {
				// Sample the timestamp timer (for end time)
				timestamp_end_time = alt_timestamp();
				To_Measure = 0;
			} 
			printf("%d,", count);
			count++;
		}
		printf("\n\n");
		
		// Measure the time overhead to read the timestamp timer by subsequently
		// calling alt_timestamp() back to back.
		T1 = alt_timestamp();
		T2 = alt_timestamp();
		timestamp_overhead_time = T2 - T1;
		
		// Print-out the Timestamp interval timer peripheral measurements.
		printf("timestamp_start_time = %u ticks\n",
					           (unsigned int) (timestamp_start_time));
		printf("timestamp_end_time = %u ticks\n\n",
							           (unsigned int) (timestamp_end_time));
		printf("timestamp measurement = %u ticks\n",
			           (unsigned int) (timestamp_end_time - timestamp_start_time));
		printf("timestamp measurement overhead = %u ticks\n",
			           (unsigned int) (timestamp_overhead_time));
		printf("Actual time  = %u ticks\n",
			           (unsigned int) ((timestamp_end_time - timestamp_start_time) -
			           timestamp_overhead_time));
		printf("Timestamp timer frequency = %u\n",
			           (unsigned int)alt_timestamp_freq());
	}
	return 0;
}


