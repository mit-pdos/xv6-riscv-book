.ig
  terminology:
    process: refers to execution in user space, or maybe struct proc &c
    process memory: the lower part of the address space
    process has one thread with two stacks (one for in kernel mode and one for
    in user mode)
talk a little about initial page table conditions:
    paging not on, but virtual mostly mapped direct to physical,
    which is what things look like when we turn paging on as well
    since paging is turned on after we create first process.
  mention why still have SEG_UCODE/SEG_UDATA?
  do we ever really say what the low two bits of %cs do?
    in particular their interaction with PTE_U
  sidebar about why it is extern char[]
..

.chapter CH:FIRST "Operating system organization"
.PP
A key requirement for an operating system is to support several activities at once.  For
example, using the system call interface described in
chapter \*[CH:UNIX]
a process can start new processes with 
.code fork .
The operating system must 
.italic-index time-share 
the resources of the computer among these processes.
For example, even if there are more processes
than there are hardware processors, the operating
system must ensure that all of the processes
make progress.  The operating system must also arrange for
.italic-index isolation 
between the processes.
That is, if one process has a bug and fails, it shouldn't affect processes that
don't depend on the failed process.
Complete isolation, however, is too strong, since it should be possible for
processes to interact; pipelines are an example.
Thus
an operating system must fulfil three requirements: multiplexing, isolation,
and interaction.
.PP
This chapter provides an overview of how operating systems are organized to achieve
these 3 requirements.  It turns out there are many ways to do so, but this text
focuses on mainstream designs centered around a 
.italic-index "monolithic kernel" , 
which is used by many Unix operating systems.  This chapter 
introduces xv6's design by
tracing the creation of the first process when xv6 starts
running.  In doing so, the text provides a glimpse of the implementation of all
major abstractions that xv6 provides, how they interact, and how the three
requirements of multiplexing, isolation, and interaction are met.  Most of xv6
avoids special-casing the first process, and instead reuses code that xv6 must
provide for standard operation.  Subsequent chapters will explore each
abstraction in more detail.
.PP
Xv6 runs on a RISC-V development board, and much of its low-level
functionality (for example, its process implementation) is specific to
RISC-V.  RISC-V is a 64-bit processor, and Xv6 is written in "LP64" C,
which means long (L) and pointers (P) in the C programming language
are 64 bits, but int is 32-bit.  This book assumes the reader has done
a bit of machine-level programming on some architecture, and will
introduce RISC-V-specific ideas as they come up.  A useful reference
for RISC-V is ``The RISC-V Reader: An Open Architecture Atlas''~\cite{riscv}.

.\"
.section "Abstracting physical resources"
.\"
.PP
The first question one might ask when encountering an operating system is why
have it at all?  That is, one could implement the system calls in
.figref unix:api
as a library, with which applications link.  In this plan,
each application could even have its own library tailored to its needs.
Applications could directly interact with hardware resources
and use those resources in the best way for the application (e.g., to achieve
high or predictable performance).  Some operating systems for
embedded devices or real-time systems are organized in this way.
.PP
The downside of this library approach is that, if there is more than one
application running, the applications must be well-behaved.
For example, each application must periodically give up the
processor so that other applications can run.
Such a 
.italic cooperative 
time-sharing scheme may be OK if all applications trust each
other and have no bugs. It's more typical for applications
to not trust each other, and to have bugs, so one often wants
stronger isolation than a cooperative scheme provides.
.PP
To achieve strong isolation it's helpful to forbid applications from
directly accessing sensitive hardware resources, and instead to abstract the
resources into services.  For example, applications interact with a file system
only through
.code open ,
.code read ,
.code write , 
and
.code close
system calls,
instead of read and writing raw disk sectors. 
This provides the application with the convenience of pathnames, and it allows
the operating system (as the implementor of the interface) to manage the disk. 
.PP
Similarly, Unix transparently switches hardware processors among processes,
saving and restoring register state as necessary,
so that applications don't have to be
aware of time sharing.  This transparency allows the operating system to share
processors even if some applications are in infinite loops.
.PP
As another example, Unix processes use 
.code exec
to build up their memory image, instead of directly interacting with physical
memory.  This allows the operating system to decide where to place a process in
memory; if memory is tight, the operating system might even store some of
a process's data on disk.
.code Exec
also provides
users with the convenience of a file system to store executable program images.  
.PP 
Many forms of interaction among Unix processes occur via file descriptors.
Not only do file descriptors abstract away many details (e.g.,
where data in a pipe or file is stored), they also are defined in a
way that simplifies interaction.
For example, if one application in a pipeline fails, the kernel
generates end-of-file for the next process in the pipeline.
.PP
As you can see, the system call interface in
.figref unix:api
is carefully designed to provide both programmer convenience and
the possibility of strong isolation.  The Unix interface
is not the only way to abstract resources, but it has proven to be a very good
one.

