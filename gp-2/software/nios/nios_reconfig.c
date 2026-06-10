/*
 * GP-2 Nios II application -- meets the W7 / R1 / R8 requirements.
 *
 * Role of Nios II (the non-critical support processor): reprogram the ReCOP
 * critical part's PROGRAM MEMORY at runtime, over the TDMA-MIN NoC, via the
 * reconfig node -- the spec's "change of program object code of critical part."
 * Each Conf-Prog reconfiguration packet is built by a CUSTOM Nios II
 * INSTRUCTION (confprog_build, R8). The JTAG UART is the debug/status channel.
 *
 * Sequence:
 *   1. Hold ReCOP in reset (recop_reset PIO) so it does not fetch while PM
 *      is being rewritten. (The NoC + reconfig node stay live -- only ReCOP
 *      is held -- so the packets we send still reach the reconfig node.)
 *   2. SET_ADDR 0x000, then stream a small ReCOP program as WRITE_WORD
 *      packets to the reconfig node. Every packet is built by the custom instr.
 *   3. Release ReCOP -> it boots the Nios-supplied program (HEX then echoes
 *      the board switches, SW[9:0]).
 *   4. Heartbeat / status over the JTAG UART.
 *
 * >>> Verify these names against your generated system.h before building:
 *       NOC_BRIDGE_BASE          (bridge instance was "noc_bridge")
 *       RECOP_RESET_PIO_BASE     (PIO instance was "recop_reset_pio")
 *       ALT_CI_<confprog_build>  (CIName was "u_confprog_build" -> likely
 *                                 ALT_CI_U_CONFPROG_BUILD; grep system.h)
 */

#include <stdio.h>
#include "system.h"
#include "io.h"                       /* IORD / IOWR */
#include "altera_avalon_pio_regs.h"   /* IOWR_ALTERA_AVALON_PIO_DATA */

/* --- adjust to match system.h if your instance names differ --- */
#define CONFPROG_BUILD(sub, payload) ALT_CI_U_CONFPROG_BUILD((sub), (payload))

/* noc_avalon_bridge register map (word addresses): 0 = TX, 1 = RX, 2 = STATUS */
#define BRIDGE_TX 0

/* Conf-Prog sub-commands (must match reconfig_node.vhd) */
#define SUB_SET_ADDR   1
#define SUB_WRITE_WORD 2

/*
 * ReCOP program for Nios to load at PM word 0: continuously echo the board
 * switches onto HEX. Shows Nios loaded a real program that reads the board
 * ($FF0 = switches) and drives it ($FF3 = HEX) -- not a baked constant.
 *   0x8010 0x0FF0   LDR R1 $0xFF0     (R1 = switches, MMIO read)
 *   0x8201 0x0FF3   STR R1 $0xFF3     (HEX = switches)
 *   0x5800 0x0000   JMP 0x0000        (loop)
 */
static const unsigned short recop_prog[] = {
    0x8010, 0x0FF0,
    0x8201, 0x0FF3,
    0x5800, 0x0000
};
#define PROG_WORDS (sizeof(recop_prog) / sizeof(recop_prog[0]))

static void busy_wait(unsigned n)
{
    volatile unsigned i;
    for (i = 0; i < n; i++) {
        /* delay loop (no system timer in this Qsys system) */
    }
}

/* Push one 32-bit packet onto NoC port 5 via the bridge TX register. */
static void send_packet(unsigned int pkt)
{
    IOWR(NOC_BRIDGE_BASE, BRIDGE_TX, pkt);
    busy_wait(2000);   /* space packets so the NoC delivers each before the next */
}

int main(void)
{
    unsigned count = 0;
    unsigned i;

    printf("\nGP-2 Nios: reprogramming ReCOP critical part over the NoC\n");

    /* 1. Hold ReCOP in reset while we rewrite its program memory. */
    IOWR_ALTERA_AVALON_PIO_DATA(RECOP_RESET_PIO_BASE, 1);

    /* 2. Position the write pointer, then stream the program. Each packet is
     *    built by the custom instruction (R8). */
    send_packet(CONFPROG_BUILD(SUB_SET_ADDR, 0x0000));
    for (i = 0; i < PROG_WORDS; i++)
        send_packet(CONFPROG_BUILD(SUB_WRITE_WORD, recop_prog[i]));

    /* 3. Release ReCOP -> it boots the program we just wrote. */
    IOWR_ALTERA_AVALON_PIO_DATA(RECOP_RESET_PIO_BASE, 0);
    printf("Reload done; ReCOP HEX now echoes the board switches (SW[9:0]).\n");

    /* 4. Heartbeat / status over the JTAG UART. */
    while (1) {
        printf("nios alive %u\n", count++);
        busy_wait(1000000);
    }

    return 0;
}
