/* The power workload's memory map: 64 KiB at address 0, code first, the stack at the top. The
 * testbench's marker and checksum addresses (0x10000 to 0x10008) are outside this memory. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x00000000, LENGTH = 64K }
SECTIONS {
  .vectors 0x00000000 : { KEEP(*(.vectors)) } > ram
  .text : { *(.text .text.*) } > ram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > ram
  .data : { *(.data .data.* .sdata .sdata.*) } > ram
  .bss (NOLOAD) : { __bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON); . = ALIGN(4); __bss_end = .; } > ram
  __stack_top = ORIGIN(ram) + LENGTH(ram);
}
