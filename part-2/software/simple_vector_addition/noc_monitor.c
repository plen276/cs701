/*
 * noc_monitor.c
 *
 * COMPSYS 701 GP2 - Nios II monitor node (NoC port 5).
 *
 * Role: passive monitor + output. The Nios sits on NoC port 5 via the
 * noc_avalon_bridge and prints every packet routed to it (e.g. COR
 * correlation results, or PD peak/period results) over the JTAG-UART.
 * It owns no board pins and only touches the NoC, so a misbehaving
 * ReCOP/ASP cannot disturb it - it simply reports what it receives.
 *
 * Packet decode (project Data format, type = bits[31:28] = 1000):
 *   - PD results encode a 2-bit kind tag in bits[27:26]:
 *       01 = global max, 10 = global min, 11 = time-between-peaks
 *   - other Data packets (e.g. from COR) carry their value in [15:0]
 *     and a routing dest in [27:24].
 * The value [15:0] is treated as signed 16-bit.
 *
 * Build: include ONLY this file in the app (remove noc_bridge_test.c
 * so there is a single main()). Name the Qsys bridge instance
 * "noc_bridge" so the BSP defines NOC_BRIDGE_BASE.
 *
 * Register map (byte offsets): 0x4 read RX, 0x8 read STATUS
 *   STATUS: bit0 = rx_valid, bits[15:8] = rx_count (free-running).
 */

#include <stdio.h>
#include "system.h"
#include "io.h"
#include "alt_types.h"

#ifndef NOC_BRIDGE_BASE
#error "NOC_BRIDGE_BASE not found: name the bridge instance 'noc_bridge' in Platform Designer, or define NOC_BRIDGE_BASE here."
#endif

#define NOC_REG_RX      0x4
#define NOC_REG_STATUS  0x8

static alt_u32 noc_status(void)   { return IORD_32DIRECT(NOC_BRIDGE_BASE, NOC_REG_STATUS); }
static alt_u32 noc_rx(void)       { return IORD_32DIRECT(NOC_BRIDGE_BASE, NOC_REG_RX); }
static alt_u32 noc_rx_count(void) { return (noc_status() >> 8) & 0xFF; }

static void decode(alt_u32 pkt)
{
    alt_u8  ptype = (alt_u8)((pkt >> 28) & 0xF);
    alt_u8  tag   = (alt_u8)((pkt >> 26) & 0x3);
    alt_16  val   = (alt_16)(pkt & 0xFFFF);   /* signed 16-bit payload */

    if (ptype == 0x8) {           /* Data packet */
        switch (tag) {
            case 0x1: printf("  PD max   = %d\n", (int)val); break;
            case 0x2: printf("  PD min   = %d\n", (int)val); break;
            case 0x3: printf("  PD period= %d  (freq ~ Fs/period)\n", (int)val); break;
            default:  printf("  DATA val = %d (0x%04X)\n", (int)val, (unsigned)(pkt & 0xFFFF)); break;
        }
    } else {
        printf("  raw=0x%08X type=0x%X val=%d\n",
               (unsigned)pkt, ptype, (int)val);
    }
}

int main(void)
{
    alt_u32 last, cur, pkt;

    printf("\n=== Nios NoC monitor (port 5) ===\n");
    printf("Waiting for packets routed to the Nios...\n");

    last = noc_rx_count();
    for (;;) {
        cur = noc_rx_count();
        if (cur != last) {
            last = cur;
            pkt  = noc_rx();
            decode(pkt);
        }
    }
    return 0;   /* not reached */
}
