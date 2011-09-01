.ig
  terminology:
    process: refers to execution in user space, or maybe struct proc &c
    process memory: the lower part of the address space
    process's kernel thread
    so: swtch() switches to a given process's kernel thread
    trapret's iret switches to the process of the current
      kernel thread
 talk a little about initial page table conditions:
    paging not on, but virtual mostly mapped direct to physical,
    which is what things look like when we turn paging on as well
    since paging is turned on after we create first process.
  mention why still have SEG_UCODE/SEG_UDATA?
  do we ever really say what the low two bits of %cs do?
    in particular their interaction with PTE_U
  show elf header for init
  introduce segmentation in real world
..
.chapter CH:MEM "The first process"
.PP
This chapter explains what happens when xv6 first starts running,
through the creation of the first process. One of the most interesting
aspects of this is how the kernel manages memory for itself and for
processes.
.PP
One purpose of processes is to isolate different programs that
share the same computer, so that
one buggy program cannot break others.
A process provides a program with what appears to be a private
memory system, or
address space,
which other processes cannot read or write. This chapter examines how
xv6 configures the processor's paging hardware to provide processes
with private address spaces, how it allocates memory to hold process
code and data, and how it creates new processes.
.\"
.section "Paging hardware"
.\"
.PP
Xv6 runs on Intel 80386 or later ("x86") processors on a PC platform,
and much of its low-level functionality (for example, its virtual
memory implementation) is x86-specific. This book assumes the reader
has done a bit of machine-level programming on some architecture, and
will introduce x86-specific ideas as they come up. Appendix \*[APP:HW]
briefly outlines the PC platform.
.PP
The x86 paging hardware uses a page
table to translate (or "map")
.italic-index virtual 
(the addresses that an x86 program manipulates) to
.italic-index physical 
addresses (the addresses that the processor chip sends to main memory).
.PP
An x86 page table is logically an array of 2^20
(1,048,576) 
.italic-index "page table entries (PTEs)". 
Each PTE contains a
20-bit physical page number (PPN) and some flags. The paging
hardware translates a virtual address by using its top 20 bits
to index into the page table to find a PTE, and replacing
those bits with the PPN in the PTE.  The paging hardware
copies the low 12 bits unchanged from the virtual to the
translated physical address.  Thus a page table gives
the operating system control over virtual-to-physical address translations
at the granularity of aligned chunks of 4096 (2^12) bytes.
.figure x86_pagetable
.PP
As shown in Figure \n[fig:x86_pagetable], the actual translation happens in two steps.
A page table is stored in physical memory as a two-level tree.
The root of the tree is a 4096-byte 
.italic-index "page directory" 
that contains 1024 PTE-like references to 
.italic-index "page table pages".
Each page table page is an array of 1024 32-bit PTEs.
The paging hardware uses the top 10 bits of a virtual address to
select a page directory entry.
If the page directory entry is present,
the paging hardware uses the next 10 bits of the virtual
address to select a PTE from the page table page that the
page directory entry refers to.
If either the page directory entry or the PTE is not present,
the paging hardware raises a fault.
This two-level structure allows a page table to omit entire
page table pages in the common case in which large ranges of
virtual addresses have no mappings.
.PP
Each PTE contains flag bits that tell the paging hardware
how the associated virtual address is allowed to be used.
.code PTE_P
indicates whether the PTE is present: if it is
not set, a reference to the page causes a fault (i.e. is not allowed).
.code PTE_W
controls whether instructions are allowed to issue
writes to the page; if not set, only reads and
instruction fetches are allowed.
.code PTE_U
controls whether user programs are allowed to use the
page; if clear, only the kernel is allowed to use the page.
Figure \n[fig:x86_pagetable] shows how it all works.
.PP
A few notes about terms.
Physical memory refers to storage cells in DRAM.
A byte of physical memory has an address, called a physical address.
A program uses virtual addresses, which the 
paging hardware translate to physical addresses, and then
send to the DRAM hardware to read or write storage.
At this level of discussion there is no such thing as virtual memory,
only virtual addresses.
.\"
.section "Address space overview"
.\"
.PP
Xv6 uses the paging hardware to give each process its own view
of memory, called an
.italic-index "address space" .
Xv6 maintains a separate page table for each process that
defines that process's address space.
An address space includes the process's
.italic-index "user memory"
starting at virtual address zero. Instructions usually come first,
followed by global variables and a "heap" area (for malloc)
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
.\"
.section "Code: entry page table"
.\"
When a PC powers on, it initializes itself and then loads a
.italic-index "boot loader"
from disk into memory and executes it.
Appendix \*[APP:BOOT] explains the details.
Xv6's boot loader loads the xv6 kernel from disk and executes it
starting at 
.code entry 
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
To allow the rest of the kernel to run,
.code entry
sets up a page table that maps virtual addresses starting at
.address 0x80000000
(called
.code KERNBASE 
.line memlayout.h:/define.KERNBASE/ )
to physical address starting at
.address 0x0 .
.PP
The entry page table is defined 
in main.c
.line 'main.c:/^pde_t.entrypgdir.*=/' .
The array initialization sets two of the 1024 PTEs,
at indices zero and 960
.code KERNBASE>>PDXSHIFT ), (
leaving the other PTEs zero.
It causes both of these PTEs to use super-pages,
each of which maps 4 megabytes of virtual address space.
Entry 0 maps virtual addresses
.code 0:0x400000
to physical addresses
.code 0:0x400000 .
This mapping is required as long as
.code entry
is executing at low addresses, but
will eventually be removed.
The pages are mapped as present
.code PTE_P
(present),
.code PTE_W
(writeable),
and
.code PTE_PS
(super page).
The flags and all other page hardware related structures are defined in
.file "mmu.h"
.sheet memlayout.h .
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
the kernel first tells the paging hardware to allow super pages by setting the flag
.code CR_PSE 
(page size extension) in the control register
.code %cr4.
Next it loads the physical address of
.code entrypgdir
into control register
.code %cr3.
The paging hardware must know the physical address of
.code entrypgdir, 
because it doesn't know how to translate virtual addresses yet; it doesn't have
a page table yet.
The symbol
.code entrypgdir
refers to an address in high memory,
and the macro
.code V2P_WO
.line 'memlayout.h:/V2P_WO/' 
subtracts
.code KERNBASE
in order to find the physical address.
To enable the paging hardware, xv6 sets the flag
.code CR0_PG
in the control register
.code %cr0.
It also sets
.code CR0_WP ,
which ensures that the kernel honors
write-protect flags in PTEs.
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
.code main,
which is also a high address.
The indirect jump is needed because the assembler would
generate a PC-relative direct jump, which would execute
the low-memory version of 
.code main .
Main cannot return, since the there's no return PC on the stack.
Now the kernel is running in high addresses in the function
.code main 
.line main.c:/^main/ .
.\"
.figure xv6_layout
.section "Address space details"
.\"
.PP
The page table created by
.code entry
has enough mappings to allow the kernel's C code to start running.
However, main immediately changes to a new page table by calling
.code kvmalloc
.line vm.c:/^kvmalloc/ ,
because kernel has a more elaborate plan for page tables that describe
process address spaces.
.PP
Each process has a separate page table, and xv6 tells
the page table hardware to switch
page tables when xv6 switches between processes.
As shown in Figure \n[fig:xv6_layout],
a process's user memory starts at virtual address
zero and can grow up to
.address KERNBASE ,
allowing a process to address up to 2 GB of memory.
When a process asks xv6 for more memory,
xv6 first finds free physical pages to provide the storage,
and then adds PTEs to the process's page table that point
to the new physical pages.
xv6 sets the 
.code PTE_U ,
.code PTE_W ,
and 
.code PTE_P
flags in these PTEs.
Most processes do not use the entire user address space;
xv6 leaves
.code PTE_P
clear in unused PTEs.
Different processes' page tables translate user addresses
to different pages of physical memory, so that each process has
private user memory.
.PP
Xv6 includes all mappings needed for the kernel to run in every
process's page table; these mappings all appear above
.address KERNBASE .
It maps virtual addresses
.address KERNBASE:KERNBASE+PHYSTOP
to
.address 0:PHYSTOP .
One reason for this mapping is so that the kernel can use its
own instructions and data.
Another reason is that the kernel sometimes needs to be able
to write a given page of physical memory, for example
when creating page table pages; having every physical
page appear at a predictable virtual address makes this convenient.
A defect of this arrangement is that xv6 cannot make use of
more than 2 GB of physical memory.
Some devices that use memory-mapped I/O appear at physical
addresses starting at
.address 0xFE000000 ,
so xv6 page tables including a direct mapping for them.
Xv6 does not set the
.code PTE_U
flag in the PTEs above
.address KERNBASE ,
so only the kernel can use them.
.PP 
Having every process's page table contain mappings for
both user memory and the entire kernel is convenient
when switching from user code to kernel code during
system calls and interrupts: such switches do not
require page table switches.
For the most part the kernel does not have its own page
table; it is almost always borrowing some process's page table.
.PP
To review, xv6 ensures that each process can only use its own memory,
and that a process sees its memory as having contiguous virtual addresses.
xv6 implements the first by setting the
.code PTE_U
bit only on PTEs of virtual addresses that refer to the process's own memory.
It implements the second using the ability of page tables to translate
successive virtual addresses to whatever physical pages happen to
be allocated to the process.
.\"
.section "Code: creating an address space"
.\"
.PP
.code main
calls
.code kvmalloc
.line vm.c:/^kvmalloc/
to create and switch to a page table with the mappings above
.code KERNBASE 
required for the kernel to run.
Most of the work happens in
.code setupkvm
.line vm.c:/^setupkvm/ .
It first allocates a page of memory to hold the page directory.
Then it calls
.code mappages
to install the translations that the kernel needs,
which are described in the 
.code kmap
.line vm.c:/^}.kmap/
array.
The translations include the kernel's
instructions and data, physical memory up to
.code PHYSTOP ,
and memory ranges which are actually I/O devices.
.code setupkvm
does not install any mappings for the user memory;
this will happen later.
.PP
.code mappages
.line vm.c:/^mappages/
installs mappings into a page table
for a range of virtual addresses to
a corresponding range of physical addresses.
It does this separately for each virtual address in the range,
at page intervals.
For each virtual address to be mapped,
.code mappages
calls
.code walkpgdir
to find the address of the PTE for that address.
It then initializes the PTE to hold the relevant physical page
number, the desired permissions (
.code PTE_W
and/or
.code PTE_U ),
and 
.code PTE_P
to mark the PTE as valid
.line vm.c:/perm...PTE_P/ .
.PP
.code walkpgdir
.line vm.c:/^walkpgdir/
mimics the actions of the x86 paging hardware as it
looks up the PTE for a virtual address (see Fig. \n[fig:x86_pagetable]).
.code walkpgdir
uses the upper 10 bits of the virtual address to find
the page directory entry
.line vm.c:/pde.=..pgdir/ .
If the page directory entry isn't present, then
the required page table page hasn't yet been allocated;
if the
.code alloc
argument is set,
.code walkpgdir
allocates it and puts its physical address in the page directory.
Finally it uses the next 10 bits of the virtual address
to find the address of the PTE in the page table page
.line vm.c:/return..pgtab/ .
.\"
.section "Physical memory allocation"
.\"
.PP
The kernel needs to allocate and free physical memory at run-time for
page tables,
process user memory,
kernel stacks,
and pipe buffers.
.PP
xv6 uses the physical memory between the end of the kernel and
.code PHYSTOP
for run-time allocation. It allocates and frees whole 4096-byte pages
at a time. It keeps track of which pages are free by threading a
linked list through the pages themselves. Allocation consists of
removing a page from the linked list; freeing consists of adding the
freed page to the list.
.PP
There is a bootstrap problem: all of physical memory must be mapped in
order for the allocator to initialize the free list, but creating a
page table with those mappings involves allocating page-table pages.
xv6 solves this problem by using a separate page allocator during
entry, which allocates memory just after the end of the kernel's data
segment. This allocator does not support freeing and is limited by the
4 MB mapping in the
.code entrypgdir ,
but that is sufficient to allocate the first kernel page table.
.\"
.section "Code: Physical memory allocator"
.\"
.PP
The allocator's data structure is a
.italic "free list" 
of physical memory pages that are available
for allocation.
Each free page's list element is a
.code struct
.code run 
.line kalloc.c:/^struct.run/ .
Where does the allocator get the memory
to hold that data structure?
It store each free page's
.code run
structure in the free page itself,
since there's nothing else stored there.
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
The function
.code main
calls 
.code kinit
to initialize the allocator
.line kalloc.c:/^kinit/ .
.code kinit
ought to determine how much physical
memory is available, but this
turns out to be difficult on the x86.
Instead it assumes that the machine has
240 megabytes
.code PHYSTOP ) (
of physical memory, and uses all the memory between the end of the kernel
and 
.code PHYSTOP
as the initial pool of free memory.
.code kinit
calls
.code kfree
with the address of each page of memory between
.code end
and
.code PHYSTOP .
This causes
.code kfree
to add those pages to the allocator's free list.
The allocator starts with no memory;
these calls to
.code kfree
give it some to manage.
.PP
The allocator refers to physical pages by their virtual
addresses as mapped in high memory, not by their physical
addresses, which is why
.code kinit
uses
.code p2v(PHYSTOP) 
to translate
.code PHYSTOP
(a physical address)
to a virtual address.
The allocator sometimes treats addresses as integers
in order to perform arithmetic on them (e.g.,
traversing all pages in
.code kinit ),
and sometimes uses addresses as pointers to read and
write memory (e.g., manipulating the 
.code run
structure stored in each page);
this dual use of addresses is the main reason that the
allocator code is full of C type casts.
The other reason is that freeing and allocation inherently
change the type of the memory.
.PP
The function
.code kfree
.line kalloc.c:/^kfree/
begins by setting every byte in the 
memory being freed to the value 1.
This will cause code that uses memory after freeing it
(uses "dangling references")
to read garbage instead of the old valid contents;
hopefully that will cause such code to break faster.
Then
.code kfree
casts
.code v 
to a pointer to
.code struct
.code run ,
records the old start of the free list in
.code r->next ,
and sets the free list equal to
.code r .
.code kalloc
removes and returns the first element in the free list.
.PP
When creating the first kernel page table, 
.code setupkvm
and 
.code walkpgdir
use
.code enter_alloc
.line kalloc.c:/^enter_alloc/
instead of 
.code kalloc .
This memory allocator moves the end of the kernel by 1 page.
.code enter_alloc
uses the symbol
.code end ,
which the linker causes to have an address that is just beyond
the end of the kernel's data segment.
A PTE can only refer to a physical address that is aligned
on a 4096-byte boundary (is a multiple of 4096), so
.code enter_alloc
uses
.code PGROUNDUP
to ensure that it allocates only aligned physical addresses.
Memory allocated with
.code enter_alloc
is never freed.
.\"
.section "Code: Process creation"
.\"
.PP
This section describes how xv6 creates the first process.
The xv6 kernel maintains many pieces of state for each process,
which it gathers into a
.code struct
.code proc
.line proc.h:/^struct.proc/ .
A process's most important pieces of kernel state are its 
page table and the physical memory it refers to,
its kernel stack, and its run state.
We'll use the notation
.code p->xxx
to refer to elements of the
.code proc
structure.
.PP
You should view the kernel state of a process as a thread
that executes in the kernel on behalf of a process.
For example, when a process makes a system call, the CPU
switches from executing the process to executing the
process's kernel thread.
The process's kernel thread executes the implementation
of the system call (e.g., reads a file), and then
returns back to the process.
.PP
.code p->pgdir
holds the process's page table, an array of PTEs.
xv6 causes the paging hardware to use a process's
.code p->pgdir
when executing that process.
A process's page table also serves as the record of the
addresses of the physical pages allocated to store the process's memory.
.PP
.code p->kstack
points to the process's kernel stack.
When a process's kernel thread is executing, for example in a system
call, it must have a stack on which to save variables and function
call return addresses.  xv6 allocates one kernel stack for each process.
The kernel stack is separate from the user stack, since the
user stack may not be valid.  Each process has its own kernel stack
(rather than all sharing a single stack) so that a system call may
wait (or "block") in the kernel to wait for I/O, and resume where it
left off when the I/O has finished; the process's kernel stack saves
much of the state required for such a resumption.
.PP
.code p->state 
indicates whether the process is allocated, ready
to run, running, waiting for I/O, or exiting.
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
gives the process a unique
.code pid
.lines proc.c:/EMBRYO/,/nextpid/ .
Next, it tries to allocate a kernel stack for the
process's kernel thread.  If the memory allocation fails, 
.code allocproc
changes the state back to
.code UNUSED
and returns zero to signal failure.
.PP
Now
.code allocproc
must set up the new process's kernel stack.
Ordinarily processes are only created by
.code fork ,
so a new process
starts life copied from its parent.  The result of 
.code fork
is a child process
that has identical memory contents to its parent.
.code allocproc
sets up the child to 
start life running its kernel thread, with a specially prepared kernel
stack and set of kernel registers that cause it to "return" to user
space at the same place (the return from the
.code fork
system call) as the parent.
.code allocproc
does part of this work by setting up return program counter
values that will cause the new process's kernel thread to first execute in
.code forkret
and then in
.code trapret
.lines proc.c:/uint.trapret/,/uint.forkret/ .
The kernel thread will start executing
with register contents copied from
.code p->context .
Thus setting
.code p->context->eip
to
.code forkret
will cause the kernel thread to execute at
the start of 
.code forkret 
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
.code trapret
just above it; that is where
.code forkret
will return.
.code trapret
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
.figure newkernelstack
.PP
As we will see in Chapter \*[CH:TRAP],
the way that control transfers from user software to the kernel
is via an interrupt mechanism, which is used by system calls,
interrupts, and exceptions.
Whenever control transfers into the kernel while a process is running,
the hardware and xv6 trap entry code save user registers on the
top of the process's kernel stack.
.code userinit
writes values at the top of the new stack that
look just like those that would be there if the
process had entered the kernel via an interrupt
.lines proc.c:/tf..cs.=./,/tf..eip.=./ ,
so that the ordinary code for returning from
the kernel back to the process's user code will work.
These values are a
.code struct
.code trapframe
which stores the user registers.
Figure \n[fig:newkernelstack] shows the state of the new process's kernel stack.
.PP
The first process is going to execute a small program
.code initcode.S ; (
.line initcode.S:1 ).
The process needs physical memory in which to store this
program, the program needs to be copied to that memory,
and the process needs a page table that refers to
that memory.
.PP
.code userinit
calls 
.code setupkvm
.line vm.c:/^setupkvm/
to create a page table for the process with (at first) mappings
only for memory that the kernel uses.  This function is the same one that the
kernel used to setup its page table.
.PP
The initial contents of the first process's memory are
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
by calling
.code inituvm ,
which allocates one page of physical memory,
maps virtual address zero to that memory,
and copies the binary to that page
.line vm.c:/^inituvm/ .
.PP
Then 
.code userinit
sets up the trap frame with the initial user mode state:
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
.PP
The stack pointer 
.code esp
is the process's largest valid virtual address,
.code p->sz .
The instruction pointer is the entry point
for the initcode, address 0.
.PP
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
in detail in Chapter \*[CH:FS].
.PP
Once the process is initialized,
.code userinit
marks it available for scheduling by setting 
.code p->state
to
.code RUNNABLE .
.\"
.section "Code: Running a process"
.\"
Now that the first process's state is prepared,
it is time to run it.
After 
.code main
calls
.code userinit ,
.code mpmain
calls
.code scheduler
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
.code switchuvm
to tell the hardware to start using the target
process's page table
.line vm.c:/lcr3.*p..pgdir/ .
Changing page tables while executing in the kernel
works because 
.code setupkvm
causes all processes' page tables to have identical
mappings for kernel code and data.
.code switchuvm
also creates a new task state segment
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
.code (uint)proc->kstack+KSTACKSIZE ,
the top of this process's kernel stack.
We will reexamine the task state segment in Chapter \*[CH:TRAP].
.PP
.code scheduler
now sets
.code p->state
to
.code RUNNING
and calls
.code swtch
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
.code cpu->scheduler ) (
rather than in any process's kernel thread context.
We'll examine
.code switch
in more detail in Chapter \*[CH:SCHED].
The final
.code ret
instruction 
.line swtch.S:/ret$/
pops a new
.code eip
from the stack, finishing the context switch.
Now the processor is running the kernel thread of process
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
On the first invocation (that is this one),
.code forkret
.line proc.c:/^forkret/
runs initialization functions that cannot be run from 
.code main 
because they must be run in the context of a regular process with its own
kernel stack. 
Then,
.code forkret
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
.code %eip
specified in the trap frame.
For
.code initproc ,
that means virtual address zero,
the first instruction of
.code initcode.S .
.PP
At this point,
.code %eip
holds zero and
.code %esp
holds 4096.
These are virtual addresses in the process's address space.
The processor's paging hardware translates them into physical addresses.
.code allocuvm
set up the PTE for the page at virtual address zero to
point to the physical memory allocated for this process,
and marked that PTE with
.code PTE_U
so that the process can use it.
No other PTEs in the process's page table have the
.code PTE_U
bit set.
The fact that
.code userinit
.line proc.c:/UCODE/
set up the low bits of
.register cs
to run the process's user code at CPL=3 means that the user code
can only use PTE entries with
.code PTE_U
set, and cannot modify sensitive hardware registers such as
.register cr3 .
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

.\"
.section "Exec"
.\"
As we saw in Chapter \*[CH:UNIX], 
.code exec
replaces the memory and registers of the
current process with a new program, but it leaves the
file descriptors, process id, and parent process the same.
.figure processlayout
.PP
Figure \n[fig:processlayout] shows the user memory image of an executing process.
The heap is above the stack so that it can expand (with
.code sbrk ).
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
.code syscall
invokes
.code sys_exec
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
.code namei
.line exec.c:/namei/ ,
which is explained in Chapter \*[CH:FS],
and then reads the ELF header. Xv6 applications are described in the widely-used 
.italic-index "ELF format" , 
defined in
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
describes a section of the application that must be loaded into memory;
xv6 programs have only one program section header, but
other systems might have separate sections
for instructions and data.
.PP
The first step is a quick check that the file probably contains an
ELF binary.
An ELF binary starts with the four-byte "magic number"
.code 0x7F ,
.code 'E' ,
.code 'L' ,
.code 'F' ,
or
.code ELF_MAGIC
.line elf.h:/ELF_MAGIC/ .
If the ELF header has the right magic number,
.code exec
assumes that the binary is well-formed.
.PP
Then 
.code exec
allocates a new page table with no user mappings with
.code setupkvm
.line exec.c:/setupkvm/ ,
allocates memory for each ELF segment with
.code allocuvm
.line exec.c:/allocuvm/ ,
and loads each segment into memory with
.code loaduvm
.line exec.c:/loaduvm/ .
The program section header for
.code /init
looks like this:
.P1
# objdump -p _init 

_init:     file format elf32-i386

Program Header:
    LOAD off    0x00000054 vaddr 0x00000000 paddr 0x00000000 align 2**2
         filesz 0x000008c0 memsz 0x000008cc flags rwx
.P2
.PP
.code allocuvm
checks that the virtual addresses requested
is below
.address KERNBASE .
.code loaduvm
.line vm.c:/^loaduvm/
uses
.code walkpgdir
to find the physical address of the allocated memory at which to write
each page of the ELF segment, and
.code readi
to read from the file.
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
.code allocuvm
allocates enough physical memory to hold 2252 bytes, but reads only 2240 bytes
from the file 
.code /init .
.PP
Now
.code exec
allocates and initializes the user stack.
It assumes that one page of stack is enough.
If not,
.code copyout
will return \-1, as will 
.code exec .
.code Exec
first copies the argument strings to the top of the stack
one at a time, recording the pointers to them in 
.code ustack .
It places a null pointer at the end of what will be the
.code argv
list passed to
.code main .
The first three entries in 
.code ustack
are the fake return PC,
.code argc ,
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
.code initcode
.line initcode.S:1
is done.
.code Exec
has replaced it with the real
.code /init
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
.PP
Although the system is up, we skipped over some important subsystems of xv6.
The next chapter examines how xv6 configures the x86 hardware to handle the
system call interrupt caused by
.code int
.code $T_SYSCALL .
The rest of the book builds up enough of the process
management and file system implementation,
on which 
.code exec
relies.
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
Like most operating systems, xv6 uses the paging hardware
for memory protection and mapping. Most operating systems make far more sophisticated
use of paging than xv6; for example, xv6 lacks demand
paging from disk, copy-on-write fork, shared memory,
and automatically extending stacks.
The x86 also supports address translation using segmentation (see Appendix \*[APP:BOOT]),
but xv6 uses them only for the common trick of
implementing per-cpu variables such as
.code proc
that are at a fixed address but have different values
on different CPUs (see
.code seginit ).
Implementations of per-CPU (or per-thread) storage on non-segment
architectures would dedicate a register to holding a pointer
to the per-CPU data area, but the x86 has so few general
registers that the extra effort required to use segmentation
is worthwhile.
.PP
xv6's address space layout has some downsides.  For example, it is potentially
awkward for the kernel to map all of physical memory into the virtual address
space. This leave zero virtual address space for user mappings on a 32-bit
machine with 4 gigabytes of DRAM.
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
Reading the memory layout table
is complicated.
In the interest of simplicity, xv6 assumes
that the machine it runs on has at least 240 megabytes
of memory, and that it is all contiguous.
A real operating system would have to do a better job.
.PP
Memory allocation was a hot topic a long time ago, the basic problems being
efficient use of very limited memory and
preparing for unknown future requests.
See Knuth.  Today people care more about speed than
space-efficiency.  In addition, a more elaborate kernel
would likely allocate many different sizes of small blocks,
rather than (as in xv6) just 4096-byte blocks;
a real kernel
allocator would need to handle small allocations as well as large
ones.
.PP
.code Exec
is the most complicated code in xv6 in and in most operating systems.
It involves pointer translation
(in
.code sys_exec
too),
many error cases, and must replace one running process
with another.
Real world operationg systems have even more complicated
.code exec 
implementations.
They handle shell scripts (see exercise below),
more complicated ELF binaries, and even multiple
binary formats.
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

2. Look at real operating systems to see how they size memory.

3. If xv6 had not used super pages, what would be the right declaration for
.code entrypgdir?

4. Unix implementations of 
.code exec
traditionally include special handling for shell scripts.
If the file to execute begins with the text
.code #! ,
then the first line is taken to be a program
to run to interpret the file.
For example, if
.code exec
is called to run
.code myprog
.code arg1
and
.code myprog 's
first line is
.code #!/interp ,
then 
.code exec
runs
.code /interp
with command line
.code /interp
.code myprog
.code arg1 .
Implement support for this convention in xv6.

5.
.code KERNBASE 
limits the amount of memory a single process can use,
which might be irritating on a machine with a full 4 GB of RAM.
Would raising
.code KERNBASE
allow a process to use more memory?
