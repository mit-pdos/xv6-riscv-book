.chapter CH:FS "File system"
.ig
        is it process or kernel thread?

        the logging text (and some of the buffer text) assumes the reader
        knows a fair amount about how inodes and directories work,
        but they are introduced later.

	have to decide on processor vs CPU, i/o vs I/O.
	
	be sure to say buffer, not block 

	TODO: Explain the name sys_mknod.
	Perhaps mknod was for a while the only way to create anything?
	
	Mount
..  
.PP
The purpose of a file system is to organize and store data. File systems
typically support sharing of data among users and applications, as well as
.italic-index persistence
so that data is still available after a reboot.
.PP
The xv6 file system provides Unix-like files, directories, and pathnames
(see Chapter \*[CH:UNIX]), and stores its data on an IDE disk for
persistence (see Chapter \*[CH:TRAP]). The file system addresses
several challenges:
.IP \[bu]  
The file system needs on-disk data structures to represent the tree
of named directories and files, to record the identities of the
blocks that hold each file's content, and to record which areas
of the disk are free.
.IP \[bu] 
The file system must support
.italic-index "crash recovery" .
That is, if a crash (e.g., power failure) occurs, the file system must
still work correctly after a restart. The risk is that a crash might
interrupt a sequence of updates and leave inconsistent on-disk data
structures (e.g., a block that is both used in a file and marked free).
.IP \[bu]  
Different processes may operate on the file system at the same time,
so the file system code must coordinate to maintain invariants.
.IP \[bu]  
Accessing a disk is orders of magnitude slower than accessing
memory, so the file system must maintain an in-memory cache of
popular blocks.
.LP
The rest of this chapter explains how xv6 addresses these challenges.
.\"
.\" -------------------------------------------
.\"
.section "Overview"
.PP
The xv6 file system implementation is
organized in seven layers, shown in 
.figref fslayer .
The disk layer reads and writes blocks on an IDE hard drive.
The buffer cache layer caches disk blocks and synchronizes access to them,
making sure that only one kernel process at a time can modify the
data stored in any particular block.  The logging layer allows higher
layers to wrap updates to several blocks in a
.italic-index transaction ,
and ensures that the blocks are updated atomically in the
face of crashes (i.e., all of them are updated or none).
The inode layer provides individual files, each represented as an
.italic-index inode
with a unique i-number
and some blocks holding the file's data.  The directory
layer implements each directory as a special kind of
inode whose content is a sequence of directory entries, each of which contains a
file's name and i-number.
The pathname layer provides
hierarchical path names like
.code /usr/rtm/xv6/fs.c ,
and resolves them with recursive lookup.
The file descriptor layer abstracts many Unix resources (e.g., pipes, devices,
files, etc.) using the file system interface, simplifying the lives of
application programmers.
.figure fslayer
.PP
The file system must have a plan for where it stores inodes and
content blocks on the disk.
To do so, xv6 divides the disk into several
sections, as shown in 
.figref fslayout .
The file system does not use
block 0 (it holds the boot sector).  Block 1 is called the 
.italic-index "superblock" ; 
it contains metadata about the file system (the file system size in blocks, the
number of data blocks, the number of inodes, and the number of blocks in the
log).  Blocks starting at 2 hold the log.  After the log are the inodes, with multiple inodes per block.  After
those come bitmap blocks tracking which data blocks are in use.
The remaining blocks are data blocks; each is either marked
free in the bitmap block, or holds content for a file or directory.
The superblock is filled in by a separate program, called
.code-index mfks ,
which builds an initial file system.
.PP
The rest of this chapter discusses each layer, starting with the
buffer cache.
Look out for situations where well-chosen abstractions at lower layers
ease the design of higher ones.
.\"
.\" -------------------------------------------
.\"
.section "Buffer cache Layer and sleep locks"
.PP
The buffer cache has two jobs: (1) synchronize access to disk blocks to ensure
that only one copy of a block is in memory and that only one kernel thread at a time
uses that copy; (2) cache popular blocks so that they don't need to be re-read from
the slow disk. The code is in
.code bio.c .
.PP
The main interface exported by the buffer cache consists of
.code-index bread
and
.code-index bwrite ;
the former obtains a
.italic-index buf
containing a copy of a block which can be read or modified in memory, and the
latter writes a modified buffer to the appropriate block on the disk.
A kernel thread must release a buffer by calling
.code-index brelse
when it is done with it.
.PP
The buffer cache synchronizes access to each block using a
.italic-index "sleep lock" .
Like spin locks, sleep locks are a tool to guarantee mutually-exclusive
access to shared data (in this case, a buffer in the buffer cache).  Unlike
spin locks, sleep locks allow a kernel thread to hold a lock for a long time,
namely across
.code sleep
operations.  For example, a kernel thread may hold a sleep lock on the buffer
that contains a directory, find out that it must read another block in the file
system (e.g., a block that contains a file in that directory), and then go to
sleep waiting for the disk driver to read the block containing information about
the file, while still holding the sleep lock on the buffer that contains the
directory.  The reason why the kernel thread may have to hold on to the sleep
lock on the directory buffer is that there are situations when xv6 must update
two blocks atomically (e.g., unlinking a file from a directory).
.PP
If a kernel thread attempts to read a block that another kernel thread has
locked, the thread's
.code
bread call will wait (using
.code sleep )
until the other thread returns the buffer to the buffer cache using
.code brelse ,
which releases the sleep lock. Since a kernel thread may hold on for a
sleep lock for a long time, the waiting thread may wait for a long time and
therefore sleep locks don't spin waiting for a lock, but use
.code sleep
to release a processor and
.code wakeup
to alert that the lock is available.
.PP
Why does xv6 have both sleep locks and spin locks?  One option is to use sleep
locks instead of spin locks everywhere.  The reason not do so is that spin locks
turn off interrupts and sleep locks don't.  There are critical sections in which
interrupts must be turned off to avoid that an interrupt handler modifies shared
data concurrently. For example, reading
.code ticks
must be done with interrupts turned off, otherwise the clock interrupt handler
may increment it while a kernel thread is reading it. Xv6 must use spin locks
for such critical sections.  The other option is to use spin locks instead of
sleep locks, but that is undesirable too.  If xv6 were to use spin locks instead
of sleep locks everywhere, then when a thread is waiting for a long-term lock,
its processor might spin for a long time during which xv6 could have done useful
work (e.g., run another user-level process).
.PP
A potential fix is to have a different spin lock that calls
.code
sleep after spinning for a while, so that a spinning processor can do something
more useful.  But, that would mean that a kernel thread may run with interrupts
disabled while sleeping.  This is undesirable because it may lead to deadlock.
For example, consider xv6 running on a machine with one processor.  If a kernel
thread goes to sleep while waiting for a disk interrupt with interrupts
disabled, then the kernel thread will never learn when the disk is done and thus
sleep forever.
.PP
In short, the properties that we want for spin locks and sleep locks are
sufficiently different that in practice operating systems have two types of
locks: spin locks for short critical sections and sleep locks for long critical
sections.  Kernel developers can then chose which one is best for any given
situation: use spin locks when a lock is needed for a few instructions and use
sleep locks when a lock is needed across operations that might sleep.
For example, the inode layer also uses sleep locks to hold long-term locks
on inodes.
.PP
Let's return to the buffer cache.
The buffer cache has a fixed number of buffers to hold disk blocks,
which means that if the file system asks for a block that is not
already in the cache, the buffer cache must recycle a buffer currently
holding some other block. The buffer cache recycles the
least recently used buffer for the new block. The assumption is that
the least recently used buffer is the one least likely to be used
again soon.
.figure fslayout
.\"
.\" -------------------------------------------
.\"
.section "Code: Buffer cache"
.PP
The buffer cache is a doubly-linked list of buffers.
The function
.code-index binit ,
called by
.code-index main
.line main.c:/binit/ ,
initializes the list with the
.code-index NBUF
buffers in the static array
.code buf
.lines bio.c:/Create.linked.list/,/^..}/ .
All other access to the buffer cache refer to the linked list via
.code-index bcache.head ,
not the
.code buf
array.
.PP
A buffer has two state bits associated with it.
.code-index B_VALID
indicates that the buffer contains a copy of the block.
.code-index B_DIRTY
indicates that the buffer content has been modified and needs
to be written to the disk.
.PP
.code Bread
.line bio.c:/^bread/
calls
.code-index bget
to get a buffer for the given sector
.line bio.c:/b.=.bget/ .
If the buffer needs to be read from disk,
.code bread
calls
.code-index iderw
to do that before returning the buffer.
.PP
.code Bget
.line bio.c:/^bget/
scans the buffer list for a buffer with the given device and sector numbers
.lines bio.c:/Is.the.block.already/,/^..}/ .
If there is such a buffer,
.code-index bget
acquires the sleep lock for the buffer.
Acquiring the sleep lock may take a long time,
because another kernel thread may have the sleep lock.
Therefore,
the implementation of a sleep lock
.lines sleeplock.c:/^acquiresleep/ ,
releases the processor by calling
.code sleep .
When the holder of the sleep lock releases the sleep lock,
it calls
.code wakeup
to alert any waiters that the lock is available.
Once a waiter obtains the sleep lock,
.code bget
returns with the locked buffer.
.PP
If there is no cached buffer for the given sector,
.code-index bget
must make one, possibly reusing a buffer that held
a different sector.
It scans the buffer list a second time, looking for a buffer
that is not locked:
any such buffer can be used.
.code Bget
edits the buffer metadata to record the new device and sector number
and acquires its sleep lock before
returning the locked buffer.
Note that the assignment to
.code flags
clears
.code-index B_VALID ,
thus ensuring that
.code bread
will read the block data from disk
rather than incorrectly using the buffer's previous contents.
.PP
Because the buffer cache is used for synchronization,
it is important that
there is only ever one buffer for a particular disk sector.
Obtaining the sleep lock in the second loop
is safe because 
.code bget 's
first loop determined that no buffer already existed for that sector,
and
.code bget
has not given up
.code bcache.lock
since then.
.PP
If all the buffers are busy, something has gone wrong:
.code bget
panics.
A more graceful response might be to sleep until a buffer became free,
though there would then be a possibility of deadlock.
.PP
Once
.code-index bread
has returned a buffer to its caller, the caller has
exclusive use of the buffer and can read or write the data bytes.
If the caller does write to the data, it must call
.code-index bwrite
to write the changed data to disk before releasing the buffer.
.code Bwrite
.line bio.c:/^bwrite/
sets the 
.code-index B_DIRTY
flag and calls
.code-index iderw
to write
the buffer to disk.
.PP
When the caller is done with a buffer,
it must call
.code-index brelse
to release it. 
(The name
.code brelse ,
a shortening of
b-release,
is cryptic but worth learning:
it originated in Unix and is used in BSD, Linux, and Solaris too.)
.code Brelse
.line bio.c:/^brelse/
releases the sleep lock and
moves the buffer
to the front of the linked list
.lines 'bio.c:/b->next->prev.=.b->prev/,/bcache.head.next.=.b/' .
Moving the buffer causes the
list to be ordered by how recently the buffers were used (meaning released):
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
buffer by scanning backward
(following 
.code prev
pointers).
.\"
.\" -------------------------------------------
.\"
.section "Logging layer"
.PP
One of the most interesting problems in file system design is crash
recovery. The problem arises because many file system operations
involve multiple writes to the disk, and a crash after a subset of the
writes may leave the on-disk file system in an inconsistent state. For
example, suppose a crash occurs during file truncation (setting
the length of a file to zero and freeing its content blocks).
Depending on the order of the disk writes, the crash 
may either leave an inode with a reference
to a content block that is marked free,
or it may leave an allocated but unreferenced content block.
.PP
The latter is relatively benign, but an inode that refers to a freed
block is likely to cause serious problems after a reboot.  After reboot, the
kernel might allocate that block to another file, and now we have two different
files pointing unintentionally to the same block.  If xv6 supported
multiple users, this situation could be a security problem, since the
old file's owner would be able to read and write blocks in the
new file, owned by a different user.
.PP
Xv6 solves the problem of crashes during file system operations with a
simple form of logging. An xv6 system call does not directly write
the on-disk file system data structures. Instead, it places a
description of all the disk writes it wishes to make in a 
.italic-index log 
on the disk. Once the system call has logged all of its writes, it writes a
special 
.italic-index commit
record to the disk indicating that the log contains
a complete operation. At that point the system call copies the writes
to the on-disk file system data structures. After those writes have
completed, the system call erases the log on disk.
.PP
If the system should crash and reboot, the file system code recovers
from the crash as follows, before running any processes. If the log is
marked as containing a complete operation, then the recovery code
copies the writes to where they belong in the on-disk file system. If
the log is not marked as containing a complete operation, the recovery
code ignores the log.  The recovery code finishes by erasing
the log.
.PP
Why does xv6's log solve the problem of crashes during file system
operations? If the crash occurs before the operation commits, then the
log on disk will not be marked as complete, the recovery code will
ignore it, and the state of the disk will be as if the operation had
not even started. If the crash occurs after the operation commits,
then recovery will replay all of the operation's writes, perhaps
repeating them if the operation had started to write them to the
on-disk data structure. In either case, the log makes operations
atomic with respect to crashes: after recovery, either all of the
operation's writes appear on the disk, or none of them appear.
.\"
.\"
.\"
.section "Log design"
.PP
The log resides at a known fixed location, specified in the superblock.
It consists of a header block followed by a sequence
of updated block copies (``logged blocks'').
The header block contains an array of sector
numbers, one for each of the logged blocks. The header block
also contains the count of logged blocks. Xv6 writes the header
block when a transaction commits, but not before, and sets the
count to zero after copying the logged blocks to the file system.
Thus a crash midway through a transaction will result in a
count of zero in the log's header block; a crash after a commit
will result in a non-zero count.
.PP
Each system call's code indicates the start and end of the sequence of
writes that must be atomic.
For efficiency, and to allow a degree of concurrency in the
file system code, the logging system can accumulate the writes
of multiple system calls into one transaction.
Thus a single commit may involve the writes of multiple
complete system calls.
To avoid splitting a system call across transactions, the logging system
only commits when no file system system calls are underway.
.PP
The idea of committing several transaction together is known as 
.italic-index "group commit" .
Group commit allows several transactions to run concurrently and allows
the file system to
.italic-index batch 
several disk operations and issue a single disk operation to the disk driver.  This allows
the disk to schedule the writing of the blocks cleverly and write at the
rate of the disk's bandwidth.   Xv6's IDE driver doesn't support batching, but 
xv6's file system design allows for it.
.PP
Xv6 dedicates a fixed amount of space on the disk to hold the log.
The total number of blocks written by the system calls in a
transaction must fit in that space.
This has two consequences.
No single system call
can be allowed to write more distinct blocks than there is space
in the log. This is not a problem for most system calls, but two
of them can potentially write many blocks: 
.code-index write
and
.code-index unlink .
A large file write may write many data blocks and many bitmap blocks
as well as an inode block; unlinking a large file might write many
bitmap blocks and an inode.
Xv6's write system call breaks up large writes into multiple smaller
writes that fit in the log,
and 
.code unlink
doesn't cause problems because in practice the xv6 file system uses
only one bitmap block.
The other consequence of limited log space
is that the logging system cannot allow a system call to start
unless it is certain that the system call's writes will
fit in the space remaining in the log.
.\"
.\"
.\"
.section "Code: logging"
.PP
A typical use of the log in a system call looks like this:
.P1
  begin_op();
  ...
  bp = bread(...);
  bp->data[...] = ...;
  log_write(bp);
  ...
  end_op();
