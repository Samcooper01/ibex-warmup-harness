/* The power workload: a short program that exercises every part of Ibex. It is compiled twice, for the
 * core (with start.S and link.ld) and for the machine that builds the activity file, and both runs must
 * print the same checksum, so a correct simulation is confirmed before its activity is used.
 *
 *   crc32       shifts, exclusive-or and branches over a buffer
 *   matmul      a 12 by 12 integer matrix multiply: multiplies, loads and stores
 *   sort        an insertion sort: compares, branches and memory traffic
 *   divide      a loop of divides and remainders
 *
 * On the core, the testbench measures activity between the two marker writes (MARK_START, MARK_END) and
 * stops at the write of the checksum (RESULT). */
#include <stdint.h>

#define N 12
#define BUF 256

static uint32_t mat_a[N][N], mat_b[N][N], mat_c[N][N];
static uint8_t buf[BUF];
static int32_t arr[64];

/* a small pseudo-random sequence, so the data is fixed and the same on every run */
static uint32_t lcg_state = 12345u;
static uint32_t lcg(void) { lcg_state = lcg_state * 1103515245u + 12345u; return lcg_state >> 8; }

static uint32_t crc32(const uint8_t *p, int n) {
    uint32_t c = 0xffffffffu;
    for (int i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
    }
    return ~c;
}

static uint32_t matmul(void) {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            uint32_t s = 0;
            for (int k = 0; k < N; k++) s += mat_a[i][k] * mat_b[k][j];
            mat_c[i][j] = s;
        }
    uint32_t h = 0;
    for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) h = h * 31u + mat_c[i][j];
    return h;
}

static uint32_t sort(void) {
    for (int i = 1; i < 64; i++) {
        int32_t v = arr[i]; int j = i - 1;
        while (j >= 0 && arr[j] > v) { arr[j + 1] = arr[j]; j--; }
        arr[j + 1] = v;
    }
    uint32_t h = 0;
    for (int i = 0; i < 64; i++) h = h * 33u + (uint32_t)arr[i];
    return h;
}

static uint32_t divide(void) {
    uint32_t h = 0;
    for (int i = 1; i <= 48; i++) {
        uint32_t a = lcg() | 1u, b = (lcg() & 0xffffu) | 1u;
        int32_t sa = (int32_t)lcg(), sb = (int32_t)((lcg() & 0x7fffu) | 1u);
        h += a / b + a % b + (uint32_t)(sa / sb) + (uint32_t)(sa % sb);
    }
    return h;
}

/* fill the inputs before the measured window */
static void setup(void) {
    for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) { mat_a[i][j] = lcg() & 0xffffu; mat_b[i][j] = lcg() & 0xffffu; }
    for (int i = 0; i < BUF; i++) buf[i] = (uint8_t)lcg();
    for (int i = 0; i < 64; i++) arr[i] = (int32_t)lcg() - (1 << 22);
}

/* the work itself, between the markers; returns the checksum */
uint32_t workload(void) {
    uint32_t h = crc32(buf, BUF);
    h ^= matmul();
    h += sort();
    h ^= divide();
    return h;
}

#ifdef __riscv
#define MARK_START (*(volatile uint32_t *)0x00010000u)
#define MARK_END   (*(volatile uint32_t *)0x00010004u)
#define RESULT     (*(volatile uint32_t *)0x00010008u)
int main(void) {
    setup();
    MARK_START = 1;
    uint32_t h = workload();
    MARK_END = 1;
    RESULT = h;
    for (;;) {}
}
#else
#include <stdio.h>
int main(void) {
    setup();
    printf("%08x\n", workload());
    return 0;
}
#endif
