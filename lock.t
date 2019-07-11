.ig
..
.chapter CH:LOCK "Locking"
.PP
Xv6 runs on multiprocessors: computers with
multiple CPUs executing independently.
These multiple CPUs share physical RAM,
and xv6 exploits the sharing to maintain
data structures that all CPUs read and write.
This sharing raises the possibility of
one CPU reading a data structure while another
CPU is mid-way through updating it, or even
multiple CPUs updating the same data simultaneously;
without careful design such parallel access is likely
to yield incorrect results or a broken data structure.
Even on a uniprocessor, an interrupt routine that uses
the same data as some interruptible code could damage
the data if the interrupt occurs at just the wrong time.
The word 
.italic-index "concurrency"
refers to situations in which
multiple instruction streams are interleaved,
due to multiprocessor parallelism, interrupts,
or thread switching.
.PP
In any situation where a shared data item may be
accessed concurrently, there must be a
.italic-index "concurrency control"
strategy to maintain correctness.
xv6 uses a handful of simple concurrency control
strategies; much more sophistication is possible.
This chapter focuses on one of the strategies used extensively
in xv6 and many other systems: the 
.italic-index lock .
.PP
A lock provides mutual exclusion, ensuring that only one CPU at a time can hold
the lock. If the programmer associates a lock with each shared data item,
and the code always holds the associated lock when using an item,
then the item will be used by only one CPU at a time.
In this situation, we say that the lock protects the data item.
.PP
The rest of this chapter explains why xv6 needs locks, how xv6 implements them, and how
it uses them.  A key observation will be that if you look at some code in
xv6, you must ask yourself if concurrent code could change
the intended behavior of the code by modifying data (or hardware resources)
it depends on.
You must keep in mind that the compiler may turn a
single C statement into several machine instructions,
and that those instructions may execute in a way that is
interleaved with instructions executing on other CPUs.
That is, you cannot assume that lines of C code
on the page are executed atomically.
Concurrency makes reasoning about correctness difficult.
.\"
.section "Race conditions"
.\"
.PP
As an example of why we need locks,
consider a linked list accessible from any
CPU on a multiprocessor.
The list supports push and pop operations, which
may be called concurrently.
Xv6's memory allocator works in much this way;
.code kalloc()
.line kalloc.c:/^kalloc/
pops a page of memory from a list of free pages,
and
.code kfree()
.line kalloc.c:/^kfree/
pushes a page onto the free list.
.PP
If there were no
concurrent requests, you might implement a list
.code push
operation as follows:
.P1
    1	struct element {
    2	  int data;
    3	  struct element *next;
    4	};
    5	
    6	struct element *list = 0;
    7	
    8	void
    9	push(int data)
   10	{
   11	  struct element *l;
   12	
   13	  l = malloc(sizeof *l);
   14	  l->data = data;
   15	  l->next = list;
   16	  list = l;
   17	}
.P2
.figure race
This implementation is correct if executed in isolation.
However, the code is not correct if more than one
copy executes concurrently.
If two CPUs execute
.code push
at the same time,
both might execute line 15
before either executes 16 (see 
.figref race ).
There would then be two
list elements with
.code next
set to the former value of
.code list .
When the two assignments to
.code list
happen at line 16,
the second one will overwrite the first;
the element involved in the first assignment
will be lost.
.PP
The lost update at line 16 is an example of a
.italic-index "race condition" .
A race condition is a situation in which a memory location is accessed
concurrently, and at least one access is a write.
A race is often a sign of a bug, either a lost update
(if the accesses are writes) or a read of
an incompletely-updated data structure.
The outcome of a race depends on
the exact timing of the two CPUs involved and
how their memory operations are ordered by the memory system,
which can make race-induced errors difficult to reproduce
and debug.
For example, adding print statements while debugging
.code push
might change the timing of the execution enough
to make the race disappear.
.PP
The usual way to avoid races is to use a lock.
Locks ensure
.italic-index "mutual exclusion" ,
so that only one CPU at a time can execute 
the sensitive lines of
.code push ;
this makes the scenario above impossible.
The correctly locked version of the above code
adds just a few lines (not numbered):
.P1
    6	struct element *list = 0;
     	struct lock listlock;
    7	
    8	void
    9	push(int data)
   10	{
   11	  struct element *l;
   12	  l = malloc(sizeof *l);
   13	  l->data = data;
   14	
     	  acquire(&listlock);
   15	  l->next = list;
   16	  list = l;
     	  release(&listlock);
   17	}
