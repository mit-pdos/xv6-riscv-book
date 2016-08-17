.chapter CH:BOOT "Boot loader"
.ig

aug 2011: let's cut this chapter altogether, probably move
the bootasm.S etc. details to an appendix.

	notes:
	this chapter is an attempt to demand page that
	information as needed while going through the source,
	because no one wants to read the intel manual first
	all by itself, without knowing how or why it's going
	to be used.
	
	as such, the chapter is a bit of an experiment.

	there isn't really anything called "32-bit mode".
..

.PP
This book takes a narrative approach to describing the xv6 kernel,
starting with what happens when the computer powers on.
Xv6 is written for a personal computer (PC) 
with an Intel x86 CPU, so many of the details
in the first few chapters will be specific to that platform.
This chapter explains how the xv6 kernel is loaded from disk into
memory and how it first starts executing.
.PP
At power-up, a PC
loads the first 512 bytes of data from the disk and executes it.
The instructions in that 512 bytes must arrange to load the full
operating system, in this case the xv6 kernel.
The 512 bytes are called the
.italic-index "boot loader" .
The code for xv6's boot loader is in files
.code bootasm.S
and
.code bootmain.c .
.PP
The boot loader is a microcosm of a kernel itself: it contains low-level
assembly and C code, it manages its own memory, and it even has a device driver,
all in under 512 bytes of machine code.  This small size and simple function
makes it a good starting point to learn about kernels; in the process, you will
learn enough about PC hardware and x86 assembly to understand the boot loader
and xv6.  If you are already familiar with PC hardware and x86 assembly, you can
skip forward to the next chapter, where xv6 starts.
.\"
.\" -------------------------------------------
.\"
.section "A personal computer"
.PP
A PC is a computer that adheres to several industry standards,
with the goal that a given piece of software can run on PCs
sold by multiple vendors.
These standards
evolve over time and a PC from 1990s doesn't look like a PC now. 
.PP
From the outside a PC is a box with a keyboard, a screen, and various devices
(e.g., CD-rom, etc.).  Inside the box is a circuit board (the "motherboard")
with CPU chips, memory chips, graphic chips, I/O controller chips,
and busses through which the chips communicate.
The busses adhere to standard protocols (e.g., PCI and USB)
so that devices will work with PCs from multiple vendors.
.PP
From our point of view, we can abstract the PC
into three components: CPU, memory, and input/output (I/O) devices.  The
CPU performs computation, the memory contains instructions and data
for that computation, and devices allow the CPU to interact with
hardware for storage, communication, and other functions.
.PP
You can think of main memory as connected to the CPU
with a set of wires, or lines, some for address bits, some for
data bits, and some for control flags.
To read a value from main memory, the CPU sends high or low voltages
representing 1 or 0 bits on the address lines and a 1 on the ``read'' line for a
prescribed amount of time and then reads back the value by interpreting the
voltages on the data lines.  To write a value to main memory, the CPU
sends appropriate bits on the address and data lines and a 1 on the ``write''
line for a prescribed amount of time.  Real memory interfaces are more
complex than this, but the details are only important if you need to
achieve high performance.
.\"
.\" -------------------------------------------
.\"
.section "Processor and memory"
.PP
A computer's CPU (central processing unit, or processor)
runs a conceptually simple loop:
it consults an address in a register called the program counter,
reads a machine instruction from that address in memory,
advances the program counter past the instruction,
and executes the instruction.
Repeat.
If the execution of the instruction does not modify the
program counter, this loop will interpret the
memory pointed at by the program counter as a 
sequence of machine instructions to run one after the other.
Instructions that do change the program counter include
branches and function calls.
.PP
The execution engine is useless without the ability to store
and modify program data.
The fastest storage for
data is provided by the processor's register set.  A
register is a storage cell inside the processor itself,
capable of holding a machine word-sized value (typically 16,
32, or 64 bits).  Data stored in registers can typically be
read or written quickly, in a single CPU cycle.
.PP
PCs have a processor that implements the x86 instruction set, which was
originally defined by Intel and has become a standard.  Several manufacturers
produce processors that implement the instruction set.  Like all other PC
standards, this standard is also evolving but newer standards are backwards
compatible with past standards. The boot loader has to deal with some of this
evolution because every PC processor starts simulating an Intel 8088, the CPU
chip in the original IBM PC released in 1981.  However, for most of xv6 you will
be concerned with the modern x86 instruction set.
.PP
The modern x86
provides eight general purpose 32-bit registers—\c
.register eax ,
.register ebx ,
.register ecx ,
.register edx ,
.register edi ,
.register esi ,
.register ebp ,
and
.register esp \c
—and a program counter
.register eip
(the ``instruction pointer'').
The common
.register-font e
prefix stands for extended, as these are 32-bit
extensions of the 16-bit registers
.register ax ,
.register bx ,
.register cx ,
.register dx ,
.register di ,
.register si ,
.register bp ,
.register sp ,
and
.register ip .
The two register sets are aliased so that,
for example,
.register ax
is the bottom half of
.register eax :
writing to
.register ax
changes the value stored in
.register eax
and vice versa.
The first four registers also have names for
the bottom two 8-bit bytes:
.register al
and
.register ah
denote the low and high 8 bits of
.register ax ;
.register bl ,
.register bh ,
.register cl ,
.register ch ,
.register dl ,
and
.register dh
continue the pattern.
In addition to these registers,
the x86 has eight 80-bit floating-point registers
as well as a handful of special-purpose registers
like the control registers
.register cr0 ,
.register cr2 ,
.register cr3 ,
and
.register cr4 ;
the debug registers
.register dr0 ,
.register dr1 ,
.register dr2 ,
and
.register dr3 ;
the segment registers
.register cs ,
.register ds ,
.register es ,
.register fs ,
.register gs ,
and
.register ss ;
and the global and local descriptor table
pseudo-registers
.register gdtr
and 
.register ldtr .
The control, segment selector, and descriptor table
registers are important to any operating system, as we
will see in this chapter.
The floating-point and debug registers are less interesting
and not used by xv6.
.PP
Registers are fast but expensive.
Most processors provide at most a few tens of general-purpose
registers. 
The next conceptual level of storage is the main
random-access memory (RAM).  Main memory is 10-100x slower
than a register, but it is much cheaper, so there can be more
of it.
One reason main memory is relatively slow is that it is
physically separate from the processor chip.
An x86 processor has a few dozen registers,
but a typical PC today has gigabytes of main memory. 
Because of the enormous differences in both access
speed and size between registers and main memory, most
processors, including the x86, store copies of
recently-accessed sections of main memory in on-chip
cache memory.
The cache memory serves as a middle ground
between registers and memory both in access time and in size.
Today's x86 processors typically have two levels of
cache, a small first-level cache with access times relatively
close to the processor's clock rate and a larger
second-level cache with access times in between the
first-level cache and main memory.
This table shows actual numbers for an Intel Core 2 Duo system:
.sp
.TS
center ;
cB s s 
cBI s s
cB cB cB
c n n .
Intel Core 2 Duo E7200 at 2.53 GHz
TODO: Plug in non-made-up numbers!
storage	access time	size
register	0.6 ns	64 bytes
L1 cache	0.5 ns	64 kilobytes
L2 cache	10 ns	4 megabytes
main memory	100 ns	4 gigabytes
.TE
.sp
.PP
For the most part, x86 processors hide the cache from the
operating system, so we can think of the processor as having
just two kinds of storage—registers and memory—and not
worry about the distinctions between the different levels of
the memory hierarchy.
.\"
.\" -------------------------------------------
.\"
.section "I/O"
.PP
Processors must communicate with devices as well as memory.
The x86 processor provides special
.opcode in
and
.opcode out
instructions that read and write values from device
addresses called I/O ports.  The hardware implementation of
these instructions is essentially the same as reading and
writing memory.  Early x86 processors had an extra
address line: 0 meant read/write from an I/O port and 1
meant read/write from main memory.
Each hardware device monitors these lines for reads and writes to
its assigned range of I/O ports.
A device's ports let the software configure the device, examine
its status, and cause the device to take actions; for example,
software can use I/O port reads and writes to cause the disk
interface hardware to read and write sectors on the disk.
.PP
Many computer architectures have no separate device access
instructions.  Instead the devices have fixed memory
addresses and the processor communicates with the device (at
the operating system's behest) by reading and writing values
at those addresses.  In fact, modern x86 architectures use
this technique, called 
.italic-index "memory-mapped I/O" , 
for most high-speed devices such as network, disk, and graphics
controllers.  For reasons of backwards compatibility,
though, the old
.opcode in
and
.opcode out
instructions linger, as do
legacy hardware devices that use them, such as the
IDE disk controller, which we will see shortly.
.\"
.\" -------------------------------------------
.\"
.section "Boot loader"
.PP
.index "boot loader
When an x86 PC boots, it starts executing a program called the BIOS,
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
The processor is in "real mode," in which it simulates an Intel 8088.
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
The addresses that an x86 program manipulates are called
.italic-index "logical addresses" 
(see 
.figref x86_translation ).
A logical address consists of a segment selector and
an offset, and is sometimes written as
\fIsegment\fP:\fIoffset\fP.
More often, the segment is implicit and the program only
directly manipulates the offset.
The segmentation hardware performs the translation
described above to generate
.italic-index "linear addresses" .
The addresses that the processor chip sends to main memory
are called
.italic-index "physical addresses" .
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
For historical reasons we will use the term "virtual address" to
refer to addresses manipulated by programs; an xv6 virtual address
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
.lines bootasm.S:/Segment.number.zero/,/Stack.Segment/ .
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
x86 processors since the 80286 have a "protected mode" which allows
physical addresses to have many more bits, and 
(since the 80386)
a "32-bit" mode that causes registers, virtual addresses,
and most integer arithmetic to be carried out with 32 bits
rather than 16.
The xv6 boot sequence enables protected mode and 32-bit mode as follows.
.figure x86_seg
.PP
In protected mode, a segment
register is an index into a segment descriptor table (see 
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
.code SEG_KDATA
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
.address 0x7d00 .
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
The kernel is an ELF format binary, defined in
.file elf.h .
An ELF binary consists of an ELF header,
.code struct
.code elfhdr
.line elf.h:/^struct.elfhdr/ ,
followed by a sequence of program section headers,
.code struct
.code proghdr
.line elf.h:/^struct.proghdr/ .
Each
.code proghdr
describes a section of the kernel that must be loaded into memory;
there is typically a section for instructions, and a few sections
for different kinds of data.
These headers typically take up the first hundred or so bytes
of the binary.
To get access to the headers,
.code bootmain
loads the first 4096 bytes of the ELF binary
.line bootmain.c:/readseg/ .
It places the in-memory copy at address
.address 0x10000 .
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
.PP
The next step is a quick check that this probably is an
ELF binary, and not an uninitialized disk.
All correct ELF binaries start with the four-byte "magic number"
.code 0x7F ,
.code 'E' ,
.code 'L' ,
.code 'F' ,
or
.code ELF_MAGIC
.line elf.h:/ELF_MAGIC/ .
If the ELF header has the right magic number, the boot
loader assumes that the binary is well-formed.
.PP
The ELF header contains the offset in the binary of the
.code proghdr s.
Each
.code proghdr
supplies
the address at which the section should be loaded in memory
.code paddr ), (
the location where the section's content lies on the disk
relative to the start of the ELF header
.code off ), (
the number of bytes to load
.code filesz ), (
and the number of bytes to allocate
in memory
.code memsz ). (
If
.code memsz
is larger than
.code filesz ,
the bytes not loaded from the binary are to be zeroed.
The xv6 kernel has one loadable program section:
.P1
# objdump -p kernel
kernel:     file format elf32-i386

Program Header:
    LOAD off    0x00001000 vaddr 0xf0100000 paddr 0x00100000 align 2**12
         filesz 0x0000b57e memsz 0x000126d0 flags rwx
.P2
.PP
.code Bootmain
reads the section's content starting from the disk location
.code off
bytes after the start of the ELF header,
and writes to memory starting at address
.code paddr .
.code Bootmain
calls
.code readseg
to load data from disk
.line bootmain.c:/readseg.*filesz/
and calls
.code stosb
to zero the remainder of the segment
.line bootmain.c:/stosb/ .
.code Stosb
.line x86.h:/^stosb/
uses the x86 instruction
.opcode rep
.opcode stosb
to initialize every byte of a block of memory.
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
It is our first example of a device driver, albeit a tiny one.
A 
.italic-index "device driver"
is the program code and data that manages an I/O device such as disk,
display, etc., typically using I/O instructions.
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
Chapter \*[CH:DISK] will examine more efficient ways to wait for hardware
status changes, but busy waiting like this
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
.PP
The kernel has been compiled and linked so that it expects to
find itself at virtual addresses starting at
.code 0xF0100000 .
That is, function call instructions mention destination addresses
that look like
.address 0xF01xxxxx ;
you can see examples in
.file kernel.asm .
This address is configured in
.file kernel.ld .
.address 0xF0100000
is a relatively high address, towards the end of the
32-bit address space;
Chapter \*[CH:MEM] explains the reasons for this choice.
There may not be any physical memory at such a
high address.
Once the kernel starts executing, 
it will set up the paging hardware to map virtual
addresses starting at 
.address 0xF0100000
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
.address 0xF0100020 : 
.P1
# objdump -f kernel

kernel:     file format elf32-i386
architecture: i386, flags 0x00000112:
EXEC_P, HAS_SYMS, D_PAGED
start address 0xf0100020
.P2
The loader must correct this address to reflect the fact
that it loaded the kernel at
.address 0x00100000
rather than at
.address 0xF0100000 ,
so it zeroes the high eight bits before calling the
entry address
.lines 'bootmain.c:/entry.=/,/entry!(!)/' .
.PP
The xv6 Makefile specifies the entry point to the linker using 
.code "-e entry" ,
indicating that the entry point should be the function named
.code entry .
This function is defined in the file
.file entry.S 
.line entry.S:/^entry/ .
.\"
.\" -------------------------------------------
.\"
.section "Real world"
.PP
The boot loader described in this chapter compiles to around
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
like the one in this chapter loads a full-featured
boot-loader from a known disk location, often relying on the
less space-constrained BIOS for disk access rather than
trying to drive the disk itself.  Then the full loader,
relieved of the 512-byte limit, can implement the complexity
needed to locate, load, and execute the desired kernel.
Perhaps a more modern design would have the BIOS directly read
a larger boot loader from the disk (and start it in
protected and 32-bit mode).
.PP
This chapter is written as if the only thing that happens
between power on and the execution of the boot loader
is that the BIOS loads the boot sector.
In fact the BIOS does a huge amount of initialization
in order to make the complex hardware of a modern
computer look like a traditional standard PC.
.PP
TODO: Also, x86 does not imply BIOS: Macs use EFI.
I wonder if the Mac has an A20 line.
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
