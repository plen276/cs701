#include <stdio.h>
#include "system.h"
#include "altera_avalon_pio_regs.h"
#include "altera_avalon_timer_regs.h"
#include "sys/alt_timestamp.h"

#define N 8

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

/* OP codes matching SW1:SW0 */
#define OP_MIN  0
#define OP_ADD  1
#define OP_SUB  2
#define OP_MUL  3

static int A[N][N];
static int B[N][N];
static int C[N][N];

void Matrix_Operations(int *A, int *B, int *C, int OP) {
    int i, j, k;
    for (i = 0; i < N; i++) {
        for (j = 0; j < N; j++) {
            int a = A[i * N + j];
            int b = B[i * N + j];
            switch (OP) {
                case OP_MIN:
                    C[i * N + j] = (a < b) ? a : b;
                    break;
                case OP_ADD:
                    C[i * N + j] = a + b;
                    break;
                case OP_SUB:
                    C[i * N + j] = a - b;
                    break;
                case OP_MUL:
                    C[i * N + j] = 0;
                    for (k = 0; k < N; k++) {
                        C[i * N + j] += A[i * N + k] * B[k * N + j];
                    }
                    break;
            }
        }
    }
}

int main() {
    // Read SW1:SW0 (bits 1 downto 0)
    int sw = IORD_ALTERA_AVALON_PIO_DATA(SWITCH_PIO_BASE);
    int sw0 = (sw >> 0) & 1;
    int sw1 = (sw >> 1) & 1;

    int op = (sw1 << 1) | sw0;

    // Light LED0 for SW0, LED1 for SW1
    IOWR_ALTERA_AVALON_PIO_DATA(LED_PIO_BASE, op);

    IOWR_ALTERA_AVALON_PIO_DATA(HEX0_PIO_BASE, 0b1111111);
    IOWR_ALTERA_AVALON_PIO_DATA(HEX1_PIO_BASE, 0b1111111);

    IOWR_ALTERA_AVALON_PIO_DATA(HEX2_PIO_BASE, seg7[sw0]);
    IOWR_ALTERA_AVALON_PIO_DATA(HEX3_PIO_BASE, seg7[sw1]);

    // Determine operation name
    const char *op_name;
    switch (op) {
        case OP_MIN: op_name = "Minimum Value";    break;
        case OP_ADD: op_name = "Addition";         break;
        case OP_SUB: op_name = "Subtraction";      break;
        case OP_MUL: op_name = "Multiplication";   break;
        default:     op_name = "Unknown";          break;
    }

    // Startup messages
    printf("This application performs NxN matrix operations.\n");
    printf("N is %d, the operation is %s.\n", N, op_name);

    /* Validate N */
    if (N < 2) {
        printf("Error: N must be at least 2. Program terminated.\n");
        return 1;
    }

    // Initialise matrices A and B, zero out C
    int i, j;
    for (i = 0; i < N; i++) {
        for (j = 0; j < N; j++) {
            A[i][j] = i * N + j + 1;
            B[i][j] = (i - j) * 3;
            C[i][j] = 0;
        }
    }

    if (alt_timestamp_start() < 0) {
        printf("No timestamp device available.\n");
        return 1;
    }

    // Measure overhead of calling alt_timestamp() back-to-back
    unsigned int t1 = alt_timestamp();
    unsigned int t2 = alt_timestamp();
    unsigned int overhead = t2 - t1;

    // Time Matrix_Operations
    unsigned int start = alt_timestamp();
    Matrix_Operations((int *)A, (int *)B, (int *)C, op);
    unsigned int end = alt_timestamp();

    unsigned int elapsed = (end - start) - overhead;
    printf("Execution time = %u ticks\n", elapsed);
    printf("Timestamp frequency = %u Hz\n", (unsigned int)alt_timestamp_freq());

    return 0;
}