.P2
The sequence of instructions between
.code acquire
and
.code release
is often called a
.italic-index "critical section" ,
and the lock protects
.code list .
.PP
When we say that a lock protects data, we really mean
that the lock protects some collection of invariants
that apply to the data.
Invariants are properties of data structures that
are maintained across operations.
Typically, an operation's correct behavior depends
on the invariants being true when the operation
begins.  The operation may temporarily violate
the invariants but must reestablish them before
finishing.
For example, in the linked list case, the invariant is that
.code list
points at the first element in the list
and that each element's
.code next
field points at the next element.
The implementation of
.code push
violates this invariant temporarily: in line 15,
.code l
points
to the next list element, but
.code list
does not point at
.code l
yet (reestablished at line 16).
The race condition we examined above
happened because a second CPU executed
code that depended on the list invariants
while they were (temporarily) violated.
Proper use of a lock ensures that only one CPU at a time
can operate on the data structure in the critical section, so that
no CPU will execute a data structure operation when the 
data structure's invariants do not hold.
.PP
You can think of a lock as
.italic-index serializing
concurrent critical sections so that they run one at a time,
and thus preserve invariants (assuming the critical sections
are correct in isolation).
You can also think of critical sections guarded by the same lock as being
atomic with respect to each other,
so that each sees only the complete set of
changes from earlier critical sections, and never sees
partially-completed updates.
.PP
Note that it would be correct to move
.code acquire
earlier in
.code push.
For example, it is fine to move the call to
.code acquire
up to before line 12.
This may reduce parallelism because then the calls
to
.code malloc
are also serialized.
The section "Using locks" below provides some guidelines for where to insert
.code acquire
and
.code release
invocations.
.\"
.section "Code: Locks"
.\"
Xv6 has two types of locks: spin-locks and sleep-locks.
We'll start with spin-locks.
Xv6 represents a spin-lock as a
.code-index "struct spinlock"
.line spinlock.h:/struct.spinlock/ .
The important field in the structure is
.code locked ,
a word that is zero when the lock is available
and non-zero when it is held.
Logically, xv6 should acquire a lock by executing code like
.P1
   21	void
   22	acquire(struct spinlock *lk)
   23	{
   24	  for(;;) {
   25	    if(lk->locked == 0) {
   26	      lk->locked = 1;
   27	      break;
   28	    }
   29	  }
   30	}
