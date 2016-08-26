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
Any code that accesses shared data concurrently from multiple CPUs (or
at interrupt time) must have a strategy for maintaining correctness
despite concurrency. xv6 uses a handful of simple concurrency control
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
Proving this implementation correct is a typical
exercise in a data structures and algorithms class.
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
This kind of problem is called a 
.italic-index "race condition" .
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
The typical way to avoid races is to use a lock.
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
programming.  Xv6 uses a few coarse data-structure specific locks; for
example, xv6 uses a single lock protecting the process table and its
invariants, which are described in Chapter \*[CH:SCHED].  A more
fine-grained approach would be to have a lock per entry in the process
table so that threads working on different entries in the process
table can proceed in parallel.  However, it complicates operations
that have invariants over the whole process table, since they might
have to take out several locks. Subsequent chapters will discuss
how each part of xv6 deals with concurrency, illustrating
how to use locks.
.\"
.section "Lock ordering"
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
Because xv6 uses relatively few coarse-grained locks, it has
few lock-order chains.  The longest chains are only two deep. For
example,
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
\*[CH:SCHED].  In the file system there are a number of examples of
chains of two because the file system must, for example, acquire a
lock on a directory and the lock on a file in that directory to unlink
a file from its parent directory correctly.  Xv6 always acquires the
locks in the order first parent directory and then the file.
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
For example, consider
.code-index release ,
which assigns 0 to
.code lk->locked .
If the processor executed
.code lk->locked=0 
before an instruction inside the critical section that the
lock is protecting, then another processor could acquire the lock and observe a
partial update. This re-ordering could break the invariant of the critical
section.
.PP
To tell the hardware and compiler not to perform such re-orderings,
xv6 uses
.code __sync_synchronize() ,
both in
.code acquire
and
.code release .
_sync_synchronize() is a memory barrier:
it tells the compiler to not reorder instructions across the
barrier, and to tell the CPU not to reorder either.
Xv6 worries about ordering only in
.code acquire
and
.code release ,
because concurrent access to other data structures than the lock structure is
performed between an
.code acquire
and
.code release .
.\"
.section "Modularity and recursive locks"
.\"
.PP
System design strives for clean, modular abstractions:
it is best when a caller does not need to know how a
callee implements particular functionality.
Locks interfere with this modularity.
For example, if a CPU holds a particular lock,
it cannot call any function 
.code f 
that will try to 
reacquire that lock: since the caller can't release
the lock until 
.code f 
returns, if 
.code f 
tries to acquire
the same lock, it will spin forever, or deadlock.
.PP
There are no transparent solutions that allow the
caller and callee to hide which locks they use.
One common, transparent, but unsatisfactory solution
is 
.italic-index "recursive locks" ,
which allow a callee to
reacquire a lock already held by its caller.
The problem with this solution is that recursive
locks can't be used to protect invariants.
After
.code insert
called
.code acquire(&listlock)
above, it can assume that no other function
holds the lock, that no other function is in the middle
of a list operation, and most importantly that all
the list invariants hold.
In a system with recursive locks,
.code insert
can assume nothing after it calls
.code acquire :
perhaps
.code acquire
succeeded only because one of 
.code insert 's
caller already held the lock
and was in the middle of editing the list data structure.
Maybe the invariants hold or maybe they don't.
The list no longer protects them.
Locks are just as important for protecting callers and callees
from each other as they are for protecting different CPUs
from each other;
recursive locks give up that property.
.ig
The last case would be a good one to construct an example around.
maybe the directory example in lecture notes
..
.PP
The interaction between interrupt handlers and non-interrupt code
provides a nice example why recursive locks are problematic.  If xv6
used recursive locks,
then interrupt handlers could
run while kernel code is in a critical section.  This could
create havoc, since when the interrupt handler runs, invariants that
the handler relies on might be temporarily violated.  For example,
.code-index ideintr
.line ide.c:/^ideintr/
assumes that the linked list with outstanding requests is well-formed.
If xv6 used recursive locks, then 
.code ideintr
might run while 
.code-index iderw
is in the middle of manipulating the linked list, and the linked list
would end up in an incorrect state.
.PP
We must consider locks part of a function's
specification.
If a function acquires a lock, the programmer must
ensure that the caller doesn't already hold it;
if a function assumes some lock is already held
(i.e., uses the protected data but doesn't acquire the lock),
the programmer must ensure that the caller already
holds the lock.
Locks force themselves into our abstractions.
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
User-level programs need locks too, but in xv6 processes have only one thread
and processes don't share memory, and so there is no need for locks in
xv6 applications.
.PP
Most operating systems support POSIX threads (Pthreads), which allow a user
process to have several threads running concurrently on different processors.
Pthreads has support for locks, barriers, etc.  Supporting Pthreads requires
support from the operating system. For example, it should be the case that if
one pthread blocks in a system call, another pthread of the same process should
be able to run on that processor.  As another example, if a pthread changes its
process's address space (e.g., grow or shrink it), the kernel must arrange that
other processors that run threads of the same process update their hardware page
tables to reflect the change in the address space.  On the x86, this involves
shooting down the translation look-aside buffer (TLB) of other processors using
inter-processor interrupts (IPIs).
.PP
It is possible to implement locks without atomic instructions, but it is
expensive, and most operating systems use atomic instructions.
.PP
Locks can be expensive when they are contended.  If one processor has a lock
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
4. Setting a bit in a buffer's
.code flags
is not an atomic operation: the processor makes a copy of 
.code flags
in a register, edits the register, and writes it back.
Thus it is important that two processes are not writing to
.code flags
at the same time.
xv6 edits the
.code B_BUSY
bit only while holding
.code buflock
but edits the 
.code B_VALID
and
.code B_WRITE
flags without holding any locks.  Why is this safe?
.PP
5. Implement a subset of Pthreads in xv6.  That is, implement a user-level
thread library so that a user process can have more than 1 thread and arrange
that these threads can run in parallel on different processors.  Come up with a
design that correctly handles a thread making a blocking system call and
changing its shared address space.