.P2
.PP
.code-index begin_op
.line log.c:/^begin.op/
waits until
the logging system is not currently committing, and until
there is enough free log space to hold
the writes from this call and all currently executing system calls.
.code log.outstanding
counts that number of calls;
the increment both reserves space and prevents a commit
from occuring during this system call.
The code conservatively assumes that each system call might write up to
.code MAXOPBLOCKS
distinct blocks.
.PP
.code-index log_write
.line log.c:/^log.write/
acts as a proxy for 
.code-index bwrite .
It records the block's sector number in memory,
reserving it a slot in the log on disk,
and marks the buffer
.code B_DIRTY
to prevent the block cache from evicting it.
The block must stay in the cache until committed:
until then, the cached copy is the only record
of the modification; it cannot be written to
its place on disk until after commit;
and other reads in the same transaction must
see the modifications.
.code log_write
notices when a block is written multiple times during a single
transaction, and allocates that block the same slot in the log.
This optimization is often called
.italic-index "absorption" .
It is common that, for example, the disk block containing inodes
of several files is written several times within a transaction.  By absorbing
several disk writes into one, the file system can save log space and
can achieve better performance because only one copy of the disk block must be
written to disk.
.PP
.code-index end_op
.line log.c:/^end.op/
first decrements the count of outstanding system calls.
If the count is now zero, it commits the current
transaction by calling
.code commit().
There are four stages in this process.
.code write_log()
.line log.c:/^write.log/
copies each block modified in the transaction from the buffer
cache to its slot in the log on disk.
.code write_head()
.line log.c:/^write.head/
writes the header block to disk: this is the
commit point, and a crash after the write will
result in recovery replaying the transaction's writes from the log.
.code-index install_trans
.line log.c:/^install_trans/
reads each block from the log and writes it to the proper
place in the file system.
Finally
.code end_op
writes the log header with a count of zero;
this has to happen before the next transaction starts writing
logged blocks, so that a crash doesn't result in recovery
using one transaction's header with the subsequent transaction's
logged blocks.
.PP
.code-index recover_from_log
.line log.c:/^recover_from_log/
is called from 
.code-index initlog
.line log.c:/^initlog/ ,
which is called during boot before the first user process runs.
.line proc.c:/initlog/
It reads the log header, and mimics the actions of
.code end_op
if the header indicates that the log contains a committed transaction.
.PP
An example use of the log occurs in 
.code-index filewrite
.line file.c:/^filewrite/ .
The transaction looks like this:
.P1
      begin_op();
      ilock(f->ip);
      r = writei(f->ip, ...);
      iunlock(f->ip);
      end_op();
