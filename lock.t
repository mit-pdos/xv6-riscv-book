.so book.mac
.chapter CH:LOCK "Locking
.PP
Xv6 runs on multiprocessors, computers with
multiple CPUs executing code independently.
These multiple CPUs operate on a single physical
address space and share data structures; xv6 must
introduce a coordination mechanism to keep them
from interfering with each other.
Even on a uniprocessor, xv6 must use some mechanism
to keep interrupt handlers from interfering with
non-interrupt code.
Xv6 uses the same low-level concept for both: locks.
Locks provide mutual exclusion, ensuring that only one CPU at a time
can hold a lock.
If xv6 only accesses a data structure 
while holding a particular lock,
then xv6 can be sure that only one CPU
at a time is accessing the data structure.
In this situation, we say that the lock protects
the data structure.
.PP
As an example, consider the implementation of a simple linked list:
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
Proving this implementation correct is a typical
exercise in a data structures and algorithms class.
Even though this implementation can be proved
correct, it isn't, at least not on a multiprocessor.
If two different CPUs execute
.code insert
at the same time,
it could happen that both execute line 15
before either executes 16.
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
This kind of problem is called a race condition.
The problem with races is that they depend on
the exact timing of the two CPUs involved and
are consequently difficult to reproduce.
For example, adding print statements while debugging
.code insert
might change the timing of the execution enough
to make the race disappear.
.PP
The typical way to avoid races is to use a lock.
Locks ensure mutual exclusion,
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
vioilates this invariant temporarily: line X creates a new
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
can operate on the data structure, so that
no CPU will execute a data structure operation when the 
data structure's invariants do not hold.
.PP
.\"
.section "Code: Locks
.\"
Xv6's represents a lock as a
.code struct
.code spinlock
.line spinlock.h:/struct.spinlock/ .
The critical field in the structure is
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
guarantee mutual exclusion on a modern
multiprocessor.
It could happen that two (or more) CPUs simultaneously
reach line 25, see that 
.code lk->locked
is zero, and then both grab the lock by executing lines
26 and 27.
At this point, two different CPUs hold the lock,
which violates the mutual exclusion property.
Rather than helping us avoid race conditions,
this implementation of
.code acquire 
has its own race condition.
The problem here is that lines 25 and 26 executed
as separate actions.  In order for the routine above
to be correct, lines 25 and 26 must execute in one
atomic step.
.PP
To execute those two lines atomically, 
xv6 relies on a special 386 hardware instruction,
.code xchg
.line x86.h:/^xchg/ .
In one atomic operation,
.code xchg
swaps a word in memory with the contents of a register.
.code Acquire
.line spinlock.c:/^acquire/
repeats this
.code xchg
instruction in a loop;
each iteration reads
.code lk->locked
and atomically sets it to 1
.line spinlock.c:/xchg..lk/ .
If the lock is held,
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
When a process acquires a lock
and forget to release it, this information
can help to identify the culprit.
These debugging fields are protected by the lock
and must only be edited while holding the lock.
.PP
.code Release
.line spinlock.c:/^release/
is the opposite of 
.code acquire :
it clears the debugging fields
and then releases the lock.
.\"
.section "Modularity and recursive locks
.\"
.PP
System design strives for clean, modular abstractions:
it is best when a caller does not need to know how a
callee implements particular functionality.
Locks interfere with this modularity.
For example, if a CPU holds a particular lock,
it cannot call any function f that will try to 
reacquire that lock: since the caller can't release
the lock until f returns, if f tries to acquire
the same lock, it will spin forever, or deadlock.
.PP
There are no transparent solutions that allow the
caller and callee to hide which locks they use.
One common, transparent, but unsatisfactory solution
is ``recursive locks,'' which allow a callee to
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
.PP
Since there is no ideal transparent solution,
we must consider locks part of the function's
specification.
The programmer must arrange that function doesn't
invoke a function f while holding a lock that f needs.
Locks force themselves into our abstractions.
.\"
.section "Code: Using locks
.\"
The hardest part about using locks is deciding how many locks
to use and which data and invariants each lock protects.
There are a few basic principles.
First, any time a variable can be written by one CPU
at the same time that another CPU can read or write it,
a lock should be introduced to keep the two
operations from overlapping.
Second, remeber that locks protect invariants:
if an invariant involves multiple data structures,
typically all of the structures need to be protected
by a single lock to ensure the invariant is maintained.
.PP
The rules above say when locks are necessary
but say nothing about when locks are unnecessary,
and it is important for efficiency not to lock too much.
For protecting kernel data structures, it would suffice
to create a single lock that must be acquired
on entering the kernel and released on exiting the kernel.
Many uniprocessor operating systems have been 
converted to run on multiprocessors using this approach,
sometimes called a ``giant kernel lock,''
but the approach sacrifices true concurrency:
only one CPU can execute in the kernel at a time.
If the kernel does any heavy computation, it would be
more efficient to use a larger set of more fine-grained
locks, so that the kernel could execute on multiple
CPUs simultaneously.
.PP
Ultimately, the choice of lock granularity is more art than science.
Xv6 uses a few coarse data-structure specific locks.
Hopefully, the examples of xv6 will help convey a feeling
for some of the art.
.PP
XXX look at code here XXX
.\"
.section "Interrupt handlers
.\"
Xv6 uses locks to protect interrupt handlers
running on one CPU from non-interrupt code accessing the same
data on another CPU.
For example,
the timer interrupt handler 
.line trap.c:/T_IRQ0...IRQ_TIMER/
increments
.code ticks
but another CPU might be in
.code sys_sleep
at the same time, using the variable
.line sysproc.c:/ticks0.=.ticks/ .
The lock
.code tickslock
synchronizes access by the two CPUs to the
single variable.
.PP
Locks are useful not just for synchronizing multiple CPUs
but also for synchronizing interrupt and non-interrupt code
on the same CPU.
The 
.code ticks
variable is used by the interrupt handler and
also by the non-interrupt function
.code sys_sleep ,
as we just saw.
If the non-interrupt code is manipulating a shared
data structure, it may not be safe for the CPU to
interrupt that code and start running an interrupt
handler that will use the data structure.
Xv6's disables interrupts on a CPU when that CPU holds a lock;
this ensures proper data access and also avoids deadlocks:
an interrupt handler can never acquire a lock aleady held
by the code it interrupted.
.PP
Before attempting to acquire a lock,
.code acquire
calls
.code pushcli
.line spinlock.c:/pushcli/
to disable interrupts.
.code Release
calls
.code popcli
.line spinlock.c:/popcli/ 
to allow them to be enabled.
(The underlying x86 instruction to
disable interrupts is named
.code cli .)
.code Pushcli
.line spinlock.c:/^pushcli/
and
.code popcli
.line spinlock.c:/^popcli/
are more than just wrappers
around 
.code cli
and
.code sti :
they are counted, so that it takes two calls
to
.code popcli
to undo two calls to
.code pushcli ;
this way, if code acquires two different locks,
interrupts will not be reenabled until both
locks have been released.
.\"
.section "Memory ordering
.\"
.PP
XXX a section about ordering of reads and writes,
reordering and such.  not too much detail, just enough
to explain the comments in spinlock.c and to give
a sense that the general problem is wicked complicated
and that it's not worth avoiding locks,
which hide memory details.
.\"
.section "Real world
.\"
xxx locking is hard and not well understood.

xxx approaches to synchronization still an active topic
of research.

xxx best to use locks as the base for higher-level constructs
like synchronized queues, although xv6 does not do this.

xxx user space locks too; xv6 doesn't let processes share memory
so no need.

xxx semaphores.

xxx no need for atomicity really; lamport's algorithm.

xxx lock-free algorithms.

