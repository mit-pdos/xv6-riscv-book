.appendix APP:HW "PC hardware"
.ig
	there isn't really anything called "32-bit mode".
..
.PP
This appendix describes personal computer (PC) hardware,
the platform on which xv6 runs.
.PP
A PC is a computer that adheres to several industry standards,
with the goal that a given piece of software can run on PCs
sold by multiple vendors.
These standards
evolve over time and a PC from 1990s doesn't look like a PC now.
Many of the current standards are public and you can find documentation
for them online.
.PP
From the outside a PC is a box with a keyboard, a screen, and various devices
(e.g., CD-ROM, etc.).  Inside the box is a circuit board (the ``motherboard'')
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
it consults an address in a register called the 
.italic-index "program counter" ,
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
(the
.italic-index "instruction pointer" ).
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
like the 
.italic-index "control registers"
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
the 
.italic-index "segment registers"
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
The control registers and segment registers are important to any operating system.
The floating-point and debug registers are less interesting
and not used by xv6.
.PP
Registers are fast but expensive.  Most processors provide at most a few tens of
general-purpose registers.  The next conceptual level of storage is the main
random-access memory (RAM).  Main memory is 10-100x slower than a register, but
it is much cheaper, so there can be more of it.  One reason main memory is
relatively slow is that it is physically separate from the processor chip.  An
x86 processor has a few dozen registers, but a typical PC today has gigabytes of
main memory.  Because of the enormous differences in both access speed and size
between registers and main memory, most processors, including the x86, store
copies of recently-accessed sections of main memory in on-chip cache memory.
The cache memory serves as a middle ground between registers and memory both in
access time and in size.  Today's x86 processors typically have three levels of
cache. Each core has a small first-level cache with access times relatively close to the
processor's clock rate and a larger second-level cache.  Several
cores share an L3 cache.
.figref xeon
shows the levels in the memory hierarchy and their access times for an Intel i7 Xeon processor.
.figure xeon
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
addresses called 
.italic-index "I/O ports" .  
The hardware implementation of
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
IDE disk controller, which xv6 uses.
