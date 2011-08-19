.so book.mac
.chapter CH:DISK "Buffer cache"
.ig
	notes:

	i don't really like mixing the disk driver into this chapter,
	but it's probably too small to stand on its own, and it is
	tied very closely to the buffer cache
	
	have to decide on processor vs CPU, i/o vs I/O.
	
	be sure to say buffer, not block
..
.PP
One of an operating system's central roles is to
enable safe cooperation between processes sharing a computer.
First, it must isolate the processes from each other,
so that one errant process cannot harm the operation of others.
To do this, xv6 uses the x86 hardware's memory segmentation
(Chapter \*[CH:MEM]).
Second, an operating system must provide controlled mechanisms
by which the now-isolated processes can overcome the isolation
and cooperate.
To do this, xv6 provides the concept of files.
One process can write data to a file, and then another can read it;
processes can also be more tightly coupled using pipes.
The next four chapters examine the implementation of files,
working up from individual disk blocks to disk data structures
to directories to system calls.
This chapter examines the disk driver and the buffer cache,
which together form the bottom layer of the file implementation.
.PP
The disk driver copies data from and back to the disk,
The buffer cache manages these temporary copies of the disk blocks.
Caching disk blocks has an obvious performance benefit: 
disk access is significantly slower than memory access,
so keeping frequently-accessed disk blocks in memory
reduces the number of disk accesses and makes the system faster.
Even so, performance is not the most important reason
for the buffer cache.
When two different processes need to edit the same disk block
(for example, perhaps both are creating files in the same directory),
the disk block is shared data, just like the process table is shared among
all kernel threads in Chapter \*[CH:SCHED].
The buffer cache serializes access to the disk blocks,
just as locks serialize access to in-memory data structures.
Like the operating system as a whole, the buffer cache's fundamental
purpose is to enable safe cooperation between processes.
.\"
.\" -------------------------------------------
.\"
.section "Code: Data structures"
.PP
Disk hardware traditionally presents the data on the disk
as a numbered sequence of 512-byte blocks (also called sectors):
sector 0 is the first 512 bytes, sector 1 is the next, and so on.
The disk drive and buffer cache coordinate the use of disk sectors
with a data structure called a buffer,
.code struct
.code buf
.line buf.h:/^struct.buf/ .
Each buffer represents the contents of one sector on a particular
disk device.  The
.code dev
and
.code sector
fields give the device and sector
number and the
.code data
field is an in-memory copy of the disk sector.
The
.code data
is often out of sync with the disk:
it might have not yet been read in from disk,
or it might have been updated but not yet written out.
The
.code flags
track the relationship between memory and disk:
the
.code B_VALID
flag means that
.code data
has been read in, and
the B_DIRTY flag means that
.code data
needs to be written out.
The
.code B_BUSY
flag is a lock bit; it indicates that some process
is using the buffer and other processes must not.
When a buffer has the
.code B_BUSY
flag set, we say the buffer is locked.
.\"
.\" -------------------------------------------
.\"
.section "Code: Disk driver"
.PP
The IDE device provides access to disks connected to the
PC standard IDE controller.
IDE is now falling out of fashion in favor of SCSI and SATA,
but the interface is very simple and lets us concentrate on the
overall structure of a driver instead of the details of a
particular piece of hardware.
.PP
The kernel initializes the disk driver at boot time by calling
.code ideinit
.line ide.c:/^ideinit/
from
.code main
.line main.c:/ideinit/ .
.code Ideinit
initializes
.code idelock
.line ide.c:/idelock/
and then must prepare the hardware.
In Chapter \*[CH:TRAP], xv6 disabled all hardware interrupts.
.code Ideinit
calls
.code picenable
and
.code ioapicenable
to enable the
.code IDE_IRQ
interrupt
.lines ide.c:/picenable/,/ioapicenable/ .
The call to
.code picenable
enables the interrupt on a uniprocessor;
.code ioapicenable
enables the interrupt on a multiprocessor,
but only on the last CPU
.code ncpu-1 ): (
on a two-processor system, CPU 1 handles disk interrupts.
.PP
Next,
.code ideinit
probes the disk hardware.
It begins by calling
.code idewait
.line ide.c:/idewait.0/
to wait for the disk to
be able to accept commands.
The disk hardware presents status bits on port
.address 0x1f7 ,
as we saw in chapter \*[CH:BOOT].
.code Idewait
.line ide.c:/^idewait/
polls the status bits until the busy bit
.code IDE_BSY ) (
is clear and the ready bit
.code IDE_DRDY ) (
is set.
.PP
Now that the disk controller is ready,
.code ideinit
can check how many disks
are present.
It assumes that disk 0 is present,
because the boot loader and the kernel
were both loaded from disk 0,
but it must check for disk 1.
It writes to port
.address 0x1f6
to select disk 1
and then waits a while for the status bit to show
that the disk is ready
.lines ide.c:/Check.if.disk.1/,/^..}/ .
If not, 
.code ideinit
assumes the disk is absent.
.PP
After
.code ideinit ,
the disk is not used again until the buffer cache calls
.code iderw ,
which updates a locked buffer
as indicated by the flags.
If
.code B_DIRTY
is set,
.code iderw
writes the buffer
to the disk; if
.code B_VALID
is not set,
.code iderw
reads the buffer from the disk.
.PP
Disk accesses typically take milliseconds,
a long time for a processor.
In Chapter \*[CH:BOOT], the boot sector
issues disk read commands and reads the status
bits repeatedly until the data is ready.
This polling or busy waiting is fine in a boot sector, which has nothing better to do.
In an operating system, however, it is more efficient to
let another process run on the CPU and arrange to receive
an interrupt when the disk operation has completed.
.code Iderw
takes this latter approach,
keeping the list of pending disk requests in a queue
and using interrupts to find out when each request has finished.
Although
.code iderw
maintains a queue of requests,
the simple IDE disk controller can only handle
one operation at a time.
The disk driver maintains the invariant that it has sent
the buffer at the front of the queue to the disk hardware;
the others are simply waiting their turn.
.PP
.code Iderw
.line ide.c:/^iderw/
adds the buffer
.code b
to the end of the queue
.lines ide.c:/Append/,/pp.=.b/ .
If the buffer is at the front of the queue,
.code iderw
must send it to the disk hardware
by calling
.code idestart
.line ide.c:/Start.disk/,/idestart/ ;
otherwise the buffer will be started once
the buffers ahead of it are taken care of.
.PP
.code Idestart
.line ide.c:/^idestart/
issues either a read or a write for the buffer's device and sector,
according to the flags.
If the operation is a write, idestart must supply the data now
.line ide.c:/outsl/
and the interrupt will signal that the data has been written to disk.
If the operation is a read, the interrupt will signal that the
data is ready, and the handler will read it.
.PP
Having added the request to the queue and started it if necessary,
.code iderw
must wait for the result.  As discussed above,
polling does not make efficient use of the CPU.
Instead,
.code iderw
sleeps, waiting for the interrupt handler to 
record in the buffer's flags that the operation is done
.lines ide.c:/while.*VALID/,/sleep/ .
While this process is sleeping,
xv6 will schedule other processes to keep the CPU busy.
.PP
Eventually, the disk will finish its operation and trigger an interrupt.
As we saw in Chapter \*[CH:TRAP],
.code trap
will call
.code ideintr
to handle it
.line trap.c:/ideintr/ .
.code Ideintr
.line ide.c:/^ideintr/
consults the first buffer in the queue to find
out which operation was happening.
If the buffer was being read and the disk controller has data waiting,
.code ideintr
reads the data into the buffer with
.code insl
.lines ide.c:/Read.data/,/insl/ .
Now the buffer is ready:
.code ideintr
sets 
.code B_VALID ,
clears
.code B_DIRTY ,
and wakes up any process sleeping on the buffer
.lines ide.c:/Wake.process/,/wakeup/ .
Finally,
.code ideintr
must pass the next waiting buffer to the disk
.lines ide.c:/Start.disk/,/idestart/ .
.\"
.\" -------------------------------------------
.\"
.section "Code: Interrupts and locks"
.ig
[XXX Is there an example we can use that would push
this back into the interrupt chapter?]
..
.PP
On a multiprocessor, ordinary kernel code can run on one CPU
while an interrupt handler runs on another.
If the two code sections share data, they must use locks
to synchronize access to that data.
For example, 
.code iderw
and
.code ideintr
share the request queue and use
.code idelock
to synchronize.
.PP
Interrupts can cause concurrency even on a single processor:
if interrupts are enabled, kernel code can be stopped
at any moment to run an interrupt handler instead.
Suppose
.code iderw
held the
.code idelock
and then got interrupted to run
.code ideintr.
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
To avoid this situation, if a lock is used by an interrupt handler,
a processor must never hold that lock with interrupts enabled.
Xv6 is more conservative: it never holds any lock with interrupts enabled.
It uses
.code pushcli
.line spinlock.c:/^pushcli/
and
.code popcli
.line spinlock.c:/^popcli/
to manage a stack of ``disable interrupts'' operations
.code cli "" (
is the x86 instruction that disables interrupts,
as we saw in Chapter \*[CH:BOOT]).
.code Acquire
calls
.code pushcli
before trying to acquire a lock
.line spinlock.c:/pushcli/ ,
and 
.code release
calls
.code popcli
after releasing the lock
.line spinlock.c:/popcli/ .
It is important that
.code acquire
call
.code pushcli
before the 
.code xchg
that might acquire the lock
.line spinlock.c:/while.xchg/ .
If the two were reversed, there would be
a few instruction cycles when the lock
was held with interrupts enabled, and
an unfortunately timed interrupt would deadlock the system.
Similarly, it is important that
.code release
call
.code popcli
only after the
.code xchg
that releases the lock
.line spinlock.c:/xchg.*0/ .
These races are similar to the ones involving
.code holding
(see Chapter \*[CH:LOCK]).
.\"
.\" -------------------------------------------
.\"
.section "Code: Buffer cache"
.PP
As discussed at the beginning of this chapter,
the buffer cache synchronizes access to disk blocks,
making sure that only one kernel process at a time
can edit the file system data in any particular buffer.
The buffer cache does this by blocking processes in
.code bread
(pronounced b-read):
if two processes call
.code bread
with the same device and sector number of an
otherwise unused disk block, the call in one process will return
a buffer immediately;
the call in the other process will not return until
the first process has signaled that it is done with the buffer
by calling
.code brelse
(b-release).
.PP
The buffer cache is a doubly-linked list of buffers.
.code Binit ,
called by
.code main
.line main.c:/binit/ ,
initializes the list with the
.code NBUF
buffers in the static array
.code buf
.lines bio.c:/Create.linked.list/,/^..}/ .
All other access to the buffer cache refer to the linked list via
.code bcache.head ,
not the
.code buf
array.
.PP
.code Bread
.line bio.c:/^bread/
calls
.code bget
to get a locked buffer for the given sector
.line bio.c:/b.=.bget/ .
If the buffer needs to be read from disk,
.code bread
calls
.code iderw
to do that before returning the buffer.
.PP
.code Bget
.line bio.c:/^bget/
scans the buffer list for a buffer with the given device and sector numbers
.lines bio.c:/Try.for.cached/,/^..}/ .
If there is such a buffer,
.code bget
needs to lock it before returning.
If the buffer is not in use,
.code bget
can set the
.code B_BUSY
flag and return
.lines 'bio.c:/if...b->flags.&.B_BUSY/,/^....}/' .
If the buffer is already in use,
.code bget
sleeps on the buffer to wait for its release.
When
.code sleep
returns,
.code bget
cannot assume that the buffer is now available.
In fact, since 
.code sleep
released and reacquired
.code buf_table_lock ,
there is no guarantee that 
.code b 
is still the right buffer: maybe it has been reused for
a different disk sector.
.code Bget
has no choice but to start over
.line bio.c:/goto.loop/ ,
hoping that the outcome will be different this time.
.PP
If there is no buffer for the given sector,
.code bget
must make one, possibly reusing a buffer that held
a different sector.
It scans the buffer list a second time, looking for a block
that is not busy:
any such block can be used
.lines bio.c:/Allocate.fresh/,/B_BUSY/ .
.code Bget
edits the block metadata to record the new device and sector number
and mark the block busy before
returning the block
.lines bio.c:/flags.=.B_BUSY/,/return.b/ .
Note that the assignment to
.code flags
not only sets the
.code B_BUSY
bit but also clears the
.code B_VALID
and
.code B_DIRTY
bits, making sure that
.code bread
will refresh the buffer data from disk
rather than use the previous block's contents.
.PP
Because the buffer cache is used for synchronization,
it is important that
there is only ever one buffer for a particular disk sector.
The assignments
.lines bio.c:/dev.=.dev/,/.flags.=.B_BUSY/
are only safe because 
.code bget 's
first loop determined that no buffer already existed for that sector,
and
.code bget
has not given up
.code buf_table_lock
since then.
.PP
If all the buffers are busy, something has gone wrong:
.code bget
panics.
A more graceful response would be to sleep until a buffer became free,
though there would be a possibility of deadlock.
.PP
Once
.code bread
has returned a buffer to its caller, the caller has
exclusive use of the buffer and can read or write the data bytes.
If the caller does write to the data, it must call
.code bwrite
to flush the changed data out to disk before releasing the buffer.
.code Bwrite
.line bio.c:/^bwrite/
sets the 
.code B_DIRTY
flag and calls
.code iderw
to write
the buffer to disk.
.PP
When the caller is done with a buffer,
it must call
.code brelse
to release it. 
(The name
.code brelse ,
a shortening of
b-release,
is cryptic but worth learning:
it originated in Unix and is used in BSD, Linux, and Solaris too.)
.code Brelse
.line bio.c:/^brelse/
moves the buffer from its position in the linked list
to the front of the list
.lines 'bio.c:/b->next->prev.=.b->prev/,/bcache.head.next.=.b/' ,
clears the
.code B_BUSY
bit, and wakes any processes sleeping on the buffer.
Moving the buffer has the effect that the
buffers are ordered by how recently they were used (meaning released):
the first buffer in the list is the most recently used,
and the last is the least recently used.
The two loops in
.code bget
take advantage of this:
the scan for an existing buffer must process the entire list
in the worst case, but checking the most recently used buffers
first (starting at
.code bcache.head
and following
.code next
pointers) will reduce scan time when there is good locality of reference.
The scan to pick a buffer to reuse picks the least recently used
block by scanning backward
(following 
.code prev
pointers);
the implicit assumption is that the least recently used
buffer is the one least likely to be used again soon.
.\"
.\" -------------------------------------------
.\"
.section "Real world"
.PP
Actual device drivers are far more complex than the disk driver in this chapter,
but the basic ideas are the same:
typically devices are slower than CPU, so the hardware uses
interrupts to notify the operating system of status changes.
Modern disk controllers typically
accept multiple outstanding disk requests at a time and even reorder
them to make most efficient use of the disk arm.
When disks were simpler, operating system often reordered the
request queue themselves, though reordering has implications
for file system consistency, as we will see in Chapter \*[CH:FSCALL].
.PP
Other hardware is surprisingly similar to disks: network device buffers
hold packets, audio device buffers hold sound samples, graphics card
buffers hold video data and command sequences.
High-bandwidth devices—disks, graphics cards, and network cards—often use
direct memory access (DMA) instead of the explicit i/o
.opcode insl , (
.opcode outsl )
in this driver.
DMA allows the disk or other controllers direct access to physical memory.
The driver gives the device the physical address of the buffer's data field and
the device copies directly to or from main memory,
interrupting once the copy is complete.
Using DMA means that the CPU is not involved at all in the transfer,
which can be more efficient and is less taxing for the CPU's memory caches.
.PP
The buffer cache in a real-world operating system is significantly
more complex than xv6's, but it serves the same two purposes:
caching and synchronizing access to the disk.
Xv6's buffer cache, like V6's, uses a simple least recently used (LRU)
eviction policy; there are many more complex
policies that can be implemented, each good for some
workloads and not as good for others.
A more efficient LRU cache would eliminate the linked list,
instead using a hash table for lookups and a heap for LRU evictions.
.PP
In real-world operating systems, 
buffers typically match the hardware page size, so that
read-only copies can be mapped into a process's address space
using the paging hardware, without any copying.
.\"
.\" -------------------------------------------
.\"
.section "Exercises"
.exercise
Setting a bit in a buffer's
.code flags
is not an atomic operation: the processor makes a copy of 
.code flags
in a register, edits the register, and writes it back.
Thus it is important that two processes are not writing to
.code flags
at the same time.
The code in this chapter edits the
.code B_BUSY
bit only while holding
.code buflock
but edits the 
.code B_VALID
and
.code B_WRITE
flags without holding any locks.
Why is this safe?
