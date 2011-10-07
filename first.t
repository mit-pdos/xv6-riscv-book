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
.chapter CH:FIRST "The first process"
.PP
This chapter explains what happens when xv6 first starts running, through the
creation of the first process.  In doing so, the text provides a glimpse of the
implementation of all major abstractions that xv6 provides, and how they
interact.  Most of xv6 avoids special-casing the first process, and instead
reuses code that xv6 must provide for standard operation.  Subsequent chapters
will explore each abstraction in more detail.
.PP
Xv6 runs on Intel 80386 or later (``x86'') processors on a PC platform, and much
of its low-level functionality (for example, its process implementation) is
x86-specific. This book assumes the reader has done a bit of machine-level
programming on some architecture, and will introduce x86-specific ideas as they
come up. Appendix \*[APP:HW] briefly outlines the PC platform.
.\"
.section "Process overview"
.\"
.PP
A process is an abstraction that provides the
illusion to a program that it has its own abstract machine.  A process
provides a program with what appears to be a private memory system, or 
.italic-index "address space" , 
which other processes cannot read or write.  The xv6 kernel
multiplexes processes on the available processors transparently, ensuring that
each process receives some CPU cycles to run. 
.P1
address space of a process
user 
kernel
.address 0x80100000 .
.P2
.PP
Xv6 uses page tables (which are implemented to by hardware) to give each process
its own view of memory.  A 
.italic-index "page table"
maps a process's address to an address
that can be used to read physical memory. Xv6
maintains a separate page table for each process that defines that process's
address space.  As illustrated in Figure XXX, an address space includes the process's
.italic-index "user memory"
starting at virtual address zero. Instructions usually come first,
followed by global variables and a ``heap'' area (for malloc)
that the process can expand as needed.
.PP
Each process's address space maps the kernel's instructions
and data as well as the user program's memory.
When a process invokes a system call, the system call
executes in the kernel mappings of the process's address space.
This arrangement exists so that the kernel's system call
code can directly refer to user memory.
In order to leave room for user memory to grow,
xv6's address spaces map the kernel at high addresses,
starting at
.address 0x80100000 .
.PP
The xv6 kernel maintains many pieces of state for each process,
which it gathers into a
.code-index "struct proc"
.line proc.h:/^struct.proc/ .
A process's most important pieces of kernel state are its 
page table and the physical memory it refers to,
its kernel stack, and its run state.
We'll use the notation
.code-index p->xxx
to refer to elements of the
.code proc
structure.
.PP
Each process has a thread of execution (or 
.italic-index thread
for short) that executes the process's program.  A thread executes a computation
but can be stopped and then resumed later.  To switch transparently between process,
the kernel can stop the current running thread and resume another process's
thread.  Much of the state of a thread (local variables, functional call return
addresses) is stored on the thread's kernel stack,
.code-index p->kstack  .
Each process's kernel stack is separate from its user stack, since the
user stack may not be valid.   So, you can view a process has having
a thread with two stacks:  one for executing in user mode and one for executing
in kernel mode.
.PP
When a process makes a system call, the processors switches from user mode to
kernel and switches from executing on the user stack to the kernel stack.  The
process executes the implementation of the system call (e.g., reads a file) on
the kernel stack, and then returns back to the user space.  A process's thread
can wait (or ``block'') in the kernel to wait for I/O, and resume where it left
off when the I/O has finished.
.PP
.code-index p->state 
indicates whether the process is allocated, ready
to run, running, waiting for I/O, or exiting.
.PP
.code-index p->pgdir
holds the process's page table, an array of PTEs.
xv6 causes the paging hardware to use a process's
.code p->pgdir
when executing that process.
A process's page table also serves as the record of the
addresses of the physical pages allocated to store the process's memory.
.\"
.section "Code: the first address space"
.\"
When a PC powers on, it initializes itself and then loads a
.italic-index "boot loader"
from disk into memory and executes it.
Appendix \*[APP:BOOT] explains the details.
Xv6's boot loader loads the xv6 kernel from disk and executes it
starting at 
.code-index entry 
.line entry.S:/^entry/ .
The x86 paging hardware is not enabled when the kernel starts;
virtual addresses map directly to physical addresses.
.PP
The boot loader loads the xv6 kernel into memory at physical address
.address 0x100000 .
The reason it doesn't load the kernel at
.address 0x80100000 ,
where the kernel expects to find its instructions and data,
is that there may not be any physical memory at such
a high address on a small machine.
The reason it places the kernel at
.address 0x100000
rather than
.address 0x0
is because the address range
.address 0xa0000:0x100000
contains older I/O devices.
.P1
figure with temporary mapping
.P2
.PP
 To allow the rest of the kernel to run,
