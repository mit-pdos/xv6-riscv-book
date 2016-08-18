.appendix APP:BOOT "The boot loader"
.ig
	there isn't really anything called "32-bit mode".

	x86 does not imply BIOS: Macs use EFI.
	I wonder if the Mac has an A20 line.
..
.PP
.index "boot loader
When an x86 PC boots, it starts executing a program called the BIOS (Basic Input/Output System),
which is stored in non-volatile memory on the motherboard.
The BIOS's job is to prepare the hardware and
.index "boot loader
then transfer control to the operating system.
Specifically, it transfers control to code loaded from the boot sector,
the first 512-byte sector of the boot disk.
The boot sector contains the boot loader:
instructions that load the kernel into memory.
The BIOS loads the boot sector at memory address
.address 0x7c00
and then jumps (sets the processor's
.register ip )
to that address.  When the boot loader begins executing, the processor is
simulating an Intel 8088, and the loader's job is to put the processor in a more
modern operating mode, to load the xv6 kernel from disk into memory, and then to
transfer control to the kernel.  The xv6 boot loader comprises two source
files, one written in a combination of 16-bit and 32-bit x86 assembly
.file bootasm.S ; (
.sheet bootasm.S )
and one written in C
.file bootmain.c ; (
.sheet bootmain.c ).
.\"
.\" -------------------------------------------
.\"
.section "Code: Assembly bootstrap"
.PP
The first instruction in the boot loader is
.opcode cli
.line bootasm.S:/cli.*interrupts/ ,
which disables processor interrupts.
Interrupts are a way for hardware devices to invoke
operating system functions called interrupt handlers.
The BIOS is a tiny operating system, and it might have
set up its own interrupt handlers as part of the initializing
the hardware.
But the BIOS isn't running anymore—the boot loader is—so it
is no longer appropriate or safe to handle interrupts from
hardware devices.
When xv6 is ready (in Chapter \*[CH:TRAP]), it will
re-enable interrupts.
.PP
The processor is in 
.italic-index "real mode" ,
in which it simulates an Intel 8088.
In real mode there are eight 16-bit general-purpose registers,
but the processor sends 20 bits of address to memory.
The segment registers
.register cs ,
.register ds ,
.register es ,
and
.register ss
provide the additional bits necessary to generate 20-bit
memory addresses from 16-bit registers.
When a program refers to a memory address, the processor
automatically adds 16 times the value of one of the
segment registers; these registers are 16 bits wide.
Which segment register is usually implicit in the
kind of memory reference:
instruction fetches use
.register cs ,
data reads and writes use
.register ds ,
and stack reads and writes use
.register ss .
.figure x86_translation
.PP
.index "boot loader
Xv6 pretends that an x86 instruction uses a virtual address for its memory operands,
but an x86 instruction actually uses a
.italic-index "logical address" 
(see 
.figref x86_translation ).
A logical address consists of a segment selector and
an offset, and is sometimes written as
\fIsegment\fP:\fIoffset\fP.
More often, the segment is implicit and the program only
directly manipulates the offset.
The segmentation hardware performs the translation
described above to generate a
.italic-index "linear address" .
If the paging hardware is enabled (see Chapter \*[CH:MEM]), it
translates linear addresses to physical addresses;
otherwise the processor uses linear addresses as physical addresses.
.PP
The boot loader does not enable the paging hardware;
the logical addresses that it uses are translated to linear
addresses by the segmentation harware, and then used directly
as physical addresses.
Xv6 configures the segmentation hardware to translate logical
to linear addresses without change, so that they are always equal.
For historical reasons we have used the term 
.italic-index "virtual address" 
to refer to addresses manipulated by programs; an xv6 virtual address
is the same as an x86 logical address, and is equal to the
linear address to which the segmentation hardware maps it.
Once paging is enabled, the only interesting address mapping
in the system will be linear to physical.
.PP
The BIOS does not guarantee anything about the 
contents of 
.register ds , 
.register es ,
.register ss ,
so first order of business after disabling interrupts
is to set
.register ax
to zero and then copy that zero into
.register ds ,
.register es ,
and
.register ss
.lines bootasm.S:/Set..ax.to.zero/,/Stack.Segment/ .
.PP
A virtual
\fIsegment\fP:\fIoffset\fP
can yield a 21-bit physical address,
but the Intel 8088 could only address 20 bits of memory,
so it discarded the top bit:
.address 0xffff0 \c
+\c
.address 0xffff
=
.address 0x10ffef ,
but virtual address
.address 0xffff \c
:\c
.address 0xffff
on the 8088
referred to physical address
.address 0x0ffef .
Some early software relied on the hardware ignoring the 21st
address bit, so when Intel introduced processors with more
than 20 bits of physical address, IBM provided a
compatibility hack that is a requirement for PC-compatible
hardware.
If the second bit of the keyboard controller's output port
is low, the 21st physical address bit is always cleared;
if high, the 21st bit acts normally.
The boot loader must enable the 21st address bit using I/O to the keyboard
controller on ports 0x64 and 0x60
.lines bootasm.S:/A20/,/outb.*%al,.0x60/ .
.PP
Real mode's 16-bit general-purpose and segment registers
make it awkward for a program to use more than 65,536 bytes
of memory, and impossible to use more than a megabyte.
x86 processors since the 80286 have a 
.italic-index "protected mode" ,
which allows physical addresses to have many more bits, and 
(since the 80386)
a ``32-bit'' mode that causes registers, virtual addresses,
and most integer arithmetic to be carried out with 32 bits
rather than 16.
The xv6 boot sequence enables protected mode and 32-bit mode as follows.
.figure x86_seg
.PP
In protected mode, a segment
register is an index into a 
.italic-index "segment descriptor table"
(see 
.figref x86_seg ).
Each table entry specifies a base physical address,
a maximum virtual address called the limit,
and permission bits for the segment.
These permissions are the protection in protected mode: the
kernel can use them to ensure that a program uses only its
own memory.
.PP 
xv6 makes almost no use of segments; it uses the paging hardware
instead, as Chapter \*[CH:MEM] describes.
The boot loader sets up the segment descriptor table
.code-index gdt
.lines bootasm.S:/^gdt:/,/data.seg/
so that all segments have a base address of zero and the maximum possible
limit (four gigabytes).
The table has a null entry, one entry for executable
code, and one entry to data.
The code segment descriptor has a flag set that indicates
that the code should run in 32-bit mode
.line asm.h:/SEG.ASM/ .
With this setup, when the boot loader enters protected mode, logical addresses map
one-to-one to physical addresses.
.PP
The boot loader executes an
.opcode lgdt
instruction 
.line bootasm.S:/lgdt/
to load the processor's global descriptor table (GDT)
register with the value
.index "boot loader
.index "global descriptor table
.code-index gdtdesc
.lines bootasm.S:/^gdtdesc:/,/address.gdt/ ,
which points to the table
.code-index gdt .
.PP
Once it has loaded the GDT register, the boot loader enables
protected mode by
setting the 1 bit
(\c
.code-index CR0_PE )
in register
.register cr0
.lines bootasm.S:/movl.*%cr0/,/movl.*,.%cr0/ .
Enabling protected mode does not immediately change how the processor
translates logical to physical addresses;
it is only when one loads a new value into a segment register
that the processor reads the GDT and changes its internal
segmentation settings.
One cannot directly modify
.register cs ,
so instead the code executes an
.opcode ljmp 
(far jump)
instruction
.line bootasm.S:/ljmp/ ,
which allows a code segment selector to be specified.
The jump continues execution at the next line
.line bootasm.S:/^start32/
but in doing so sets 
.register cs
to refer to the code descriptor entry in
.code-index gdt .
That descriptor describes a 32-bit code segment,
so the processor switches into 32-bit mode.
The boot loader has nursed the processor
through an evolution from 8088 through 80286 
to 80386.
.PP
The boot loader's first action in 32-bit mode is to
initialize the data segment registers with
.code-index SEG_KDATA
.lines bootasm.S:/movw.*SEG_KDATA/,/Stack.Segment/ .
Logical address now map directly to physical addresses.
The only step left before
executing C code is to set up a stack
in an unused region of memory.
The memory from
.address 0xa0000
to
.address 0x100000
is typically littered with device memory regions,
and the xv6 kernel expects to be placed at
.address 0x100000.
The boot loader itself is at
.address 0x7c00
through
.address 0x7e00 
(512 bytes).
Essentially any other section of memory would be a fine
location for the stack.
The boot loader chooses
.address 0x7c00
(known in this file as
.code $start )
as the top of the stack;
the stack will grow down from there, toward
.address 0x0000 ,
away from the boot loader.
.PP
Finally the boot loader calls the C function
.code-index bootmain
.line bootasm.S:/call.*bootmain/ .
.code Bootmain 's
job is to load and run the kernel.
It only returns if something has gone wrong.
In that case, the code sends a few output words
on port
.address 0x8a00
.lines bootasm.S:/bootmain.returns/,/spin:/-1 .
On real hardware, there is no device connected
to that port, so this code does nothing.
If the boot loader is running inside a PC simulator, port 
.address 0x8a00
is connected to the simulator itself and can transfer control
back to the simulator.
Simulator or not, the code then executes an infinite loop
.lines bootasm.S:/^spin:/,/jmp/ .
A real boot loader might attempt to print an error message first.
.\"
.\" -------------------------------------------
.\"
.section "Code: C bootstrap"
.PP
The C part of the boot loader,
.file bootmain.c
.line bootmain.c:1 ,
expects to find a copy of the kernel executable on the
disk starting at the second sector.
The kernel is an ELF format binary, 
as we have seen in Chapter \*[CH:MEM].
To get access to the ELF headers,
.code bootmain
loads the first 4096 bytes of the ELF binary
.line bootmain.c:/readseg/ .
It places the in-memory copy at address
.address 0x10000 .
.ig
.PP
.code bootmain
casts between pointers and 
.code int s
and between different kinds of pointers
.lines "bootmain.c:/elfhdr..0x10000/ 'bootmain.c:/readseg!(!(/' 'and so on'" .
These casts only make sense if the compiler and processor represent
.code int s
and all pointers in essentially the same way, which
is not true for all hardware/compiler combinations.
It is true for the x86 in 32-bit mode:
.code int s
are 32 bits wide, and all pointers are
32-bit byte addresses.
..
.PP
The next step is a quick check that this probably is an
ELF binary, and not an uninitialized disk.
.code Bootmain
reads the section's content starting from the disk location
.code off
bytes after the start of the ELF header,
and writes to memory starting at address
.code paddr .
.code Bootmain
calls
.code-index readseg
to load data from disk
.line bootmain.c:/readseg.*filesz/
and calls
.code-index stosb
to zero the remainder of the segment
.line bootmain.c:/stosb/ .
.code Stosb
.line x86.h:/^stosb/
uses the x86 instruction
.opcode rep
.opcode stosb
to initialize every byte of a block of memory.
.ig
.PP
.code Readseg
.line bootmain.c:/^readseg/
reads at least
.code count
bytes from the disk
.code offset
into memory at
.code pa .
The x86 IDE disk interface
operates on 512-byte sectors, so
.code readseg
may read not only the desired section of memory but
also some bytes before and after, depending on alignment.
For the program segment in the example above, the
boot loader will call 
.code "readseg((uchar*)0x100000, 0xb57e, 0x1000)" .
.code Readseg
begins by computing the ending physical address, the first memory
address above 
.code paddr
that doesn't need to be loaded from disk
.line bootmain.c:/epa.=/ ,
and rounding
.code pa
down to a sector-aligned disk offset.
Then it
converts the offset from a byte offset to
a sector offset;
it adds 1 because the kernel starts at disk
sector 1 (disk sector 0 is the boot sector).  
Finally, it calls
.code readsect
to read each sector into memory.
.PP
.PP
.code Readsect
.line bootmain.c:/^readsect/
reads a single disk sector.
.code Readsect
begins by calling
.code waitdisk
to wait
until the disk signals that it is ready to accept a command.
The disk does so by setting the top two bits of its status
byte (connected to input port
.address 0x1f7 )
to
.code 01 .
.code Waitdisk
.line bootmain.c:/^waitdisk/
reads the status byte until the bits are set that way.
Chapter \*[CH:TRAP] uses efficient ways to wait for hardware
status changes, but polling like this
is fine for the boot loader.
.PP
Once the disk is ready,
.code readsect
issues a read command.
It first writes command arguments—the sector count and the
sector number (offset)—to the disk registers on output
ports
.address 0x1f2 -\c
.address 0x1f6
.lines bootmain.c:/1F2/,/1F6/ .
The bits
.code 0xe0
in the write to port
.code 0x1f6
signal to the disk that
.code 0x1f3 -\c
.code 0x1f6
contain a sector number (a so-called linear block address),
in contrast to a more
complicated cylinder/head/sector address
used in early PC disks.
After writing the arguments, 
.code readsect
writes to the
command register
to trigger the read
.line bootmain.c:/0x1F7/ .
The command
.code 0x20
is ``read sectors.''
Now the disk will read the
data stored in the specified sectors and make it available
in 32-bit pieces on input port
.code 0x1f0 .
.code Waitdisk
.line bootmain.c:/^waitdisk/
waits until the disk signals that the data is ready,
and then the call to
.code insl
reads the 128 
.code SECTSIZE/4 ) (
32-bit pieces into memory starting at
.code dst
.line bootmain.c:/insl.0x1F0/ .
.PP
.code Inb ,
.code outb ,
and
.code insl
are not ordinary C functions.  They are
inlined functions whose bodies are assembly language
fragments
.line "x86.h:/^inb/ x86.h:/^outb/ x86.h:/^insl/" .
When 
.code gcc 
(the C compiler xv6 uses) sees the call to
.code inb
.line 'bootmain.c:/inb!(/' ,
the inlined assembly causes it to emit a single
.code inb
instruction. 
This style allows the use of low-level instructions
like
.code inb
and
.code outb
while still writing the control logic in C instead of assembly.
.PP
The implementation of
.code insl
.line x86.h:/^insl/
is worth looking at more closely.
.code Rep
.code insl
is actually a tight loop masquerading as a single
instruction.
The
.code rep
prefix executes the following instruction
.register ecx
times, decrementing
.register ecx
after each iteration.
The
.code insl
instruction reads a 32-bit value from port 
.register dx
into
memory at address
.register edi
and then increments
.register edi
by 4.
Thus
.code rep
.code insl
copies
.register ecx "" 4×
bytes, in 32-bit chunks, from port
.register dx
into memory starting at address
.register edi .
The register annotations tell 
.code gcc 
to prepare for the assembly sequence by storing
.code dst
in
.register edi ,
.code cnt
in
.register ecx ,
and
.code port
in
.register dx .
Thus the
.code insl
function copies
.code cnt "" 4×
bytes from the
32-bit port
.code port
into memory starting at
.code dst .
The
.code cld
instruction clears the processor's direction flag,
so that the
.code insl
instruction
increments
.register edi ;
when the
flag is set,
.code insl
decrements
.register edi
instead. 
The x86 calling convention does not define the state of the
direction flag on entry to a function, so each use of an
instruction like
.code insl
must initialize it to the desired value.
.PP
The boot loader is almost done. 
.code Bootmain
loops calling
.code readseg ,
which loops calling
.code readsect
.lines 'bootmain.c:/for.;/,/!}/' .
At the end of the loop,
.code bootmain
has loaded the kernel into memory.
..
.PP
The kernel has been compiled and linked so that it expects to
find itself at virtual addresses starting at
.code 0x80100000 .
Thus, function call instructions must mention destination addresses
that look like
.address 0x801xxxxx ;
you can see examples in
.file kernel.asm .
This address is configured in
.file kernel.ld .
.address 0x80100000
is a relatively high address, towards the end of the
32-bit address space;
Chapter \*[CH:MEM] explains the reasons for this choice.
There may not be any physical memory at such a
high address.
Once the kernel starts executing, 
it will set up the paging hardware to map virtual
addresses starting at 
.address 0x80100000
to physical addresses starting at
.address 0x00100000 ;
the kernel assumes that there is physical memory at
this lower address.
At this point in the boot process, however, paging
is not enabled.
Instead, 
.file kernel.ld
specifies that the ELF
.code paddr
start at
.address 0x00100000 ,
which causes the boot loader to copy the kernel to the
low physical addresses to which the paging hardware
will eventually point.
.PP
The boot loader's final step is to call the kernel's
entry point, which is the instruction at which the
kernel expects to start executing.
For xv6 the entry address is
.address 0x10000c: 
.P1
# objdump -f kernel

kernel:     file format elf32-i386
architecture: i386, flags 0x00000112:
EXEC_P, HAS_SYMS, D_PAGED
start address 0x0010000c
.P2
By convention, the 
.code-index _start 
symbol specifies the ELF entry point,
which is defined in the file
.file entry.S 
.line entry.S:/^_start/ .
Since xv6 hasn't set up virtual memory yet, xv6's entry point is
the physical address of 
.code-index entry
.line entry.S:/^entry/ .
.\" -------------------------------------------
.\"
.section "Real world"
.PP
The boot loader described in this appendix compiles to around
470 bytes of machine code, depending on the optimizations
used when compiling the C code.  In order to fit in that
small amount of space, the xv6 boot loader makes a major
simplifying assumption, that the kernel has been written to
the boot disk contiguously starting at sector 1.  More
commonly, kernels are stored in ordinary file systems, where
they may not be contiguous, or are loaded over a network.
These complications require the boot loader to be able to
drive a variety of disk and network controllers and
understand various file systems and network protocols.  In
other words, the boot loader itself must be a small
operating system.  Since such complicated boot loaders
certainly won't fit in 512 bytes, most PC operating systems
use a two-step boot process.  First, a simple boot loader
like the one in this appendix loads a full-featured
boot-loader from a known disk location, often relying on the
less space-constrained BIOS for disk access rather than
trying to drive the disk itself.  Then the full loader,
relieved of the 512-byte limit, can implement the complexity
needed to locate, load, and execute the desired kernel.
Modern PCs avoid many of the above complexities, because
they support the Unified Extensible Firmware Interface (UEFI),
which allows the PC to read
a larger boot loader from the disk (and start it in
protected and 32-bit mode).
.PP
This appendix is written as if the only thing that happens
between power on and the execution of the boot loader
is that the BIOS loads the boot sector.
In fact the BIOS does a huge amount of initialization
in order to make the complex hardware of a modern
computer look like a traditional standard PC.
.\"
.\" -------------------------------------------
.\"
.section "Exercises
.exercise
Due to sector granularity, the call to 
.code readseg 
in the text is equivalent to
.code "readseg((uchar*)0x100000, 0xb500, 0x1000)".
In practice, this sloppy behavior turns out not to be a problem
Why doesn't the sloppy readsect cause problems?
.answer
Answer is a combination of non-overlapping code/data pages
and aligned virtual address/file offsets.
..
.exercise
something about BIOS lasting longer + security problems
.exercise
Suppose you wanted bootmain() to load the kernel at 0x200000
instead of 0x100000, and you did so by modifying bootmain()
to add 0x100000 to the va of each ELF section. Something would
go wrong. What?
.exercise
It seems potentially dangerous for the boot loader to copy the ELF
header to memory at the arbitrary location
.code 0x10000 .
Why doesn't it call
.code malloc
to obtain the memory it needs?
