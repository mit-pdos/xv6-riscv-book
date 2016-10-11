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
simultaneous writes to the same data structure
from multiple CPUs, or even reads simultaneous with a write;
without careful design such parallel access is likely
to yield incorrect results or a broken data structure.
Even on a uniprocessor, an interrupt routine that uses
the same data as some interruptible code could damage
the data if the interrupt occurs at just the wrong time.
.PP
Any code that accesses shared data concurrently
must have a strategy for maintaining correctness
despite concurrency.
The concurrency may arise from accesses by multiple cores,
or by multiple threads,
or by interrupt code.
xv6 uses a handful of simple concurrency control
strategies; much more sophistication is possible.
This chapter focuses on one of the strategies used extensively
in xv6 and many other systems: the 
.italic-index lock .
.PP
A lock provides mutual exclusion, ensuring that only one CPU at a time can hold
the lock. If a lock is associated with each shared data item,
and the code always holds the associated lock when using a given
item,
then we can be sure that the item is used from only one CPU at a time.
In this situation, we say that the lock protects the data item.
.PP
The rest of this chapter explains why xv6 needs locks, how xv6 implements them, and how
it uses them.  A key observation will be that if you look at some code in
xv6, you must ask yourself if another processor (or interrupt) could change
the intended behavior of the code by modifying data (or hardware resources)
it depends on.
You must keep in mind that a
single C statement can be several machine instructions and thus another processor or an interrupt may
muck around in the middle of a C statement.  You cannot assume that lines of code
on the page are executed atomically.
Concurrency makes reasoning about 
correctness much more difficult.
.\"
.section "Race conditions"
.\"
.PP
As an example on why we need locks, consider several processors sharing a single disk, such
as the IDE disk in xv6.  The disk driver maintains a linked list of
the outstanding disk requests 
.line ide.c:/idequeue/
and processors may add new
requests to the list concurrently
.line ide.c:/^iderw/ .
If there were no
concurrent requests, you might implement the linked list as follows:
.P1
    1	struct list {
    2	  int data;
    3	  struct list *next;
    4	};
    5	
    6	struct list *list = 0;
    7	
    8	void
    9	insert(int data)
   10	{
   11	  struct list *l;
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
.code insert
at the same time,
it could happen that both execute line 15
before either executes 16 (see 
.figref race ).
If this happens, there will now be two
list nodes with
.code next
set to the former value of
.code list .
When the two assignments to
.code list
happen at line 16,
the second one will overwrite the first;
the node involved in the first assignment
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
.code insert
might change the timing of the execution enough
to make the race disappear.
.PP
The usual way to avoid races is to use a lock.
Locks ensure
.italic-index "mutual exclusion" ,
so that only one CPU can execute 
.code insert
at a time; this makes the scenario above
impossible.
The correctly locked version of the above code
adds just a few lines (not numbered):
.P1
    6	struct list *list = 0;
     	struct lock listlock;
    7	
    8	void
    9	insert(int data)
   10	{
   11	  struct list *l;
   12	
     	  acquire(&listlock);
   13	  l = malloc(sizeof *l);
   14	  l->data = data;
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
points at the first node in the list
and that each node's
.code next
field points at the next node.
The implementation of
.code insert
violates this invariant temporarily: line 13 creates a new
list element
.code l
with the intent that
.code l
be the first node in the list,
but 
.code l 's
next pointer does not point at the next node
in the list yet (reestablished at line 15)
and
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
.\"
.section "Code: Locks"
.\"
Xv6 represents a lock as a
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
   25	    if(!lk->locked) {
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
Rather than helping us avoid race conditions,
this implementation of
.code-index acquire 
has its own race condition.
The problem here is that lines 25 and 26 executed
as separate actions.  In order for the routine above
to be correct, lines 25 and 26 must execute in one
.italic-index "atomic"
(i.e., indivisible) step.
.PP
To execute those two lines atomically, 
xv6 relies on a special x86 instruction,
.code-index xchg
.line x86.h:/^xchg/ .
In one atomic operation,
.code xchg
swaps a word in memory with the contents of a register.
The function
.code-index acquire
.line spinlock.c:/^acquire/
repeats this
.code xchg
instruction in a loop;
each iteration atomically reads
.code lk->locked
and sets it to 1
.line spinlock.c:/xchg..lk/ .
If the lock is already held,
.code lk->locked
will already be 1, so the
.code xchg
returns 1 and the loop continues.
If the
.code xchg
returns 0, however,
.code acquire
has successfully acquired the lock—\c
.code locked
was 0 and is now 1—\c
so the loop can stop.
Once the lock is acquired,
.code acquire
records, for debugging, the CPU and stack trace
that acquired the lock.
If a process forgets to release a lock, this information
can help to identify the culprit.
These debugging fields are protected by the lock
and must only be edited while holding the lock.
.PP
The function
.code-index release
.line spinlock.c:/^release/
is the opposite of 
.code acquire :
it clears the debugging fields
and then releases the lock.
The function uses an assembly instruction to clear
.code locked ,
because clearing this field should be atomic so that the
.code xchg
instruction won't see a subset of the 4 bytes
that hold
.code locked
updated.
The x86 guarantees that a 32-bit
.code movl
updates all 4 bytes atomically.  Xv6 cannot use a regular C assignment, because
the C language specification does not specify that a single assignment is
atomic.
.PP
Xv6's implementation of spinlocks is x86-specific, and xv6 is thus not directly
portable to other processors.  To allow for portable implementations of
spinlocks, the C language supports a library of atomic instructions; a portable
operating system would use those instructions.
.\"
.section "Code: Using locks"
.\"
Xv6 uses locks in many places to avoid race conditions.  A simple
example is in the IDE driver
.sheet ide.c .
As mentioned in the beginning of the chapter,
.code-index iderw 
.line ide.c:/^iderw/ 
has a queue of disk requests
and processors may add new
requests to the list concurrently
.line ide.c:/DOC:insert-queue/ .
To protect this list and other invariants in the driver,
.code iderw
acquires the
.code-index idelock 
.line ide.c:/DOC:acquire-lock/
and 
releases it at the end of the function.
Exercise 1 explores how to trigger the race condition that we saw at the
beginning of the chapter by moving the 
.code acquire
to after the queue manipulation.
It is worthwhile to try the exercise because it will make clear that it is not
that easy to trigger the race, suggesting that it is difficult to find
race-conditions bugs.  It is not unlikely that xv6 has some races.
.PP
A hard part about using locks is deciding how many locks
to use and which data and invariants each lock protects.
There are a few basic principles.
First, any time a variable can be written by one CPU
at the same time that another CPU can read or write it,
a lock should be introduced to keep the two
operations from overlapping.
Second, remember that locks protect invariants:
if an invariant involves multiple data structures,
typically all of the structures need to be protected
by a single lock to ensure the invariant is maintained.
.PP
The rules above say when locks are necessary but say nothing about
when locks are unnecessary, and it is important for efficiency not to
lock too much, because locks reduce parallelism.  If efficiency wasn't important, then one could use a
uniprocessor computer and not worry at all about locks.  For protecting
kernel data structures, it might suffice to create a single lock that
must be acquired on entering the kernel and released on exiting the
kernel (though system calls such as pipe reads or
.code wait
would pose a problem).  Many uniprocessor operating systems have been converted to
run on multiprocessors using this approach, sometimes called a ``giant
kernel lock,'' but the approach sacrifices true concurrency: only one
CPU can execute in the kernel at a time.  If the kernel does any heavy
computation, it would be more efficient to use a larger set of more
fine-grained locks, so that the kernel could execute on multiple CPUs
simultaneously.
.PP
Ultimately, the choice of lock granularity is an exercise in parallel
programming.  Xv6 uses a few coarse data-structure specific locks (see
.figref locktable ).
For
example, xv6 uses a single lock protecting the process table and its
invariants, which are described in Chapter \*[CH:SCHED].  A more
fine-grained approach would be to have a lock per entry in the process
table so that threads working on different entries in the process
table can proceed in parallel.  However, it complicates operations
that have invariants over the whole process table, since they might
have to take out several locks. Subsequent chapters will discuss
how each part of xv6 deals with concurrency, illustrating
how to use locks.
.figure locktable
.\"
.section "Deadlock and lock ordering"
.\"
If a code path through the kernel must hold several locks at the same time, it is
important that all code paths acquire the locks in the same order.  If
they don't, there is a risk of deadlock.  Let's say two code paths in
xv6 needs locks A and B, but code path 1 acquires locks in the order A
then B, and the other code acquires them in the order B then A. This
situation can result in a deadlock, because code path 1 might acquire
lock A and before it acquires lock B, code path 2 might acquire lock
B. Now neither code path can proceed, because code path 1 needs lock
B, which code path 2 holds, and code path 2 needs lock A, which code
path 1 holds.  To avoid such deadlocks, all code paths must acquire
locks in the same order. The need for a global lock acquisition order
means that locks are effectively part of each function's specification: the
caller must invoke functions in a way that causes locks to be acquired
in the agreed-on order.
.PP
Because xv6 uses relatively few coarse-grained locks, it has few lock-order
chains.  The longest chain with spinlocks is only two deep. For example,
.code-index ideintr
holds the ide lock while calling 
.code-index wakeup ,
which acquires the 
.code-index ptable 
lock.
There are a number of other examples involving 
.code-index sleep
and
.code-index wakeup .
These orderings come about because
.code sleep
and 
.code wakeup 
have a complicated invariant, as discussed in Chapter
\*[CH:SCHED].
.PP
In the file system there are a number of examples of more complicated situations
because the file system holds long-term locks (called
.italic-index sleeplocks
in xv6), and a
kernel thread may hold several of them.  For example, a kernel thread in the
file system must acquire a lock on a directory and the lock on a new file to add
the file to the directory correctly.  In addition, the kernel thread may hold at
the same time a lock on one buffer (e.g., holding a block of the new file).  To
avoid deadlock, kernel threads always acquire the locks in the order first
parent directory, then the file, and then a file block.
.PP
The longest lock chain in xv6 combines the above spinlock chain and the
long-term lock chain. This chain is 5 locks long: the 3 long-term locks in the
file system and then the ide lock and the
.code ptable
lock to read a file block from the disk.
.PP
It is possible for xv6 to deadlock, however, when, for example, running with a
small buffer cache. Therefore, xv6 panics when it runs out of buffers rather
waiting for a free buffer and run the risk of deadlock.
.section "Interrupt handlers"
.\"
Xv6 uses locks to protect interrupt handlers
running on one CPU from kernel code accessing the same
data on another CPU.
For example,
the timer interrupt handler 
.line trap.c:/T_IRQ0...IRQ_TIMER/
increments
.code-index ticks ,
but another CPU might be in
.code-index sys_sleep
.line sysproc.c:/ticks0.=.ticks/ 
reading
.code ticks
at the same time.
The lock
.code-index tickslock
synchronizes access by the two CPUs to the
single variable.
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
To avoid this situation, if a lock is used by an interrupt handler,
a processor must never hold that lock with interrupts enabled.
Xv6 is more conservative: it never holds any lock with interrupts enabled.
It uses
.code-index pushcli
.line spinlock.c:/^pushcli/
and
.code-index popcli
.line spinlock.c:/^popcli/
to manage a stack of ``disable interrupts'' operations
.code-index cli "" (
is the x86 instruction that disables interrupts).
.code Acquire
calls
.code-index pushcli
before trying to acquire a lock
.line spinlock.c:/pushcli/ ,
and 
.code release
calls
.code-index popcli
after releasing the lock
.line spinlock.c:/popcli/ .
.code Pushcli
.line spinlock.c:/^pushcli/
and
.code-index popcli
.line spinlock.c:/^popcli/
are more than just wrappers
around 
.code-index cli
and
.code-index sti :
they are counted, so that it takes two calls
to
.code popcli
to undo two calls to
.code pushcli ;
this way, if code holds two locks,
interrupts will not be reenabled until both
locks have been released.
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
a processor may want to issue the instruction early so that it can
overlap with other instructions and avoid processor stalls. For
example, a processor may notice that in a serial sequence of
instructions A and B are not dependent on each other and start
instruction B before A so that it will be completed when the processor
completes A.
A compiler may perform a similar re-ordering by emitting instruction
B before instruction A in the executable file.
Concurrency, however, may expose this reordering to
software, which can lead to incorrect behavior.
.PP
For example, in this code for
.code insert ,
it would be a disaster if the compiler or processor caused the effects
of line 4 (or 3 or 5) to be visible to other cores after the effects
of line 6:
.P1
    1	  acquire(&listlock);
    2	  l = malloc(sizeof *l);
    3	  l->data = data;
    4	  l->next = list;
    5	  list = l;
    6	  release(&listlock);
.P2
To tell the hardware and compiler not to perform such re-orderings,
xv6 uses
.code __sync_synchronize() ,
in both
.code acquire
and
.code release .
_sync_synchronize() is a memory barrier:
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
.section "Limitations of spin-locks"
.\"
.PP
Spin-locks are often a clean solution to concurrency problems,
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
.PP
It is easy for xv6 to deadlock when holding a spin lock across
.code sleep ,
as we will see
in Chapter \*[CH:FS],
because spinlocks disable interrupts.
Therefore, xv6 supports
.code-index "sleep locks"
for kernel threads that must hold long-term locks.  For example, a kernel thread
may need to hold a lock on a block read from disk while reading another block
from the disk so that it can update both blocks in an atomic operation.
As will see, xv6 implements sleep locks using spin locks.
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
1. Write a parallel program using POSIX threads, which is supported on most
operating systems. For example, implement a parallel hash table and measure if
the number of puts/gets scales with increasing number of cores.
.PP
2. Remove the xchg in acquire. Explain what happens when you run xv6?
.PP
3. Move the acquire in iderw to before sleep.  Is there a race? Why don't you
observe it when booting xv6 and run stressfs?  Increase critical section with a
dummy loop; what do you see now?  explain.
.PP
4. Implement a subset of Pthreads in xv6.  That is, implement a user-level
thread library so that a user process can have more than 1 thread and arrange
that these threads can run in parallel on different processors.  Come up with a
design that correctly handles a thread making a blocking system call and
changing its shared address space.


