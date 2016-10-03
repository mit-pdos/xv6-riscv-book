.ig
   Sidebar about panic:
	panic is the kernel's last resort: the impossible has happened and the
	kernel does not know how to proceed.  In xv6, panic does ...
..
.chapter CH:TRAP "Traps, interrupts, and drivers"
.PP
When running a process, a CPU executes the normal processor loop: read an
instruction, advance the program counter, execute the instruction, repeat.  But
there are events on which control from a user program must transfer back to the
kernel instead of executing the next instruction.  These events include a device
signaling that it wants attention, a user program doing something illegal (e.g.,
references a virtual address for which there is no page table entry), or a user
program asking the kernel for a service with a system call.  There are three
main challenges in handling these events: 1) the kernel must arrange that a
processor switches from user mode to kernel mode (and back); 2) the kernel and
devices must coordinate their parallel activities; and 3) the kernel must
understand the interface of the devices.  Addressing these 3 challenges requires
detailed understanding of hardware and careful programming, and can result in
opaque kernel code.  This chapter explains how xv6 addresses these three
challenges.
.\"
.section "Systems calls, exceptions, and interrupts"
.\"
There are three cases when control must be transferred from a user program to
the kernel. First, a system call: when a user program asks for an operating
system service, as we saw at the end of the last chapter.
Second, an
.italic-index exception :
when a program performs an illegal action. Examples of illegal actions include
divide by zero, attempt to access memory for a page-table entry that is not
present, and so on.  Third, an
.italic-index interrupt :
when a device generates a signal to indicate that
it needs attention from the operating system.  For example, a clock chip may
generate an interrupt every 100 msec to allow the kernel to implement
time sharing.  As another example, when the disk has read a block from
disk, it generates an interrupt to alert the operating system that the
block is ready to be retrieved.
.PP
The kernel handles all interrupts, rather than processes
handling them, because in most cases only the kernel has the
required privilege and state. For example, in order to time-slice
among processes in response the clock interrupts, the kernel
must be involved, if only to force uncooperative processes to
yield the processor.
.PP
In all three cases, the operating system design must arrange for the
following to happen.  The system must save the processor's registers for future
transparent resume.  The system must be set up for execution
in the kernel.  The system must chose a place for the kernel to start
executing. The kernel must be able to retrieve information about the
event, e.g., system call arguments.  It must all be done securely; the system
must maintain isolation of user processes and the kernel.
.PP
To achieve this goal the operating system must be aware of the details
of how the hardware handles system calls, exceptions, and interrupts.
In most processors these three events are handled by a single hardware
mechanism.  For example, on the x86, a program invokes a system call
by generating an
interrupt using the 
.code-index int
instruction.   Similarly, exceptions generate an interrupt too.  Thus, if
the operating system has a plan for interrupt handling, then the
operating system can handle system calls and exceptions too.
.PP
The basic plan is as follows.  An interrupts stops the normal
processor loop and starts executing a new sequence
called an
.italic-index "interrupt handler" .  
Before starting the interrupt handler,
the processor saves its registers, so that the operating system
can restore them when it returns from the interrupt.
A challenge in the transition to and from the interrupt handler is
that the processor should switch from user mode to kernel mode, and
back.
.PP
A word on terminology: Although the official x86 term is interrupt,
xv6 refers to all of these as 
.italic-index traps , 
largely because it was the term
used by the PDP11/40 and therefore is the conventional Unix term.
This chapter uses the terms trap and interrupt interchangeably, but it
is important to remember that traps are caused by the current process
running on a processor (e.g., the process makes a system call and as a
result generates a trap), and interrupts are caused by devices and may
not be related to the currently running process.
For example, a disk may generate an interrupt when
it is done retrieving a block for one process, but
at the time of the interrupt some other process may be running.
This
property of interrupts makes thinking about interrupts more difficult
than thinking about traps, because interrupts happen
concurrently with other activities. Both rely, however, on the same hardware
mechanism to transfer control between user and kernel mode securely, which we
will discuss next.
.\"
.section "X86 protection"
.\"
.PP
The x86 has 4 protection levels, numbered 0 (most privilege) to 3
(least privilege).  In practice, most operating systems use only 2
levels: 0 and 3, which are then called 
.italic-index "kernel mode" 
and 
.italic-index "user mode" ,
respectively.  The current privilege level with which the x86 executes
instructions is stored in
.register cs
register,
in the field CPL.
.PP
On the x86, interrupt handlers are defined in the interrupt descriptor
table (IDT). The IDT has 256 entries, each giving the
.register cs
and
.register eip
to be used when handling the corresponding interrupt.
.ig
pointer to the IDT table.
..
.PP
To make a system call on the x86, a program invokes the 
.code int
.italic n
instruction, where 
.italic n 
specifies the index into the IDT. The
.code int
instruction performs the following steps:
.IP \[bu] 
Fetch the 
.italic n 'th
descriptor from the IDT,
where 
.italic n
is the argument of
.code int .
.IP \[bu] 
Check that CPL in 
.register cs
is <= DPL,
where DPL is the privilege level in the descriptor.
.IP \[bu] 
Save
.register esp
and
.register ss
in CPU-internal registers, but only if the target segment
selector's PL < CPL.
.IP \[bu] 
Load
.register ss
and
.register esp
from a task segment descriptor.
.IP \[bu] 
Push
.register ss.
.IP \[bu] 
Push
.register esp.
.IP \[bu] 
Push
.register eflags.
.IP \[bu] 
Push
.register cs.
.IP \[bu] 
Push
.register eip.
.IP \[bu] 
Clear the IF bit in
.register eflags ,
but only on an interrupt.
.IP \[bu] 
Set 
.register cs
and
.register eip
to the values in the descriptor.
.PP
The
.code-index int
instruction is a complex instruction, and one might wonder whether all
these actions are necessary.  For example, the check CPL <= DPL allows the kernel to
forbid 
.code int
calls to inappropriate IDT entries such as device interrupt routines.  For a user
program to execute 
.code int ,
the IDT entry's DPL must be 3.
If the user program doesn't have the appropriate privilege, then 
.code int
will result in
.code int 
13, which is a general protection fault.
As another example, the
.code int
instruction cannot use the user stack to save values, because the process
may not have a valid stack pointer;
instead, the hardware uses the
stack specified in the task segment, which is set by the kernel.
.figure intkstack
.PP
.figref intkstack 
shows the stack after
an 
.code int
instruction completes and there was a privilege-level change (the privilege
level in the descriptor is lower than CPL).
If the 
.code int
instruction didn't require a privilege-level change, the x86
won't save
.register ss
and
.register esp.
After both cases, 
.register eip
is pointing to the address specified in the descriptor table, and the
instruction at that address is the next instruction to be executed and
the first instruction of the handler for
.code int
.italic n .
It is job of the operating system to implement these handlers, and
below we will see what xv6 does.
.PP
An operating system can use the
.code-index iret
instruction to return from an
.code-index int
instruction. It pops the saved values during the 
.code int
instruction from the stack, and resumes execution at the saved 
.register eip.
.\"
.section "Code: The first system call"
.\"
.PP
Chapter \*[CH:FIRST] ended with 
.code-index initcode.S
invoking a system call.
Let's look at that again
.line initcode.S:/'T_SYSCALL'/ .
The process pushed the arguments
for an 
.code-index exec
call on the process's stack, and put the
system call number in
.register eax.
The system call numbers match the entries in the syscalls array,
a table of function pointers
.line syscall.c:/'syscalls'/ .
We need to arrange that the 
.code int
instruction switches the processor from user mode to kernel mode,
that the kernel invokes the right kernel function (i.e.,
.code sys_exec ),
and that the kernel can retrieve the arguments for
.code-index sys_exec .
The next few subsections describe how xv6 arranges this for system
calls, and then we will discover that we can reuse the same code for
interrupts and exceptions.
.\"
.section "Code: Assembly trap handlers"
.\"
.PP
Xv6 must set up the x86 hardware to do something sensible
on encountering an
.code-index int
instruction, which causes the processor to generate a trap.
The x86 allows for 256 different interrupts.
Interrupts 0-31 are defined for software
exceptions, like divide errors or attempts to access invalid memory addresses.
Xv6 maps the 32 hardware interrupts to the range 32-63
and uses interrupt 64 as the system call interrupt.
.ig
pointer to the x86 exception table with vector numbers (DE, DB, ...)
..
.PP
.code Tvinit
.index tvinit
.line trap.c:/^tvinit/ ,
called from
.code-index main ,
sets up the 256 entries in the table
.code-index idt .
Interrupt
.code i
is handled by the
code at the address in
.code-index vectors[i] .
Each entry point is different, because the x86
does not provide the trap number to the interrupt handler.
Using 256 different handlers is the only way to distinguish
the 256 cases.
.PP
.code Tvinit
handles
.code-index T_SYSCALL ,
the user system call trap,
specially: it specifies that the gate is of type ``trap'' by passing a value of
.code 1
as second argument.
Trap gates don't clear the 
.code-index IF
flag, allowing other interrupts during the system call handler.
.PP
The kernel also sets the system call gate privilege to
.code-index DPL_USER ,
which allows a user program to generate
the trap with an explicit
.code int
instruction.
xv6 doesn't allow processes to raise other interrupts (e.g., device
interrupts) with
.code int ;
if they try, they will encounter
a general protection exception, which
goes to vector 13. 
.PP
When changing protection levels from user to kernel mode, the kernel
shouldn't use the stack of the user process, because it may not be valid.
The user process may be malicious or
contain an error that causes the user
.register esp 
to contain an address that is not part of the process's user memory.
Xv6 programs the x86 hardware to perform a stack switch on a trap by
setting up a task segment descriptor through which the hardware loads a stack
segment selector and a new value for
.register esp.
The function
.code-index switchuvm
.line vm.c:/^switchuvm/ 
stores the address of the top of the kernel stack of the user
process into the task segment descriptor.
.ig
TODO: Replace SETGATE with real code.
..
.PP
When a trap occurs, the processor hardware does the following.
If the processor was executing in user mode,
it loads
.register esp
and
.register ss
from the task segment descriptor,
pushes the old user
.register ss
and
.register esp
onto the new stack.
If the processor was executing in kernel mode,
none of the above happens.
The processor then pushes the
.register eflags,
.register cs,
and
.register eip
registers.  For some traps (e.g., a page fault), the processor also pushes an
error word.  The processor then loads
.register eip
and
.register cs
from the relevant IDT entry.
.PP
xv6 uses a Perl script
.line vectors.pl:1
to generate the entry points that the IDT entries point to.
Each entry pushes an error code
if the processor didn't, pushes the interrupt number, and then
jumps to
.code-index alltraps .
.figure trapframe
.PP
.code Alltraps
.line trapasm.S:/^alltraps/
continues to save processor registers: it pushes
.register ds,
.register es,
.register fs,
.register gs,
and the general-purpose registers
.lines trapasm.S:/Build.trap.frame/,/pushal/ .
The result of this effort is that the kernel stack now contains a
.code "struct trapframe"
.line x86.h:/trapframe/
containing the processor registers at the time of the trap (see 
.figref trapframe ).
The processor pushes
.register ss,
.register esp,
.register eflags,
.register cs, 
and
.register eip.
The processor or the trap vector pushes an error number,
and 
.code-index alltraps 
pushes the rest.
The trap frame contains all the information necessary
to restore the user mode processor registers
when the kernel returns to the current process,
so that the processor can continue exactly as it was when
the trap started.  Recall from Chapter \*[CH:MEM], that 
.code userinit
built a trapframe by hand to achieve this goal (see 
.figref first:newkernelstack ).
.PP
In the case of the first system call, the saved 
.register eip
is the address of the instruction right after the 
.code int
instruction.
.register cs 
is the user code segment selector.
.register eflags
is the content of the
.register eflags
register at the point of executing the 
.code int
instruction.
As part of saving the general-purpose registers,
.code alltraps
also saves 
.register eax,
which contains the system call number for the kernel
to inspect later.
.PP
Now that the user mode processor registers are saved,
.code-index alltraps
can finishing setting up the processor to run kernel C code.
The processor set the selectors
.register cs
and
.register ss
before entering the handler;
.code alltraps
sets
.register ds
and
.register es
.lines "'trapasm.S:/movw.*SEG_KDATA/,/%es/'" .
It sets 
.register fs
and
.register gs
to point at the 
.code-index SEG_KCPU
per-CPU data segment
.lines "'trapasm.S:/movw.*SEG_KCPU/,/%gs/'" .
.PP
Once the segments are set properly,
.code-index alltraps
can call the C trap handler
.code-index trap .
It pushes
.register esp,
which points at the trap frame it just constructed,
onto the stack as an argument to
.code trap
.line "'trapasm.S:/pushl.%esp/'" .
Then it calls
.code trap
.line trapasm.S:/call.trap/ .
After
.code trap 
returns,
.code-index alltraps
pops the argument off the stack by
adding to the stack pointer
.line trapasm.S:/addl/
and then starts executing the code at
label
.code-index trapret .
We traced through this code in Chapter \*[CH:MEM]
when the first user process ran it to exit to user space.
The same sequence happens here: popping through
the trap frame restores the user mode registers and then
.code-index iret
jumps back into user space.
.PP
The discussion so far has talked about traps occurring in user mode,
but traps can also happen while the kernel is executing.
In that case the hardware does not switch stacks or save
the stack pointer or stack segment selector;
otherwise the same steps occur as in traps from user mode,
and the same xv6 trap handling code executes.
When 
.code iret
later restores a kernel mode 
.register cs,
the processor continues executing in kernel mode.
.\"
.section "Code: C trap handler"
.\"
.PP
We saw in the last section that each handler sets
up a trap frame and then calls the C function
.code-index trap .
.code Trap
.line 'trap.c:/^trap!(/'
looks at the hardware trap number
.code-index tf->trapno
to decide why it has been called and what needs to be done.
If the trap is
.code-index T_SYSCALL ,
.code trap
calls the system call handler
.code-index syscall .
We'll revisit the 
.code-index proc->killed
checks in Chapter \*[CH:SCHED].  \" XXX really?
.PP
After checking for a system call, trap looks for hardware interrupts
(which we discuss below). In addition to the expected hardware
devices, a trap can be caused by a spurious interrupt, an unwanted
hardware interrupt.
.ig
give a concrete example.
..
.PP
If the trap is not a system call and not a hardware device looking for
attention,
.code-index trap
assumes it was caused by incorrect behavior (e.g.,
divide by zero) as part of the code that was executing before the
trap.  
If the code that caused the trap was a user program, xv6 prints
details and then sets
.code proc->killed
to remember to clean up the user process.
We will look at how xv6 does this cleanup in Chapter \*[CH:SCHED].
.PP
If it was the kernel running, there must be a kernel bug:
.code trap
prints details about the surprise and then calls
.code-index panic .
.\"
.section "Code: System calls"
.\"
.PP
For system calls,
.code-index trap
invokes
.code-index syscall
.line syscall.c:/'^syscall'/ .
.code Syscall 
loads the system call number from the trap frame, which
contains the saved
.register eax,
and indexes into the system call tables.
For the first system call, 
.register eax
contains the value 
.code-index SYS_exec
.line syscall.h:/'SYS_exec'/ ,
and
.code syscall
will invoke the 
.code SYS_exec 'th 
entry of the system call table, which corresponds to invoking
.code sys_exec .
.PP
.code Syscall
records the return value of the system call function in
.register eax.
When the trap returns to user space, it will load the values
from
.code-index cp->tf
into the machine registers.
Thus, when 
.code exec
returns, it will return the value
that the system call handler returned
.line "'syscall.c:/eax = syscalls/'" .
System calls conventionally return negative numbers to indicate
errors, positive numbers for success.
If the system call number is invalid,
.code-index syscall
prints an error and returns \-1.
.PP
Later chapters will examine the implementation of
particular system calls.
This chapter is concerned with the mechanisms for system calls.
There is one bit of mechanism left: finding the system call arguments.
The helper functions argint, argptr, argstr, and argfd retrieve the 
.italic n 'th 
system call
argument, as either an integer, pointer, a string, or a file descriptor.
.code-index argint 
uses the user-space 
.register esp 
register to locate the 
.italic n'th 
argument:
.register esp 
points at the return address for the system call stub.
The arguments are right above it, at 
.register esp+4.
Then the nth argument is at 
.register esp+4+4*n.  
.PP
.code argint 
calls 
.code-index fetchint
to read the value at that address from user memory and write it to
.code *ip .  
.code fetchint 
can simply cast the address to a pointer, because the user and the
kernel share the same page table, but the kernel must verify that the
pointer lies within the user part of the address
space.
The kernel has set up the page-table hardware to make sure
that the process cannot access memory outside its local private memory:
if a user program tries to read or write memory at an address of
.code-index p->sz 
or above, the processor will cause a segmentation trap, and trap will
kill the process, as we saw above.
The kernel, however,
can derefence any address that the user might have passed, so it must check explicitly that the address is below
.code p->sz .
.PP
.code-index argptr
fetches the
.italic n th 
system call argument and checks that this argument is a valid
user-space pointer.
Note that two checks occur during a call to 
.code argptr .
First, the user stack pointer is checked during the fetching
of the argument.
Then the argument, itself a user pointer, is checked.
.PP
.code-index argstr 
interprets the
.italic n th 
argument as a pointer.  It ensures that the pointer points at a
NUL-terminated string and that the complete string is located below
the end of the user part of the address space.
.PP
Finally,
.code-index argfd
.line sysfile.c:/^argfd/
uses
.code argint
to retrieve a file descriptor number, checks if it is valid
file descriptor, and returns the corresponding
.code struct
.code file .
.PP
The system call implementations (for example, sysproc.c and sysfile.c)
are typically wrappers: they decode the arguments using 
.code argint ,
.code argptr , 
and 
.code argstr
and then call the real implementations.
In chapter \*[CH:MEM],
.code sys_exec
uses these functions to get at its arguments.
.\"
.section "Code: Interrupts"
.\"
.PP
Devices on the motherboard can generate interrupts, and xv6 must set up
the hardware to handle these interrupts.
Devices usually interrupt in order to tell the kernel that some hardware
event has occured, such as I/O completion.
Interrupts are usually optional in the sense that the kernel could
instead periodically check (or "poll") the device hardware to check
for new events.
Interrupts are preferable to polling if the events are relatively
rare, so that polling would waste CPU time.
Interrupt handling shares some of the code already needed
for system calls and exceptions.
.PP
Interrupts are similar to system calls, except devices generate them
at any time.  There is hardware on the motherboard to signal the CPU
when a device needs attention (e.g., the user has typed a character on
the keyboard). We must program the device to generate an interrupt, and
arrange that a CPU receives the interrupt. 
.PP
Let's look at the timer device and timer interrupts.  We would like
the timer hardware to generate an interrupt, say, 100 times per
second so that the kernel can track the passage of time and so the
kernel can time-slice among multiple running processes.  The choice of
100 times per second allows for decent interactive performance while
not swamping the processor with handling interrupts.  
.PP
Like the x86 processor itself, PC motherboards have evolved, and the
way interrupts are provided has evolved too.  The early boards had a
simple programmable interrupt controler (called the PIC), and you can
.index "programmable interrupt controler (PIC)"
find the code to manage it in
.code picirq.c .
.PP
With the advent of multiprocessor PC boards, a new way of handling
interrupts was needed, because each CPU needs an interrupt controller
to handle interrupts sent to it, and there must be a method for
routing interrupts to processors.  This way consists of two parts: a
part that is in the I/O system (the IO APIC,
.code ioapic.c), 
and a part that is attached to each processor (the
local APIC, 
.code lapic.c).
Xv6 is designed for a
board with multiple processors, and each processor must be programmed
to receive interrupts.
.PP
To also work correctly on uniprocessors, Xv6 programs the programmable
interrupt controler (PIC)
.line picirq.c:/^picinit/ .  
Each PIC handles a maximum of 8 interrupts (i.e., devices) and
multiplexes them onto the interrupt pin of the processor.  To allow for
more than 8 devices, PICs can be cascaded and typically boards have at
least two.  Using
.code-index inb
and 
.code-index outb
instructions Xv6 programs the master to
generate IRQ 0 through 7 and the slave to generate IRQ 8 through 16.
Initially xv6 programs the PIC to mask all interrupts.
The code in
.code-index timer.c
sets timer 1 and enables the timer interrupt
on the PIC
.line timer.c:/^timerinit/ .
This description omits some of the details of programming the PIC.
These details of the PIC (and the IOAPIC and LAPIC) are not important
to this text but the interested reader can consult the manuals for
each device, which are referenced in the source files.
.PP
On multiprocessors, xv6 must program the IOAPIC, and the LAPIC on
each processor.
The IO APIC has a table and the processor can program entries in the
table through memory-mapped I/O, instead of using 
.code inb
and 
.code outb
instructions.
During initialization, xv6 programs to map interrupt 0 to IRQ 0, and
so on, but disables them all.  Specific devices enable particular
interrupts and say to which processor the interrupt should be routed.
For example, xv6 routes keyboard interrupts to processor 0
.line console.c:/^consoleinit/ .
Xv6 routes disk interrupts to the highest numbered processor on the
system, as we will see below.
.PP
The timer chip is inside the LAPIC, so that each processor can receive
timer interrupts independently. Xv6 sets it up in
.code-index lapicinit
.line lapic.c:/^lapicinit/ .
The key line is the one that programs the timer
.line lapic.c:/lapicw.TIMER/ .
This line tells the LAPIC to periodically generate an interrupt at
.code-index IRQ_TIMER,
which is IRQ 0.
Line
.line lapic.c:/lapicw.TPR/
enables interrupts on a CPU's LAPIC, which will cause it to deliver
interrupts to the local processor.
.PP
A processor can control if it wants to receive interrupts through the
.code-index IF
flag in the
.register eflags
register.
The instruction
.code-index cli
disables interrupts on the processor by clearing 
.code IF , 
and
.code-index sti
enables interrupts on a processor.  Xv6 disables interrupts during
booting of the main cpu
.line bootasm.S:/cli/
and the other processors
.line entryother.S:/cli/ .
The scheduler on each processor enables interrupts
.line proc.c:/sti/ .
To control that certain code fragments are not interrupted, xv6
disables interrupts during these code fragments (e.g., see
.code-index switchuvm
.line vm.c:/^switchuvm/ ).
.PP
The timer interrupts through vector 32 (which xv6 chose to handle IRQ
0), which xv6 setup in
.code-index idtinit 
.line main.c:/idtinit/ .
The only difference between vector 32 and vector 64 (the one for
system calls) is that vector 32 is an interrupt gate instead of a trap
gate.  Interrupt gates clear
.code IF ,
so that the interrupted processor doesn't receive interrupts while it
is handling the current interrupt.  From here on until
.code-index trap , 
interrupts follow
the same code path as system calls and exceptions, building up a trap frame.
.PP
.code Trap
when it's called for a time interrupt, does just two things:
increment the ticks variable 
.line trap.c:/ticks!+!+/ , 
and call
.code-index wakeup . 
The latter, as we will see in Chapter \*[CH:SCHED], may cause the
interrupt to return in a different process.
.ig
Turns out our kernel had a subtle security bug in the way it handled traps... vb 0x1b:0x11, run movdsgs, step over breakpoints that aren't mov ax, ds, dump_cpu and single-step. dump_cpu after mov gs, then vb 0x1b:0x21 to break after sbrk returns, dump_cpu again.
..
.ig
point out that we are trying to be manly with interrupts, by turning them on often in the kernel.  probably would be just fine to turn them on only when the kernel is idle.
..
.\"
.section "Drivers"
.\"
A
.italic-index driver
is the code in an operating system that manages a particular device:
it tells the device hardware to perform operations,
configures the device to generate interrupts when done,
and handles the resulting interrupts.
Driver code can be tricky to write
because a driver executes concurrently with the device that it manages.  In
addition, the driver must understand the device's interface (e.g., which I/O
ports do what), and that interface can be complex and poorly documented.
.PP
The disk driver provides a good example.  The disk driver copies data
from and back to the disk.  Disk hardware traditionally presents the data on the
disk as a numbered sequence of 512-byte 
.italic blocks 
.index block
(also called 
.italic sectors ): 
.index sector
sector 0 is the first 512 bytes, sector 1 is the next, and so on. The block size
that an operating system uses for its file system maybe different than the
sector size that a disk uses, but typically the block size is a multiple of the
sector size.  Xv6's block size is identical to the disk's sector size.  To
represent a block xv6 has a structure
.code "struct buf"
.line buf.h:/^struct.buf/ .
The
data stored in this structure is often out of sync with the disk: it might have
not yet been read in from disk (the disk is working on it but hasn't returned
the sector's content yet), or it might have been updated but not yet written
out.  The driver must ensure that the rest of xv6 doesn't get confused when the
structure is out of sync with the disk.
.\"
.\" -------------------------------------------
.\"
.section "Code: Disk driver"
.PP
The IDE device provides access to disks connected to the
PC standard IDE controller.
IDE is now falling out of fashion in favor of SCSI and SATA,
but the interface is simple and lets us concentrate on the
overall structure of a driver instead of the details of a
particular piece of hardware.
.PP
Xv6 represent file system blocks using
.code-index "struct buf"
.line buf.h:/^struct.buf/ .
.code BSIZE
.line fs.h:/BSIZE/
is identical to the IDE's sector size and thus
each buffer represents the contents of one sector on a particular
disk device.  The
.code dev
and
.code sector
fields give the device and sector
number and the
.code data
field is an in-memory copy of the disk sector.
Although the xv6 file system chooses
.code BSIZE
to be identical to the IDE's sector size, the driver can handle
a
.code BSIZE
that is a multiple of the sector size. Operating systems often use
bigger blocks than 512 bytes to obtain higher disk throughput.
.PP
The
.code flags
track the relationship between memory and disk:
the
.code-index B_VALID
flag means that
.code data
has been read in, and
the 
.code-index B_DIRTY 
flag means that
.code data
needs to be written out.
.PP
The kernel initializes the disk driver at boot time by calling
.code-index ideinit
.line ide.c:/^ideinit/
from
.code-index main
.line main.c:/ideinit/ .
.code Ideinit
calls
.code-index picenable
and
.code-index ioapicenable
to enable the
.code-index IDE_IRQ
interrupt
.lines ide.c:/picenable/,/ioapicenable/ .
The call to
.code picenable
enables the interrupt on a uniprocessor;
.code ioapicenable
enables the interrupt on a multiprocessor,
but only on the last CPU
.code ncpu-1 ): (
on a two-processor system, CPU 1 handles disk interrupts.
.PP
Next,
.code-index ideinit
probes the disk hardware.
It begins by calling
.code-index idewait
.line ide.c:/idewait.0/
to wait for the disk to
be able to accept commands.
A PC motherboard presents the status bits of the disk hardware on I/O port
.address 0x1f7 .
.code Idewait
.line ide.c:/^idewait/
polls the status bits until the busy bit
.code-index IDE_BSY ) (
is clear and the ready bit
.code-index IDE_DRDY ) (
is set.
.PP
Now that the disk controller is ready,
.code ideinit
can check how many disks
are present.
It assumes that disk 0 is present,
because the boot loader and the kernel
were both loaded from disk 0,
but it must check for disk 1.
It writes to I/O port
.address 0x1f6
to select disk 1
and then waits a while for the status bit to show
that the disk is ready
.lines ide.c:/Check.if.disk.1/,/^..}/ .
If not, 
.code ideinit
assumes the disk is absent.
.PP
After
.code ideinit ,
the disk is not used again until the buffer cache calls
.code-index iderw ,
which updates a locked buffer
as indicated by the flags.
If
.code-index B_DIRTY
is set,
.code iderw
writes the buffer
to the disk; if
.code-index B_VALID
is not set,
.code-index iderw
reads the buffer from the disk.
.PP
Disk accesses typically take milliseconds,
a long time for a processor.
The boot loader
issues disk read commands and reads the status
bits repeatedly until the data is ready (see Appendix \*[APP:BOOT]).
This 
.italic-index polling 
or 
.italic-index "busy waiting"
is fine in a boot loader, which has nothing better to do.
In an operating system, however, it is more efficient to
let another process run on the CPU and arrange to receive
an interrupt when the disk operation has completed.
.code Iderw
takes this latter approach,
keeping the list of pending disk requests in a queue
and using interrupts to find out when each request has finished.
Although
.code iderw
maintains a queue of requests,
the simple IDE disk controller can only handle
one operation at a time.
The disk driver maintains the invariant that it has sent
the buffer at the front of the queue to the disk hardware;
the others are simply waiting their turn.
.PP
.code Iderw
.line ide.c:/^iderw/
adds the buffer
.code b
to the end of the queue
.lines ide.c:/Append/,/pp.=.b/ .
If the buffer is at the front of the queue,
.code-index iderw
must send it to the disk hardware
by calling
.code-index idestart
.line ide.c:/Start.disk/,/idestart/ ;
otherwise the buffer will be started once
the buffers ahead of it are taken care of.
.PP
.code Idestart
.line ide.c:/^idestart/
issues either a read or a write for the buffer's device and sector,
according to the flags.
If the operation is a write,
.code idestart
must supply the data now
.line ide.c:/outsl/
and the interrupt will signal that the data has been written to disk.
If the operation is a read, the interrupt will signal that the
data is ready, and the handler will read it.
Note that
.code-index idestart
has detailed knowledge about the IDE device, and writes the right values at the
right ports.  If any of these 
.code outb
statements is wrong, the IDE will do something differently than what we want.
Getting these details right is one reason why writing device drivers is
challenging.
.PP
Having added the request to the queue and started it if necessary,
.code iderw
must wait for the result.  As discussed above,
polling does not make efficient use of the CPU.
Instead,
.code-index iderw
sleeps, waiting for the interrupt handler to 
record in the buffer's flags that the operation is done
.lines ide.c:/while.*VALID/,/sleep/ .
While this process is sleeping,
xv6 will schedule other processes to keep the CPU busy.
.PP
Eventually, the disk will finish its operation and trigger an interrupt.
.code-index trap
will call
.code-index ideintr
to handle it
.line trap.c:/ideintr/ .
.code Ideintr
.line ide.c:/^ideintr/
consults the first buffer in the queue to find
out which operation was happening.
If the buffer was being read and the disk controller has data waiting,
.code ideintr
reads the data into the buffer with
.code-index insl
.lines ide.c:/Read.data/,/insl/ .
Now the buffer is ready:
.code ideintr
sets 
.code-index B_VALID ,
clears
.code-index B_DIRTY ,
and wakes up any process sleeping on the buffer
.lines ide.c:/Wake.process/,/wakeup/ .
Finally,
.code ideintr
must pass the next waiting buffer to the disk
.lines ide.c:/Start.disk/,/idestart/ .
.\"
.section "Real world"
.\"
Supporting all the devices on a PC motherboard in its full glory is much work,
because there are many devices, the devices have many features, and the protocol
between device and driver can be complex.  In many operating systems, the
drivers together account for more code in the operating system than the core
kernel.
.PP
Actual device drivers are far more complex than the disk driver in this chapter,
but the basic ideas are the same:
typically devices are slower than CPU, so the hardware uses
interrupts to notify the operating system of status changes.
Modern disk controllers typically
accept a 
.italic-index batch 
of disk requests at a time and even reorder
them to make most efficient use of the disk arm.
When disks were simpler, operating system often reordered the
request queue themselves.
.PP 
Many operating systems have drivers for solid-state disks because they provide
much faster access to data.  But, although a solid-state works very differently
from a traditional mechanical disk, both devices provide block-based interfaces
and reading/writing blocks on a solid-state disk is still more expensive than
reading/writing RAM.
.PP
Other hardware is surprisingly similar to disks: network device buffers
hold packets, audio device buffers hold sound samples, graphics card
buffers hold video data and command sequences.
High-bandwidth devices—disks, graphics cards, and network cards—often use
direct memory access (DMA) instead of the explicit I/O
.opcode insl , (
.opcode outsl )
in this driver.
DMA allows the disk or other controllers direct access to physical memory.
The driver gives the device the physical address of the buffer's data field and
the device copies directly to or from main memory,
interrupting once the copy is complete.
Using DMA means that the CPU is not involved at all in the transfer,
which can be more efficient and is less taxing for the CPU's memory caches.
.PP
Most of the devices in this chapter used I/O instructions to program them, which
reflects the older nature of these devices.  All modern devices are programmed
using memory-mapped I/O.  
.PP
Some drivers dynamically switch between polling and interrupts, because using
interrupts can be expensive, but using polling can introduce delay until the
driver processes an event.  For example, for a network driver that receives a
burst of packets, may switch from interrupts to polling since it knows that more
packets must be processed and it is less expensive to process them using polling.
Once no more packets need to be processed, the driver may switch back to
interrupts, so that it will be alerted immediately when a new packet arrives.
.PP
The IDE driver routed interrupts statically to a particular processor.  Some
drivers have a sophisticated algorithm for routing interrupts to processor so
that the load of processing packets is well balanced but good locality is
achieved too.  For example, a network driver might arrange to deliver interrupts
for packets of one network connection to the processor that is managing that
connection, while interrupts for packets of another connection are delivered to
another processor.  This routing can get quite sophisticated; for example, if
some network connections are short lived while others are long lived and the
operating system wants to keep all processors busy to achieve high throughput.
.PP
If user process reads a file, the data for that file is copied twice.  First, it
is copied from the disk to kernel memory by the driver, and then later it is
copied from kernel space to user space by the 
.code read
system call.  If the user process, then sends the data on the network, then
the data is copied again twice: once from user space to kernel space and from
kernel space to the network device.  To support applications for which low
latency is important (e.g., a Web serving static Web pages), operating systems
use special code paths to avoid these many copies.  As one example,
in real-world operating systems, 
buffers typically match the hardware page size, so that
read-only copies can be mapped into a process's address space
using the paging hardware, without any copying.
.\"
.section "Exercises"
.\"
1. Set a breakpoint at the first instruction of syscall() to catch the very
first system call (e.g., br syscall). What values are on the stack at this
point?  Explain the output of x/37x $esp at that breakpoint with each value
labeled as to what it is (e.g., saved %ebp for trap, trapframe.eip, scratch
space, etc.).

2. Add a new system call that returns the uptime (i.e., return the number
of ticks since xv6 booted).

3. Write a driver for a disk that supports the SATA standard (search for SATA on
the Web). Unlike IDE, SATA isn't obsolete.  Use SATA's tagged command queuing to
issue many commands to the disk so that the disk internally can reorder commands
to obtain high performance.

4. Add simple driver for an Ethernet card.