.code entry
sets up a page table that maps virtual addresses starting at
.address 0x80000000
(called
.code-index KERNBASE 
.line memlayout.h:/define.KERNBASE/ )
to physical address starting at
.address 0x0 .
.PP
The entry page table is defined 
in main.c
.line 'main.c:/^pde_t.entrypgdir.*=/' .
We look at the details of page tables in Chapter  \*[CH:MEM],
but the short story is that entry 0 maps virtual addresses
.code 0:0x400000
to physical addresses
.code 0:0x400000 .
This mapping is required as long as
.code-index entry
is executing at low addresses, but
will eventually be removed.
.PP
Entry 960
maps virtual addresses
.code KERNBASE:KERNBASE+0x400000
to physical addresses
.address 0:0x400000 .
This entry will be used by the kernel after
.code entry
has finished; it maps the high virtual addresses at which
the kernel expects to find its instructions and data
to the low physical addresses where the boot loader loaded them.
This mapping restricts the kernel instructions and data to 4 Mbytes.
.PP
Returning to
.code entry,
it loads the physical address of
.code-index entrypgdir
into control register
.register cr3.
The paging hardware must know the physical address of
.code entrypgdir, 
because it doesn't know how to translate virtual addresses yet; it doesn't have
a page table yet.
The symbol
.code entrypgdir
refers to an address in high memory,
and the macro
.code-index V2P_WO
.line 'memlayout.h:/V2P_WO/' 
subtracts
.code KERNBASE
in order to find the physical address.
To enable the paging hardware, xv6 sets the flag
.code-index CR0_PG
in the control register
.register cr0.
.PP
The processor is still executing instructions at
low addresses after paging is enabled, which works
since
.code entrypgdir
maps low addresses.
If xv6 had omitted entry 0 from
.code entrypgdir,
the computer would have crashed when trying to execute
the instruction after the one that enabled paging.
.PP
Now
.code entry
needs to transfer to the kernel's C code, and run
it in high memory.
First it must make the stack pointer,
.register esp ,
point to a stack so that C code will work
.line entry.S:/movl.*stack.*esp/ .
All symbols have high addresses, including
.code stack ,
so the stack will still be valid even when the
low mappings are removed.
Finally 
.code entry
jumps to
.code-index main ,
which is also a high address.
The indirect jump is needed because the assembler would
generate a PC-relative direct jump, which would execute
the low-memory version of 
.code-index main .
Main cannot return, since the there's no return PC on the stack.
Now the kernel is running in high addresses in the function
.code-index main 
.line main.c:/^main/ .
.\"
.section "Code: creating the first process"
.\"
.PP
After
.code main
initializes several devices and subsystems of xv6, 
it creates the first process starts by calling 
.code userinit
.line main.c:/userinit/  .
.code Userinit 's
first action is to call
.code-index allocproc .
The job of
.code allocproc
.line proc.c:/^allocproc/
is to allocate a slot
(a
.code struct
.code proc )
in the process table and
to initialize the parts of the process's state
required for its kernel thread to execute.
.code Allocproc 
is called for all new processes, while
.code userinit
is called only for the very first process.
.code Allocproc
scans the table for a process with state
.code UNUSED
.lines proc.c:/for.p.=.ptable.proc/,/goto.found/ .
When it finds an unused process, 
.code allocproc
sets the state to
.code-index EMBRYO
to mark it as used and
gives the process a unique
.code-index pid
.lines proc.c:/EMBRYO/,/nextpid/ .
Next, it tries to allocate a kernel stack for the
process's kernel thread.  If the memory allocation fails, 
.code allocproc
changes the state back to
.code UNUSED
and returns zero to signal failure.
.figure newkernelstack
.PP
Now
.code allocproc
must set up the new process's kernel stack.
Ordinarily processes are created only by
.code fork ,
so a new process
starts life copied from its parent.  The result of 
.code fork
is a child process
that has identical memory contents to its parent.
.code allocproc
sets up the child to 
start life running its kernel thread, with a specially prepared kernel
stack and set of kernel registers that cause it to ``return'' to user
space at the same place (the return from the
.code fork
system call) as the parent.
The layout of the prepared kernel stack will be as shown in 
.figref newkernelstack .
.code allocproc
does part of this work by setting up return program counter
values that will cause the new process's kernel thread to first execute in
.code-index forkret
and then in
.code-index trapret
.lines proc.c:/uint.trapret/,/uint.forkret/ .
The kernel thread will start executing
with register contents copied from
.code-index p->context .
Thus setting
.code p->context->eip
to
.code forkret
will cause the kernel thread to execute at
the start of 
.code-index forkret 
.line proc.c:/^forkret/ .
This function 
will return to whatever address is at the bottom of the stack.
The context switch code
.line swtch.S:/^swtch/
sets the stack pointer to point just beyond the end of
.code p->context .
.code allocproc
places
.code p->context
on the stack, and puts a pointer to
.code-index trapret
just above it; that is where
.code-index forkret
will return.
.code-index trapret
restores user registers
from values stored at the top of the kernel stack and jumps
into the process
.line trapasm.S:/^trapret/ .
This setup is the same for ordinary
.code fork
and for creating the first process, though in
the latter case the process will start executing at
location zero rather than at a return from
.code fork .
.PP
As we will see in Chapter \*[CH:TRAP],
the way that control transfers from user software to the kernel
is via an interrupt mechanism, which is used by system calls,
interrupts, and exceptions.
Whenever control transfers into the kernel while a process is running,
the hardware and xv6 trap entry code save user registers on the
top of the process's kernel stack.
.code-index userinit
writes values at the top of the new stack that
look just like those that would be there if the
process had entered the kernel via an interrupt
.lines proc.c:/tf..cs.=./,/tf..eip.=./ ,
so that the ordinary code for returning from
the kernel back to the process's user code will work.
These values are a
.code-index "struct trapframe"
which stores the user registers.  Now the new process's kernel stack is
completely prepared as shown in 
.figref newkernelstack .
.PP
The first process is going to execute a small program
.code-index initcode.S ; (
.line initcode.S:1 ).
The process needs physical memory in which to store this
program, the program needs to be copied to that memory,
and the process needs a page table that refers to
that memory.
.PP
.code-index userinit
calls 
.code-index setupkvm
.line vm.c:/^setupkvm/
to create a page table for the process with (at first) mappings
only for memory that the kernel uses.
We will study  this function in detail in Chapter \*[CH:MEM], but
the layout of the address space is as in Figure XXX.
.PP
The initial contents of the first process's memory are
the compiled form of
.code-index initcode.S ;
as part of the kernel build process, the linker
embeds that binary in the kernel and
defines two special symbols
.code-index _binary_initcode_start
and
.code-index _binary_initcode_size
telling the location and size of the binary.
.code Userinit
copies that binary into the new process's memory
by calling
.code-index inituvm ,
which allocates one page of physical memory,
maps virtual address zero to that memory,
and copies the binary to that page
.line vm.c:/^inituvm/ .
.PP
Then 
.code userinit
sets up the trap frame with the initial user mode state:
the
.register cs
register contains a segment selector for the
.code-index SEG_UCODE
segment running at privilege level
.code-index DPL_USER
(i.e., user mode not kernel mode),
and similarly
.register ds ,
.register es ,
and
.register ss
use
.code-index SEG_UDATA
with privilege
.code-index DPL_USER .
The
.register eflags
.code-index FL_IF
is set to allow hardware interrupts;
we will reexamine this in Chapter \*[CH:TRAP].
.PP
The stack pointer 
.register esp
is the process's largest valid virtual address,
.code p->sz .
The instruction pointer is the entry point
for the initcode, address 0.
.PP
The function
.code-index userinit
sets
.code-index p->name
to
.code "initcode"
mainly for debugging.
Setting
.code-index p->cwd
sets the process's current working directory;
we will examine
.code-index namei
in detail in Chapter \*[CH:FS].
.PP
Once the process is initialized,
.code-index userinit
marks it available for scheduling by setting 
.code p->state
to
.code-index RUNNABLE .
.\"
.section "Code: Running the first process"
.\"
Now that the first process's state is prepared,
it is time to run it.
After 
.code main
calls
.code userinit ,
.code-index mpmain
calls
.code-index scheduler
to start running processes
.line main.c:/scheduler/ .
.code Scheduler
.line proc.c:/^scheduler/
looks for a process with
.code p->state
set to
.code RUNNABLE ,
and there's only one it can find:
.code initproc .
It sets the per-cpu variable
.code proc
to the process it found and calls
.code-index switchuvm
to tell the hardware to start using the target
process's page table
.line vm.c:/lcr3.*p..pgdir/ .
Changing page tables while executing in the kernel
works because 
.code-index setupkvm
causes all processes' page tables to have identical
mappings for kernel code and data.
.code switchuvm
also creates a new task state segment
.code-index SEG_TSS
that instructs the hardware to handle
an interrupt by returning to kernel mode
with
.register ss
and
.register esp
set to
.code-index SEG_KDATA 
.code <<3
and
.code (uint)proc->kstack+KSTACKSIZE ,
the top of this process's kernel stack.
We will reexamine the task state segment in Chapter \*[CH:TRAP].
.PP
.code-index scheduler
now sets
.code p->state
to
.code RUNNING
and calls
.code-index swtch
.line swtch.S:/^swtch/ 
to perform a context switch to the target process's kernel thread.
.code swtch 
saves the current registers and loads the saved registers
of the target kernel thread
.code proc->context ) (
into the x86 hardware registers,
including the stack pointer and instruction pointer.
The current context is not a process but rather a special
per-cpu scheduler context, so
.code scheduler
tells
.code swtch
to save the current hardware registers in per-cpu storage
.code-index cpu->scheduler ) (
rather than in any process's kernel thread context.
We'll examine
.code-index switch
in more detail in Chapter \*[CH:SCHED].
The final
.code-index ret
instruction 
.line swtch.S:/ret$/
pops a new
.register eip
from the stack, finishing the context switch.
Now the processor is running on the kernel stack of process
.code p .
.PP
.code Allocproc
set
.code initproc 's
.code p->context->eip
to
.code-index forkret ,
so the 
.code-index ret
starts executing
.code-index forkret .
.code Forkret
releases the 
.code ptable.lock
(see Chapter \*[CH:LOCK]).
On the first invocation (that is this one),
.code-index forkret
.line proc.c:/^forkret/
runs initialization functions that cannot be run from 
.code-index main 
because they must be run in the context of a regular process with its own
kernel stack. 
Then, 
.code forkret 
returns.
.code Allocproc
arranged that the top word on the stack after
.code-index p->context
is popped off
would be 
.code-index trapret ,
so now 
.code trapret
begins executing,
with 
.register esp
set to
.code p->tf .
.code Trapret
.line trapasm.S:/^trapret/ 
uses pop instructions to walk
up the trap frame just as 
.code-index swtch
did with the kernel context:
.code-index popal
restores the general registers,
then the
.code-index popl 
instructions restore
.register gs ,
.register fs ,
.register es ,
and
.register ds .
The 
.code-index addl
skips over the two fields
.code trapno
and
.code errcode .
Finally, the
.code-index iret
instructions pops 
.register cs ,
.register eip ,
and
.register flags
off the stack.
The contents of the trap frame
have been transferred to the CPU state,
so the processor continues at the
.register eip
specified in the trap frame.
For
.code-index initproc ,
that means virtual address zero,
the first instruction of
.code-index initcode.S .
.PP
At this point,
.register eip
holds zero and
.register esp
holds 4096.
These are virtual addresses in the process's address space.
The processor's paging hardware translates them into physical addresses.
.code-index allocuvm
set up the PTE for the page at virtual address zero to
point to the physical memory allocated for this process,
and marked that PTE with
.code-index PTE_U
so that the process can use it.
No other PTEs in the process's page table have the
.code PTE_U
bit set.
The fact that
.code-index userinit
.line proc.c:/UCODE/
set up the low bits of
.register cs
to run the process's user code at CPL=3 means that the user code
can only use PTE entries with
.code PTE_U
set, and cannot modify sensitive hardware registers such as
.register cr3 .
So the process is constrained to using only its own memory.
.\"
.section "The first system call: exec"
.\"
.PP
The first action of 
.code initcode.S
is to call invoke  the
.code exec
system call.
As we saw in Chapter \*[CH:UNIX], 
.code-index exec
replaces the memory and registers of the
current process with a new program, but it leaves the
file descriptors, process id, and parent process the same.
.PP
.code Initcode.S
.line initcode.S:/^start/
begins by pushing three values
on the stack—\c
.code $argv ,
.code $init ,
and
.code $0 —\c
and then sets
.register eax
to
.code-index SYS_exec
and executes
.code int
.code-index T_SYSCALL :
it is asking the kernel to run the
.code-index exec
system call.
If all goes well,
.code exec
never returns: it starts running the program 
named by
.code $init ,
which is a pointer to
the NUL-terminated string
.code "/init"
.line initcode.S:/init.0/,/init.0/ .
If the
.code exec
fails and does return,
initcode
loops calling the
.code-index exit
system call, which definitely
should not return
.line initcode.S:/for.*exit/,/jmp.exit/ .
.PP
The arguments to the
.code exec
system call are
.code $init
and
.code $argv .
The final zero makes this hand-written system call look like the
ordinary system calls, as we will see in Chapter \*[CH:TRAP].  As
before, this setup avoids special-casing the first process (in this
case, its first system call), and instead reuses code that xv6 must
provide for standard operation.
.figure processlayout
.PP
.figref processlayout 
shows the user memory image of an executing process.
The heap is above the stack so that it can expand (with
.code-index sbrk ).
The stack is a single page, and is
shown with the initial contents as created by exec.
Strings containing the command-line arguments, as well as an
array of pointers to them, are at the very top of the stack.
Just under that are values that allow a program
to start at
.code main
as if the function call
.code main(argc,
.code argv)
had just started.
.\"
.section "Code: exec"
.\"
When the system call arrives (Chapter \*[CH:TRAP]
will explain how that happens),
.code-index syscall
invokes
.code-index sys_exec
via the 
.code syscalls
table
.line syscall.c:/static.int...syscalls/ .
.code Sys_exec
.line sysfile.c:/^sys_exec/
parses the system call arguments (also explained in Chapter \*[CH:TRAP]),
and invokes
.code exec
.line sysfile.c:/exec.path/ .
.PP
.code Exec
.line exec.c:/^exec/
opens the named binary 
.code path
using
.code-index namei
.line exec.c:/namei/ ,
which is explained in Chapter \*[CH:FS].
Then, it reads the ELF header. Xv6 applications are described in the widely-used 
.italic-index "ELF format" , 
defined in
.file elf.h .
An ELF binary consists of an ELF header,
.code-index "struct elfhdr"
.line elf.h:/^struct.elfhdr/ ,
followed by a sequence of program section headers,
.code "struct proghdr"
.line elf.h:/^struct.proghdr/ .
Each
.code proghdr
describes a section of the application that must be loaded into memory;
xv6 programs have only one program section header, but
other systems might have separate sections
for instructions and data.
.PP
.code Exec
allocates a new page table with no user mappings with
.code-index setupkvm
.line exec.c:/setupkvm/ ,
allocates memory for each ELF segment with
.code-index allocuvm
.line exec.c:/allocuvm/ ,
and loads each segment into memory with
.code-index loaduvm
.line exec.c:/loaduvm/ .
.PP
The program section header's
.code filesz
may be less than the
.code memsz ,
indicating that the gap between them should be filled
with zeroes (for C global variables) rather than read from the file.
For 
.code /init ,
.code filesz 
is 2240 bytes and
.code memsz 
is 2252 bytes,
and thus 
.code-index allocuvm
allocates enough physical memory to hold 2252 bytes, but reads only 2240 bytes
from the file 
.code /init .
.PP
Now
.code-index exec
allocates and initializes the user stack.
It allocates just one stack page.
.code Exec
copies the argument strings to the top of the stack
one at a time, recording the pointers to them in 
.code-index ustack .
It places a null pointer at the end of what will be the
.code-index argv
list passed to
.code main .
The first three entries in 
.code ustack
are the fake return PC,
.code-index argc ,
and
.code argv
pointer.
.PP
During the preparation of the new memory image,
if 
.code exec
detects an error like an invalid program segment,
it jumps to the label
.code bad ,
frees the new image,
and returns \-1.
.code Exec
must wait to free the old image until it 
is sure that the system call will succeed:
if the old image is gone,
the system call cannot return \-1 to it.
The only error cases in
.code exec
happen during the creation of the image.
Once the image is complete, 
.code exec
can install the new image
.line exec.c:/switchuvm/
and free the old one
.line exec.c:/freevm/ .
Finally,
.code exec
returns 0.
Success!
.PP
Now the
.code-index initcode
.line initcode.S:1
is done.
.code Exec
has replaced it with the 
.code-index /init
binary, loaded out of the file system.
.code Init
.line init.c:/^main/
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
Most operating systems have adopted the process
concept, and most processes look similar to xv6's.
A real operating system would find free
.code proc
structures with an explicit free list
in constant time instead of the linear-time search in
.code allocproc ;
xv6 uses the linear scan
(the first of many) for simplicity.
.PP
xv6's address space layout has the defect that it cannot make use
of more than 2 GB of physical RAM.  It's possible to fix this,
though the best plan would be to switch to a machine with 64-bit
addresses.
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
.code trapret ,
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
