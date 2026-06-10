/*
 * GP-2 Nios II first smoke test.
 *
 * Purpose: prove the generated Nios subsystem can boot from on-chip memory
 * and print through the JTAG UART. Keep this intentionally tiny; NoC bridge
 * and ReCOP reconfiguration tests come after this passes.
 */

#include <stdio.h>

static void busy_wait(void)
{
    volatile unsigned i;
    for (i = 0; i < 1000000u; i++) {
        /* delay loop */
    }
}

int main(void)
{
    unsigned count = 0;

    printf("\nGP-2 Nios hello world\n");
    printf("Nios is alive; JTAG UART is working.\n");

    while (1) {
        printf("heartbeat %u\n", count++);
        busy_wait();
    }

    return 0;
}
