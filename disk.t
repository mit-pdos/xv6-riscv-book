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
To do this, xv6 uses the x86 hardware's hardware page tables
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
This chapter examines  the buffer cache,
which forms the bottom layer of the file implementation.
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
.\"
.\" -------------------------------------------
.\"
.section "Exercises"