.\"
.section "User mode, kernel mode, and system calls"
.\"
.PP
Strong isolation requires a hard boundary between applications and the operating
system.  If the application makes a mistake, we don't want the operating system
to fail or other applications to fail. Instead, the operating system should be
able to clean up the failed application and continue running other applications.
To achieve strong isolation, the operating system must arrange that applications cannot modify (or even
read) the operating system's data structures and instructions and that
applications cannot access other process's memory.
.PP
Processors provide hardware support for strong isolation.   For
example, a RISC-V processor, has three modes in which
the processor can execute instructions:
.italic-index "machine mode" ,
.italic-index "kernel mode" 
(called
.italic-index "supervisor mode"
in RISC-V terminology), and
.italic-index "user mode" .
Instructions executing in machine mode have full privilege and a
processor starts in machine mode.  Machine mode is mostly intended for
configuring a computer.  Xv6 executes a few lines of machine mode and
then jumps into kernel mode.
.PP
In kernel mode the processor is allowed to execute 
.italic-index "privileged instructions" .
For example, enabling and disabling interrupts,  reading and writing
the register that holds the address of a page table, etc.
If an application in user mode attempts to execute
a privileged instruction, then the processor doesn't execute the instruction, but switches
to kernel mode so that the software in kernel mode can clean up the application,
because it did something it shouldn't be doing. 
.figref unix:os
in Chapter  \*[CH:UNIX] illustrates this organization.  An application can
execute only user-mode instructions (e.g., adding numbers, etc.) and is said to
be running in 
.italic-index "user space"  ,
while the software in kernel mode can also execute privileged instructions and
is said to be running in
.italic-index "kernel space"  .
The software running in kernel space (or in kernel mode) is called
the
.italic-index "kernel" .
.PP
An application that wants to invoke a kernel function (e.g., the
.code read
system call in xv6) must to
transition to the kernel.  Processors provide a special instruction that switches the
processor from user mode to kernel mode and enters the kernel at an entry point
specified by the kernel.  (The RISC-V
processor provides the 
.code ecall
instruction for this purpose.)  Once the processor has switched to kernel mode,
the kernel can then validate the arguments of the system call, decide whether
the application is allowed to perform the requested operation, and then deny it
or execute it.  It is important that the kernel sets the entry point for
transitions to kernel mode; if the application could decide the kernel entry
point, a malicious application could enter the kernel at a point where the
validation of arguments etc. is skipped.
.\"
.section "Kernel organization"
.\"
.PP
A key design question is what part of the operating
system should run in kernel mode. 
One possibility is that the entire operating system resides
in the kernel, so that the implementations of all system calls
run in kernel mode.
This organization is called a
. italic-index "monolithic kernel"  .
.PP
In this organization the entire operating system runs with full hardware
privilege. This organization is convenient because the OS designer doesn't have
to decide which part of the operating system doesn't need full hardware
privilege.  Furthermore, it easy for different parts of the operating system to
cooperate.  For example, an operating system might have a buffer cache that can
be shared both by the file system and the virtual memory system. 
.PP
A downside of the monolithic organization is that the interfaces between
different parts of the operating system are often complex (as we will see in the
rest of this text), and therefore it is easy for an operating system developer
to make a mistake.  In a monolithic kernel, a mistake is fatal, because an error
in kernel mode will often result in the kernel to fail.  If the kernel fails,
the computer stops working, and thus all applications fail too.  The computer
must reboot to start again.
.PP
To reduce the risk of mistakes in the kernel, OS designers can minimize the
amount of operating system code that runs in kernel mode, and execute the
bulk of the operating system in user mode.
This kernel organization is called a
. italic-index "microkernel"  .
.figure mkernel
.PP
.figref mkernel
illustrates this microkernel design.  In the figure, the file system runs as a
user-level process.  OS services running as processes are called servers.
To allow applications to interact with the
file server, the kernel provides an inter-process communication
mechanism to send messages from one
user-mode process to another.  For example, if an application like the shell
wants to read or write a file, it sends a message to the file server and waits
for a response. 
.PP
In a microkernel, the kernel interface consists of a few low-level
functions for starting applications, sending messages,
accessing device hardware, etc.  This organization allows the kernel to be 
relatively simple, as most of the operating system
resides in user-level servers.
.PP
Xv6 is
implemented as a monolithic kernel, following most Unix operating systems.
Thus, in xv6, the kernel interface corresponds to the operating system
interface, and the kernel implements the complete operating system.  Since 
xv6 doesn't provide many services, its kernel is smaller than some
microkernels.
.\"
.section "Process overview"
.\"
.PP
The unit of isolation in xv6 (as in other Unix operating systems) is a 
.italic-index "process" .
The process abstraction prevents one process from wrecking or spying on
another process's memory, CPU, file descriptors, etc.  It also prevents a process
from wrecking the kernel itself, so that a process can't subvert the kernel's
isolation mechanisms.
The kernel must implement the process abstraction with care because
a buggy or malicious application may trick the kernel or hardware in doing
something bad (e.g., circumventing enforced isolation).  The mechanisms used by
the kernel to implement processes include the user/kernel mode flag, address spaces,
and time-slicing of threads.
.PP
To help enforce isolation, the process abstraction provides the
illusion to a program that it has its own private machine.  A process provides
a program with what appears to be a private memory system, or
.italic-index "address space" , 
which other processes cannot read or write.
A process also provides the program with what appears to be its own
CPU to execute the program's instructions.
.PP
Xv6 uses page tables (which are implemented by hardware) to give each process
its own address space. The RISC-V page table
translates (or ``maps'') a
.italic-index "virtual address"
(the address that an RISC-V instruction manipulates) to a
.italic-index "physical address"
(an address that the processor chip sends to main memory).
.figure as
.PP
Xv6 maintains a separate page table for each process that defines that process's
address space.  As illustrated in 
.figref as ,
an address space includes the process's
.italic-index "user memory"
starting at virtual address zero. Instructions come first,
followed by global variables, then the stack,
and finally a ``heap'' area (for malloc)
that the process can expand as needed.
Xv6 runs on a RISC-V processor with 39 bits of virtual addresses,
so the maximum address is 2^39-1 = 0x3fffffffff.
At the top of the address space xv6 reserves some
.italic-index "trampoline"
memory to switch to the kernel, as we will explain later.
.PP
The xv6 kernel maintains many pieces of state for each process,
which it gathers into a
.code-index "struct proc"
.line kernel/proc.h:/^struct.proc/ .
A process's most important pieces of kernel state are its 
page table, its kernel stack, and its run state.
We'll use the notation
.code-index p->xxx
to refer to elements of the
.code proc
structure.
.PP
Each process has a thread of execution (or 
.italic-index thread
for short) that executes the process's instructions.
A thread can be suspended and later resumed.
To switch transparently between processes,
the kernel suspends the currently running thread and resumes another process's
thread.  Much of the state of a thread (local variables, function call return
addresses) is stored on the thread's stacks.
Each process has two stacks: a user stack and a kernel stack
.code-index p->kstack  ). (
When the process is executing user instructions, only its user stack
is in use, and its kernel stack is empty.
When the process enters the kernel (for a system call or interrupt),
the kernel code executes on the process's kernel stack; while
a process is in the kernel, its user stack still contains saved
data, but isn't actively used.
A process's thread alternates between actively using its user stack
and its kernel stack. The kernel stack is separate (and protected from
user code) so that the kernel
can execute even if a process has wrecked its user stack.
.PP
When a process makes a system call, the processor switches to the 
kernel stack, raises the hardware privilege level, and starts
executing the kernel instructions that implement the system call.
When the system call completes, the kernel returns to user space:
the hardware lowers its privilege level, switches back to the
user stack, and resumes executing user instructions just after
the system call instruction.
A process's thread
can ``block'' in the kernel to wait for I/O, and resume where it left
off when the I/O has finished.
.PP
.code-index p->state 
indicates whether the process is allocated, ready
to run, running, waiting for I/O, or exiting.
.PP
.code-index p->pagetable
holds the process's page table, in the format
that the RISC-V hardware expects.
xv6 causes the paging hardware to use a process's
.code p->pagetable
when executing that process.
A process's page table also serves as the record of the
addresses of the physical pages allocated to store the process's memory.
.\"
.section "Code: starting xv6 and the shell"
.\"
To make xv6 more concrete, we'll overview how the kernel starts and
runs a shell. The subsequent chapters will describe the mechanisms
that show up in this overview in more detail.
.PP
When a RISC-V development board powers on, it initializes
itself and runs a program boot loader which is stored in read-only
memory.  The boot loader loads the xv6 kernel into memory.  Then, in
machine mode, the processor executes xv6 starting at
.code-index start
.line kernel/entry.S:/^_entry/ .
Xv6 starts with the RISC-V paging hardware disabled:
virtual addresses map directly to physical addresses.
.PP
The loader loads the xv6 kernel into memory at physical address
.address 0x80000000 .
The reason it places the kernel at
.address 0x80000000
rather than
.address 0x0
is because the address range
.address 0x0:0x80000000
contains I/O devices.
.PP
The instructions at
.code _entry
set up a stack so that xv6 can run C code.
xv6 declares space for an initial stack,
.code stack0 ,
in the file
.code start.c
.line kernel/start.c:/stack0/ .
The code at
.code _entry
loads the stack pointer register
.register sp
with the address
.code stack0
+ 4096, the top of the stack, because the stack
on RISC-V grows down.
Now we have a stack,
.code _entry
calls into C code at
.code mstart
.line kernel/start.c:/^mstart/ .
.PP
The function
.code mstart
prepares for running in kernel mode.
To enter kernel mode, the RISC-V processor
provides the instruction
.code mret .
This instruction assumes that the processor
entered machine mode from supervisor mode.
.code mstart
sets up the processor to pretend
that machine mode was entered
from supervisor mode:
it sets the previous privilege mode to
supervisor in the register
.register mstatus ,
it sets the return address to
.code main
by writing
.code main 's
address into
the register
.register mepc ,
disables virtual memory in supervisor mode
by writing
.code 0
into the page-table register
.register satp ,
and delegates all interrupts and exceptions
to supervisor mode.
.PP
Before jumping into supervisor mode,
.code mstart
performs one more task: it programs the clock
chip to generate interrupts and arranges
that on a clock interrupt the program
counter will be set to
.code machinevec
.line kernel/kernelvec.S:/^machinevec/
by setting the register
.register mtvec
to the address of
.code machinevec .
With this bookkeeping out of the way,
.code mstart
"returns" to supervisor
mode by calling
.code mret .
This causes the program counter to change
to
.code main
.line kernel/main.c:/^main/ .
.PP
After
.code main
.line kernel/main.c:/^main/  
initializes several devices and subsystems, 
it creates the first process by calling 
.code userinit
.line kernel/proc.c:/^userinit/  .
The first process is executing a small program,
.code-index initcode.S 
.line user/initcode.S:1 .
The first action of 
.code initcode.S
is to invoke  the
.code exec
system call to replace itself with
.code-index /init ,
loaded out of the file system.
Invoking
.code exec
causes
.code initcode.S
to enter the kernel and execute
.code exec
.line kernel/exec.c:/^exec/ .
As we saw in Chapter \*[CH:UNIX], 
.code-index exec
replaces the memory and registers of the
current process with a new program (in this case,
.code /init ),
but it leaves the
file descriptors, process id, and parent process unchanged.
Once the kernel has completed the
.code exec
system call, the kernel will return to user space and run
.code-index /init .
.code Init
.line user/init.c:/^main/
creates a new console device file
if needed
and then opens it as file descriptors 0, 1, and 2.
Then it loops,
starting a console shell, 
handles orphaned zombies until the shell exits,
and repeats.
The system is up.
.\"
.section "Real world"
.\"
.PP
In the real world, one can find both monolithic kernels and microkernels. Many
Unix kernels are monolithic. For example, Linux has a monolithic kernel,
although some OS functions run as user-level servers (e.g., the windowing
system).  Kernels such as L4, Minix, QNX are organized as a microkernel with
servers, and have seen wide deployment in embedded settings.
.PP
Most operating systems have adopted the process concept, and most
processes look similar to xv6's.  Modern operating systems, however,
support several threads within a process, to allow a single process to
exploit multicore processors.  Supporting multiple threads in a
process involves quite a bit of machinery that xv6 doesn't have,
including potential interface changes (e.g., Linux's
.code clone ,
a variant of
.code fork ),
to control which parts of
a process threads share.
.\"
.section "Exercises"
.\"
1. Set a breakpoint at swtch.  Single step with gdb's
.code stepi
through the ret to
.code forkret ,
then use gdb's
.code finish
to proceed to
.code sysexit ,
then
.code stepi
until you get to
.code initcode 
at virtual address zero.

2.
.code KERNBASE 
limits the amount of memory a single process can use,
which might be irritating on a machine with a full 4 GB of RAM.
Would raising
.code KERNBASE
allow a process to use more memory?
