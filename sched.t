.so book.mac
.chapter CH:SCHED "Scheduling"
.PP
Any operating system is likely to run with more processes than the
computer has processors, and so some plan is needed to time share the
processors between the processes. An ideal plan is transparent to user
processes.  A common approach is to provide each process
with the illusion that it has its own virtual processor, and have the
operating system multiplex multiple virtual processors on a single
physical processor.
.PP
Xv6 adopts this approach.  If two processes want to run on
a single CPU, xv6 multiplexes them, switching many times per
second between executing one and the other.  This multiplexing
creates the illusion that each process has its own CPU, just as xv6
used the memory allocator and hardware segmentation to create the
illusion that each process has its own memory.
.PP
Implementing multiplexing has a few challenges. First, how to switch
from one process to another? Xv6 uses the standard mechanism of context
switching; although the idea is simple, the code to implement is
typically among the most opaque code in an operating system. Second,
how to do context switching transparently?  Xv6 uses the standard
technique of using the timer interrupt handler to drive context switches.
Third, many CPUs may be switching among processes concurrently, and a locking plan
is necessary to avoid races. Fourth, when a process has exited its
memory and other resources must be freed, but it cannot do all of
this itself because (for example) it can't free its own kernel
stack while still using it.
Xv6 tries to solve these problems as
simply as possible, but nevertheless the resulting code is
tricky.
.PP
xv6 must provide
ways for processes to coordinate among themselves. For example,
a parent process may need to wait for one of its children to
exit, or a process reading on a pipe may need to wait for
some other process to write the pipe.
Rather than make the waiting process waste CPU by repeatedly checking
whether the desired event has happened, xv6 allows a process to give
up the CPU and sleep
waiting for an event, and allows another process to wake the first
process up. Care is needed to avoid races that result in
the loss of event notifications.
As an example of these problems and their solution, this
chapter examines the implementation of pipes.
.\"
.section "Code: Scheduler"
.\"
Chapter \*[CH:MEM] breezed through the scheduler on the way to user space.
Let's take a closer look at it.
Each processor runs
.code mpmain
at boot time; the last thing 
.code mpmain
does is call
.code scheduler
.line "'main.c:/scheduler!(!)/'" .
.PP
.code Scheduler
.line proc.c:/^scheduler/ 
runs a simple loop:
find a process to run, run it until it stops, repeat.
At the beginning of the loop, 
.code scheduler
enables interrupts with an explicit
.code sti
.line "'proc.c:/sti!(!)/'" ;
this is important for the special case in which no process
is currently runnable and some processes are waiting for I/O interrupts:
if interrupts are disabled for the entire scheduler
loop, the system will never run another process.
Then the scheduler
loops over the process table
looking for a runnable process, one that has
.code p->state 
.code ==
.code RUNNABLE .
Once it finds a process, it sets the per-CPU current process
variable
.code proc ,
switches to the process's page table with
.code switchuvm ,
marks the process as
.code RUNNING ,
and then calls
.code swtch
to start running it
.lines proc.c:/Switch.to/,/swtch/ .
.\"
.section "Code: Context switching"
.\"
.PP
Every xv6 process has its own kernel stack and register set, as we saw in
Chapter \*[CH:MEM].
Each CPU has its own kernel stack to use when running
the scheduler.
.code Swtch
saves the scheduler's context-its stack pointer and registers—and
switches to the chosen process's kernel thread context.
When it is time for the process to give up the CPU,
the process's kernel thread will call
.code swtch
to save its own context and return to the scheduler context.
Each context is represented by a
.code struct
.code context* ,
a pointer to a structure stored on the kernel stack involved.
.code Swtch
takes two arguments:
.code struct
.code context
.code **old
and
.code struct
.code context
.code *new ;
it saves the current context, storing a pointer to it in
.code *old ,
and then restores the context described by
.code new .
.PP
Instead of following the scheduler into
.code swtch ,
let's instead follow our user process back in.
We saw in Chapter \*[CH:TRAP]
that one possibility at the end of each interrupt
is that 
.code trap
calls 
.code yield .
.code Yield
in turn calls
.code sched ,
which calls
.code swtch
to save the current context in
.code proc->context
and switch to the scheduler context previously saved in 
.code cpu->scheduler
.line proc.c:/swtch..proc/ .
.PP
.code Swtch
.line swtch.S:/swtch/
starts by loading its arguments off the stack
into the registers
.code %eax
and
.code %edx
.lines swtch.S:/movl/,/movl/ ;
.code swtch
must do this before it
changes the stack pointer
and can no longer access the arguments
via
.code %esp .
Then 
.code swtch
pushes the register state, creating a context structure
on the current stack.
Only the callee-save registers need to be saved;
the convention on the x86 is that these are
.code %ebp ,
.code %ebx ,
.code %esi ,
.code %ebp ,
and
.code %esp .
.code Swtch
pushes the first four explicitly
.lines swtch.S:/pushl..ebp/,/pushl..edi/ ;
it saves the last implicitly as the
.code struct
.code context*
written to
.code *old 
.line swtch.S:/movl..esp/ .
There is one more important register:
the program counter 
.code %eip
was saved by the
.code call
instruction that invoked
.code swtch
and is on the stack just above
.code %ebp .
Having saved the old context,
.code swtch
is ready to restore the new one.
It moves the pointer to the new context
into the stack pointer
.line swtch.S:/movl..edx/ .
The new stack has the same form as the old one that
.code swtch
just left—the new stack
.italic was
the old one in a previous call to
.code swtch —\c
so 
.code swtch
can invert the sequence to restore the new context.
It pops the values for
.code %edi ,
.code %esi ,
.code %ebx ,
and
.code %ebp
and then returns
.lines swtch.S:/popl/,/ret/ .
Because 
.code swtch
has changed the stack pointer, the values restored
and the instruction address returned to
are the ones from the new context.
.PP
In our example, 
.code sched
called
.code swtch
to switch to
.code cpu->scheduler ,
the per-CPU scheduler context.
That new context had been saved by 
.code scheduler 's
call to
.code swtch
.line proc.c:/swtch..cpu/ .
When the
.code swtch
we have been tracing returns,
it returns not to
.code sched
but to 
.code scheduler ,
and its stack pointer points at the current CPU's
scheduler stack, not
.code initproc 's
kernel stack.
.\"
.section "Code: Scheduling"
.\"
.PP
The last section looked at the low-level details of
.code swtch ;
now let's take 
.code swtch
as a given and examine the conventions involved
in switching from process to scheduler and back to process.
A process
that wants to give up the CPU must
acquire the process table lock
.code ptable.lock ,
release any other locks it is holding,
update its own state
.code proc->state ), (
and then call
.code sched .
.code Yield
.line proc.c:/^yield/
follows this convention, as do
.code sleep
and
.code exit ,
which we will examine later.
.code Sched
double-checks those conditions
.lines "'proc.c:/if..holding/,/running/'"
and then an implication of those conditions:
since a lock is held, the CPU should be
running with interrupts disabled.
Finally,
.code sched
calls
.code swtch
to save the current context in 
.code proc->context
and switch to the scheduler context in
.code cpu->scheduler .
.code Swtch
returns on the scheduler's stack
as though
.code scheduler 's
.code swtch
had returned
.line proc.c:/swtch..cpu/ .
The scheduler continues the 
.code for
loop, finds a process to run, 
switches to it, and the cycle repeats.
.PP
We just saw that xv6 holds
.code ptable.lock
across calls to
.code swtch :
the caller of
.code swtch
must already hold the lock, and control of the lock passes to the
switched-to code.  This convention is unusual with locks; the typical
convention is the thread that acquires a lock is also responsible of
releasing the lock, which makes it easier to reason about correctness.
For context switching is necessary to break the typical convention because
.code ptable.lock
protects invariants on the process's
.code state
and
.code context
fields that are not true while executing in
.code swtch .
One example of a problem that could arise if
.code ptable.lock
were not held during
.code swtch :
a different CPU might decide
to run the process after 
.code yield
had set its state to
.code RUNNABLE ,
but before 
.code swtch
caused it to stop using its own kernel stack.
The result would be two CPUs running on the same stack,
which cannot be right.
.PP
A kernel thread always gives up its
processor in
.code sched 
and always switches to the same location in the scheduler, which
(almost) always switches to a process in
.code sched . 
Thus, if one were to print out the line numbers where xv6 switches
threads, one would observe the following simple pattern:
.line proc.c:/swtch..cpu/ ,
.line proc.c:/swtch..proc/ ,
.line proc.c:/swtch..cpu/ ,
.line proc.c:/swtch..proc/ ,
and so on.  The procedures in which this stylized switching between
two threads happens are sometimes referred to as co-routines; in this
example,
.code sched
and
.code scheduler
are co-routines of each other.
.PP
There is one case when the scheduler's 
.code swtch
to a new process does not end up in
.code sched .
We saw this case in Chapter \*[CH:MEM]: when a
new process is first scheduled, it begins at
.code forkret
.line proc.c:/^forkret/ .
.code Forkret
exists only to honor this convention by releasing the 
.code ptable.lock ;
otherwise, the new process could start at
.code trapret .
.\"
.section "Sleep and wakeup"
.\"
.PP
Locks help CPUs and processes avoid interfering with each other,
and scheduling helps processes share a CPU,
but so far we have no abstractions that make it easy
for processes to communicate.
Sleep and wakeup fill that void, allowing one process to 
sleep waiting for an event and another process to wake it up
once the event has happened.
.PP
To illustrate what we mean, let's consider a
simple producer/consumer queue.
The queue allows one process to send a nonzero pointer
to another process.
Assuming there is only one sender and one receiver
and they execute on different CPUs,
this implementation is correct:
.P1
  100	struct q {
  101	  void *ptr;
  102	};
  103	
  104	void*
  105	send(struct q *q, void *p)
  106	{
  107	  while(q->ptr != 0)
  108	    ;
  109	  q->ptr = p;
  110	}
  111	
  112	void*
  113	recv(struct q *q)
  114	{
  115	  void *p;
  116	
  117	  while((p = q->ptr) == 0)
  118	    ;
  119	  q->ptr = 0;
  120	  return p;
  121	}
.P2
.code Send
loops until the queue is empty
.code ptr "" (
.code ==
.code 0)
and then puts the pointer
.code p
in the queue.
.code Recv
loops until the queue is non-empty
and takes the pointer out.
When run in different processes,
.code send
and
.code recv
both edit
.code q->ptr ,
but
.code send
only writes to the pointer when it is zero
and
.code recv
only writes to the pointer when it is nonzero,
so they do not step on each other.
.PP
The implementation above may be correct,
but it is very expensive.  If the sender sends
rarely, the receiver will spend most
of its time spinning in the 
.code while
loop hoping for a pointer.
The receiver's CPU could find more productive work
if there were a way for the receiver to be notified when the
.code send
had delivered a pointer.
.code Sleep
and
.code wakeup 
provide such a mechanism.
.code Sleep(chan)
sleeps on the pointer
.code chan ,
called the wait channel,
which may be any kind of pointer;
the sleep/wakeup code uses this pointer only as an identifying address
and never dereferences it.
.code Sleep
puts the calling process to sleep, releasing the CPU
for other work.
It does not return until the process is awake again.
.code Wakeup(chan)
wakes all the processes 
sleeping on
.code chan
(if any),
causing their
.code sleep
calls to return.
We can change the queue implementation to use
.code sleep
and
.code wakeup :
.P1
  201	void*
  202	send(struct q *q, void *p)
  203	{
  204	  while(q->ptr != 0)
  205	    ;
  206	  q->ptr = p;
  207	  wakeup(q);  /* wake recv */
  208	}
  209	
  210	void*
  211	recv(struct q *q)
  212	{
  213	  void *p;
  214	
  215	  while((p = q->ptr) == 0)
  216	    sleep(q);
  217	  q->ptr = 0;
  218	  return p;
  219	}
.P2
.PP
This code is more efficient but no longer correct, because it suffers
from what is known as the "lost wake up" problem.
Suppose that
.code recv
finds that
.code q->ptr
.code ==
.code 0 
on line 215
and decides to call 
.code sleep .
Before
.code recv
can sleep,
.code send
runs on another CPU:
it changes
.code q->ptr
to be nonzero and calls
.code wakeup ,
which finds no processes sleeping.
Now
.code recv
continues executing at line 216:
it calls
.code sleep
and goes to sleep.
This causes a problem:
.code recv
is asleep waiting for a pointer
that has already arrived.
The next
.code send
will sleep waiting for 
.code recv
to consume the pointer in the queue,
at which point the system will be deadlocked.
.PP
The root of this problem is that the
invariant that
.code recv
only sleeps when
.code q->ptr
.code ==
.code 0
is violated by 
.code send
running at just the wrong moment.
To protect this invariant, we introduce a lock,
which 
.code sleep
releases only after the calling process
is asleep; this avoids the missed wakeup in
the example above.
Once the calling process is awake again
.code sleep
reacquires the lock before returning.
The following code is correct and makes
efficient use of the CPU when 
.code recv
must wait:
.P1
  300	struct q {
  301	  struct spinlock lock;
  302	  void *ptr;
  303	};
  304	
  305	void*
  306	send(struct q *q, void *p)
  307	{
  308	  lock(&q->lock);
  309	  while(q->ptr != 0)
  310	    ;
  311	  q->ptr = p;
  312	  wakeup(q);
  313	  unlock(&q->lock);
  314	}
  315	
  316	void*
  317	recv(struct q *q)
  318	{
  319	  void *p;
  320	
  321	  lock(&q->lock);
  322	  while((p = q->ptr) == 0)
  323	    sleep(q, &q->lock);
  324	  q->ptr = 0;
  325	  unlock(&q->lock);
  326	  return p;
  327	}
.P2
.PP
A complete implementation would also sleep
in
.code send
when waiting for a receiver to consume
the value from a previous
.code send .
.\"
.section "Code: Sleep and wakeup"
.\"
.PP
Let's look at the implementation of
.code sleep
and
.code wakeup
in xv6.
The basic idea is to have
.code sleep
mark the current process as
.code SLEEPING
and then call
.code sched
to release the processor;
.code wakeup
looks for a process sleeping on the given pointer
and marks it as 
.code RUNNABLE .
.PP
.code Sleep
.line proc.c:/^sleep/
begins with a few sanity checks:
there must be a current process
.line proc.c:/proc.==.0/
and
.code sleep
must have been passed a lock
.lines "'proc.c:/lk == 0/,/sleep.without/'" .
Then 
.code sleep
acquires 
.code ptable.lock
.line proc.c:/sleeplock1/ .
Now the process going to sleep holds both
.code ptable.lock
and
.code lk .
Holding
.code lk
was necessary in the caller (in the example,
.code recv ):
it
ensured that no other process (in the example,
one running
.code send )
could start a call
.code wakeup(chan) .
Now that
.code sleep
holds
.code ptable.lock ,
it is safe to release
.code lk :
some other process may start a call to
.code wakeup(chan) ,
but
.code wakeup
will not run until it can acquire
.code ptable.lock ,
so it must wait until
.code sleep
is done,
keeping the
.code wakeup
from missing the
.code sleep .
.PP
There is a minor complication: if 
.code lk
is equal to
.code &ptable.lock ,
then
.code sleep
would deadlock trying to acquire it as
.code &ptable.lock
and then release it as
.code lk .
In this case,
.code sleep
considers the acquire and release
to cancel each other out
and skips them entirely
.line proc.c:/sleeplock0/ .
.PP
Now that
.code sleep
holds
.code ptable.lock
and no others,
it can put the process to sleep by recording
the sleep channel,
changing the process state,
and calling
.code sched
.line proc.c:/chan.=.chan/,/sched/ .
.PP
At some point later, a process will call
.code wakeup(chan) .
.code Wakeup
.line proc.c:/^wakeup/
acquires
.code ptable.lock
and calls
.code wakeup1 ,
which does the real work.
It is important that
.code wakeup
hold the
.code ptable.lock
both because it is manipulating process states
and because, as we just saw,
.code ptable.lock
makes sure that
.code sleep
and
.code wakeup
do not miss each other.
.code Wakeup1 "" (
is a separate function because
sometimes the scheduler needs to
execute a wakeup when it already
holds the 
.code ptable.lock ;
we will see an example of this later.)
.code Wakeup1
.line proc.c:/^wakeup1/
loops over the process table.
When it finds a process in state
.code SLEEPING
with a matching
.code chan ,
it changes that process's state to
.code RUNNABLE .
The next time the scheduler runs, it will
see that the process is ready to be run.
.PP
There is another complication: spurious wakeups.
.\"
.section "Code: Pipes"
.\"
The simple queue we used earlier in this Chapter
was a toy, but xv6 contains a real queue
that uses
.code sleep
and
.code wakeup
to synchronize readers and writers.
That queue is the implementation of pipes.
We saw the interface for pipes in Chapter \*[CH:UNIX]:
bytes written to one end of a pipe are copied
in an in-kernel buffer and then can be read out
of the other end of the pipe.
Future chapters will examine the file system support
surrounding pipes, but let's look now at the
implementations of 
.code pipewrite
and
.code piperead .
.PP
Each pipe
is represented by a 
.code struct
.code pipe ,
which contains
a 
.code lock
and a 
.code data
buffer.
The fields
.code nread
and
.code nwrite
count the number of bytes read from
and written to the buffer.
The buffer wraps around:
the next byte written after
.code buf[PIPESIZE-1]
is 
.code buf[0] ,
but the counts do not wrap.
This convention lets the implementation
distinguish a full buffer 
.code nwrite "" (
.code ==
.code nread+PIPESIZE )
from an empty buffer
.code nwrite
.code ==
.code nread ),
but it means that indexing into the buffer
must use
.code buf[nread
.code %
.code PIPESIZE]
instead of just
.code buf[nread] 
(and similarly for
.code nwrite ).
Let's suppose that calls to
.code piperead
and
.code pipewrite
happen simultaneously on two different CPUs.
.PP
.code Pipewrite
.line pipe.c:/^pipewrite/
begins by acquiring the pipe's lock, which
protects the counts, the data, and their
associated invariants.
.code Piperead
.line pipe.c:/^piperead/
then tries to acquire the lock too, but cannot.
It spins in
.code acquire
.line spinlock.c:/^acquire/
waiting for the lock.
While
.code piperead
waits,
.code pipewrite
loops over the bytes being written—\c
.code addr[0] ,
.code addr[1] ,
\&...,
.code addr[n-1] —\c
adding each to the pipe in turn
.line "'pipe.c:/nwrite!+!+/'" .
During this loop, it could happen that
the buffer fills
.line pipe.c:/pipewrite-full/ .
In this case, 
.code pipewrite
calls
.code wakeup
to alert any sleeping readers to the fact
that there is data waiting in the buffer
and then sleeps on
.code &p->nwrite
to wait for a reader to take some bytes
out of the buffer.
.code Sleep
releases 
.code p->lock
as part of putting
.code pipewrite 's
process to sleep.
.PP
Now that
.code p->lock
is available,
.code piperead
manages to acquire it and start running in earnest:
it finds that
.code p->nread
.code !=
.code p->nwrite
.line pipe.c:/pipe-empty/
.code pipewrite "" (
went to sleep because
.code p->nwrite
.code ==
.code p->nread+PIPESIZE
.line pipe.c:/pipewrite-full/ )
so it falls through to the 
.code for
loop, copies data out of the pipe
.line pipe.c:/piperead-copy/,/^..}/ ,
and increments 
.code nread
by the number of bytes copied.
That many bytes are now available for writing, so
.code piperead
calls
.code wakeup
.line pipe.c:/piperead-wakeup/
to wake any sleeping writers
before it returns to its caller.
.PP
.code Wakeup
finds a process sleeping on
.code &p->nwrite ,
the process that was running
.code pipewrite
but stopped when the buffer filled.
It marks that process as
.code RUNNABLE .
.PP
Let's suppose that the scheduler on the other CPU
has decided to run some other process,
so
.code pipewrite
does not start running again immediately.
Instead,
.code piperead
returns to its caller, who then calls
.code piperead
again. 
Let's also suppose that the first
.code piperead
consumed all the data from the pipe buffer,
so now
.code p->nread
.code ==
.code p->nwrite .
.code Piperead
sleeps on
.code &p->nread
to await more data
.line pipe.c:/piperead-sleep/ .
Once the process calling
.code piperead
is asleep, the CPU can run
.code pipewrite 's
process, causing 
.code sleep
to return
.line pipe.c:/pipewrite-sleep/ .
.code Pipewrite
finishes its loop, copying the remainder of
its data into the buffer
.line "'pipe.c:/nwrite!+!+/'" .
Before returning,
.code pipewrite
calls
.code wakeup
in case there are any readers
waiting for the new data
.line pipe.c:/pipewrite-wakeup1/ .
There is one, the
.code piperead
we just left.
It continues running
.line pipe.c/piperead-sleep/
and copies the new data out of the pipe.
.\"
.section "Code: Wait and exit"
.\"
.code Sleep
and
.code wakeup
do not have to be used for implementing queues.
They work for any condition that can be checked
in code and needs to be waited for.
As we saw in Chapter \*[CH:UNIX],
a parent process can call
.code wait
to wait for a child to exit.
In xv6, when a child exits, it does not die immediately.
Instead, it switches to the
.code ZOMBIE
process state until the parent calls
.code wait
to learn of the exit.
The parent is then responsible for freeing the
memory associated with the process 
and preparing the
.code struct
.code proc
for reuse.
Each process structure
keeps a pointer to its parent in
.code p->parent .
If the parent exits before the child, the initial process
.code init
adopts the child
and waits for it.
This step is necessary to make sure that some
process cleans up after the child when it exits.
All the process structures are protected by
.code ptable.lock .
.PP
.code Wait
begins by
acquiring 
.code ptable.lock .
Then it scans the process table
looking for children.
If 
.code wait
finds that the current process has children
but that none of them have exited,
it calls
.code sleep
to wait for one of the children to exit
.line proc.c:/wait-sleep/
and loops.
Here,
the lock being released in 
.code sleep
is
.code ptable.lock ,
the special case we saw above.
.PP
.code Exit
acquires
.code ptable.lock
and then wakes the current process's parent
.line "'proc.c:/wakeup1!(proc->parent!)/'" .
This may look premature, since 
.code exit
has not marked the current process as a
.code ZOMBIE
yet, but it is safe:
although the parent is now marked as
.code RUNNABLE ,
the loop in
.code wait
cannot run until
.code exit
releases 
.code ptable.lock
by calling
.code sched
to enter the scheduler,
so
.code wait
can't look at
the exiting process until after
the state has been set to
.code ZOMBIE
.line proc.c:/state.=.ZOMBIE/ .
Before exit reschedules,
it reparents all of
the exiting process's children,
passing them to the
.code initproc
.lines proc.c:/Pass.abandoned/,/wakeup1/+2 .
Finally,
.code exit
calls
.code sched
to relinquish the CPU.
.PP
Now the scheduler can choose to run the
exiting process's parent, which is asleep in
.code wait
.line proc.c:/wait-sleep/ .
The call to
.code sleep
returns holding
.code ptable.lock ;
.code wait
rescans the process table
and finds the exited child with
.code state
.code ==
.code ZOMBIE .
.line proc.c:/state.==.ZOMBIE/ .
It records the child's
.code pid
and then cleans up the 
.code struct 
.code proc ,
freeing the memory associated
with the process
.line proc.c:/pid.=.p..pid/,/killed.=.0/ .
.PP
The child process could have done most
of the cleanup during
.code exit ,
but it is important that the parent 
process be the one to free
.code p->kstack :
when the child runs
.code exit ,
its stack sits in the memory allocated as
.code p->kstack .
The stack can only be freed once the child process
has called
.code swtch
(via
.code sched )
and moved off it.
This reason is the main one that the scheduler procedure runs on its
own stack, and that xv6 organizes 
.code sched
and
.code scheduler
as co-routines.
Xv6 couldn't invoke the procedure
.code scheduler
directly from the child, because that procedure would then be running on a stack
that might be removed by the parent process calling
.code wait .
.\"
.section "Scheduling concerns"
.\"
.PP
XXX spurious wakeups

