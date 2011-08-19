.so book.mac
.ig
	notes:

	i'm not very happy with this chapter.
	it feels phoned in.
	
	it is also too big, but it is hard to break up.
	namei should probably move out.
	
	TODO: add discussion of write ordering for
	low-level file system data structures:
	never write a pointer before the block is on disk,
	never free a block until the pointer has been zeroed on disk.

..
.chapter CH:FSDATA "File system data structures"
.PP
This chapter describes xv6's on-disk file-system layout:
the on-disk data structures that 
implement xv6's files, directories, and free lists.
Layout is not a very interesting topic in itself. 
Much more interesting is the question of how to update
on-disk file system structures in a way that is safe
if interrupted by a crash; that is the topic of the next
chapter, which describes xv6's file system log.
.PP
The disk driver and buffer cache (Chapter \*[CH:DISK]) provide safe, synchronized
access to disk blocks.
Individual blocks are still a very low-level interface, too raw for most
programs.
Xv6, following Unix, provides a hierarchical file system that allows
programs to treat storage as a tree of named files, each containing
a variable length sequence of bytes.
The file system is implemented in four layers:
.P1
-------------
   pathnames
-------------
  directories
-------------
    inodes
-------------
    blocks
-------------
.P2
The lowest layer is the block allocator, which
keeps track of which blocks are in use.
The second layer implements unnamed files, each consisting
of an ``inode'' and a sequence of blocks holding the file's data.
The third layer implements directories of named files.
A directory is a special kind
of inode whose content is a sequence of directory entries, 
each of which contains a name and a reference to the named file's inode.
The highest layer provides hierarchical path names like
.code /usr/rtm/xv6/fs.c .
.\"
.\" -------------------------------------------
.\"
.section "File system layout"
.PP
Xv6 lays out its file system as follows.
The file system does not use block 0 (it holds the boot sector).
Block 1 is called the superblock; it contains metadata about the
file system.
Blocks starting at 2 hold inodes,
with multiple inodes per block.
After those come bitmap blocks tracking which data
blocks are in use. Most of the remaining blocks are data blocks,
which hold file and directory contents.
The blocks at the very end of the disk hold the log.
.PP
The header
.code fs.h
.line fs.h:1
contains constants and data structures describing the layout of the file system.
For example, the superblock contains four numbers: the file system size in blocks,
the number of data blocks, the number of inodes, and the number of blocks
in the log.
.\"
.\" -------------------------------------------
.\"
.section "Code: Block allocator"
.PP
xv6's block allocator
maintains a free bitmap on disk, with one bit per block. 
A zero bit indicates that the corresponding block is free;
a one bit indicates that it is in use.
The bits corresponding to the boot sector, superblock, inode
blocks, and bitmap blocks are always set.
.PP
The block allocator provides two functions:
.code balloc
allocates a new disk block, and
.code bfree
frees a block.
.code Balloc
.line fs.c:/^balloc/
starts by calling
.code readsb
to read the superblock from the disk (or buffer cache) into
.code sb .
.code balloc
decides which blocks hold the data block free bitmap
by calculating how many blocks are consumed by the
boot sector, the superblock, and the inodes (using 
.code BBLOCK ).
The loop
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
the buffer cache only lets one process use a block at a time.
.PP
.code Bfree
.line fs.c:/^bfree/
finds the right bitmap block and clears the right bit.
Again the exclusive use implied by
.code bread
and
.code brelse
avoids the need for explicit locking.
.\"
.\" -------------------------------------------
.\"
.section "Inodes
.PP
The term ``inode'' can have one of two related meanings.
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
.code struct
.code dinode
.line fs.h:/^struct.dinode/ .
The 
.code type
field distinguishes between files, directories, and special
files (devices).
A type of zero indicates that an on-disk inode is free.
.PP
The kernel keeps the set of active inodes in memory;
its
.code struct
.code inode
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
.code iget
and
.code iput
functions acquire and release pointers to an inode,
modifying the reference count.
Pointers to an inode can come from file descriptors,
current working directories, and transient kernel code
such as
.code exec .
.PP
The
.code struct
.code inode
that 
.code iget
returns may not have any useful content.
In order to ensure it holds a copy of the on-disk
inode, code must call
.code ilock .
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
.section "Code: Inodes
.PP
To allocate a new inode (for example, when creating a file),
xv6 calls
.code ialloc
.line fs.c:/^ialloc/ .
.code Ialloc
is similar to
.code balloc :
it loops over the inode structures on the disk, one block at a time,
looking for one that is marked free.
When it finds one, it claims it by writing the new 
.code type
to the disk and then returns an entry from the inode cache
with the tail call to 
.code iget
.line "'fs.c:/return.iget!(dev..inum!)/'" .
Like in
.code balloc ,
the correct operation of
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
.code iget
scans, it records the position of the first empty slot
.lines fs.c:/^....if.empty.==.0/,/empty.=.ip/ ,
which it uses if it needs to allocate a new cache entry.
In both cases,
.code iget
returns one reference to the caller: it is the caller's 
responsibility to call 
.code iput
to release the inode.
It can be convenient for some callers to arrange to call
.code iput
multiple times.
.code Idup
.line fs.c:/^idup/
increments the reference count so that an additional
.code iput
call is required before the inode can be dropped from the cache.
.PP
Callers must lock the inode using
.code ilock
before reading or writing its metadata or content.
.code Ilock
.line fs.c:/^ilock/
uses a now-familiar sleep loop to wait for
.code ip->flag 's
.code I_BUSY
bit to be clear and then sets it
.lines 'fs.c:/^..while.ip->flags.&.I_BUSY/,/I_BUSY/' .
Once
.code ilock
has exclusive access to the inode, it can load the inode metadata
from the disk (more likely, the buffer cache)
if needed.
.code Iunlock
.line fs.c:/^iunlock/
clears the
.code I_BUSY
bit and wakes any processes sleeping in
.code ilock .
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
.code iput
sees that there are no C pointer references to an inode
and that the inode has no links to it (occurs in no
directory), then the inode and its data blocks must
be freed.
.code Iput
relocks the inode;
calls
.code itrunc
to truncate the file to zero bytes, freeing the data blocks;
sets the inode type to 0 (unallocated);
writes the change to disk;
and finally unlocks the inode
.lines 'fs.c:/ip..ref.==.1/,/^..}/' .
.PP
The locking protocol in 
.code iput
deserves a closer look.
The first part worth examining is that when locking
.code ip ,
.code iput
simply assumed that it would be unlocked, instead of using a sleep loop.
This must be the case, because the caller is required to unlock
.code ip
before calling
.code iput ,
and
the caller has the only reference to it
.code ip->ref "" (
.code ==
.code 1 ).
The second part worth examining is that
.code iput
temporarily releases
.line fs.c:/^....release/
and reacquires
.line fs.c:/^....acquire/
the cache lock.
This is necessary because
.code itrunc
and
.code iupdate
will sleep during disk i/o,
but we must consider what might happen while the lock is not held.
Specifically, once 
.code iupdate
finishes, the on-disk structure is marked as available
for use, and a concurrent call to
.code ialloc
might find it and reallocate it before 
.code iput
can finish.
.code Ialloc
will return a reference to the block by calling
.code iget ,
which will find 
.code ip
in the cache, see that its 
.code I_BUSY
flag is set, and sleep.
Now the in-core inode is out of sync compared to the disk:
.code ialloc
reinitialized the disk version but relies on the 
caller to load it into memory during
.code ilock .
In order to make sure that this happens,
.code iput
must clear not only
.code I_BUSY
but also
.code I_VALID
before releasing the inode lock.
It does this by zeroing
.code flags
.line 'fs.c:/^....ip->flags.=.0/' .
.\"
.\"
.\"
.section "Code: Inode contents
.PP
The on-disk inode structure,
.code struct
.code dinode ,
contains a size and an array of block numbers.
The inode data is found in the blocks listed
in the
.code dinode 's
.code addrs
array.
The first
.code NDIRECT
blocks of data are listed in the first
.code NDIRECT
entries in the array; these blocks are called ``direct blocks''.
The next 
.code NINDIRECT
blocks of data are listed not in the inode
but in a data block called the ``indirect block''.
The last entry in the
.code addrs
array gives the address of the indirect block.
Thus the first 6 kB 
.code NDIRECT \c (
×\c
.code BSIZE )
bytes of a file can be loaded from blocks listed in the inode,
while the next
.code 64 kB
.code NINDIRECT \c (
×\c
.code BSIZE )
bytes can only be loaded after consulting the indirect block.
This is a good on-disk representation but a 
complex one for clients.
.code Bmap
manages the representation so that higher-level routines such as
.code readi
and
.code writei ,
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
.code Bmap
.line fs.c:/^bmap/
begins by picking off the easy case: the first 
.code NDIRECT
blocks are listed in the inode itself
.lines 'fs.c:/^..if.bn.<.NDIRECT/,/^..}/' .
The next 
.code NINDIRECT
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
panics: callers are responsible for not asking about out-of-range block numbers.
.PP
.code Bmap
allocates block as needed.
Unallocated blocks are denoted by a block number of zero.
As
.code bmap
encounters zeros, it replaces them with the numbers of fresh blocks,
allocated on demand.
.line "'fs.c:/^....if..addr.=.*==.0/,/./' 'fs.c:/^....if..addr.*NDIRECT.*==.0/,/./'" .
.PP
.code Bmap
allocates blocks on demand as the inode grows;
.code itrunc
frees them, resetting the inode's size to zero.
.code Itrunc
.line fs.c:/^itrunc/
starts by freeing the direct blocks
.lines 'fs.c:/^..for.i.=.0.*NDIRECT/,/^..}/'
and then the ones listed in the indirect block
.lines 'fs.c:/^....for.j.=.0.*NINDIRECT/,/^....}/' ,
and finally the indirect block itself
.lines 'fs.c:/^....bfree.*NDIRECT/,/./' .
.PP
.code Bmap
makes it easy to write functions to access the inode's data stream,
like 
.code readi
and
.code writei .
.code Readi
.line fs.c:/^readi/
reads data from the inode.
It starts 
making sure that the offset and count are not reading
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
.code Writei
.line fs.c:/^writei/
is identical to
.code readi ,
with three exceptions:
writes that start at or cross the end of the file
grow the file, up to the maximum file size
.lines "'fs.c:/^..if.off.!+.n.>.MAXFILE/,/./'" ;
the loop copies data into the buffers instead of out
.line 'fs.c:/memmove.bp->data/' ;
and if the write has extended the file,
.code writei
must update its size
.line "'fs.c:/^..if.n.>.0.*off.>.ip->size/,/^..}/'" .
.PP
Both
.code readi
and
.code writei
begin by checking for
.code ip->type
.code ==
.code T_DEV .
This case handles special devices whose data does not
live in the file system; we will return to this case in
Chapter \*[CH:FSCALL].
.PP
.code Stati
.line fs.c:/^stati/
copies inode metadata into the 
.code stat
structure, which is exposed to user programs
via the
.code stat
system call
(see Chapter \*[CH:FSCALL]).
.\"
.\"
.\"
.section "Code: Directories
.PP
Xv6 implements a directory as a special kind of file:
it has type
.code T_DIR
and its data is a sequence of directory entries.
Each entry is a
.code struct
.code dirent
.line fs.h:/^struct.dirent/ ,
which contains a name and an inode number.
The name is at most
.code DIRSIZ
(14) characters;
if shorter, it is terminated by a NUL (0) byte.
Directory entries with inode number zero are free.
.PP
.code Dirlookup
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
.code iget 
.line 'fs.c:/^......if.namecmp/,/^......}/' .
.code Dirlookup
is the reason that 
.code iget
returns unlocked inodes.
The caller has locked
.code dp ,
so if the lookup was for
.code "." ,
an alias for the current directory,
attempting to lock the inode before
returning would try to re-lock
.code dp
and deadlock.
(There are more complicated deadlock scenarios involving
multiple processes and
.code ".." ,
an alias for the parent directory;
.code "."
is not the only problem.)
The caller can unlock
.code dp
and then lock
.code ip ,
ensuring that it only holds one lock at a time.
.PP
.code Dirlink
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
.section "Code: Path names
.PP
Lookup of full pathnames in the directory hierarchy
is the job of
.code namei
and related functions.
.PP
.code Namei
.line fs.c:/^namei/
evaluates 
.code path
as a hierarchical path name and returns the corresponding 
.code inode .
.code Nameiparent
is a variant: it stops before the last element, returning the 
inode of the parent directory and copying the final element into
.code name .
Both call the generalized function
.code namex
to do the real work.
.PP
.code Namex
.line fs.c:/^namex/
starts by deciding where the path evaluation begins.
If the path begins with a slash, evaluation begins at the root;
otherwise, the current directory
.line "'fs.c:/..if.!*path.==....!)/,/idup/'" .
Then it uses
.code skipelem
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
.code ilock
runs,
.code ip->type
is not guaranteed to have been loaded from disk.)
If the call is 
.code nameiparent
and this is the last path element, the loop stops early,
as per the definition of
.code nameiparent ;
the final path element has already been copied
into
.code name ,
so
.code namex
need only
return the unlocked
.code ip
.lines fs.c:/^....if.nameiparent/,/^....}/ .
Finally, the loop looks for the path element using
.code dirlookup
and prepares for the next iteration by setting
.code ip.=.next
.lines 'fs.c:/^....if..next.*dirlookup/,/^....ip.=.next/' .
When the loop runs out of path elements, it returns
.code ip .
.PP
TODO: It is possible that namei belongs with all its uses,
like open and close, and not here in data structure land.
.\"
.\"
.\"
.section "Real world
.PP
Xv6's file system implementation assumes that disk operations are
far more expensive than computation.
It uses an efficient tree structure on disk but comparatively
inefficient linear scans in the inode
and buffer cache.
The caches are small enough and disk accesses expensive enough
to justify this tradeoff.  Modern operating systems with
larger caches and faster disks use more efficient in-memory
data structures.
The disk structure, however, with its inodes and direct blocks and indirect blocks,
has been remarkably persistent.
BSD's UFS/FFS and Linux's ext2/ext3 use essentially the same data structures.
The most inefficient part of the file system layout is the directory,
which requires a linear scan over all the disk blocks during each lookup.
This is reasonable when directories are only a few disk blocks,
especially if the entries in each disk block can be kept sorted,
but when directories span many disk blocks.
Microsoft Windows's NTFS, Mac OS X's HFS, and Solaris's ZFS, just to name a few, implement
a directory as an on-disk balanced tree of blocks.
This is more complicated than reusing the file implementation
but guarantees logarithmic-time directory lookups.
.PP
Xv6 is intentionally naive about disk failures: if a disk
operation fails, xv6 panics.
Whether this is reasonable depends on the hardware:
if an operating systems sits atop special hardware that uses
redundancy to mask disk failures, perhaps the operating system
sees failures so infrequently that panicking is okay.
On the other hand, operating systems using plain disks
should expect failures and handle them more gracefully,
so that the loss of a block in one file doesn't affect the
use of the rest of the files system.
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
allowing rich functionality like growing or shrinking the logical
device by adding or removing disks on the fly.
Of course, a storage layer that can grow or shrink on the fly
requires a file system that can do the same: the fixed-size array
of inode blocks used by Unix file systems does not work well
in such environments.
Separating disk management from the file system may be
the cleanest design, but the complex interface between the two
has led some systems, like Sun's ZFS, to combine them.
.PP
Other features: snapshotting and backup.
.\"
.\"
.\"
.section Exercises
.PP
Exercise: why panic in balloc?  Can we recover?
.PP
Exercise: why panic in ialloc?  Can we recover?
.PP
Exercise: inode generation numbers.
