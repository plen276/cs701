// avg_ref.c
// Reference software model for AVG-ASP moving-average behaviour.

#include <stdint.h>
#include <stdbool.h>

#define MAX_L 16

typedef struct {
    int16_t window[MAX_L];
    int32_t sum;
    int count;
    int index;
    int L;
    int shift;
    bool bypass;
} AvgRef;

void avg_init(AvgRef *avg, int mode) {
    avg->sum = 0;
    avg->count = 0;
    avg->index = 0;
    avg->bypass = false;

    for (int i = 0; i < MAX_L; i++) {
        avg->window[i] = 0;
    }

    switch (mode) {
        case 0: avg->bypass = true; avg->L = 1;  avg->shift = 0; break;
        case 1: avg->L = 4;  avg->shift = 2; break;
        case 2: avg->L = 8;  avg->shift = 3; break;
        case 3: avg->L = 16; avg->shift = 4; break;
        default: avg->bypass = true; avg->L = 1; avg->shift = 0; break;
    }
}

// Returns true when output is valid.
// During WARMUP, returns false.
bool avg_process_sample(AvgRef *avg, int16_t x, int16_t *y) {
    if (avg->bypass) {
        *y = x;
        return true;
    }

    int16_t old = avg->window[avg->index];

    avg->window[avg->index] = x;
    avg->index = (avg->index + 1) % avg->L;

    if (avg->count < avg->L) {
        avg->sum += x;
        avg->count++;

        if (avg->count < avg->L) {
            return false;
        }

        *y = (int16_t)(avg->sum >> avg->shift);
        return true;
    }

    avg->sum += x - old;
    *y = (int16_t)(avg->sum >> avg->shift);
    return true;
}
