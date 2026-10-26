/* Start-up for the power workload. Ibex boots at boot_addr + 0x80 (boot_addr is 0 in the testbench), and
 * its exception vectors sit at boot_addr: every vector parks in a loop, which the testbench reports as a
 * failure if the program never writes its checksum. */
    .section .vectors, "ax"
    .option norvc
    .org 0x00
    .rept 32
    j trap
    .endr
    .org 0x80
    j _start

    .text
    .globl _start
_start:
    la sp, __stack_top
    la t0, __bss_start
    la t1, __bss_end
1:  bge t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
trap:
    j trap
