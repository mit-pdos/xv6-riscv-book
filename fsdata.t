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
.chapter CH:FSDATA "File system data structures
.PP
The disk driver and buffer cache (Chapter \*[CH:DISK]) provide safe, synchronized
access to disk blocks.
Individual blocks are still a very low-level interface, too raw for most
programs.
Xv6, following Unix, provides a hierarchical file system that allows
programs to treat storage as a tree of named files, each containing
a variable length sequence of bytes.
The file system is implemented in four steps.
The first step is the block allocator.  It manages disk blocks, keeping
track of which blocks are in use,
just as the memory allocator in Appendix \*[APP:MEM] tracks which
memory pages are in use.
The second step is unnamed files called inodes (pronounced i-node).
Inodes are a collection of allocated blocks holding a variable length
sequence of bytes.
The third step is directories.  A directory is a special kind
of inode whose content is a sequence of directory entries, 
each of which lists a name and a pointer to another inode.
The last step is hierarchical path names like
.code /usr/rtm/xv6/fs.c ,
a convenient syntax for identifying particular files or directories.
.\"
.\" -------------------------------------------
.\"
.section "File system layout
.PP
Xv6 lays out its file system as follows.
Block 0 is unused, left available for use by the operating system boot sequence.
Block 1 is called the superblock; it contains metadata about the
file system.
After block 1 comes a sequence of inodes blocks, each containing
inode headers.
After those come bitmap blocks tracking which data
blocks are in use, and then the data blocks themselves.
.PP
The header
.code fs.h
.line fs.h:1
contains constants and data structures describing the layout of the file system.
The superblock contains three numbers: the file system size in blocks,
the number of data blocks, and the number of inodes.
.\"
.\" -------------------------------------------
.\"
.section "Code: Block allocator
.PP
The block allocator is made up of the two functions:
.code balloc
allocates a new disk block and
.code bfree
frees one.
.code Balloc
.line fs.c:/^balloc/
starts by calling
.code readsb
to read the superblock.
.code Readsb "" (
.line fs.c:/^readsb/
is almost trivial: it reads the block,
copies the contents into 
.code sb ,
and releases the block.)
Now that 
.code balloc
knows the number of inodes in the file system,
it can consult the in-use bitmaps to find a free data block.
The loop
.code fs.c:/^..for.b.=.0/
considers every block, starting at block 0 up to 
.code sb.size ,
the number of blocks in the file system,
checking for a block whose bitmap bit is zero,
indicating it is free.
If
.code balloc
finds such a block, it updates the bitmap 
and returns the block
For efficiency, the loop is split into two 
pieces: the inner loop checks all the bits in
a single bitmap block—there are
.code BPB \c
—and the outer loop considers all the blocks in increments of
.code BPB .
There may be multiple processes calling
.code balloc
simultaneously, and yet there is no explicit locking.
Instead,
.code balloc
relies on the fact that the buffer cache
.code bread "" (
and
.code brelse )
only let one process use a buffer at a time.
When reading and writing a bitmap block
.lines 'fs.c:/for.bi.=.0/,/^....}/' ,
.code balloc
can be sure that it is the only process in the system
using that block.
.PP
.code Bfree
.line fs.c:/^bfree/
is the opposite of 
.code balloc
and has an easier job: there is no search.
It finds the right bitmap block, clears the right bit, and is done.
Again the exclusive use implied by
.code bread
and
.code brelse
avoids the need for explicit locking.
.PP
When blocks are loaded in memory, they are referred to
by pointers to
.code buf
structures; as we saw in the last chapter, a more
permanent reference is the block's address on disk,
its block number.
.\"
.\" -------------------------------------------
.\"
.section "Inodes
.PP
In Unix technical jargon,
the term inode refers to an unnamed file in the file system,
but the precise meaning can be one of three, depending on context.
First, there is the on-disk data structure, which contains
metadata about the inode, like its size and the list of blocks storing its data.
Second, there is the in-kernel data structure, which contains
a copy of the on-disk structure but adds extra metadata needed
within the kernel.
Third, there is the concept of an inode as the whole unnamed file,
including not just the header but also its content, the sequence of bytes
in the data blocks.
Using the one word to mean all three related ideas can be confusing at first
but should become natural.
.PP
Inode metadata is stored in an inode structure, and all the inode
structures for the file system are packed into a separate section
of disk called the inode blocks.
Every inode structure is the same size, so it is easy, given a
number n, to find the nth inode structure on the disk.
In fact, this number n, called the inode number or i-number,
is how inodes are identified in the implementation.
.PP
The on-disk inode structure is a 
.code struct
.code dinode
.line fs.h:/^struct.dinode/ .
The 
.code type
field in the inode header doubles as an allocation bit:
a type of zero means the inode is available for use.
The kernel keeps the set of active inodes in memory;
its
.code struct
.code inode
is the in-memory copy of a 
.code struct
.code dinode
on disk.
The access rules for in-memory inodes are similar to the rules for
buffers in the buffer cache:
there is an inode cache,
.code iget
fetches an inode from the cache, and
.code iput
releases an inode.
Unlike in the buffer cache,
.code iget
returns an unlocked inode:
it is the caller's responsibility to lock the inode with
.code ilock
before reading or writing metadata or content
and then to unlock the inode with
.code iunlock
before calling
.code iput .
Leaving locking to the caller allows the file system calls
(described in Chapter \*[CH:FSSYS]) to manage the atomicity of
complex operations.
Multiple processes can hold a reference to an inode
.code ip
returned by 
.code iget
.code ip->ref "" (
counts exactly how many),
but only one process can lock the inode at a time.
.PP
The inode cache is not a true cache: its only purpose is to
synchronize access by multiple processes to shared inodes.
It does not actually cache inodes when they are not being used;
instead it assumes that the buffer cache is doing a good job
of avoiding unnecessary disk acceses and makes no effort to avoid
calls to
.code bread .
The in-memory copy of the inode augments the disk fields with the
device and inode number, the reference count mentioned earlier,
and a set of flags.
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
releases a reference to an inode
by decrementing the reference count
.line 'fs.c:/^..ip->ref--/' .
If this is the last reference, so that the count would become zero,
the inode is about to become 
unreachable: its disk data needs to be reclaimed.
.code Iput
relocks the inode;
calls
.code itrunc
to truncate the file to zero bytes, freeing the data blocks;
sets the type to 0 (unallocated);
writes the change to disk;
and finally unlocks the inode
.lines 'fs.c:/ip..ref.==.1/,/^..}/' .
.PP
The locking protocol in 
.code iput
deserves a closer look.
The first part with examining is that when locking
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
contains a 
a size and a list of block numbers.
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
blocks are litsed in the indirect block at
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
encouters zeros, it replaces them with the numbers of fresh blocks,
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
Chapter \*[CH:DEV].
.PP
.code Stati
.line fs.c:/^stati/
copies inode metadata into the 
.code stat
structure, which is exposed to user programs
via the
.code stat
system call
(see Chapter \*[CH:FSSYS]).
.\"
.\"
.\"
.section "Code: Directories
.PP
Xv6 implements a directory as a special kind of file:
it has type
.code T_DEV
and its data is a sequence of directory entries.
Each entry is a
.code struct
.code dirent
.line fs.h:/^struct.dirent/ ,
which contains a name and an inode number.
The name is at most
.code DIRSIZ
(14) letters;
if shorter, it is terminated by a NUL (0) byte.
Directory entries with inode number zero are unallocated.
.PP
.code Dirlookup
.line fs.c:/^dirlookup/
searches the directory for an entry with the given name.
If it finds one, it returns the corresponding inode, unlocked,
and sets 
.code *poff
to the byte offset of the entry within the directory,
in case the caller wishes to edit it.
The outer for loop
.line 'fs.c:/^..for.off.=.0.*dp->size.*BSIZE/'
considers each block in the directory in turn; the inner
loop 
.line 'fs.c:/^....for.de.=..struct.dirent/'
considers each directory entry in the block,
ignoring entries with inode number zero.
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
If
.code dirlookup
is read,
.code dirlink
is write.
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
.PP
.code Dirlookup
and
.code dirlink
use different loops to scan the directory:
.code dirlookup
operates a block at a time, like
.code balloc
and
.code ialloc ,
while
.code dirlink
operates one entry at a time by calling
.code readi .
The latter approach calls
.code bread
more often—once per entry instead of once per block—but is
simpler and makes it easy to exit the loop with
.code off
set correctly.
The more complex loop in 
.code dirlookup
does not save any disk i/o—the buffer cache
avoids redundant reads—but doe savoid repeated
locking and unlocking of
.code bcache.lock
in
.code bread .
The extra work may have been deemed necessary in
.code dirlooup
but not 
.code dirlink
because the former is so much more common than the latter.
(TODO: Make this paragraph into an exercise?)
.\"
.\"
.\"
.section "Path names
.PP
The code examined so far implements a hierarchical file system.
The earliest Unix systems, such as the version described
in Thompson and Ritchie's earliest paper, stops here.
Those systems looked up names in the current directory only;
to look in another directory, a process needed to first move
into that directory.
Before long, it became clear that it would be useufl to refer to
directories further away:
the name
.code xv6/fs.c
means first look up
.code xv6 ,
which must be a directory,
and then look up
.code fs.c 
in that directory.
A path beginning with a slash is called rooted.
The name
.code /xv6/fs.c
is like
.code xv6/fs.c
but starts the lookup 
at the root of the file system tree instead of the current directory.
Now, decades later, hierarchical, optionally rooted path names
are so commonplace that it is easy to forgoet
that they had to be invented; Unix did that.
(TODO: Is this really true?)
.\"
.\"
.\"
.section "Code: Path names
.PP
The final section of
.code fs.c
interprets hierarchical path names.
.code Skipelem
.line fs.c:/^skipelem/
helps parse them.
It copies the first element of
.code path
to 
.code name
and retrns a pointer to the remainder of
.code path ,
skipping over leading slashes.
Appendix \*[APP:C] examines the implementation in detail.
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
far more expensive than cpu operations.
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
Windows's NTFS, OS X's HFS, and Sun's ZFS, just to name a few, implement
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
Xv6, like most operating systems, requires that the file system
fit on one disk device and not change in size.
As large databases and multimedia files drive storage
requirements ever higher, operating systems are developing ways
to eliminate the ``one disk per file system'' bttleneck.
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
