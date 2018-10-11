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
A word on terminology: Although the official x86 term is exception,
xv6 uses the term
.italic-index trap , 
largely because it was the term
used by the PDP11/40 and therefore is the conventional Unix term.
Furthermore, this chapter uses the terms trap and interrupt interchangeably, but it
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
concurrently with other activities.
.\"
.section "X86 Interrupts"
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
.PP
Devices can generate interrupts
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
simple programmable interrupt controler (called the PIC).
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
board with multiple processors: it ignores interrupts from the PIC, and
configures the IOAPIC and local APIC.
.PP
The IO APIC has a table and the processor can program entries in the
table through memory-mapped I/O.
During initialization, xv6 programs to map interrupt 0 to IRQ 0, and
so on, but disables them all.  Specific devices enable particular
interrupts and say to which processor the interrupt should be routed.
For example, xv6 routes keyboard interrupts to processor 0
.line console.c:/^consoleinit/ .
Xv6 routes disk interrupts to the highest numbered processor on the
system, as we will see later in this chapter.
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
.\"
.section "X86 protection and interrupt handling"
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
register, in the field CPL.  On an interrupt or exception, the processor may
have to switch from user mode to kernel mode (e.g., when an interrupt arrives
while user code is running on the processor).
.PP
On the x86, interrupt handlers are defined in the interrupt descriptor
table (IDT). The IDT has 256 entries, each giving the
.register cs
and
.register rip
to be used when handling the corresponding interrupt.
.ig
pointer to the IDT table.
..
.PP
When a device raises an interrupt, the x86 allows it to specify
a trap number
.italic n
to identify the source of the interrupt.  For example, as mentioned above, xv6
programs the timer chip to interrupt with number
.code IRQ_TIMER
.line traps.h:/IRQ_TIMER/ ,
which corresponds to trap T_IRQ0
.line traps.h:/T_IRQ0/ .
Some trap numbers are predefined by the x86.  For example, if software
divides by zero, then the processor will use trap number
.code-index T_DIVIDE
.line traps.h:/T_DIVIDE/ 
to handle that exception.
The trap number is used as an index into the IDT.
.PP
On
receive an interrupt or exception, the x86 performs
the following steps:
.IP \[bu] 
Fetch the 
.italic n 'th
descriptor from the IDT,
where 
.italic n
is the argument of
.code int .
.IP \[bu] 
Save
.register rsp
and
.register ss
in CPU-internal registers.
.IP \[bu] 
Sets
.register ss
to NULL and
loads
.register rsp
from a task segment descriptor.
.IP \[bu] 
Push saved
.register ss.
.IP \[bu] 
Push saved
.register rsp.
.IP \[bu] 
Push
.register eflags.
.IP \[bu] 
Push
.register cs.
.IP \[bu] 
Push
.register rip.
.IP \[bu] 
Clear the IF bit in
.register eflags ,
but only on an interrupt.
.IP \[bu] 
Set 
.register cs
and
.register rip
to the values in the IDT entry for
.code n .
.PP
.figref intkstack 
shows the stack after the processor receives
an interrupt or exception.
For some traps (e.g., a page fault), the processor also pushes an
error word. 
.figure intkstack
.PP
Taking interrupt or exception
is a complex step, and one might wonder whether all
these actions are necessary.
For example, is it necessary to change stacks?
The kernel shouldn't use the stack of the user process, because it may not be valid.
The user process may be malicious or
contain an error that causes the user
.register rsp 
to contain an address that is not part of the process's user memory.
Instead, the hardware uses the
stack specified in the task segment, which is set by the kernel.
.PP
After receiving an interrupt or exception,
the
.register rip
is pointing to the address specified in the descriptor table, and the
instruction at that address is the next instruction to be executed and
the first instruction of the handler for
trap number
.italic n .
It is job of the operating system to implement these handlers, and
below we will see what xv6 does.
.PP
An operating system can use the
.code-index iret
instruction to return from an
interrupt or exception. It pops the saved values during the 
.code int
instruction from the stack, and resumes execution at the saved
.register rip.
.PP
Although the description above is x86 specific, every processor has
a mechanism like this one to handle interrupts and exceptions.
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
Xv6 programs the x86 hardware to perform a stack switch on a trap by
setting up a task segment descriptor through which the hardware loads a stack
segment selector and a new value for
.register rsp.
The function
.code-index switchuvm
.line vm.c:/^switchuvm/ 
stores the address of the top of the kernel stack of the user
process into the task segment descriptor.
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
.register r15
through
.register rax .
The result of this effort is that the kernel stack now contains a
.code "struct trapframe"
.line x86.h:/trapframe/
containing the processor registers at the time of the trap (see 
.figref trapframe ).
The processor pushes
.register ss,
.register rsp,
.register eflags,
.register cs, 
and
.register rip.
The processor or the trap vector pushes an error number,
and 
.code-index alltraps 
pushes the rest.
.PP
The trap frame contains all the information necessary
to restore the user mode processor registers
when the kernel returns to the current process,
so that the processor can continue exactly as it was when
the trap started.
.PP
Now that the user mode processor registers are saved,
.code-index alltraps
can finishing setting up the processor to run kernel C code.
It passes
.register rsp
as a first argument to the C function
.code trap
by moving it into
.register rdi
.line "'trapasm.S:/1:mov..%rsp/'" ,
following the C calling convention.
Thus,
.register rdi ,
the first argument,
points at the trap frame
.code alltraps
just constructed.
Then
.code alltraps
calls
.code trap
.line trapasm.S:/call.trap/ ,
which we will discus below.
.PP
After
.code trap 
returns,
.code-index trapret
restores the user mode registers,
popping values from the kernel stack.
Then, it discards the trap number and
the error code that trap vectors
pushed.
Finally, it returns to user
space by executing
.code-index iret .
.code Iret
pops the remaining values of the stack, loading the user stack
and program counter into
.register rsp
and
.register rip ,
respectively.
.PP
The discussion so far has talked about traps occurring in user mode,
but traps can also happen while the kernel is executing.
In that case the hardware does not switch stacks;
otherwise the same steps occur as in traps from user mode,
and the same xv6 trap handling code executes.
When 
.code iret
later restores a kernel mode 
.register cs,
the processor continues executing in kernel mode.
.PP
Xv6 calls
.code switchgs
on system calls when switching from user to kernel mode, as we will
see below.  To make the interrupt handling and system call path
similar,
.code alltraps
also calls
.code swapgs
when switching from user mode, but not when
handling an interrupt in kernel mode (because it is already in kernel
mode then).
To determine whether the processor is in kernel mode,
.code alltraps
compares the kernel code segment selector with the one saved on the stack
.line 'trapasm.S:/cmpw..SEG_KCODE/' .
If they are the same, then there is no need to call
.code swapgs .
Otherwise, it calls
.code swapgs .
.\"
.section "Code: Enabling/disabling interrupts"
.\"
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
enables interrupts on a processor.  The bootloader disables interrupts during
booting of the main cpu
and xv6 disables interrupts when booting the other processors
.line entryother.S:/cli/ .
The scheduler on each processor enables interrupts
.line proc.c:/sti/ .
To control that certain code fragments are not interrupted, xv6
disables interrupts during these code fragments.  For example,
.code trapret
above clears interrupts
.line trapasm.S:/^..cli/ .
.\"
.section "Code: C trap handler"
.\"
.PP
We saw that each trap handler sets
up a trap frame and then calls the C function
.code-index trap .
.code Trap
.line 'trap.c:/^trap!(/'
looks at the hardware trap number
.code-index tf->trapno
to decide why it has been called and what needs to be done.
The timer interrupts through vector 32 (which xv6 chose to handle IRQ
0), which xv6 setup in
.code-index idtinit 
.line main.c:/idtinit/ .
.code Trap
for a timer interrupt does just two things:
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
.PP
In addition to the expected hardware
devices, a trap can be caused by a spurious interrupt, an unwanted
hardware interrupt.
.ig
give a concrete example.
..
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
.section "Code: The first system call"
.\"
.PP
Chapter \*[CH:FIRST] ended with 
.code-index initcode.S
invoking a system call.
Let's look at that again
.line initcode.S:/'SYS_exec'/ .
The process pushed the arguments
for an 
.code-index exec
call on the process's stack, and put the
system call number in
.register rax.
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
.section "Code: System calls"
.\"
.PP
X86 processors for 32-bit machines handled systems calls with the same mechanism
for interrupts and exceptions, and operating systems reserved one entry in the IDT
for system calls.  X86-64 processors have a special instruction for system
calls (
.code syscall ),
which saves less state than interrupts and exceptions do, and give the operating
system more flexibility on what to save and what not to save.  This allows
operating systems to optimize code paths for specific systems calls.  For
example, for systems calls that do little work (e.g., asking what the ID is of
the current process), it is unnecessary to save and restore all the
state that interrupts and exceptions do. 
.PP
The
.code syscall
instruction itself does less work than what the processor does on
an interrupt:
.IP \[bu] 
It saves
.register eflags
into
.register r11
and masks
.register eflags
using
a value that kernel programs into a special register reserved for this
purpose, namely
.code MSR_SFMASK
.line vm.c:/MSR_SFMASK/ .
The processor clears in
.register eflags
every bit corresponding to a bit that is set in the MSR_SFMASK.
.IP \[bu]
It saves
.register rip
into
.register rcx ,
and loads
.register rip
with a value that the kernel programs into a special register reserved
for this purpose, namely
.code MSR_LSTAR
.line vm.c:/MSR_LSTAR/ .
Xv6 programs the address of
.code sysentry
into this location.
.IP \[bu] 
It loads
.register cs
and
.register ss
selectors with values from
.code MSR_STAR
.line vm.c:/MSR_STAR/ .
xv6 programs
.code SEG_KCODE
into
.code MSR_STAR ,
which has the privilege level set to kernel mode.
.PP
Thus, after executing
.code syscall ,
xv6 starts running at
.code sysentry
.line trapasm.S:/^sysentry/
in kernel mode with interrupts disabled.
Note that the
.code syscall
instruction doesn't consult the IDT and does not save the user's stack pointer,
unlike interrupts and exceptions. If the kernel wants
to use
.register rsp ,
it is the responsibility of the kernel to
save the value of the stack pointer before changing it.
.PP
.code
Syscall allows entering into and returning from the kernel with low overhead. As
a result, a system call that can be implemented with a few assembly instructions
(e.g., return the PID of the current process) can run quickly.  The processor
executes the few steps to transfer to the kernel (saving
.register eflags
and
.register rip ,
and loading them with new values), then it runs the instructions for the system
call, and returns back to user space by calling
.code sysret ,
which copies
.register rcx
into
.register rip
and loads
.register eflags
from
.register r11 .
.PP
Xv6 doesn't optimize for performance. It always runs C code for a system call
and thus needs a stack to call into a C function.  The kernel
cannot assume that the value that a user program stored in
.register rsp
is save to use; the value may be an invalid address (e.g., without a mapping
in the page table).  Thus, it must save
.register rsp
and load it with the address of the process's kernel stack.
Where can xv6 save
.register rsp ?
The scratch space must be per core, because each core may
be executing a system call.
.PP
To quickly find a per-core area, the processor provides per core a pair of
special registers
.code-index MSR_GS_BASE
and
.code-index MSR_GS_KERNBASE .
During initialization,
each core stores a pointer to its
.code-index "struct cpu"
into both registers
.line vm.c:/MSR_GS_KERNBASE/ .
This struct
.line proc.h:/^struct.cpu/
records
the process currently running
on the processor (if any),
the processor's unique hardware identifier
.code apicid ), (
and some other information.
To refer to
.code MSR_GS_BASE ,
the kernel must use the code segment selector
.register gs ,
which xv6 programs to contain
.code SEG_KDATA
.line vm.c:/SEG_KDATA/ .
With this setup a core can refer to
the first entry of its
.code "struct cpu"
using
.code %gs:0 .
Because user code can also program
.code MSR_GS_BASE ,
the processor provides a special instruction
.code swapgs ,
which swaps the contents of
.code MSR_GS_BASE
and
.code MSR_GS_KERNBASE ,
causing the value of MSR_GS_KERNBASE to be
loaded into
.code MSR_GS_BASE .
Since user code cannot program
.code MSR_GS_KERNBASE ,
.code swapgs
will cause
.code MSR_GS_BASE
to have a valid pointer to this core's
.code "struct cpu" .
.PP
Returning to
.code sysentry
.line trapasm.S:/^sysentry/ ,
after 
.code sysentry
executes
.code swapps ,
it saves
.register rax
(which contains the number of the system call)
and
.register rsp
(which contains the user stack pointer)
into the core's
.code "struct cpu" .
The
.code "struct cpu"
has reserved two fields for this purpose
.line proc.h:/^struct.cpu/ .
Next,
.code sysentry
loads the current process's kernel stack
into
.register rsp
.lines trapasm.S:/movq...gs/,/movq...rax,..rsp/ .
Then,
.code sysentry
restores
.register rax ,
and builds up the syscall frame
.line x86.h:/^struct.sysframe/ ,
which we briefly saw in Chapter \*[CH:FIRST]. It pushes
the registers that
.code syscall
used to store the process's instruction pointer and eflags,
along with
.register rax .
Next, it saves callee-saved registers and the registers
that are used to pass arguments.  It passes a pointer
to the syscall frame to the C function
.code syscall
.line syscall.c:/^syscall/
by storing the stack pointer into the register
for the first argument.
.PP
Note that a system call saves less state than an interrupt;
.code "struct sysframe"
and
.code "struct trapframe"
are different).  For example, a system call doesn't save the caller-saved
registers: it is the job of the caller to save them, if it wants them to be
saved.  Interrupts can force a user process to enter the kernel at anytime, and
the process has no opportunity to save caller-saved registers or any registers
for that matter.  Thus, the hardware and xv6 must save all of a user process's
state so that it can be restored when returning to user space.
.PP
.code-index Syscall
.line syscall.c:/'^syscall'/ 
loads the system call number from the syscall frame, which
contains the saved
.register rax,
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
When the system call returns to user space,
.code sysexit
.line trapasm.S:/^sysexit/
will load the values
from
.code-index cp->sf
into the machine registers
and return to user space
using
.code sysret .
.PP
Thus, when 
.code exec
returns, it will return the value
that the system call handler returned
.line "'syscall.c:/rax = syscalls/'" .
System calls conventionally return negative numbers to indicate
errors, positive numbers for success.
If the system call number is invalid,
.code-index syscall
prints an error and returns \-1.
.PP
.code sysexit
disables interrupts
while restoring machine registers and the user stack to
ensure that an interrupt doesn't run on a user stack.  After
.code "mov (%rsp),%rsp" ,
the user stack is in
.register rsp
but the processor is still in kernel mode.
Thus, if an interrupt arrives right after this
.code mov
instruction,
the processor will not switch to a kernel stack (because it is still in kernel
mode) and will attempt to the user stack, which may not be valid.
By disabling interrupts,
.code sysexit
ensures that this situation can never happen.
.\"
.section "Code: System call arguments"
.\"
.PP
Later chapters will examine the implementation of
particular system calls.
This chapter is concerned with the mechanisms for system calls.
There is one bit of mechanism left: finding the system call arguments.
The helper functions
.code argint ,
.code argaddr ,
.code argptr ,
.code argstr ,
and
.code argfd
retrieve the 
.italic n 'th 
system call
argument, as either an integer, pointer, a string, or a file descriptor.
.code-index argint
and
.code-index argaddr
use the function
.code fetcharg
to locate the
.italic n'th 
argument. The C calling conventions specify that argument 0 is passed
through
.register rdi ,
argument 1 through
.register rsi ,
argument 2 through
.register rdx ,
argument 3 through
.register r10 ,
argument 4 through
.register r8 ,
and argument 5 through
.register r9.
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
.code-index fetchaddr ,
is like
.code fetchint ,
but retrieves 64-bit value instead of a 32-bit int.
.PP
.code-index argptr
fetches the
.italic n th 
system call argument and checks that this argument is a valid
user-space pointer.
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
.code argaddr ,
.code argptr , 
and 
.code argstr
and then call the real implementations.
In chapter \*[CH:MEM],
.code sys_exec
uses these functions to get at its arguments.


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
.code-index ioapicenable
to enable the
.code-index IDE_IRQ
interrupt
.line ide.c:/ioapicenable/ .
The call to
.code ioapicenable
enables the interrupt only on the last CPU
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
.line ide.c:/outsl/ .
.code idestart
moves the data to a buffer in the disk controller
using the
.code outsl
instruction; 
using CPU instructions to move data to/from device hardware
is called programmed I/O.
Eventually the disk hardware will raise an
interrupt to signal that the data has been written to disk.
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
yields the CPU for other processes by sleeping,
waiting for the interrupt handler to 
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
reads the data from a buffer in the disk controller
into memory with
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
When disks were simpler, operating systems often reordered the
request queue themselves.
.PP 
Many operating systems have drivers for solid-state disks because they provide
much faster access to data.  But, although a solid-state disk works very differently
from a traditional mechanical disk, both devices provide block-based interfaces
and reading/writing blocks on a solid-state disk is still more expensive than
reading/writing RAM.
.PP
Other hardware is surprisingly similar to disks: network device buffers
hold packets, audio device buffers hold sound samples, graphics card
buffers hold video data and command sequences.
High-bandwidth devices—disks, graphics cards, and network cards—often use
direct memory access (DMA) instead of programmed I/O
.opcode insl , (
.opcode outsl ).
DMA allows the device direct access to physical memory.
The driver gives the device the physical address of the buffer's data and
the device copies directly to or from main memory,
interrupting once the copy is complete.
DMA is faster and more efficient than programmed I/O
and is less taxing for the CPU's memory caches.
.PP
Some drivers dynamically switch between polling and interrupts, because using
interrupts can be expensive, but using polling can introduce delay until the
driver processes an event.  For example, a network driver that receives a
burst of packets may switch from interrupts to polling since it knows that more
packets must be processed and it is less expensive to process them using polling.
Once no more packets need to be processed, the driver may switch back to
interrupts, so that it will be alerted immediately when a new packet arrives.
.PP
The IDE driver routes interrupts statically to a particular processor.  Some
drivers configure the IO APIC
to route interrupts to multiple processors to spread out
the work of processing packets.
For example, a network driver might arrange to deliver interrupts
for packets of one network connection to the processor that is managing that
connection, while interrupts for packets of another connection are delivered to
another processor.  This routing can get quite sophisticated; for example, if
some network connections are short lived while others are long lived and the
operating system wants to keep all processors busy to achieve high throughput.
.PP
If a program reads a file, the data for that file is copied twice.  First, it
is copied from the disk to kernel memory by the driver, and then later it is
copied from kernel space to user space by the 
.code read
system call.  If the program then sends the data over the network, 
the data is copied twice more: from user space to kernel space and from
kernel space to the network device.  To support applications for which 
efficiency is important (e.g., serving popular images on the Web), operating systems
use special code paths to avoid copies.  As one example,
in real-world operating systems, 
buffers typically match the hardware page size, so that
read-only copies can be mapped into a process's address space
using the paging hardware, without any copying.
.\"
.section "Exercises"
.\"
.PP
1. Set a breakpoint in
.code trap
to catch the first timer interrupt. What values are on the stack at this
point?  Explain the output of x/37x $rsp at that breakpoint with each value
labeled as to what it is (e.g., saved %ebp for trap, trapframe.rip, scratch
space, etc.).
.PP
2.  Add a new system call to get the current UTC time and return it to the user
program. You may want to use the helper function,
.code cmostime
.line lapic.c:/cmostime/ ,
to read the real time clock. The file date.h contains the definition
of the
.code "struct rtcdate"
.line date.h:/rtcdate/ ,
which you will provide as an argument to
.code cmostime
as a pointer.
.PP
3. Write a driver for a disk that supports the SATA standard (search for SATA on
the Web). Unlike IDE, SATA isn't obsolete.  Use SATA's tagged command queuing to
issue many commands to the disk so that the disk internally can reorder commands
to obtain high performance.
.PP
4. Add simple driver for an Ethernet card.
