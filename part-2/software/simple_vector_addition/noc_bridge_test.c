/*
 * noc_bridge_test.c
 *
 * COMPSYS 701 GP2 - Nios II <-> TDMA-MIN NoC bridge bring-up test.
 *
 * Standalone loopback check for the noc_avalon_bridge component:
 * the top level loops the bridge's send conduit back into its recv
 * conduit, so every 32-bit word written to the TX register must come
 * back unchanged on the RX register. A "new packet" is detected via
 * the free-running 8-bit receive counter in STATUS (never lost).
 *
 * Prereqs:
 *   - Add noc_avalon_bridge to the Qsys system, connect its Avalon
 *     slave to the Nios data master, clock/reset to the system, and
 *     export the conduit as "noc". Name the instance "noc_bridge"
 *     so the BSP defines NOC_BRIDGE_BASE (otherwise edit the macro).
 *   - Regenerate the BSP after changing the system.
 *
 * Register map (byte offsets):
 *   0x0 W TX     : 32-bit packet to send (bit 31 must be 1 = valid)
 *   0x4 R RX     : last received packet
 *   0x8 R STATUS : bit0 = rx_valid, bits[15:8] = rx_count
 */

#include <stdio.h>
#include "system.h"
#include "io.h"
#include "alt_types.h"

#ifndef NOC_BRIDGE_BASE
/* If you named the Qsys instance differently, set its base here, e.g.
 * #define NOC_BRIDGE_BASE NOC_AVALON_BRIDGE_0_BASE */
#error "NOC_BRIDGE_BASE not found: name the bridge instance 'noc_bridge' in Platform Designer, or define NOC_BRIDGE_BASE here."
#endif

#define NOC_REG_TX      0x0
#define NOC_REG_RX      0x4
#define NOC_REG_STATUS  0x8

static void     noc_send(alt_u32 pkt)   { IOWR_32DIRECT(NOC_BRIDGE_BASE, NOC_REG_TX, pkt); }
static alt_u32  noc_rx(void)            { return IORD_32DIRECT(NOC_BRIDGE_BASE, NOC_REG_RX); }
static alt_u32  noc_status(void)        { return IORD_32DIRECT(NOC_BRIDGE_BASE, NOC_REG_STATUS); }
static alt_u32  noc_rx_count(void)      { return (noc_status() >> 8) & 0xFF; }

int main(void)
{
    /* All test packets have bit 31 = 1 (the NoC "valid" bit). */
    const alt_u32 tests[] = { 0x80000000u, 0x8ABCDEF0u, 0x93400040u, 0xA12E0044u };
    const int     N = (int)(sizeof(tests) / sizeof(tests[0]));
    int  i, spin, pass = 0;
    alt_u32 cnt0, rx;

    printf("\n=== NoC bridge loopback self-test ===\n");

    for (i = 0; i < N; i++) {
        cnt0 = noc_rx_count();
        noc_send(tests[i]);

        /* Loopback returns within a few cycles; bound the wait. */
        for (spin = 0; spin < 100000; spin++) {
            if (noc_rx_count() != cnt0) break;
        }

        rx = noc_rx();
        if (rx == tests[i]) {
            printf("  [%d] TX=0x%08X  RX=0x%08X  PASS\n",
                   i, (unsigned)tests[i], (unsigned)rx);
            pass++;
        } else {
            printf("  [%d] TX=0x%08X  RX=0x%08X  FAIL\n",
                   i, (unsigned)tests[i], (unsigned)rx);
        }
    }

    printf("Result: %d/%d packets looped back correctly.\n", pass, N);
    return 0;
}
