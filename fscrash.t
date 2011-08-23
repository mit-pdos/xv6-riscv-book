.so book.mac
.\"
.\"
.\"
.chapter CH:FSCRASH "File system crash recovery"
.PP
One of the most interesting aspects of file system design is crash
recovery. The problem arises because many file system operations
involve multiple writes to the disk, and a crash after a subset of the
writes may leave the on-disk file system in an inconsistent state. For
example, depending on the order of the disk writes, a crash during
file deletion may either leave a directory entry pointing to a free
inode, or an allocated but unreferenced inode. The latter is relatively
benign, but a directory entry that refers to a freed inode is
likely to cause serious problems after a reboot.
.PP
Xv6 solves the problem of crashes during file system operations with a
simple version of logging. An xv6 system call does not directly write
the on-disk file system data structures. Instead, it places a
description of all the disk writes it wishes to make in a ``log'' on
the disk. Once the system call has logged its writes, it writes a
special ``commit'' record to the disk indicating the the log contains
a complete operation. At that point the system call copies the writes
to the on-disk file system data structures. After those writes have
completed, the system call erases the log on disk.
.PP
If the system should crash and reboot, the file system code recovers
from the crash as follows, before running any processes. If the log is
marked as containing a complete operation, then the recovery code
copies the writes to where they belong in the on-disk file system. If
the log is not marked as containing a complete operation, the recovery
code ignores it. In either case, the recovery code finishes by erasing
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
.section "Design"
.PP
The log resides at a known fixed location at the very end of the disk.
It consists of a header block followed by a sequence
of data blocks. The header block contains an array of sector
number, one for each of the logged data blocks. The header block
also contains the count of logged blocks. Xv6 writes the header
block when a transaction commits, but not before, and sets the
count to zero after copying the logged blocks to the file system.
Thus a crash midway through a transaction will result in a
count of zero in the log's header block; a crash after a commit
will result in a non-zero count.
.PP
Each system call's code indicates the start and end of the sequence of
writes that must be atomic; we'll call such a sequence a transaction,
though it is much simpler than a database transaction. Only one system
call can be in a transaction at any one time: other processes must
wait until any ongoing transaction has finished. Thus the log holds at
most one transaction at a time.
.PP
Xv6 only allows a single transaction at a time in order to avoid the
following kind of race that could occur if concurrent transactions
were allowed. Suppose transaction X has written a modification to an
inode into the log. Concurrent transaction Y then reads a different
inode in the same block, updates that inode, writes the inode block to
the log, and commits. It would be a disaster if the commit of Y write
X's modified inode to the file system, since X has not yet committed.
There are sophisticated ways to solve this problem; xv6 solves it by
outlawing concurrent transactions.
.PP
Xv6 allows read-only system calls to execute concurrently with a
transaction. Inode locks cause the transaction to appear atomic to the
read-only system call.
.PP
Xv6 dedicates a fixed amount of space on the disk to hold the log.
No system call
can be allowed to write more distinct blocks than there is space
in the log. This is not a problem for most system calls, but two
of them can potentially write many blocks: 
.code write
and
.code unlink .
A large file write may write many data blocks and many bitmap blocks
as well as an inode block; unlinking a large file might write many
bitmap blocks and an inode.
Xv6's write system call breaks up large writes into multiple smaller
writes that fit in the log,
and 
.code unlink
doesn't cause problems because in practice the xv6 file system uses
only one bitmap block.
.\"
.\"
.\"
.section "Code"
.PP
A typical use of the log in a system call looks like this:
.P1
  begin_trans();
  ...
  bp = bread(...);
  bp->data[...] = ...;
  log_write(bp);
  ...
  commit_trans();
.P2
.PP
.code begin_trans
.line log.c:/^begin.trans/
waits until it obtains exclusive use of the log and then returns.
.PP
.code log_write
.line log.c:/^log.write/
acts as a proxy for 
.code bwrite ;
it appends the block's new content to the log and
records the block's sector number.
.code log_write
leaves the modified block in the in-memory buffer cache,
so that subsequent reads of the block during the transaction
will yield the modified block.
.code log_write
notices when a block is written multiple times during a single
transaction, and overwrites the block's previous copy in the log.
.PP
.code commit_trans
.line log.c:/^commit.trans/
first write's the log's header block to disk, so that a crash
after this point will cause recovery to re-write the blocks
in the log. 
.code commit_trans
then calls
.code install_trans
.line log.c:/^install_trans/
to read each block from the log and write it to the proper
place in the file system.
Finally
.code commit_trans
writes the log header with a count of zero,
so that a crash after the next transaction starts
will result in the recovery code ignoring the log.
.PP
.code recover_from_log
.line log.c:/^recover_from_log/
is called during a reboot.
It reads the log header, and mimics the actions of
.code commit_trans
if the header indicates that the log contains a committed transaction.
.PP
An example use of the log occurs in 
.code filewrite
.line file.c:/^filewrite/ .
The transaction looks like this:
.P1
      begin_trans();
      ilock(f->ip);
      r = writei(f->ip, ...);
      iunlock(f->ip);
      commit_trans();
.P2
This code is wrapped in a loop that breaks up large writes into individual
transactions of just a few sectors at a time, to avoid overflowing
the log.  The call to
.code writei
writes many blocks as part of this
transaction: the file's inode, one or more bitmap blocks, and some data
blocks.
The call to
.code ilock
occurs after the
.code begin_trans
as part of an overall strategy to avoid deadlock:
since there is effectively a lock around each transaction,
the deadlock-avoiding lock ordering rule is transaction
before inode.
.\"
.\"
.\"
.section "Real world"
.PP
Xv6's logging system is woefully inefficient. It does not allow concurrent
updating system calls, even when the system calls operate on entirely
different parts of the file system. It logs entire blocks, even if
only a few bytes in a block are changed. It performs synchronous
log writes, a block at a time, each of which is likely to require an
entire disk rotation time. Real logging systems address all of these
problems.
.PP
Logging is not the only way to provide crash recovery. Early file systems
used a scavenger during reboot (for example, the UNIX
.code fsck
program) to examine every file and directory and the block and inode
free lists, looking for and resolving inconsistencies. Scavenging can take
hours for large file systems, and there are situations where it is not
possible to guess the correct resolution of an inconsistency. Recovery
from a log is much faster and is correct.