XXX checking p->killed

XXX thundering herd

.\"
.section "Real world"
.\"
.PP
.code Sleep
and
.code wakeup
are a simple and effective synchronization method,
but there are many others.
The first challenge in all of them is to
avoid the ``missed wakeups'' problem we saw at the
beginning of the chapter.
The original Unix kernel's
.code sleep
simply disabled interrupts,
which sufficed because Unix ran on a single-CPU system.
Because xv6 runs on multiprocessors,
it adds an explicit lock to
.code sleep .
FreeBSD's
.code msleep
takes the same approach.
Plan 9's 
.code sleep
uses a callback function that runs with the scheduling
lock held just before going to sleep;
the function serves as a last minute check
of the sleep condition, to avoid missed wakeups.
The Linux kernel's
.code sleep
uses an explicit process queue instead of
a wait channel; the queue has its own internal lock.
(XXX Looking at the code that seems not
to be enough; what's going on?)
.PP
Scanning the entire process list in
.code wakeup
for processes with a matching
.code chan
is inefficient.  A better solution is to
replace the
.code chan
in both
.code sleep
and
.code wakeup
with a data structure that holds
a list of processes sleeping on that structure.
Plan 9's
.code sleep
and
.code wakeup
call that structure a rendezvous point or
.code Rendez .
Many thread libraries refer to the same
structure as a condition variable;
in that context, the operations
.code sleep
and
.code wakeup
are called
.code wait
and
.code signal .
All of these mechanisms share the same
flavor: the sleep condition is protected by
some kind of lock dropped atomically during sleep.
.PP
Semaphores are another common coordination
mechanism.
A semaphore is an integer value with two operations,
increment and decrement (or up and down).
It is aways possible to increment a semaphore,
but the semaphore value is not allowed to drop below zero:
a decrement of a zero semaphore sleeps until
another process increments the semaphore,
and then those two operations cancel out.
The integer value typically corresponds to a real
count, such as the number of bytes available in a pipe buffer
or the number of zombie children that a process has.
Using an explicit count as part of the abstraction
avoids the ``missed wakeup'' problem:
there is an explicit count of the number
of wakeups that have occurred.
The count also avoids the spurious wakeup
and thundering herd problems inherent in 
condition variables.

Exercises:

Sleep has to check lk != &ptable.lock
to avoid a deadlock
.lines proc.c:/sleeplock0/,/^..}/ .
It could eliminate the special case by 
replacing
.P1
if(lk != &ptable.lock){
  acquire(&ptable.lock);
  release(lk);
}
.P2
with
.P1
release(lk);
acquire(&ptable.lock);
 .P2
Doing this would break
.code sleep .
How?

Most process cleanup could be done by either
.code exit
or
.code wait ,
but we saw above that
.code exit
must not free
.code p->stack .
It turns out that
.code exit
must be the one to close the open files.
Why?
The answer involves pipes.

Implement semaphores in xv6.
You can use mutexes but do not use sleep and wakeup.
Replace the uses of sleep and wakeup in xv6
with semaphores.  Judge the result.


Additional reading:

cox and mullender, semaphores.

pike et al, sleep and wakeup