.P2
Unfortunately, this implementation does not
guarantee mutual exclusion on a multiprocessor.
It could happen that two CPUs simultaneously
reach line 25, see that 
.code lk->locked
is zero, and then both grab the lock by executing line 26.
At this point, two different CPUs hold the lock,
which violates the mutual exclusion property.
What we need is a way to
make lines 25 and 26 execute as an
.italic-index "atomic"
(i.e., indivisible) step.
.PP
Because locks are widely used,
multi-core processors usually provide instructions that
can be used to implement an atomic version of
lines 25 and 26.
On the RISC-V this instruction is
.code "amoswap register, address" .
.code amoswap
reads the value at the memory address,
writes the contents of the register to that address,
and puts the value it read into the register.
That is, it swaps the contents of the register and the memory address.
It performs this sequence atomically, using special
hardware to prevent any
other CPU from using the memory address between the read and the write.
.PP
Xv6's 
.code-index acquire
.line spinlock.c:/^acquire/
uses the portable C library call 
.code "__sync_lock_test_and_set" ,
which boils down to the
.code amoswap
instruction;
the return value is the old (swapped) contents of
.code lk->locked .
The
.code acquire
function wraps the swap in a loop, retrying (spinning) until it has
acquired the lock.
Each iteration swaps one into
.code lk->locked 
and checks the previous value;
if the previous value is zero, then we've acquired the
lock, and the swap will have set 
.code lk->locked
to one.
If the previous value is one, then some other CPU
holds the lock, and the fact that we swapped one into
.code lk->locked
didn't change its value.
.PP
Once the lock is acquired,
.code acquire
records, for debugging, the CPU 
that acquired the lock.
The
.code lk->cpu
field is protected by the lock
and must only be changed while holding the lock.
.PP
The function
.code-index release
.line spinlock.c:/^release/
is the opposite of 
.code acquire :
it clears the 
.code lk->cpu
field
and then releases the lock.
Conceptually, the release just requires assigning zero to
.code lk->locked .
The C standard allows compilers to implement assignment
with multiple store instructions,
so a C assignment might be non-atomic with respect
to concurrent code.
Instead,
.code release
uses the C library function
.code "__sync_lock_release"
that performs an atomic assignment.
This function also boils down to a RISC-V
.code amoswap
instruction.
.\"
.section "Code: Using locks"
.\"
Xv6 uses locks in many places to avoid race conditions.
To see a simple example much like
.code push
above,
look at
.code kalloc
.line kalloc.c:/^kalloc/
and
.code free
.line kalloc.c:/^free/ .
Try Exercises 1 and 2 to see what happens if those
functions omit the locks.
You'll likely find that it's difficult to trigger incorrect
behavior, suggesting that it's hard to ensure that code
is free from locking errors and races.
It is not unlikely that xv6 has some races.
.PP
A hard part about using locks is deciding how many locks
to use and which data and invariants each lock should protect.
There are a few basic principles.
First, any time a variable can be written by one CPU
at the same time that another CPU can read or write it,
a lock should be introduced to keep the two
operations from overlapping.
Second, remember that locks protect invariants:
if an invariant involves multiple memory locations,
typically all of them need to be protected
by a single lock to ensure the invariant is maintained.
.PP
The rules above say when locks are necessary but say nothing about when locks
are unnecessary, and it is important for efficiency not to lock too much,
because locks reduce parallelism.  If parallelism isn't important, then one
could arrange to have only a single thread and not worry about locks.  A simple
kernel can do this on a multiprocessor by having a single lock that must be
acquired on entering the kernel and released on exiting the kernel (though
system calls such as pipe reads or
.code wait
would pose a problem).  Many uniprocessor operating systems have been converted to
run on multiprocessors using this approach, sometimes called a ``giant
kernel lock,'' but the approach sacrifices parallelism: only one
CPU can execute in the kernel at a time.  If the kernel does any heavy
computation, it would be more efficient to use a larger set of more
fine-grained locks, so that the kernel could execute on multiple CPUs
simultaneously.
.PP
As an example of relatively coarse-grained locking, xv6's
.code kalloc.c
allocator has a single free list protected by a single
lock. If concurrent allocation were a performance bottleneck,
it might be helpful to have multiple free lists, each with
its own lock, to allow truly parallel allocation.
As an example of relatively fine-grained locking, xv6
has a separate lock for each file, so that processes that
manipulate different files can often proceed without waiting
for each others' locks. On the other hand, this locking
scheme could be made even more fine-grained, if one wanted
to have good performance for processes that simultaneously
write different areas of the same file.
Ultimately lock granularity decisions need to be driven
by performance measurements as well as complexity considerations.
.PP
As subsequent chapters explain each part of xv6, they
will mention examples of xv6's use of locks
to deal with concurrency.
As a preview,
.figref locktable
lists all of the locks in xv6.
.figure locktable
.\"
.section "Deadlock and lock ordering"
.\"
If a code path through the kernel must hold several locks at the same time, it is
important that all code paths acquire those locks in the same order.  If
they don't, there is a risk of deadlock.  Let's say two code paths in
xv6 need locks A and B, but code path 1 acquires locks in the order A
then B, and the other path acquires them in the order B then A.
Suppose thread T1 executes code path 1 and acquires lock A,
and thread T2 executes code path 2 and acquires lock B.
Next T1 will try to acquire lock B, and T2 will try to acquire lock A.
Both acquires will block indefinitely, because in both cases the
other thread holds the needed lock, and won't release it until
its acquire returns.
To avoid such deadlocks, all code paths must acquire
locks in the same order. The need for a global lock acquisition order
means that locks are effectively part of each function's specification: 
callers must invoke functions in a way that causes locks to be acquired
in the agreed-on order.
.PP
Xv6 has many lock-order chains of length two involving
per-process locks
(the lock in each
.code "struct proc" )
due to the way that
.code sleep
works as discussed in Chapter
\*[CH:SCHED].
For example,
.code-index ideintr
holds the ide lock while calling 
.code-index wakeup ,
which acquires the 
.code-index ptable 
lock.
The file system code contains xv6's longest lock chains.
For example, creating a file requires simultaneously
holding a lock on the directory, a lock on the new file's inode,
a lock on a disk block buffer, 
.code idelock ,
and
.code ptable.lock .
To avoid deadlock, file system code always acquires locks in the order 
mentioned in the previous sentence.
.section "Locks and interrupt handlers"
.\"
Xv6 uses spin-locks in many situations to protect data that is used by
both interrupt handlers and threads.
For example,
a timer interrupt might
.line trap.c:/T_IRQ0...IRQ_TIMER/
increment
.code-index ticks 
at about the same time that a kernel
thread reads
.code ticks 
in
.code-index sys_sleep
.line sysproc.c:/ticks0.=.ticks/  .
The lock
.code-index tickslock
serializes the two accesses.
.PP
Interrupts can cause concurrency even on a single processor:
if interrupts are enabled, kernel code can be stopped
at any moment to run an interrupt handler instead.
Suppose
.code-index iderw
held the
.code-index idelock
and then got interrupted to run
.code-index ideintr .
.code Ideintr
would try to lock
.code idelock ,
see it was held, and wait for it to be released.
In this situation,
.code idelock
will never be released—only
.code iderw
can release it, and
.code iderw
will not continue running until
.code ideintr
returns—so the processor, and eventually the whole system, will deadlock.
.PP
To avoid this situation, if a spin-lock is used by an interrupt handler,
a processor must never hold that lock with interrupts enabled.
Xv6 is more conservative: when a processor enters a spin-lock
critical section, xv6 always ensures interrupts are disabled on
that processor.
Interrupts may still occur on other processors, so 
an interrupt's
.code acquire
can wait for a thread to release a spin-lock; just not on the same processor.
.PP
xv6 re-enables interrupts when a processor holds no spin-locks; it must
do a little book-keeping to cope with nested critical sections.
.code acquire
calls
.code-index pushcli
.line spinlock.c:/^pushcli/
and
.code release
calls
.code-index popcli
.line spinlock.c:/^popcli/
to track the nesting level of locks on the current processor.
When that count reaches zero,
.code popcli 
restores the interrupt enable state that existed 
at the start of the outermost critical section.
The
.code cli
and
.code sti
functions execute the x86 interrupt disable and enable
instructions, respectively.
.PP
It is important that
.code-index acquire
call
.code pushcli
before the 
.code-index xchg
that might acquire the lock
.line spinlock.c:/while.xchg/ .
If the two were reversed, there would be
a few instruction cycles when the lock
was held with interrupts enabled, and
an unfortunately timed interrupt would deadlock the system.
Similarly, it is important that
.code-index release
call
.code-index popcli
only after the
.code-index xchg
that releases the lock
.line spinlock.c:/xchg.*0/ .
.\"
.section "Instruction and memory ordering"
.\"
.PP
This chapter has assumed that code executes in the order
in which the code appears in the program.  Many
compilers and processors, however, execute code out of order
to achieve
higher performance.  If an instruction takes many cycles to complete,
a processor may issue the instruction early so that it can
overlap with other instructions and avoid processor stalls. For
example, a processor may notice that in a serial sequence of
instructions A and B are not dependent on each other.
The processor may start instruction B first, either because its
inputs are ready before A's inputs, or in order to overlap
execution of A and B.
A compiler may perform a similar re-ordering by emitting instructions
for one statement before the instructions for a statement that precedes it
in the source.
.PP
Compilers and processors follow certain rules when they re-order to
ensure that they don't change the results of correctly-written
serial code.
However, the rules do allow changing the results of concurrent code,
and can easily lead to incorrect behavior on multiprocessors
or if there are interrupts.
.PP
For example, in this code for
.code push ,
it would be a disaster if the compiler or processor caused the effects
of line 4 (or 2 or 5) to be visible to other cores after the effects
of line 6:
.P1
    1	  l = malloc(sizeof *l);
    2	  l->data = data;
    3	  acquire(&listlock);
    4	  l->next = list;
    5	  list = l;
    6	  release(&listlock);
