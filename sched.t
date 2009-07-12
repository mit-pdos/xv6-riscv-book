.so book.mac
.chapter CH:SCHED "Scheduling
.PP
In some sense, locks are needed because the 
the computer has too many cpus: a single-cpu
interrupt-free system could not need locking,
although it would suffer other problems.
At the same time, even our multiprocessors have too few cpus:
Modern operating systems implement the illusion that
the machine can simultaneously run many processes,
more processes than there are cpus.
If two different processes are competing for a single cpu,
xv6 multiplexes them, switching many times per second
between executing one and the other.
Xv6 uses multiplexing to create the illusion that each process 
has its own cpu, just as xv6 used the memory allocator
and hardware segmentation to create the illusion that each
process has its own memory.
.PP
Once there are multiple processes executing, xv6 must
provide some way for them to coordinate.
Since each cpu runs at most one cpu at a time,
locks suffice to implement mutual exclusion, but
processes need more than mutual exclusion.
Often it is necessary for one process to wait for
another to perform some action.
Rather than make the waiting process waste cpu by
repeatedly checking whether that action has happened,
xv6 allows a process to sleep waiting for an event
and allows another process to wake the first process.
.PP
As an example of these problems
and their solution, this chapter examines the implementation of pipes.
.\"
.section "Code: Scheduler
.\"
Chapter \*[CH:MEM] breezed through the scheduler on the way to user space.
Let's take a closer look at it.
Each processor runs
.code mpmain
at boot time; the last thing 
.code mpmain
does is call
.code scheduler
.line main.c:/scheduler!(!)/ .
.PP
.code Scheduler
.line proc.c:/^scheduler/ runs a simple loop:
find a process to run, run it until it stops, repeat.
At the beginning of the loop, 
.code scheduler
enables interrupts with an explicit
.code sti
.line proc.c:/sti!(!)/ ,
so that if a hardware interrupt is waiting
to be handled, the scheduler's cpu
will handle it before continuing.
Then the scheduler
loops over the process table
looking for a runnable process, one that has
.code p->state 
.code ==
.code RUNNABLE .
Once it finds a process, it sets the per-cpu current process
variable
.code cp ,
updates the user segments with
.code usegment ,
marks the process as
.code RUNNING ,
and then calls
.code swtch
to start running it
.lines proc.c:/Switch.to/,/swtch/ .
.\"
.section "Code: Context switching
.\"
.PP
Every xv6 process has its own kernel stack and register set, as we saw in
Chapter \*[CH:MEM].
Each cpu has its own kernel stack to use when running
the scheduler.
.code Swtch
saves the scheduler's context—it's stack and registers—and
switches to the chosen process's context.
When it is time for the process to give up the cpu,
it will call
.code swtch
to save its own context and return to the scheduler context.
Each context is represented by a
.code struct
.code context* ,
a pointer to a structure stored on the stack involved.
.code Swtch
takes two arguments
.code struct
.code context
.code **old
and
.code struct
.code context
.code *new ;
it saves the current context, storing a pointer to it in
.code *old
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
.code cp->context
and switch to the scheduler context previously saved in 
.code c->context
.line proc.c:/swtch!(.cp-/ .
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
.I was
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
and the address returned to
are the ones from the new context.
.PP
In our example, 
.code sched 's
called
.code swtch
to switch to
.code c->context ,
the per-cpu scheduler context.
That new context had been saved by 
.code scheduler 's
call to
.code swtch
.line proc.c:/swtch!(.c-/ .
When the
.code swtch
we have been tracing returns,
it returns not to
.code sched
but to 
.code scheduler ,
and its stack pointer points at the
scheduler stack, not
.code initproc 's
kernel stack.
.\"
.section "Code: Scheduling
.\"
.PP
The last section looked at the low-level details of
.code swtch ;
now let's take 
.code swtch
as a given and examine the conventions involved
in switching from process to scheduler and back to process.
The convention in xv6 is that a process
that wants to give up the cpu must
acquire the process table lock
.code &ptable.lock ,
release any other locks it is holding,
update its own state
.code cp->state ), (
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
double checks those conditions
.lines proc.c:/if.!holding/,/running/
and then an implication:
since a lock is held, the cpu should be
running with interrupts disabled.
Finally,
.code sched
calls
.code swtch
to save the current context in 
.code cp->context
and switch to the scheduler context in
.code c->context .
.code Swtch
returns on the scheduler's stack
as though
.code scheduler 's
.code swtch
had returned
.line proc.c:/swtch..c-/ .
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
must already hold the lock,
and control of the lock passes to the
switched-to code.
This is necessary because
.code &ptable.lock
protects the 
.code state
and
.code context
fields in each process structure.
Without the lock, it could happen that a process
decided to yield, set its state to
.code RUNNABLE ,
and then before it could
.code swtch
to give up the cpu, a different cpu would
try to run it using 
.code swtch .
This other cpu's call to
.code swtch
would use a stale context, the one from the
last time the process was started, causing time
to appear to move backward.
It would also cause two cpus to be executing
on the same stack.  Both are incorrect.
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
.section "Code: Sleep and wakeup
.\"
.PP
XXX



Now we can see why
.code sched
requires 
.code &ptable.lock
to be held: 
It continues the
.code for
loop, looking for 


.lines proc.c:/if.readeflags/,/interruptible/
and
since the process may stop running
for an 
First, note that
.code yield
acquires
the process table lock
.code &ptable.lock
and sets the current process's state to
.code RUNNABLE
before calling
.code sched 
.lines proc.c:/yieldlock/,/sched/ .

changing their state,
and calling 


.PP
Let's suppose that this call to
.code swtch
is running the initial process as created by
.code allocproc .
The context will have a 
.code eip
of
.code forkret :
returning from
.code swtch
will start running
.code forkret .
.code Forkret
.line proc.c:/^forkret/
releases 
.code &ptable.lock ,
as does any other function that 



as we saw in Chapter \*[CH:MEM], the 




.\"
.section "Code: Sleep and wakeup
.\"

.\"
.section "Code: Pipes
.\"

.\"
.section "Real world
.\"
sleep and wakeup are a simple form of condition variable.


