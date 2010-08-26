.so book.mac
.ig
	this is even rougher than most chapters
..
.chapter CH:MEM "Processes"
.PP
One of an operating system's central roles
is to allow multiple programs to share the CPUs
and main memory safely, isolating them so that
one errant program cannot break others.
To that end, xv6 provides the concept of a process,
as described in Chapter \*[CH:UNIX].
This chapter examines how xv6 allocates
memory to hold process code and data,
how it creates a new process,
and how it configures the processor's paging
hardware to give each process the illusion that
it has a private memory address space.
The next few chapters will examine how xv6 uses hardware
support for interrupts and context switching to create
the illusion that each process has its own private CPU.
.\"
.section "Address Spaces"
.\"
.PP
xv6 ensures that each process can only read and write the memory that
xv6 has allocated to it, and not for example the kernel's memory or
the memory of other processes. xv6 also arranges for each process's
memory to be contiguous and to start at virtual address zero. The C
language definition and the Gnu linker expect process memory to be
contiguous. Process memory starts at zero because that is what Unix
has always done. A process's view of memory is called an address space.
.PP
x86 protected mode defines three kinds of addresses. Executing
software generates
virtual addresses when it fetches instructions or reads and writes
memory; instructions cannot directly use a linear or physical addresses.
The segmentation hardware translates virtual to linear addresses.
Finally, the paging hardware (when enabled) translates linear to physical
addresses. xv6 sets up the segmentation hardware so that virtual and
linear addresses are always the same: the segment descriptors
all have a base of zero and the maximum possible limit.
xv6 sets up the x86 paging hardware to translate linear to physical
addresses in a way that implements process address spaces with
the properties outlined above.
.PP
The paging hardware uses a page table to translate linear to
physical addresses. A page table is logically an array of 2^20
(1,048,576) page table entries (PTEs). Each PTE contains a
20-bit physical page number (PPN) and some flags. The paging
hardware translates a linear address by using its top 20 bits
to index into the page table to find a PTE, and replacing
those bits with the PPN in the PTE.  The paging hardware
copies the low 12 bits unchanged from the linear to the
translated physical address.  Thus a page table gives
the operating system control over linear-to-physical address translations
at the granularity of aligned chunks of 4096 (2^12) bytes.
.PP
Each PTE also contains flag bits that affect how the page of linear
addresses that refer to the PTE are translated.
.code PTE_P
controls whether the PTE is valid: if it is
not set, a reference to the page causes a fault (i.e. is not allowed).
.code PTE_W
controls whether instructions are allowed to issue
writes to the page; if not set, only reads and
instruction fetches are allowed.
.code PTE_U
controls whether user programs are allowed to use the
page; if clear, only the kernel is allowed to use the page.
.PP
xv6 uses page tables to implement process address spaces as
follows. Each process has a separate page table, and xv6 tells
the page table hardware to switch
page tables when xv6 switches between processes.
A process's user-accessible memory starts at linear address
zero and can have size of at most 640 kilobytes.
xv6 sets up the PTEs for the lower 640 kilobytes (i.e.,
the first 160 PTEs in the process's page table) to point
to whatever pages of physical memory xv6 has allocated for
the process's memory. xv6 sets the
.code PTE_U
bit on the first 160 PTEs so that a process can use its
own memory.
If a process has asked xv6 for less than 640 kilobytes,
xv6 will fill in fewer than 160 of these PTEs.
.PP
Different processes' page tables translate the first 160 pages to
different pages of physical memory, so that each process has
private memory.
However, xv6 sets up every process's page table to translate linear addresses
above 640 kilobytes in the same way.
To a first approximation, all processes' page tables map linear
addresses above 640 kilobytes directly to physical addresses.
However, xv6 does not set the
.code PTE_U
flag in the relevant PTEs.
This means that the kernel is allowed to use linear addresses
above 640 kilobytes, but user processes are not.
For example, the kernel can use its own instructions and data
(at linear/physical addresses starting at one megabyte).
The kernel can also read and write all the physical memory beyond
the end of its data segment, since linear addresses map directly
to physical addresses in this range.
.PP 
Note that every process's page table simultaneously contains
translations for both all of the user process's memory and all
of the kernel's memory.
This setup is very convenient: it means that xv6 can switch between
the kernel and the process when making system calls without
having to switch page tables.
The price paid for this convenience is that the sum of the size
of the kernel and the largest process must be less than four
gigabytes on a machine with 32-bit addresses. xv6 has much
more restrictive sizes---each user process must fit in 640 kilobytes---but 
that 640 is easy to increase.
.PP
With the page table arrangement that xv6 sets up, a process can use
the lower 640 kilobytes of linear addresses, but cannot use any
other addresses---even though xv6 maps all of physical memory
in every process's page table, it sets the
.code PTE_U
bits only for addresses under 640 kilobytes.
Assuming many things (a user process can't change the page table,
xv6 never maps the same physical page into the lower 640 kilobytes
of more than one process's page table, etc.),
the result is that a process can use its own memory
but not the memory of any other process or of the kernel.
.\"
.section "Memory allocation"
.\"
.PP
xv6 needs to allocate physical memory at run-time to store its own data structures
and to store processes' memory. There are three main questions
to be answered when allocating memory. First,
what physical memory (i.e. DRAM storage cells) are to be used?
Second, at what linear address or addresses is the newly
allocated physical memory to be mapped? And third, how
does xv6 know what physical memory is free and what memory
is already in use?
.PP
xv6 maintains a pool of physical memory available for run-time allocation.
It uses the physical memory beyond the end of the loaded kernel's
data segment. xv6 allocates (and frees) physical memory at page (4096-byte)
granularity. It keeps a linked list of free physical pages;
xv6 deletes newly allocated pages from the list, and adds freed
pages back to the list.
.PP
When the kernel allocates physical memory that only it will use, it
does not need to make any special arrangement to be able to
refer to that memory with a linear address: the kernel sets up
all page tables so that linear addresses map directly to physical
addresses for addresses above 640 KB. Thus if the kernel allocates
the physical page at physical address 0x200000 for its internal use,
it can use that memory via linear address 0x200000 without further ado.
.PP
What if a user process allocates memory with
.code sbrk ?
Suppose that the current size of the process is 12 kilobytes,
and that xv6 finds a free page of physical memory at physical address
0x201000. In order to ensure that user process memory remains contiguous,
that physical page should appear at linear address 0x3000.
This is the time (and the only time) when xv6 uses the paging hardware's
ability to translate a linear address to a different physical address.
xv6 modifies the 3rd PTE (which covers the range 0x3000 to 0x3fff)
to refer to physical page number 0x201 (the upper 20 bits of 0x201000),
and sets the 
.code PTE_U
and
.code PTE_W
bits in that PTE.
Now the user process will be able to use 16 kilobytes of contiguous
memory starting at linear address zero.
Two different PTEs now refer to this page of physical memory:
the PTE for linear address 0x201000 and the PTE for linear address
0x3000. The kernel can use the memory with either of these linear
addresses; the user process can only use the second.
.\"
.section "Code: Memory allocator"
.\"
.PP
The xv6 kernel calls
.code kalloc
and
.code kfree
to allocate and free physical memory at run-time.
The kernel uses run-time allocation for user process
memory and for these kernel data strucures:
kernel stacks, pipe buffers, and page tables.
The allocator manages page-sized (4096-byte) blocks of memory.
The kernel can directly use allocated memory through a linear
address equal to the allocated memory's physical address.
.PP
.code Main
calls 
.code pminit ,
which in turn calls
.code kinit
to initialize the allocator
.line vm.c:/kinit/ .
.code pminit
ought to determine how much physical
memory is available, but this
turns out to be difficult on the x86.
.code pminit
assumes that the machine has
16 megabytes
.code PHYSTOP ) (
of physical memory, and tells
.code kinit
to use all the memory between the end of the kernel
and 
.code PHYSTOP
as the initial pool of free memory.
.PP
.code Kinit
.line kalloc.c:/^kinit/
calls
.code kfree
with the address that
.code pminit
passed to it.
This will cause
.code kfree
to add that memory to the allocator's list of free pages.
The allocator starts with no memory;
this initial call to
.code kfree
gives it some to manage.
.PP
The allocator maintains a
.italic "free list" 
of memory regions that are available
for allocation.
It keeps the list sorted in increasing
order of address in order to ease the task
of merging contiguous blocks of freed memory.
Each contiguous region of available
memory is represented by a
.code struct
.code run .
But where does the allocator get the memory
to hold that data structure?
It uses the memory being tracked 
to store the
.code run
structure tracking it.
Each
.code run
.code *r
represents the memory from address
.code (uint)r
to
.code (uint)r 
.code +
.code r->len .
The free list is
protected by a spin lock 
.line kalloc.c:/^struct/,/}/ .
The list and the lock are wrapped in a struct
to make clear that the lock protects the fields
in the struct.
For now, ignore the lock and the calls to
.code acquire
and
.code release ;
Chapter \*[CH:LOCK] will examine
locking in detail.
.PP
.code Kfree
.line kalloc.c:/^kfree/
begins by setting every byte in the 
memory being freed to the value 1.
This step is not necessary,
but it helps break incorrect code that
continues to refer to memory after freeing it.
This kind of bug is called a dangling reference.
By setting the memory to a bad value,
.code kfree
increases the chance of making such
code use an integer or pointer that is out of range
.code 0x11111111 "" (
is around 286 million).
.PP
.code Kfree 's
first real work is to store a
.code run
in the memory at
.code v .
It uses a cast in order to make
.code p ,
which is a pointer to a
.code run ,
refer to the same memory as
.code v .
It also sets
.code pend
to the
.code run
for the block following
.code v
.lines kalloc.c:/p.=..struct.run/,/pend.=/ .
If that block is free,
.code pend
will appear in the free list.
Now 
.code kfree
walks the free list, considering each run 
.code r .
The list is sorted in increasing address order, 
so the new run 
.code p
belongs before the first run
.code r
in the list such that
.code r >
.code pend .
The walk stops when either such an
.code r
is found or the list ends,
and then 
.code kfree
inserts
.code p
in the list before
.code r
.lines kalloc.c:/Insert.p.before.r/,/rp.=.p/ .
The odd-looking
.code for
loop is explained by the assignment
.code *rp
.code =
.code p :
in order to be able to insert
.code p
.italic before
.code r ,
the code had to keep track of where
it found the pointer 
.code r ,
so that it could replace that pointer with 
.code p .
The value
.code rp
points at where
.code r
came from.
.PP
There are two other cases besides simply adding
.code p
to the list.
If the new run
.code p
abuts an existing run,
those runs need to be coalesced into one large run,
so that allocating and freeing small blocks now
does not preclude allocating large blocks later.
The body of the 
.code for
loop checks for these conditions.
First, if
.code rend
.code ==
.code p
.line kalloc.c/rend.==.p/ ,
then the run
.code r
ends where the new run
.code p
begins.
In this case, 
.code p
can be absorbed into
.code r
by increasing
.code r 's
length.
If growing 
.code r
makes it abut the next block in the list,
that block can be absorbed too
.lines "'kalloc.c/r->next && r->next == pend/,/}/'" .
Second, if
.code pend
.code ==
.code r
.line kalloc.c/pend.==.r/ ,
then the run 
.code p
ends where the new run
.code r
begins.
In this case,
.code r
can be absorbed into 
.code p
by increasing
.code p 's
length
and then replacing
.code r
in the list with
.code p
.lines "'kalloc.c:/pend.==.r/,/}/'" .
.PP
.code Kalloc
has a simpler job than 
.code kfree :
it walks the free list looking for
a run that is large enough to
accommodate the allocation.
When it finds one, 
.code kalloc
takes the memory from the end of the run
.lines "'kalloc.c:/r->len >= n/,/-=/'" .
If the run has no memory left,
.code kalloc
deletes the run from the list
.lines "'kalloc.c:/r->len == 0/,/rp = r->next/'"
before returning.
.\"
.section "Code: Process creation"
.\"
.PP
This section describes how xv6 creates the very first process.
Xv6 represents each process by a 
.code struct
.code proc
.line proc.h:/^struct.proc/ 
entry in the statically-sized
.code ptable.proc
process table.
The most important fields of a
.code struct
.code proc
are
.code mem ,
which points to the physical memory containing the process's
instructions, data, and stack;
.code kstack ,
which points to the process's kernel stack for use in interrupts
and system calls; and
and 
.code state ,
which indicates whether the process is allocated, ready
to run, running, etc.
.PP
The story of the creation of the first process starts when
.code main
.line main.c:/userinit/ 
calls
.code userinit
.line proc.c:/^userinit/ ,
whose first action is to call
.code allocproc .
The job of
.code allocproc
.line proc.c:/^allocproc/
is to allocate a slot in the process table and
to initialize the parts of the process's state
required for it to execute in the kernel.
.code Allocproc 
is called for all new processes, while
.code userinit
is only called for the very first process.
.code Allocproc
scans the table for a process with state
.code UNUSED
.lines proc.c:/for.p.=.ptable.proc/,/goto.found/ .
When it finds an unused process, 
.code allocproc
sets the state to
.code EMBRYO
to mark it as used and
gives the processes a unique
.code pid
.lines proc.c:/EMBRYO/,/nextpid/ .
Next, it tries to allocate a kernel stack for the
process.  If the memory allocation fails, 
.code allocproc
changes the state back to
.code UNUSED
and returns zero to signal failure.
.PP
Now
.code allocproc
must set up the new process's kernel stack.
As we will see in Chapter \*[CH:TRAP],
the usual way that a process enters the kernel
is via an interrupt mechanism, which is used by system calls,
interrupts, and exceptions.
The process's kernel stack
is the one it uses when executing in the kernel
during the handling of that interrupt.
.code Allocproc
writes values at the top of the new stack that
look just like those that would be there if the
process had entered the kernel via an interrupt,
so that the ordinary code for returning from
the kernel back to the user part of a process will work.
These values are a
.code struct
.code trapframe
which stores the user registers,
the address of the kernel code that returns from an
interrupt
.code trapret ) (
for use as a function call return address,
and a 
.code struct
.code context
which holds the process's kernel registers.
When the kernel switches contexts to this new process,
the context switch will restore
its kernel registers; it will then execute kernel code to return
from an interrupt and thus restore the user registers,
and then execute user instructions.
.code Allocproc
sets
.code p->context->eip 
to
.code forkret ,
so that the process will start executing in the kernel
at the start of
.code forkret .
The context switching code will start executing the
new process with the stack pointer set to
.code p->context+1 ,
which points to the stack slot holding the address of the
.code trapret
function, just as if
.code forkret
had been called by
.code trapret.
.P1
 ----------  <-- top of new process's kernel stack
| esp      |
| ...      |
| eip      |
| ...      |
| edi      | <-- p->tf (new proc's user registers)
| trapret  | <-- address forkret will return to
| eip      |
| ...      |
| edi      | <-- p->context (new proc's kernel registers)
|          |
| (empty)  |
|          |
 ----------  <-- p->kstack
.P2
.PP
.code Main
calls
.code userinit
to create the first user process
.line main.c:/userinit/ .
.code Userinit
.line proc.c:/^userinit/
calls
.code allocproc ,
saves a pointer to the process as
.code initproc ,
ad then configures the new process's
user state.
First, the process needs memory.
This first process is going to execute a very tiny
program
.code initcode.S ; (
.line initcode.S:1 ),
so the memory need only be a single page
.line proc.c:/sz.=.PAGE/,/kalloc/ .
The initial contents of that memory are
the compiled form of
.code initcode.S ;
as part of the kernel build process, the linker
embeds that binary in the kernel and
defines two special symbols
.code _binary_initcode_start
and
.code _binary_initcode_size
telling the location and size of the binary
(XXX sidebar about why it is extern char[]).
.code Userinit
copies that binary into the new process's memory
and zeros the rest
.lines proc.c:/memset.p..mem/,/memmove/ .
Then it sets up the trap frame with the initial user mode state:
the
.code cs
register contains a segment selector for the
.code SEG_UCODE
segment running at privilege level
.code DPL_USER
(i.e., user mode not kernel mode),
and similarly
.code ds ,
.code es ,
and
.code ss
use
.code SEG_UDATA
with privilege
.code DPL_USER .
The
.code eflags
.code FL_IF
is set to allow hardware interrupts;
we will reexamine this in Chapter \*[CH:TRAP].
The stack pointer 
.code esp
is the process's largest valid virtual address,
.code p->sz .
The instruction pointer is the entry point
for the initcode, address 0.
Note that
.code initcode
is not an ELF binary and has no ELF header.
It is just a small headerless binary that expects
to run at address 0,
just as the boot sector is a small headerless binary
that expects to run at address
.code 0x7c00 .
.code Userinit
sets
.code p->name
to
.code "initcode"
mainly for debugging.
Setting
.code p->cwd
sets the process's current working directory;
we will examine
.code namei
in detail in Chapter \*[CH:FSDATA].
.\" TODO: double-check: is it FSDATA or FSCALL?  namei might move.
.PP
Once the process is initialized,
.code userinit
marks it available for scheduling by setting 
.code p->state
to
.code RUNNABLE .
.\"
.section "Code: Running a process
.\"
Rather than use special code to start the first
process running and guide it to user space,
xv6 has chosen to set up the initial data structure
state as if that process was already running.
But it wasn't running and still isn't:
so far, this has been just an elaborate
construction exercise, like lining up dominoes.
Now it is time to knock over the first domino,
set the operating system and the hardware in motion
and watch what happens.
.PP
.code Main
calls
.code ksegment
to initialize the kernel's segment descriptor table
.line main.c:/ksegment/ .
.code Ksegment
initializes a per-CPU global descriptor table
.code c->gdt
with the same segments that the boot sector
configured
(and one more, 
.code SEG_KCPU ,
which we will revisit in Chapter \*[CH:LOCK]).
After calling
.code userinit ,
which we examined above,
.code main
calls
.code scheduler
to start running user processes
.line main.c:/scheduler/ .
.code Scheduler
.line proc.c:/^scheduler/
looks for a process with
.code p->state
set to
.code RUNNABLE ,
and there's only one it can find:
.code initproc .
It sets the global variable
.code cp
to the process it found
.code cp "" (
stands for current process)
and calls
.code usegment
to create segments on this CPU for the user-space
execution of the process
.line "'proc.c:/usegment!(!)/'" .
Usegment
.line proc.c:/^usegment/
creates code and data segments
.code SEG_UCODE
and
.code SEG_UDATA
mapping addresses 0 through
.code cp->sz-1
to the memory at
.code cp->mem .
It also creates a new task state segment
.code SEG_TSS
that instructs the hardware to handle
an interrupt by returning to kernel mode
with
.code ss
and
.code esp
set to
.code SEG_KDATA<<3
and
.code (uint)cp->kstack+KSTACKSIZE ,
the top of this process's kernel stack.
We will reexamine the task state segment in Chapter \*[CH:TRAP].
.PP
Now that
.code usegment
has created the user code and data segments,
the scheduler can start running the process.
It sets
.code p->state
to
.code RUNNING
and calls
.code swtch
.line swtch.S:/^swtch/ ,
to perform a context switch from one kernel process to another; in
this invocation, from a scheduler process to
.code p .
.code Swtch ,
which we will reexamine in Chapter \*[CH:SCHED],
saves the scheduler's registers that must be saved; i.e., the context
.line proc.h:/^struct.context/
that a process needs to later resume correctly.
Then,
.code Swtch
loads 
.code p->context
into the hardware registers.
The final
.code ret
instruction 
.line swtch.S:/ret$/
pops a new
.code eip
from the stack, finishing the context switch.
Now the processor is running process
.code p .
.PP
.code Allocproc
set
.code initproc 's
.code p->context->eip
to
.code forkret ,
so the 
.code ret
starts executing
.code forkret .
.code Forkret
.line proc.c:/^forkret/
releases the 
.code ptable.lock
(see Chapter \*[CH:LOCK])
and then returns.
.code Allocproc
arranged that the top word on the stack after
.code p->context
is popped off
would be 
.code trapret ,
so now 
.code trapret
begins executing,
with 
.code %esp
set to
.code p->tf .
.code Trapret
.line trapasm.S:/^trapret/ 
uses pop instructions to walk
up the trap frame just as 
.code swtch
did with the kernel context:
.code popal
restores the general registers,
then the
.code popl 
instructions restore
.code %gs ,
.code %fs ,
.code %es ,
and
.code %ds .
The 
.code addl
skips over the two fields
.code trapno
and
.code errcode .
Finally, the
.code iret
instructions pops 
.code %cs ,
.code %eip ,
and
.code %eflags
off the stack.
The contents of the trap frame
have been transferred to the CPU state,
so the processor continues at the
.code %cs:%eip
specified in the trap frame.
For
.code initproc ,
that means
.code SEG_UCODE:0 ,
the first instruction of
.code initcode.S .
.PP
At this point,
.code %eip
holds zero and
.code %esp
holds 4096.
These are virtual addresses in the process's user address space.
The processor's segmentation machinery translates them into physical addresses.
The relevant segmentation registers (cs, ds, and ss) and
segment descriptors were set up by 
.code userinit
and
.code usegment
to translate virtual address zero to physical address
.code p->mem ,
with a maximum virtual address of
.code p->sz .
The fact that the process is running with CPL=3 (in the low
bits of cs) means that it cannot use the segment descriptors
.code SEG_KCODE
and
.code SEG_KDATA ,
which would give it access to all of physical memory.
So the process is constrained to using only its own memory.
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
.code %eax
to
.code $SYS_exec
and executes
.code int
.code $T_SYSCALL :
it is asking the kernel to run the
.code exec
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
.code exit
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
.PP
The next chapter examines how xv6 configures
the x86 hardware to handle the system call interrupt
caused by
.code int
.code $T_SYSCALL .
The rest of the book builds up enough of the process
management and file system implementation
to finally implement
.code exec
in Chapter \*[CH:EXEC].
.\"
.section "Real world"
.\"
.PP
Most operating systems have adopted the process
concept, and most processes look similar to xv6's.
A real operating system would use an explicit free list
for constant time allocation instead of the linear time search in
.code allocproc ;
xv6 uses the linear scan
(the first of many) for its utter simplicity.
.PP
Xv6 departs from modern operating systems in its use of
segmentation registers for process isolation and address
translation.
Most operating systems for the x86
uses the paging hardware for address translation
and protection; they treat the segmentation hardware
mostly as a nuisance to be disabled by creating no-op segments
like the boot sector did.
However, a simple paging scheme is somewhat more complex to
implement than a simple segmentation scheme.  Since xv6
does not aspire to any of the advanced features which
would require paging, it uses segmentation instead.
.ig
The real reasons are that we didn't want to make it too easy
to copy paging code from xv6 to jos, and that we wanted to
provide a contrast to paging, and that it's a nod to V6's
use of PDP11 segments. Next time let's use paging.
..
.PP
The one common use of segmentation is to implement
variables like xv6's
.code cp
that are at a fixed address but have different values
in different threads.
Implementations of per-CPU (or per-thread) storage on other
architectures would dedicate a register to holding a pointer
to the per-CPU data area, but the x86 has so few general
registers that the extra effort required to use segmentation
is worthwhile.
.PP
xv6's use of segmentation instead of paging is awkward in a
couple of ways, even given its low ambitions.
First, it causes user-space address zero to be a valid address,
so that programs do  not fault when they dereference null pointers;
a paging system could force faults by marking the first page
invalid, which turns out to be invaluable for catching bugs
in C code.
Second, xv6's segment scheme places the stack at a relatively low
address which prevents automatic stack extension.
Finally, all of a process's memory must be contiguous in physical
memory, leading to fragmentation and/or copying.
.PP
In the earliest days of operating systems,
each operating system was tailored to a specific
hardware configuration, so the amount of memory
could be a hard-wired constant.
As operating systems and machines became
commonplace, most developed a way to determine
the amount of memory in a system at boot time.
On the x86, there are at least three common algorithms:
the first is to probe the physical address space looking for
regions that behave like memory, preserving the values
written to them;
the second is to read the number of kilobytes of 
memory out of a known 16-bit location in the PC's non-volatile RAM;
and the third is to look in BIOS memory
for a memory layout table left as
part of the multiprocessor tables.
None of these is guaranteed to be reliable,
so modern x86 operating systems typically
augment one or more of them with complex
sanity checks and heuristics.
In the interest of simplicity, xv6 assumes
that the machine it runs on has at least one megabyte
of memory past the end of the kernel.
Since the kernel is around 50 kilobytes and is
loaded one megabyte into the address space,
xv6 is assuming that the machine has at 
least a little more than 2 MB of memory.
A real operating system would have to do a better job.
.PP
Memory allocation was a hot topic a long time ago.  Basic problem was
how to make the most efficient use of the available memory and how
best to prepare for future requests without knowing what the future
requests were going to be.  See Knuth.  Today, more effort is spent on
making memory allocators fast rather than on making them
space-efficient.  The runtimes of today's modern programming languages
allocate mostly many small blocks.  Xv6 avoids smaller than a page
allocations by using fixed-size data structures.  A real kernel
allocator would need to handle small allocations as well as large
ones, although the paging hardware might keep it from needing to
handle objects larger than a page.
.\"
.section "Exercises"
.\"
1. Set a breakpoint at swtch.  Single step through to forkret.
Set another breakpoint at forkret's ret.
Continue past the release.
Single step into trapret and then all the way to the iret.
Set a breakpoint at 0x1b:0 and continue.
Sure enough you end up at initcode.

2. Do the same thing except single step past the iret.
You don't end up at 0x1b:0.  What happened?
Explain it.
Peek ahead to the next chapter if necessary.
.ig
[[Intent here is to point out the clock interrupt,
so that students aren't confused by it trying
to see the return to user space.
But maybe the clock interrupt doesn't happen at the
first iret anymore.  Maybe it happens when the 
scheduler turns on interrupts.  That would be great;
if it's not true already we should make it so.]]
..

3. Look at real operating systems to see how they size memory.