.P2
If the hardware or compiler would re-order, for example, the effects of line 4 to
be visible after line 6, then another processor can acquire
.code listlock
and observe that
.code list
points to
.code l ,
but it won't observe that
.code l->next
is set to the remainder of the list and won't be able to read the rest of the list.
.PP
To tell the hardware and compiler not to perform such re-orderings,
xv6 uses
.code __sync_synchronize() ,
in both
.code acquire
and
.code release .
.code _sync_synchronize()
is a memory barrier:
it tells the compiler and CPU to not reorder loads or stores across the
barrier.
Xv6 worries about ordering only in
.code acquire
and
.code release ,
because concurrent access to data structures other than the lock structure is
performed between 
.code acquire
and
.code release .
.\"
.section "Sleep locks"
.\"
.PP
Sometimes xv6 code needs to hold a lock for a long time. For example,
the file system (Chapter \*[CH:FS]) keeps a file locked while reading
and writing its content on the disk, and these disk operations can
take tens of milliseconds. Efficiency demands that the processor be
yielded while waiting so that other threads can make
progress, and this in turn means that xv6 needs locks that 
work well when held across context switches.
Xv6 provides such locks in the form of
.italic-index "sleep-locks" .
.PP
Xv6 sleep-locks support yielding the processor during their critical
sections. This property poses a design challenge: if thread T1 holds
lock L1 and has yielded the processor, and thread T2 wishes to acquire
L1, we have to ensure that T1 can execute while T2 is waiting so
that T1 can release L1. T2 can't use the spin-lock acquire
function here: it
spins with interrupts turned off, and that would prevent T1
from running. To avoid this deadlock, the sleep-lock acquire
routine
(called
.code acquiresleep )
yields the processor while waiting, and does not disable
interrupts.
.PP
.code acquiresleep
.line sleeplock.c:/^acquiresleep/
uses techniques that will be explained in
Chapter \*[CH:SCHED].
At a high level, a sleep-lock has a
.code locked
field that is protected by a spinlock, and 
.code acquiresleep 's
call to
.code sleep
atomically yields the CPU and releases the spin-lock.
The result is that other threads can execute while
.code acquiresleep
waits.
.PP
Because sleep-locks leave interrupts enabled, they cannot be
used in interrupt handlers.
Because
.code acquiresleep
may yield the processor,
sleep-locks cannot be used inside spin-lock critical
sections (though spin-locks can be used inside sleep-lock
critical sections).
.PP
Spin-locks have low overhead, but they waste CPU time if they
are held for long periods when other CPUs are waiting
for them.
Thus they are best suited for short critical sections.
Xv6 uses sleep-locks in the file system,
where it is convenient to
be able to hold locks across lengthy disk operations.
.\"
.section "Limitations of locks"
.\"
.PP
Locks often solve concurrency problems cleanly,
but there are times when they are awkward. Subsequent chapters will
point out such situations in xv6; this section outlines some
of the problems that come up.
.PP
Sometimes a function uses data which must be guarded by a lock,
but the function is called both from code that already holds
the lock and from code that wouldn't otherwise need the lock.
One way to deal with this is to have two variants of the function,
one that acquires the lock, and the other that expects the
caller to already hold the lock; see
.code wakeup1
for an example
.line proc.c:/^wakeup1/ .
Another approach is for the function to require callers
to hold the lock whether the caller needs it or not,
as with 
.code sched
.line proc.c:/^sched/ .
Kernel developers need to be aware of such requirements.
.PP
It might seem that one could simplify situations where both
caller and callee need a lock by allowing 
.italic-index "recursive locks" ,
so that if a function holds a lock,
any function it calls is allowed to re-acquire the lock.
However, the programmer would then need to reason about
all combinations of caller and callee, because it
will no longer be the case that the data structure's
invariants always hold after an acquire.
Whether recursive locks are better than xv6's use of conventions about
functions that require a lock to be held is not clear.
The larger lesson is that 
(as with global lock ordering to avoid deadlock) lock requirements 
sometimes can't be private, but intrude themselves on
the interfaces of functions and modules.
.PP
A situation in which locks are insufficient is when one thread needs
to wait for another thread's update to a data structure, for example
when a pipe's reader waits for some other thread to write the pipe. The waiting
thread cannot hold the lock on the data, since that
would prevent the update it is waiting for. Instead, xv6 provides
a separate mechanism that jointly manages the lock and
event wait; see the description of
.code sleep
and
.code wakeup
in Chapter \*[CH:SCHED].
.\"
.section "Real world"
.\"
Concurrency primitives and parallel programming are active areas of research,
because programming with locks is still challenging.  It is best to use locks as the
base for higher-level constructs like synchronized queues, although xv6 does not
do this.  If you program with locks, it is wise to use a tool that attempts to
identify race conditions, because it is easy to miss an invariant that requires
a lock.
.PP
Most operating systems support POSIX threads (Pthreads), which allow a user
process to have several threads running concurrently on different processors.
Pthreads has support for user-level locks, barriers, etc.  Supporting Pthreads requires
support from the operating system. For example, it should be the case that if
one pthread blocks in a system call, another pthread of the same process should
be able to run on that processor.  As another example, if a pthread changes its
process's address space (e.g., grow or shrink it), the kernel must arrange that
other processors that run threads of the same process update their hardware page
tables to reflect the change in the address space.  On the x86, this involves
shooting down the
.italic-index "Translation Look-aside Buffer (TLB)"
of other processors using inter-processor interrupts (IPIs).
.PP
It is possible to implement locks without atomic instructions, but it is
expensive, and most operating systems use atomic instructions.
.PP
Locks can be expensive if many processors try to acquire the same lock
at the same time.  If one processor has a lock
cached in its local cache, and another processor must acquire the lock, then the
atomic instruction to update the cache line that holds the lock must move the line
from the one processor's cache to the other processor's cache, and perhaps
invalidate any other copies of the cache line.  Fetching a cache line from
another processor's cache can be orders of magnitude more expensive than
fetching a line from a local cache.
.PP
To avoid the expenses associated with locks, many operating systems use
lock-free data structures and algorithms.  For example, it is possible to
implement a linked list like the one in the beginning of the chapter that
requires no locks during list searches, and one atomic instruction to insert an
item in a list.  Lock-free programming is more complicated, however, than
programming locks; for example, one must worry about instruction and memory
reordering.  Programming with locks is already hard, so xv6 avoids the
additional complexity of lock-free programming.
.\"
.section "Exercises"
.\"
.PP
1. Comment out the calls to
.code acquire
and
.code release
in
.code kalloc
.line kalloc.c:/^kalloc/ .
This seems like it should cause problems for
kernel code that calls
.code kalloc ;
what symptoms do you expect to see?
When you run xv6, do you see these symptoms?
How about when running
.code usertests ?
If you don't see a problem, why not?
See if you can provoke a problem by inserting
dummy loops into the critical section of
.code kalloc .
.PP
2. Suppose that you instead commented out the
locking in
.code kfree 
(after restoring locking in
.code kalloc ).
What might now go wrong? Is lack of locks in
.code kfree
less harmful than in
.code kalloc ?
.PP
3. If two CPUs call
.code kalloc
at the same time, one will have to wait for the other,
which is bad for performance.
Modify 
.code kalloc.c
to have more parallelism, so that simultaneous
calls to
.code kalloc
from different CPUs can proceed without waiting for each other.
.PP
4. Write a parallel program using POSIX threads, which is supported on most
operating systems. For example, implement a parallel hash table and measure if
the number of puts/gets scales with increasing number of cores.
.PP
5. Implement a subset of Pthreads in xv6.  That is, implement a user-level
thread library so that a user process can have more than 1 thread and arrange
that these threads can run in parallel on different processors.  Come up with a
design that correctly handles a thread making a blocking system call and
changing its shared address space.
