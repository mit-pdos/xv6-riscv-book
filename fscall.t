.so book.mac
.ig
	notes:

	perhaps namei belongs at the start of this chapter?
..
.chapter CH:FSCALL
.PP
XXX intro
write ordering
note on terminology: file means open file.

.\"
.\"
.\"
.section "Code: Files
.PP
Xv6 gives each process its own table of open files, as we saw in
Chapter \*[CH:UNIX].
Each open file is represented by a
.code struct
.code file
.line file.h:/^struct.file/ ,
which is a wrapper around either an inode or a pipe,
plus an i/o offset.
Each call to 
.code open
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
.code dup
or shared it with a child using
.code fork .
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
.code ftable .
Like the inode cache, the file table
has a function to allocate a file
.code filealloc ), (
create a duplicate reference
.code filedup ), (
release a reference
.code fileclose ), (
and read and write data
.code fileread "" (
and 
.code filewrite ).
.PP
The first three follow the now-familiar form.
.code Filealloc
.line file.c:/^filealloc/
scans the file table for an unreferenced file
.code f->ref "" (
.code ==
.code 0 )
and returns a new reference;
.code filedup
.line file.c:/^filedup/
increments the reference count;
and
.code fileclose
.line file.c:/^fileclose/
decrements it.
When a file's reference count reaches zero,
.code fileclose
releases the underlying pipe or inode,
according to the type.
.PP
.code Filestat ,
.code fileread ,
and
.code filewrite
implement the 
.code stat ,
.code read ,
and
.code write
operations on files.
.code Filestat
.line file.c:/^filestat/
is only allowed on inodes and calls
.code stati .
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
Remember from Chapter \*[CH:FSDATA] that the inode functions require the caller
to handle locking
.lines "'file.c:/stati/-1,/iunlock/' 'file.c:/readi/-1,/iunlock/' 'file.c:/writei/-1,/iunlock/'" .
The inode locking has the convenient side effect that the
read and write offsets are updated atomically, so that
multiple writing to the same file simultaneously
cannot overwrite each other's data, though their writes may end up interlaced.
.\"
.\"
.\"
.section "Code: System calls
.PP
Chapter \*[CH:TRAP] introduced helper functions for
implementing system calls: 
.code argint ,
.code argstr ,
and
.code argptr .
The file system adds another:
.code argfd
.line sysfile.c:/^argfd/
interprets the 
.code n th
argument as a file descriptor.
It calls
.code argint
to fetch the integer
.code fd
and then checks that
.code fd
is a valid file table index.
Although 
.code argfd
returns a reference to the file in
.code *pf ,
it does not increment the reference count:
the caller shares the reference from the file table.
As we will see, this convention avoids reference count
operations in most system calls.
.PP
The function
.code fdalloc
.line sysfile.c:/^fdalloc/
helps manage the current process's file table:
it scans the table for an open slot, and if it finds one,
inserts
.code f
and returns the index of the slot,
which will serve as the file descriptor.
It is up to the caller to manage the reference count.
.PP
Finally we are ready to implement system calls.
The simplest is
.code sys_dup
.line sysfile.c:/^sys_dup/ ,
which makes use of both of these helpers.
It calls
.code argfd
to obtain the file corresponding to the system call argument
and then calls
.code fdalloc
to assign it an additional file descriptor.
If both are successful, it calls
.code filedup
to adjust the reference count:
.code fdalloc
has created a new reference.
Similarly, 
.code sys_close
.line sysfile.c:/^sys_close/
obtains a file, removes it from the file table,
and releases the reference.
.PP
.code Sys_read
.line sysfile.c:/^sys_read/
parses its arguments as a file descriptor,
a pointer, and a size and then calls
.code fileread .
Note that no reference count operations are
necessary: 
.code sys_read
is piggybacking on the reference in the file table.
The reference cannot disappear during the
.code sys_read
because each process has its own file table,
and it is impossible for the process to call
.code sys_close
while it is in the middle of
.code sys_read .
.code Sys_write
.line sysfile.c:/^sys_write/
is identical to
.code sys_read
except that it calls
.code filewrite .
.code Sys_fstat
.line sysfile.c:/^sys_fstat/
is very similar to the previous two.
.PP
.code Sys_link
and
.code sys_unlink
edit directories, creating or removing references to inodes.
They are another good example of the power of exposing
the file system locking to higher-level functions.
.PP
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
count—the number of directories in which it appears—\c
and flushes the new count to disk
.lines sysfile.c:/nlink!+!+/,/iupdate/ .
Then
.code sys_link
calls
.code nameiparent
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
.code sys_link
must go back and decrement
.code ip->nlink .
.PP
.code Sys_link
would have simpler control flow and error handling if it
delayed the increment of
.code ip->nlink
until it had successfully created the link,
but doing this would put the file system temporarily in an unsafe state.
The low-level file system code in Chapter \*[CH:FSDATA] was
careful not to write out pointers to disk blocks before writing
the disk blocks themselves, lest the machine crash with a file system
with pointers to old blocks.
The same principle is being used here: to avoid dangling pointers,
it is important that the link count always be at least as large
as the true number of links.
If the system crashed after
.code sys_link
creating the second link but before it incremented
.code ip->nlink ,
then the file system would have an inode with
two links but a link count set to one.
Removing one of the links would cause the inode to be 
reused even though there was still a reference to it.
.PP
.code Sys_unlink
.line sysfile.c:/^sys_unlink/
is the opposite of
.code sys_link :
it removes the named
.code path
from the file system.
It calls
.code nameiparent
to find the parent directory,
.code sysfile.c:/nameiparent.path/ ,
checks that the final element,
.code name ,
exists in the directory
.line sysfile.c:/dirlookup.*==/ ,
clears the directory entry
.line sysfile.c:/writei/ ,
and then updates the link count
.line "'sysfile.c:/dp->nlink--/+5'" .
As was the case for
.code sys_link ,
the order here is important:
.code sys_unlink
must update the link count only after the 
directory entry has been removed.
There are a few more steps if the entry
being removed is a directory:
it must be empty
.line "'sysfile.c:/&& .isdirempty/'"
and after it has been removed, the parent directory's
link count must be decremented,
to reflect that the child's
.code ..
entry is gone.
.PP
.code Sys_link
creates a new name for an existing inode.
.code Create
.line sysfile.c:/^create/
creates a new name for a new inode.
It is a generalization of the three file creation
system calls:
.code open
with the
.code O_CREATE
flag makes a new ordinary file,
.code mkdir
makes a new directory ,
and
.code mkdev
makes a new device file.
Like
.code sys_link ,
.code create
starts by caling
.code nameiparent
to get the inode of the parent directory
.line "sysfile.c:/nameiparent.path/ 'XXX probably wrong'"
It then calls
.code dirlookup
to check whether the name already exists
.line 'sysfile.c:/dirlookup.*[^=]=.0/' .
If the name does exist, 
.code create 's
behavior depends on which system call it is being used for:
.code open
has different semantics from 
.code mkdir
and
.code mkdev .
If
.code create
is being used on behalf of
.code open
.code type "" (
.code ==
.code T_FILE )
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
.code ialloc
.line sysfile.c:/ialloc/ .
If the new inode is a directory, 
.code create
initializes it with
.code .
and
.code ..
entries.
Finally, now that the data is initialized properly,
.code create
can link it into the parent directory
.line sysfile.c:/if.dirlink/ .
.code Create ,
like
.code sys_link ,
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
.code sys_open ,
.code sys_mkdir ,
and
.code sys_mknod .
(TODO: Explain the name sys_mknod.
Perhaps mknod was for a while the only way to create anything?)
.PP
.code Sys_open
.line sysfile.c:/^sys_open/
is the most complex, because creating a new file is only
a small part of what it can do.
If
.code open
is passed the
.code O_CREATE
flag, it calls
.code create
.line sysfile.c:/create.*T_FILE/ .
Otherwise, it calls
.code namei
.line sysfile.c:/if..ip.=.namei.path/ .
.code Create
returns a locked inode, but 
.code namei
does not, so
.code sys_open
must lock the inode itself.
This provides a convenient place to check that directories
are only opened for reading, not writing.
Assuming the inode was obtained one way or the other,
.code sys_open
allocates a file and a file descriptor
.line sysfile.c:/filealloc.*fdalloc/
and then fills in the file
.lines sysfile.c:/type.=.FD_INODE/,/writable/ .
Since we have been so careful to initialize data structures
before creating pointers to them, this sequence
should feel wrong, but it is safe:
no other process can access the partially initialized file since it is only
in the current process's table, 
and these data structures are in memory, not on disk, so
they don't persist across a machine crash.
.PP
.code Sys_mkdir
.line sysfile.c:/^sys_mkdir/
and
.code sys_mknod
.line sysfile.c:/^sys_mknod/
are trivial:
they parse their arguments, call
.code create ,
and release the inode it returns.
.PP
.code Sys_chdir
.line sysfile.c:/^sys_chdir/
changes the current directory, which is stored as
.code cp->cwd
rather than in the file table.
It evaluates the new path, checks that it is a directory,
releases the old
.code cp->cwd ,
and saves the new one in its place.
.PP
Chapter \*[CH:SYNC] examined the implementation of pipes
before we even had a file system.
.code Sys_pipe
connects that implementation to the file system
by providing a way to create a pipe pair.
Its argument is a pointer to space for two integers,
where it will record the two new file descriptors.
Then it allocates the pipe and installs the file descriptors.
Chapter \*[CH:SYNC] did not examine
.code pipealloc
.line pipe.c:/^pipealloc/
and
.code pipeclose
.line pipe.c:/^pipeclose/ ,
but they should be straightforward after walking through the examples above.
.PP
The final file system call
is
.code exec ,
which is the topic of the next chapter.
.\"
.\"
.\"
.section "Real world
.PP
The file system interface in this chapter has proved remarkably durable:
modern systems such as BSD and Linux continue to be based on the
same core system calls.
In those systems, multiple processes (sometimes called threads)
can share a file descriptor table.  That introduces another level
of locking and complicates the reference counting here.
.PP
Xv6 has two different file implementations: pipes and inodes.
Modern Unix systems have many: pipes, network connections, and
inodes from many different types of file systems, including
network file systems.
Instead of the
.code if
statements in
.code fileread
and
.code filewrite ,
these systems typically give each open file a table of function pointers,
one per operation,
and call the function pointer to invoke that inode's
implementation of the call.
Network file systems and user-level file systems 
provide functions that turn those calls into network RPCs
and wait for the response before returning.
Network file systems are now an everyday occurrence,
but networking in general is beyond the scope of this book.
On the other hand, the World Wide Web is in some ways
a global-scale hierarchical file system.
.\"
.\"
.\"
.section "Exercises
.PP
Exercise: why doesn't filealloc panic when it runs out of files?
Why is this more common and therefore worth handling?
.PP
Exercise: suppose the file corresponding to 
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
Exercise:
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
Exercise: 
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