.P2
This code is wrapped in a loop that breaks up large writes into individual
transactions of just a few sectors at a time, to avoid overflowing
the log.  The call to
.code-index writei
writes many blocks as part of this
transaction: the file's inode, one or more bitmap blocks, and some data
blocks.
.\"
.\"
.\"
.section "Code: Block allocator"
.PP
File and directory content is stored in disk blocks,
which must be allocated from a free pool.
xv6's block allocator
maintains a free bitmap on disk, with one bit per block. 
A zero bit indicates that the corresponding block is free;
a one bit indicates that it is in use.
The program
.code mkfs
sets the bits corresponding to the boot sector, superblock, log blocks, inode
blocks, and bitmap blocks.
.PP
The block allocator provides two functions:
.code-index balloc
allocates a new disk block, and
.code-index bfree
frees a block.
.code Balloc
The loop in
.code balloc
at
.line fs.c:/^..for.b.=.0/
considers every block, starting at block 0 up to 
.code sb.size ,
the number of blocks in the file system.
It looks for a block whose bitmap bit is zero,
indicating that it is free.
If
.code balloc
finds such a block, it updates the bitmap 
and returns the block.
For efficiency, the loop is split into two 
pieces.
The outer loop reads each block of bitmap bits.
The inner loop checks all 
.code BPB
bits in a single bitmap block.
The race that might occur if two processes try to allocate
a block at the same time is prevented by the fact that
the buffer cache only lets one process use any one bitmap block at a time.
.PP
.code Bfree
.line fs.c:/^bfree/
finds the right bitmap block and clears the right bit.
Again the exclusive use implied by
.code bread
and
.code brelse
avoids the need for explicit locking.
.PP
As with much of the code described in the remainder of this chapter, 
.code balloc
and
.code bfree
must be called inside a transaction.
.\"
.\" -------------------------------------------
.\"
.section "Inode layer"
.PP
The term 
.italic-index inode 
can have one of two related meanings.
It might refer to the on-disk data structure containing
a file's size and list of data block numbers.
Or ``inode'' might refer to an in-memory inode, which contains
a copy of the on-disk inode as well as extra information needed
within the kernel.
.PP
All of the on-disk inodes
are packed into a contiguous area
of disk called the inode blocks.
Every inode is the same size, so it is easy, given a
number n, to find the nth inode on the disk.
In fact, this number n, called the inode number or i-number,
is how inodes are identified in the implementation.
.PP
The on-disk inode is defined by a
.code-index "struct dinode"
.line fs.h:/^struct.dinode/ .
The 
.code type
field distinguishes between files, directories, and special
files (devices).
A type of zero indicates that an on-disk inode is free.
The
.code nlink
field counts the number of directory entries that
refer to this inode, in order to recognize when the
on-disk inode and its data blocks should be freed.
The
.code size
field records the number of bytes of content in the file.
The
.code addrs
array records the block numbers of the disk blocks holding
the file's content.
.PP
The kernel keeps the set of active inodes in memory;
.code-index "struct inode"
.line file.h:/^struct.inode/
is the in-memory copy of a 
.code struct
.code dinode
on disk.
The kernel stores an inode in memory only if there are
C pointers referring to that inode. The
.code ref
field counts the number of C pointers referring to the
in-memory inode, and the kernel discards the inode from
memory if the reference count drops to zero.
The
.code-index iget
and
.code-index iput
functions acquire and release pointers to an inode,
modifying the reference count.
Pointers to an inode can come from file descriptors,
current working directories, and transient kernel code
such as
.code exec .
.PP
A pointer returned by
.code iget()
is guaranteed to be valid until the corresponding call to
.code iput() ;
the inode won't be deleted, and the memory referred to
by the pointer won't be re-used for a different inode.
.code iget()
provides non-exclusive access to an inode, so that
there can be many pointers to the same inode.
Many parts of the file system code depend on this behavior of
.code iget() ,
both to hold long-term references to inodes (as open files
and current directories) and to prevent races while avoiding
deadlock in code that manipulates multiple inodes (such as
pathname lookup).
.PP
The
.code struct
.code inode
that 
.code iget
returns may not have any useful content.
In order to ensure it holds a copy of the on-disk
inode, code must call
.code-index ilock .
This locks the inode (so that no other process can
.code ilock
it) and reads the inode from the disk,
if it has not already been read.
.code iunlock
releases the lock on the inode.
Separating acquisition of inode pointers from locking
helps avoid deadlock in some situations, for example during
directory lookup.
Multiple processes can hold a C pointer to an inode
returned by 
.code iget ,
but only one process can lock the inode at a time.
.PP
The inode cache only caches inodes to which kernel code
or data structures hold C pointers.
Its main job is really synchronizing access by multiple processes,
not caching.
If an inode is used frequently, the buffer cache will probably
keep it in memory if it isn't kept by the inode cache.
.\"
.\" -------------------------------------------
.\"
.section "Code: Inodes"
.PP
To allocate a new inode (for example, when creating a file),
xv6 calls
.code-index ialloc
.line fs.c:/^ialloc/ .
.code Ialloc
is similar to
.code-index balloc :
it loops over the inode structures on the disk, one block at a time,
looking for one that is marked free.
When it finds one, it claims it by writing the new 
.code type
to the disk and then returns an entry from the inode cache
with the tail call to 
.code-index iget
.line "'fs.c:/return.iget!(dev..inum!)/'" .
The correct operation of
.code ialloc
depends on the fact that only one process at a time
can be holding a reference to 
.code bp :
.code ialloc
can be sure that some other process does not
simultaneously see that the inode is available
and try to claim it.
.PP
.code Iget
.line fs.c:/^iget/
looks through the inode cache for an active entry 
.code ip->ref "" (
.code >
.code 0 )
with the desired device and inode number.
If it finds one, it returns a new reference to that inode.
.lines 'fs.c:/^....if.ip->ref.>.0/,/^....}/' .
As
.code-index iget
scans, it records the position of the first empty slot
.lines fs.c:/^....if.empty.==.0/,/empty.=.ip/ ,
which it uses if it needs to allocate a cache entry.
.PP
Code must lock the inode using
.code-index ilock
before reading or writing its metadata or content.
.code Ilock
.line fs.c:/^ilock/
uses a now-familiar sleep lock for this purpose.
Once
.code-index ilock
has exclusive access to the inode, it can load the inode metadata
from the disk (more likely, the buffer cache)
if needed.
The function
.code-index iunlock
.line fs.c:/^iunlock/
releases the sleep lock,
which may cause any processes sleeping
to be woken up.
.PP
.code Iput
.line fs.c:/^iput/
releases a C pointer to an inode
by decrementing the reference count
.line 'fs.c:/^..ip->ref--/' .
If this is the last reference, the inode's
slot in the inode cache is now free and can be re-used
for a different inode.
.PP
If 
.code-index iput
sees that there are no C pointer references to an inode
and that the inode has no links to it (occurs in no
directory), then the inode and its data blocks must
be freed.
.code Iput
relocks the inode;
calls
.code-index itrunc
to truncate the file to zero bytes, freeing the data blocks;
sets the inode type to 0 (unallocated);
writes the change to disk;
and finally unlocks the inode
.lines 'fs.c:/ip..ref.==.1/,/^..}/' .
.PP
The locking protocol in 
.code-index iput
in the case in which it frees the inode
deserves a closer look.
First, when locking
.code ip ,
.code-index iput
assumes that it is unlocked.
This must be the case: the caller is required to unlock
.code ip
before calling
.code iput ,
and no other process can lock this inode,
because no other process can get a pointer to it.
That is because, in this code path, the inode has no references,
no links (i.e., no pathname refers to it),
and is not (yet) marked free.
The second part worth examining is that
.code iput
temporarily releases
.line fs.c:/^....release/
and reacquires
.line fs.c:/^....acquire/
the inode cache lock,
because
.code-index itrunc
and
.code-index iupdate
will sleep during disk I/O.
But we must consider what might happen while the lock is not held.
Specifically, once 
.code iupdate
finishes, the on-disk inode is marked as free,
and a concurrent call to
.code-index ialloc
might find it and reallocate it before 
.code iput
can finish.
.code Ialloc
will return a reference to the block by calling
.code-index iget ,
which will find 
.code ip
in the cache, see that
it is locked, and sleep.
Now the in-core inode is out of sync compared to the disk:
.code ialloc
reinitialized the disk version but relies on the 
caller to load it into memory during
.code ilock .
In order to make sure that this happens,
.code iput
must clear
.code-index I_VALID
before releasing the inode lock.
It does this by zeroing
.code flags
.line 'fs.c:/^....ip->flags.=.0/' .
.PP
.code iput()
can write to the disk.
This means that any system call that uses the file system
may write the disk, even calls like
.code read()
that appear to be read-only.
This, in turn, means that even read-only system calls
must be wrapped in transactions if they use the file system.
.\"
.\"
.\"
.section "Code: Inode content"
.figure inode
.PP
The on-disk inode structure,
.code-index "struct dinode" ,
contains a size and an array of block numbers (see 
.figref inode ).
The inode data is found in the blocks listed
in the
.code dinode 's
.code addrs
array.
The first
.code-index NDIRECT
blocks of data are listed in the first
.code NDIRECT
entries in the array; these blocks are called 
.italic-index "direct blocks" .
The next 
.code-index NINDIRECT
blocks of data are listed not in the inode
but in a data block called the
.italic-index "indirect block" .
The last entry in the
.code addrs
array gives the address of the indirect block.
Thus the first 6 kB 
.code NDIRECT \c (
×\c
.code-index BSIZE )
bytes of a file can be loaded from blocks listed in the inode,
while the next
.code 64 kB
.code NINDIRECT \c (
×\c
.code BSIZE )
bytes can only be loaded after consulting the indirect block.
This is a good on-disk representation but a 
complex one for clients.
The function
.code-index bmap
manages the representation so that higher-level routines such as
.code-index readi
and
.code-index writei ,
which we will see shortly.
.code Bmap
returns the disk block number of the
.code bn 'th
data block for the inode
.code ip .
If
.code ip
does not have such a block yet,
.code bmap
allocates one.
.PP
The function
.code-index bmap
.line fs.c:/^bmap/
begins by picking off the easy case: the first 
.code-index NDIRECT
blocks are listed in the inode itself
.lines 'fs.c:/^..if.bn.<.NDIRECT/,/^..}/' .
The next 
.code-index NINDIRECT
blocks are listed in the indirect block at
.code ip->addrs[NDIRECT] .
.code Bmap
reads the indirect block
.line 'fs.c:/bp.=.bread.ip->dev..addr/'
and then reads a block number from the right 
position within the block
.line 'fs.c:/a.=..uint!*.bp->data/' .
If the block number exceeds
.code NDIRECT+NINDIRECT ,
.code bmap 
panics; 
.code writei
contains the check that prevents this from happening
.line 'fs.c:/off...n...MAXFILE.BSIZE/' .
.PP
.code Bmap
allocates blocks as needed.
An
.code ip->addrs[]
or indirect
entry of zero indicates that no block is allocated.
As
.code bmap
encounters zeros, it replaces them with the numbers of fresh blocks,
allocated on demand.
.line "'fs.c:/^....if..addr.=.*==.0/,/./' 'fs.c:/^....if..addr.*NDIRECT.*==.0/,/./'" .
.PP
.code-index itrunc
frees a file's blocks, resetting the inode's size to zero.
.code Itrunc
.line fs.c:/^itrunc/
starts by freeing the direct blocks
.lines 'fs.c:/^..for.i.=.0.*NDIRECT/,/^..}/' ,
then the ones listed in the indirect block
.lines 'fs.c:/^....for.j.=.0.*NINDIRECT/,/^....}/' ,
and finally the indirect block itself
.lines 'fs.c:/^....bfree.*NDIRECT/,/./' .
.PP
.code Bmap
makes it easy for
.code-index readi
and
.code-index writei 
to get at an inode's data.
.code Readi
.line fs.c:/^readi/
starts by
making sure that the offset and count are not 
beyond the end of the file.
Reads that start beyond the end of the file return an error
.lines 'fs.c:/^..if.off.>.ip->size/,/./'
while reads that start at or cross the end of the file 
return fewer bytes than requested
.lines 'fs.c:/^..if.off.!+.n.>.ip->size/,/./' .
The main loop processes each block of the file,
copying data from the buffer into 
.code dst
.lines 'fs.c:/^..for.tot=0/,/^..}/' .
.\" NOTE: It is very hard to write line references
.\" for writei because so many of the lines are identical
.\" to those in readi.  Luckily, identical lines probably
.\" don't need to be commented upon.
.code-index writei
.line fs.c:/^writei/
is identical to
.code-index readi ,
with three exceptions:
writes that start at or cross the end of the file
grow the file, up to the maximum file size
.lines "'fs.c:/^..if.off.!+.n.>.MAXFILE/,/./'" ;
the loop copies data into the buffers instead of out
.line 'fs.c:/memmove.bp->data/' ;
and if the write has extended the file,
.code-index writei
must update its size
.line "'fs.c:/^..if.n.>.0.*off.>.ip->size/,/^..}/'" .
.PP
Both
.code-index readi
and
.code-index writei
begin by checking for
.code ip->type
.code ==
.code-index T_DEV .
This case handles special devices whose data does not
live in the file system; we will return to this case in the file descriptor layer.
.PP
The function
.code-index stati
.line fs.c:/^stati/
copies inode metadata into the 
.code stat
structure, which is exposed to user programs
via the
.code-index stat
system call.
.\"
.\"
.\"
.section "Code: directory layer"
.PP
A directory is implemented internally much like a file.
Its inode has type
.code-index T_DIR
and its data is a sequence of directory entries.
Each entry is a
.code-index "struct dirent"
.line fs.h:/^struct.dirent/ ,
which contains a name and an inode number.
The name is at most
.code-index DIRSIZ
(14) characters;
if shorter, it is terminated by a NUL (0) byte.
Directory entries with inode number zero are free.
.PP
The function
.code-index dirlookup
.line fs.c:/^dirlookup/
searches a directory for an entry with the given name.
If it finds one, it returns a pointer to the corresponding inode, unlocked,
and sets 
.code *poff
to the byte offset of the entry within the directory,
in case the caller wishes to edit it.
If
.code dirlookup
finds an entry with the right name,
it updates
.code *poff ,
releases the block, and returns an unlocked inode
obtained via
.code-index iget .
.code Dirlookup
is the reason that 
.code iget
returns unlocked inodes.
The caller has locked
.code dp ,
so if the lookup was for
.code-index "." ,
an alias for the current directory,
attempting to lock the inode before
returning would try to re-lock
.code dp
and deadlock.
(There are more complicated deadlock scenarios involving
multiple processes and
.code-index ".." ,
an alias for the parent directory;
.code "."
is not the only problem.)
The caller can unlock
.code dp
and then lock
.code ip ,
ensuring that it only holds one lock at a time.
.PP
The function
.code-index dirlink
.line fs.c:/^dirlink/
writes a new directory entry with the given name and inode number into the
directory
.code dp .
If the name already exists,
.code dirlink
returns an error
.lines 'fs.c:/Check.that.name.is.not.present/,/^..}/' .
The main loop reads directory entries looking for an unallocated entry.
When it finds one, it stops the loop early
.lines 'fs.c:/^....if.de.inum.==.0/,/./' ,
with 
.code off
set to the offset of the available entry.
Otherwise, the loop ends with
.code off
set to
.code dp->size .
Either way, 
.code dirlink
then adds a new entry to the directory
by writing at offset
.code off
.lines 'fs.c:/^..strncpy/,/panic/' .
.\"
.\"
.\"
.section "Code: Path names"
.PP
Path name lookup involves a succession of calls to
.code-index dirlookup ,
one for each path component.
.code Namei
.line fs.c:/^namei/
evaluates 
.code path
and returns the corresponding 
.code inode .
The function
.code-index nameiparent
is a variant: it stops before the last element, returning the 
inode of the parent directory and copying the final element into
.code name .
Both call the generalized function
.code-index namex
to do the real work.
.PP
.code Namex
.line fs.c:/^namex/
starts by deciding where the path evaluation begins.
If the path begins with a slash, evaluation begins at the root;
otherwise, the current directory
.line "'fs.c:/..if.!*path.==....!)/,/idup/'" .
Then it uses
.code-index skipelem
to consider each element of the path in turn
.line fs.c:/while.*skipelem/ .
Each iteration of the loop must look up 
.code name
in the current inode
.code ip .
The iteration begins by locking
.code ip
and checking that it is a directory.
If not, the lookup fails
.lines fs.c:/^....ilock.ip/,/^....}/ .
(Locking
.code ip
is necessary not because 
.code ip->type
can change underfoot—it can't—but because
until 
.code-index ilock
runs,
.code ip->type
is not guaranteed to have been loaded from disk.)
If the call is 
.code-index nameiparent
and this is the last path element, the loop stops early,
as per the definition of
.code nameiparent ;
the final path element has already been copied
into
.code name ,
so
.code-index namex
need only
return the unlocked
.code ip
.lines fs.c:/^....if.nameiparent/,/^....}/ .
Finally, the loop looks for the path element using
.code-index dirlookup
and prepares for the next iteration by setting
.code "ip = next"
.lines 'fs.c:/^....if..next.*dirlookup/,/^....ip.=.next/' .
When the loop runs out of path elements, it returns
.code ip .
.PP
The procedure
.code namex
may take a long time to complete: it could involve several disk operations to
read inodes and directory blocks for the directories traversed in the pathname
(if they are not in the buffer cache).  Xv6 is carefully designed so that if an
invocation of
.code namex
by one kernel thread is blocked on a disk I/O, another kernel thread looking up
a different pathname can proceed concurrently.
.code namex
locks each directory in the path separately so that lookups in different
directories can proceed in parallel.
.PP
This concurrency introduces some challenges. For example, while one kernel
thread is looking up a pathname another kernel thread may be changing the
directory tree by unlinking a directory.  A potential risk is that a lookup
may be searching a directory that has been deleted by another kernel thread and
its blocks have been re-used for another directory or file.
.PP
Xv6 avoids such races.  For example, when executing
.code dirlookup
in
.code namex ,
the lookup thread holds the lock on the directory and
.code dirlookup
returns an inode that was obtained using
.code iget .
.code iget
increases the reference count of the inode.  Only after receiving the
inode from
.code dirlookup
does
.code namex
release the lock on the directory.  Now another thread may unlink the inode from
the directory but xv6 will not delete the inode yet, because the reference count
of the inode is still larger than zero.
.PP
Another risk is deadlock.  For example,
.code next
points to the same inode as
.code ip
when looking up ".".
Locking
.code next
before releasing the lock on
.code ip
would result in a deadlock.
To avoid this deadlock,
.code namex
unlocks the directory before obtaining a lock on
.code next .
Here again we see why the separation between
.code iget
and
.code ilock
is important.
.\"
.\"
.\"
.section "File descriptor layer"
.PP
One of the cool aspect of the Unix interface is that most resources in Unix are
represented as a file, including devices such as the console, pipes, and of
course, real files.  The file descriptor layer is the layer that achieves this
uniformity.
.PP
Xv6 gives each process its own table of open files, or
file descriptors, as we saw in
Chapter \*[CH:UNIX].
Each open file is represented by a
.code-index "struct file"
.line file.h:/^struct.file/ ,
which is a wrapper around either an inode or a pipe,
plus an i/o offset.
Each call to 
.code-index open
creates a new open file (a new
.code struct
.code file ):
if multiple processes open the same file independently,
the different instances will have different i/o offsets.
On the other hand, a single open file
(the same
.code struct
.code file )
can appear
multiple times in one process's file table
and also in the file tables of multiple processes.
This would happen if one process used
.code open
to open the file and then created aliases using
.code-index dup
or shared it with a child using
.code-index fork .
A reference count tracks the number of references to
a particular open file.
A file can be open for reading or writing or both.
The
.code readable
and
.code writable
fields track this.
.PP
All the open files in the system are kept in a global file table,
the 
.code-index ftable .
The file table
has a function to allocate a file
.code-index filealloc ), (
create a duplicate reference
.code-index filedup ), (
release a reference
.code-index fileclose ), (
and read and write data
.code-index fileread "" (
and 
.code-index filewrite ).
.PP
The first three follow the now-familiar form.
.code Filealloc
.line file.c:/^filealloc/
scans the file table for an unreferenced file
.code f->ref "" (
.code ==
.code 0 )
and returns a new reference;
.code-index filedup
.line file.c:/^filedup/
increments the reference count;
and
.code-index fileclose
.line file.c:/^fileclose/
decrements it.
When a file's reference count reaches zero,
.code fileclose
releases the underlying pipe or inode,
according to the type.
.PP
The functions
.code-index filestat ,
.code-index fileread ,
and
.code-index filewrite
implement the 
.code-index stat ,
.code-index read ,
and
.code-index write
operations on files.
.code Filestat
.line file.c:/^filestat/
is only allowed on inodes and calls
.code-index stati .
.code Fileread
and
.code filewrite
check that the operation is allowed by
the open mode and then
pass the call through to either
the pipe or inode implementation.
If the file represents an inode,
.code fileread
and
.code filewrite
use the i/o offset as the offset for the operation
and then advance it
.lines "'file.c:/readi/,/./' 'file.c:/writei/,/./'" .
Pipes have no concept of offset.
Recall that the inode functions require the caller
to handle locking
.lines "'file.c:/stati/-1,/iunlock/' 'file.c:/readi/-1,/iunlock/' 'file.c:/writei/-1,/iunlock/'" .
The inode locking has the convenient side effect that the
read and write offsets are updated atomically, so that
multiple writing to the same file simultaneously
cannot overwrite each other's data, though their writes may end up interlaced.
.\"
.\"
.\"
.section "Code: System calls"
.PP
With the functions that the lower layers provide the implementation of most
system calls is trivial (see
.file sysfile.c  ). 
There are a few calls that
deserve a closer look.
.PP
The functions
.code-index sys_link
and
.code-index sys_unlink
edit directories, creating or removing references to inodes.
They are another good example of the power of using 
transactions. 
.code Sys_link
.line sysfile.c:/^sys_link/
begins by fetching its arguments, two strings
.code old
and
.code new
.line sysfile.c:/argstr.*old.*new/ .
Assuming 
.code old
exists and is not  a directory
.lines sysfile.c:/namei.old/,/^..}/ ,
.code sys_link
increments its 
.code ip->nlink
count.
Then
.code sys_link
calls
.code-index nameiparent
to find the parent directory and final path element of
.code new 
.line sysfile.c:/nameiparent.new/
and creates a new directory entry pointing at
.code old 's
inode
.line "'sysfile.c:/!|!| dirlink/'" .
The new parent directory must exist and
be on the same device as the existing inode:
inode numbers only have a unique meaning on a single disk.
If an error like this occurs, 
.code-index sys_link
must go back and decrement
.code ip->nlink .
.PP
Transactions simplify the implementation because it requires updating multiple
disk blocks, but we don't have to worry about the order in which we do
them. They either will all succeed or none.
For example, without transactions, updating
.code ip->nlink
before creating a link, would put the file system temporarily in an unsafe
state, and a crash in between could result in havoc.
With transactions we don't have to worry about this.
.PP
.code Sys_link
creates a new name for an existing inode.
The function
.code-index create
.line sysfile.c:/^create/
creates a new name for a new inode.
It is a generalization of the three file creation
system calls:
.code-index open
with the
.code-index O_CREATE
flag makes a new ordinary file,
.code-index mkdir
makes a new directory,
and
.code-index mkdev
makes a new device file.
Like
.code-index sys_link ,
.code-index create
starts by caling
.code-index nameiparent
to get the inode of the parent directory.
It then calls
.code-index dirlookup
to check whether the name already exists
.line 'sysfile.c:/dirlookup.*[^=]=.0/' .
If the name does exist, 
.code create 's
behavior depends on which system call it is being used for:
.code open
has different semantics from 
.code-index mkdir
and
.code-index mkdev .
If
.code create
is being used on behalf of
.code open
.code type "" (
.code ==
.code-index T_FILE )
and the name that exists is itself
a regular file,
then 
.code open
treats that as a success,
so
.code create
does too
.line "sysfile.c:/^......return.ip/" .
Otherwise, it is an error
.lines sysfile.c:/^......return.ip/+1,/return.0/ .
If the name does not already exist,
.code create
now allocates a new inode with
.code-index ialloc
.line sysfile.c:/ialloc/ .
If the new inode is a directory, 
.code create
initializes it with
.code-index .
and
.code-index ..
entries.
Finally, now that the data is initialized properly,
.code-index create
can link it into the parent directory
.line sysfile.c:/if.dirlink/ .
.code Create ,
like
.code-index sys_link ,
holds two inode locks simultaneously:
.code ip
and
.code dp .
There is no possibility of deadlock because
the inode
.code ip
is freshly allocated: no other process in the system
will hold 
.code ip 's
lock and then try to lock
.code dp .
.PP
Using
.code create ,
it is easy to implement
.code-index sys_open ,
.code-index sys_mkdir ,
and
.code-index sys_mknod .
.code Sys_open
.line sysfile.c:/^sys_open/
is the most complex, because creating a new file is only
a small part of what it can do.
If
.code-index open
is passed the
.code-index O_CREATE
flag, it calls
.code create
.line sysfile.c:/create.*T_FILE/ .
Otherwise, it calls
.code-index namei
.line sysfile.c:/if..ip.=.namei.path/ .
.code Create
returns a locked inode, but 
.code namei
does not, so
.code-index sys_open
must lock the inode itself.
This provides a convenient place to check that directories
are only opened for reading, not writing.
Assuming the inode was obtained one way or the other,
.code sys_open
allocates a file and a file descriptor
.line sysfile.c:/filealloc.*fdalloc/
and then fills in the file
.lines sysfile.c:/type.=.FD_INODE/,/writable/ .
Note that no other process can access the partially initialized file since it is only
in the current process's table.
.PP
Chapter \*[CH:SCHED] examined the implementation of pipes
before we even had a file system.
The function
.code-index sys_pipe
connects that implementation to the file system
by providing a way to create a pipe pair.
Its argument is a pointer to space for two integers,
where it will record the two new file descriptors.
Then it allocates the pipe and installs the file descriptors.
.\"
.\" -------------------------------------------
.\"
.section "Real world"
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
Modern buffer caches are typically integrated with the
virtual memory system to support memory-mapped files.
.PP
Xv6's logging system is inefficient.
A commit cannot occur concurrently with file system system calls.
The system logs entire blocks, even if
only a few bytes in a block are changed. It performs synchronous
log writes, a block at a time, each of which is likely to require an
entire disk rotation time. Real logging systems address all of these
problems.
.PP
Logging is not the only way to provide crash recovery. Early file systems
used a scavenger during reboot (for example, the UNIX
.code-index fsck
program) to examine every file and directory and the block and inode
free lists, looking for and resolving inconsistencies. Scavenging can take
hours for large file systems, and there are situations where it is not
possible to resolve inconsistencies in a way that causes the original
system calls to be atomic. Recovery
from a log is much faster and causes system calls to be atomic
in the face of crashes.
.PP
Xv6 uses the same basic on-disk layout of inodes and directories
as early UNIX;
this scheme has been remarkably persistent over the years.
BSD's UFS/FFS and Linux's ext2/ext3 use essentially the same data structures.
The most inefficient part of the file system layout is the directory,
which requires a linear scan over all the disk blocks during each lookup.
This is reasonable when directories are only a few disk blocks,
but is expensive for directories holding many files.
Microsoft Windows's NTFS, Mac OS X's HFS, and Solaris's ZFS, just to name a few, implement
a directory as an on-disk balanced tree of blocks.
This is complicated but guarantees logarithmic-time directory lookups.
.PP
Xv6 is naive about disk failures: if a disk
operation fails, xv6 panics.
Whether this is reasonable depends on the hardware:
if an operating systems sits atop special hardware that uses
redundancy to mask disk failures, perhaps the operating system
sees failures so infrequently that panicking is okay.
On the other hand, operating systems using plain disks
should expect failures and handle them more gracefully,
so that the loss of a block in one file doesn't affect the
use of the rest of the file system.
.PP
Xv6 requires that the file system
fit on one disk device and not change in size.
As large databases and multimedia files drive storage
requirements ever higher, operating systems are developing ways
to eliminate the ``one disk per file system'' bottleneck.
The basic approach is to combine many disks into a single
logical disk.  Hardware solutions such as RAID are still the 
most popular, but the current trend is moving toward implementing
as much of this logic in software as possible.
These software implementations typically 
allow rich functionality like growing or shrinking the logical
device by adding or removing disks on the fly.
Of course, a storage layer that can grow or shrink on the fly
requires a file system that can do the same: the fixed-size array
of inode blocks used by xv6 would not work well
in such environments.
Separating disk management from the file system may be
the cleanest design, but the complex interface between the two
has led some systems, like Sun's ZFS, to combine them.
.PP
Xv6's file system lacks many other features of modern file systems; for example,
it lacks support for snapshots and incremental backup.
.PP
Modern Unix systems allow many kinds of resources to be
accessed with the same system calls as on-disk storage:
named pipes, network connections,
remotely-accessed network file systems, and monitoring and control
interfaces such as
.code /proc .
Instead of xv6's
.code if
statements in
.code-index fileread
and
.code-index filewrite ,
these systems typically give each open file a table of function pointers,
one per operation,
and call the function pointer to invoke that inode's
implementation of the call.
Network file systems and user-level file systems 
provide functions that turn those calls into network RPCs
and wait for the response before returning.
.\"
.\" -------------------------------------------
.\"
.section "Exercises"
.PP
1. Why panic in
.code balloc ?
Can xv6 recover?
.PP
2. Why panic in
.code ialloc ?
Can xv6 recover?
.PP
3. Why doesn't
.code filealloc
panic when it runs out of files?
Why is this more common and therefore worth handling?
.PP
4. Suppose the file corresponding to 
.code ip
gets unlinked by another process
between 
.code sys_link 's
calls to 
.code iunlock(ip)
and
.code dirlink .
Will the link be created correctly?
Why or why not?
.PP
6.
.code create
makes four function calls (one to
.code ialloc
and three to
.code dirlink )
that it requires to succeed.
If any doesn't,
.code create
calls
.code panic .
Why is this acceptable?
Why can't any of those four calls fail?
.PP
7. 
.code sys_chdir
calls
.code iunlock(ip)
before
.code iput(cp->cwd) ,
which might try to lock
.code cp->cwd ,
yet postponing
.code iunlock(ip)
until after the
.code iput
would not cause deadlocks.
Why not?
.PP
8. Implement the
.code lseek
system call.  Supporting
.code lseek
will also require that you modify
.code filewrite
to fill holes in the file with zero if
.code lseek
sets
.code off
beyond
.code f->ip->size.
.PP
9. Add
.code O_TRUNC
and
.code O_APPEND
to
.code open ,
so that
.code >
and
.code >>
operators work in the shell.
