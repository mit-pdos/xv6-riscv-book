.so book.mac
.ig
	this is even rougher than most chapters
..
.chapter CH:MEM "Processes
.PP
One of an operating system's central roles
is to allow multiple programs to share the CPUs
and main memory safely, isolating them so that
one errant program cannot break others.
To that end, xv6 provides the concept of a process,
as described in Chapter \*[CH:UNIX].
xv6 implements a process as a set of data structures,
but a process is quite special:
it comes alive with help from the hardware.
This chapter examines how xv6 allocates
memory to hold process code and data,
how it creates a new process,
and how it configures the processor's segmentation
hardware to give each process the illusion that
it hash its own private memory address space.
The next few chapters will examine how xv6 uses hardware
support for interrupts and context switching to create
the illusion that each process has its own private cpu.
.\"
.section "Code: Memory allocation
.\"
.PP
xv6 allocates most of its data structures statically, by
declaring C global variables and arrays.
The linker and the boot loader cooperate to decide exactly
what memory locations will hold these variables, so that the
C code doesn't have to explictly allocate memory.
However, xv6 does explicitly and dynamically allocate physical memory
for user process memory, for the kernel stacks of user processes,
and for pipe buffers.
When xv6 needs memory for one of these purposes,
it calls
.code kalloc ;
when it no longer needs them memory, it calls
.code kfree
to release the memory back to the allocator.
Xv6's memory allocator manages blocks of memory
that are a multiple of 4096 bytes,
because the allocator is used mainly to allocate
process address spaces, and the x86 segmentation
hardware manages those address spaces in
multiples of 4 kilobytes.
The xv6 allocator calls one of these 4096-byte units a
page, though it has nothing to do with paging.
.PP
.code Main
calls 
.code kinit
to initialize the allocator
.line main.c:/kinit/ .
.code Kinit
ought to begin by determining how much physical
memory is available, but this
turns out to be difficult on the x86.
Xv6 doesn't need much memory, so
it assumes that there is at least one megabyte
available past the end of the loaded kernel
and uses that megabyte.
The kernel is around 50 kilobytes and is
loaded one megabyte into the address space,
so xv6 is assuming that the machine has at 
least a little more than two megabytes of memory,
a very safe assumption on modern hardware.
.PP
.code Kinit
.line kalloc.c:/^kinit/
uses the special linker-defined symbol
.code end
to find the end of the kernel's static data
and rounds that address up to a multiple of 4096 bytes
.line kalloc.c:/~.PAGE/ .
When 
.code n
is a power of two, the expression
.code (a+n-1)
.code &
.code ~(n-1)
is a common C idiom to round
.code a
up to the next multiple of
.code n .
.code Kinit
then does a surprising thing:
it calls
.code kfree
to free a megabyte of memory starting at that address
.line kalloc.c:/kfree.start/ .
The discussion of
.code kalloc
and
.code kfree
above said that
.code kfree
was for returning memory allocated with
.code kalloc ,
but that was a client-centric perspective.
From the allocator's point of view,
calls to
.code kfree
give it memory to hand out,
and then calls to
.code kalloc
ask for the memory back.
The allocator starts with no memory;
this initial call to
.code kfree
gives it a megabyte to manage.
.PP
The allocator maintains a
.I "free list" 
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
The allocator does another surprising thing:
it uses the memory being tracked as the
place to store the
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
This step is unnecessary for correct operation,
but it helps break incorrect code that
continues to refer to memory after freeing it.
This kind of bug is called a dangling reference.
By setting the memory to a bad value,
.code kfree
increases the chance of making such
code use an integer or pointer that is out of range
.code 0x01010101 "" (
is around 16 million).
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
.I before
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
accomodate the allocation.
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
.section "Code: Process creation
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
.code Allocproc is called for all new processes, while
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
Now
.code allocproc
must set up the new process's kernel stack.
As we will see in Chapter \*[CH:TRAP],
the usual way that a process enters the kernel
is via an interrupt.
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
.code proc.c:/sz.=.PAGE/,/kalloc/ .
The initial contents of that memory are
the compiled form of
.code initcode.S ;
as part of the kernel build process, the linker
embeds that binary in the kernel and
defines two special symbols
.code _binary_initcode_start
and
.code _binary_initcode_size
telling the loction and size of the binary
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
initializes a per-cpu global descriptor table
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
to create a few more segments on this cpu
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
to switch to the new process's
kernel context
.line "'proc.c:/swtch.*c->context.*p->context/'" .
.code Swtch
.line swtch.S:/^swtch/ ,
which we will reexamine in Chapter \*[CH:PROC],
sets 
.code %esp
to its second argument,
in this case
.code &p->context ,
XXX maybe should do in detail here XXX
and pops the callee-save registers
.code edi ,
.code esi ,
.code ebx ,
and 
.code ebp 
from the stack.
The final
.code ret
instruction pops a new
.code eip
from the stack, finishing the context switch.
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
arranged that the word on the stack
above
.code forkret 's
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
have been transferred to the cpu state,
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
The final zero makes this hand-written
system call look like the ordinary assembly stub system calls.
XXX look at C call, assembly stubs.
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
.section "Real world
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
Every other operating system for the x86
uses the paging hardware for address translation
and protection; they treat the segmentation hardware
mostly as a nuisance to be disabled by creating no-op segments
like the boot sector did.
Xv6 uses segmentation instead of paging mainly for
simplicitly.
This allows us to focus on operating system services
like process management and the file system
instead of complex memory management.
Essentially any other operating system textbook
can be consulted for more on page tables and paging.
.PP
The one common use of segmentation is as a way to
provide cheap per-thread storage, like xv6 does to create per-cpu storage.
Implementations of per-cpu (or per-thread) storage on other
architectures would dedicate a register to holding a pointer
to the per-cpu data area, but the x86 has so few general
registers that the extra effort required to use segmentation
is worthwhile.
.PP
There is one important drawback to xv6's use of segmentation
instead of paging: without page tables,
there is no way to make address 0 is an invalid address.
This means that if xv6 or a user program dereferences
a null pointer, it reads or writes the memory at that
location and keeps running.
In contrast, systems that use paging typically leave
the first few pages of the address space unmapped,
so that dereferencing a null pointer causes a memory fault.
This one drawback would be severe enough to warrant
the implementation of paging if xv6 were more than
just a teaching operating system.
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
Memory allocation was a hot topic a long time ago.
Basic problem was how to make the most efficient
use of the available memory and how best to
prepare for future requests without knowing what
the future requests were going to be.
See Knuth.
Today, more effort is spent on making memory allocators
fast rather than on making them space-efficient.
Today's allocation heavy languages, small blocks dominate.
Xv6 avoids smaller than a page allocations by 
using fixed-size data structures.
A real kernel allocator would need to handle
small allocations as well as large ones,
although the paging hardware might keep it
from needing to handle objects larger than a page.
.\"
.section "Exercises
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
[[Intent here is to point out the clock interrupt,
so that students aren't confused by it trying
to see the return to user space.
But maybe the clock interrupt doesn't happen at the
first iret anymore.  Maybe it happens when the 
scheduler turns on interrupts.  That would be great;
if it's not true already we should make it so.]]

3. Look at real operating systems to see how they size memory.

