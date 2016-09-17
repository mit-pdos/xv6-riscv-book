.chapter CH:UNIX "Operating system interfaces"
.PP
The job of an operating system is to share a computer among
multiple programs and to provide a more useful set of services
than the hardware alone supports.
The operating system manages and abstracts
the low-level hardware, so that, for example,
a word processor need not concern itself with which type
of disk hardware is being used.
It also shares the hardware among multiple programs so
that they run (or appear to run) at the same time.
Finally, operating systems provide controlled ways for programs
to interact, so that they can share data or work together.
.PP
An operating system provides services to user programs through an interface.
.index "interface design"
Designing a good interface turns out to be
difficult.  On the one hand, we would like the interface to be
simple and narrow because that makes it easier to get the
implementation right.  On the other hand,
we may be tempted to offer many sophisticated features to applications.
The trick in
resolving this tension is to design interfaces that rely on a few
mechanisms that can be combined to provide much generality.
.PP
This book uses a single operating system as a concrete example to
illustrate operating system concepts.  That operating system,
xv6, provides the basic interfaces introduced by Ken Thompson and
Dennis Ritchie's Unix operating system, as well as mimicking Unix's
internal design.  Unix provides a
narrow interface whose mechanisms combine well, offering a surprising
degree of generality.  This interface has been so successful that
modern operating systems—BSD, Linux, Mac OS X, Solaris, and even, to a
lesser extent, Microsoft Windows—have Unix-like interfaces.
Understanding xv6 is a good start toward understanding any of these
systems and many others.
.PP
As shown in 
.figref os ,
xv6 takes the traditional form of a
.italic-index kernel ,
a special program that provides
services to running programs.
Each running program, called a
.italic-index process ,
has memory containing instructions, data, and a stack. The
instructions implement the
program's computation.  The data are the variables on which
the computation acts. The stack organizes the program's procedure calls.
.PP
When a
process needs to invoke a kernel service, it invokes a procedure call
in the operating system interface.  Such a procedure is called a
.italic-index "system call" .
The system call enters the kernel;
the kernel performs the service and returns.
Thus a process alternates between executing in
.italic-index "user space"
and
.italic-index "kernel space" .
.PP
The kernel uses the CPU's hardware protection mechanisms to
ensure that each process executing in user space can access only
its own memory.
The kernel executes with the hardware privileges required to
implement these protections; user programs execute without
those privileges.
When a user program invokes a system call, the hardware
raises the privilege level and starts executing a pre-arranged
function in the kernel.
.figure os
.PP
The collection of system calls that a kernel provides
is the interface that user programs see.
The xv6 kernel provides a subset of the services and system calls
that Unix kernels traditionally offer.  
.figref api 
lists all of xv6's system calls.
.PP
The rest of this chapter outlines xv6's services—\c
processes, memory, file descriptors, pipes, and file system—\c
and illustrates them with code snippets and discussions
of how the 
.italic-index "shell" , 
which is the primary user interface to 
traditional Unix-like systems, uses them.
The shell's use of system calls illustrates how carefully they
have been designed.
.PP
The shell is an ordinary program that reads commands from the user
and executes them.
The fact that the shell is a user program, not part of the kernel, 
illustrates the power of the system call interface: there is nothing
special about the shell.
It also means that the shell is easy to replace; as a result,
modern Unix systems have a variety of
shells to choose from, each with its own user interface
and scripting features.
The xv6 shell is a simple implementation of the essence of
the Unix Bourne shell.  Its implementation can be found at line
.line sh.c:1 .
.\"
.\"	Processes and memory
.\"
.section "Processes and memory"
.PP
An xv6 process consists of user-space memory (instructions, data, and stack)
and per-process state private to the kernel.
Xv6 can
.italic-index time-share 
processes: it transparently switches the available CPUs
among the set of processes waiting to execute.
When a process is not executing, xv6 saves its CPU registers,
restoring them when it next runs the process.
The kernel associates a process identifier, or
.code-index pid ,
with each process.
.figure api
.PP
A process may create a new process using the
.code-index fork
system call.
.code Fork
creates a new process, called the 
.italic-index "child process" , 
with exactly the same memory contents
as the calling process, called the 
.italic-index "parent process" .
.code Fork
returns in both the parent and the child.
In the parent,
.code-index fork
returns the child's pid;
in the child, it returns zero.
For example, consider the following program fragment:
.P1
int pid = fork();
if(pid > 0){
  printf("parent: child=%d\en", pid);
  pid = wait();
  printf("child %d is done\en", pid);
} else if(pid == 0){
  printf("child: exiting\en");
  exit();
} else {
  printf("fork error\en");
}
.P2
The
.code-index exit
system call causes the calling process to stop executing and
to release resources such as memory and open files.
The
.code-index wait
system call returns the pid of an exited child of the
current process; if none of the caller's children
has exited,
.code-index wait
waits for one to do so.
In the example, the output lines
.P1
parent: child=1234
child: exiting
.P2
might come out in either order, depending on whether the
parent or child gets to its
.code-index printf
call first.
After the child exits the parent's
.code-index wait
returns, causing the parent to print
.P1
parent: child 1234 is done
.P2
Although the child has the same memory contents as the parent initially, the
parent and child are executing with different memory and different registers:
changing a variable in one does not affect the other. For example, when the
return value of
.code wait
is stored into
.code pid 
in the parent process,
it doesn't change the variable 
.code pid
in the child.  The value of
.code pid
in the child will still be zero.
.PP
The
.code-index exec
system call
replaces the calling process's memory with a new memory
image loaded from a file stored in the file system.
The file must have a particular format, which specifies which part of
the file holds instructions, which part is data, at which instruction
to start, etc. xv6
uses the ELF format, which Chapter \*[CH:MEM] discusses in
more detail.
When
.code-index exec
succeeds, it does not return to the calling program;
instead, the instructions loaded from the file start
executing at the entry point declared in the ELF header.
.code Exec
takes two arguments: the name of the file containing the
executable and an array of string arguments.
For example:
.P1
char *argv[3];

argv[0] = "echo";
argv[1] = "hello";
argv[2] = 0;
exec("/bin/echo", argv);
printf("exec error\en");
.P2
This fragment replaces the calling program with an instance
of the program 
.code /bin/echo
running with the argument list
.code echo
.code hello .
Most programs ignore the first argument, which is 
conventionally the name of the program.
.PP
The xv6 shell uses the above calls to run programs on behalf of
users. The main structure of the shell is simple; see
.code main 
.line sh.c:/main/ .
The main loop reads a line of input from the user with
.code-index getcmd .
Then it calls 
.code fork , 
which creates a copy of the shell process. The
parent calls
.code wait ,
while the child runs the command.  For example, if the user
had typed
.code "echo hello" '' ``
to the shell,
.code runcmd
would have been called with
.code "echo hello" '' ``
as the argument.
.code runcmd 
.line sh.c:/runcmd/
runs the actual command. For
.code "echo hello" '', ``
it would call
.code exec 
.line sh.c:/exec.ecmd/ .
If
.code exec
succeeds then the child will execute instructions from
.code echo
instead of
.code runcmd .  
At some point
.code echo
will call
.code exit ,
which will cause the parent to return from
.code wait
in 
.code main
.line sh.c:/main/ .
You might wonder why
.code-index fork
and
.code-index exec
are not combined in a single call; we
will
see later that separate calls for creating a process
and loading a program is a clever design.
.PP
Xv6 allocates most user-space memory
implicitly:
.code-index fork
allocates the memory required for the child's copy of the
parent's memory, and 
.code-index exec
allocates enough memory to hold the executable file.
A process that needs more memory at run-time (perhaps for
.code-index malloc )
can call
.code sbrk(n)
to grow its data memory by
.code n
bytes;
.code-index sbrk
returns the location of the new memory.
.PP
Xv6 does not provide a notion of users or of protecting
one user from another; in Unix terms, all xv6 processes
run as root.
.\"
.\"	I/O and File descriptors
.\"
.section "I/O and File descriptors"
.PP
A 
.italic-index "file descriptor" 
is a small integer representing a kernel-managed object
that a process may read from or write to.
A process may obtain a file descriptor by opening a file, directory,
or device, or by creating a pipe, or by duplicating an existing
descriptor.
For simplicity we'll often refer to the object a file descriptor
refers to as a ``file'';
the file descriptor interface abstracts away the differences between
files, pipes, and devices, making them all look like streams of bytes.
.PP
Internally, the xv6 kernel uses the file descriptor
as an index into a per-process table,
so that every process has a private space of file descriptors
starting at zero.
By convention, a process reads from file descriptor 0 (standard input),
writes output to file descriptor 1 (standard output), and
writes error messages to file descriptor 2 (standard error).
As we will see, the shell exploits the convention to implement I/O redirection
and pipelines. The shell ensures that it always has three file descriptors
open
.line sh.c:/open..console/ ,
which are by default file descriptors for the console.
.PP
The
.code read
and
.code write
system calls read bytes from and write bytes to
open files named by file descriptors.
The call
.code read(fd,
.code buf,
.code n)
reads at most
.code n
bytes from the file descriptor
.code fd ,
copies them into
.code buf ,
and returns the number of bytes read.
Each file descriptor that refers to a file
has an offset associated with it.
.code Read
reads data from the current file offset and then advances
that offset by the number of bytes read:
a subsequent
.code read
will return the bytes following the ones returned by the first
.code read .
When there are no more bytes to read,
.code read
returns zero to signal the end of the file.
.PP
The call
.code write(fd,
.code buf,
.code n)
writes
.code n
bytes from
.code buf
to the file descriptor
.code fd
and returns the number of bytes written.
Fewer than
.code n
bytes are written only when an error occurs.
Like
.code read ,
.code write
writes data at the current file offset and then advances
that offset by the number of bytes written:
each
.code write
picks up where the previous one left off.
.PP
The following program fragment (which forms the essence of
.code cat )
copies data from its standard input
to its standard output.  If an error occurs, it writes a message
to the standard error.
.P1
char buf[512];
int n;

for(;;){
  n = read(0, buf, sizeof buf);
  if(n == 0)
    break;
  if(n < 0){
    fprintf(2, "read error\en");
    exit();
  }
  if(write(1, buf, n) != n){
    fprintf(2, "write error\en");
    exit();
  }
}
.P2
The important thing to note in the code fragment is that
.code cat
doesn't know whether it is reading from a file, console, or a pipe.
Similarly 
.code cat
doesn't know whether it is printing to a console, a file, or whatever.
The use of file descriptors and the convention that file descriptor 0
is input and file descriptor 1 is output allows a simple
implementation
of 
.code cat .
.PP
The
.code close
system call
releases a file descriptor, making it free for reuse by a future
.code open ,
.code pipe ,
or
.code dup
system call (see below).
A newly allocated file descriptor 
is always the lowest-numbered unused
descriptor of the current process.
.PP
File descriptors and
.code-index fork
interact to make I/O redirection easy to implement.
.code Fork
copies the parent's file descriptor table along with its memory,
so that the child starts with exactly the same open files as the parent.
The system call
.code-index exec
replaces the calling process's memory but preserves its file table.
This behavior allows the shell to
implement I/O redirection by forking, reopening chosen file descriptors,
and then execing the new program.
Here is a simplified version of the code a shell runs for the
command
.code cat
.code <
.code input.txt :
.P1
char *argv[2];

argv[0] = "cat";
argv[1] = 0;
if(fork() == 0) {
  close(0);
  open("input.txt", O_RDONLY);
  exec("cat", argv);
}
.P2
After the child closes file descriptor 0,
.code open
is guaranteed to use that file descriptor
for the newly opened
.code input.txt :
0 will be the smallest available file descriptor.
.code Cat
then executes with file descriptor 0 (standard input) referring to
.code input.txt .
.PP
The code for I/O redirection in the xv6 shell works in exactly this way
.line sh.c:/case.REDIR/ .
Recall that at this point in the code the shell has already forked the
child shell and that 
.code runcmd 
will call
.code exec
to load the new program.  Now it should be clear why it is a good idea that
.code fork
and 
.code exec 
are separate calls.  Because if they are separate, the shell can fork a child,
use
.code open ,
.code close ,
.code dup
in the child to change the standard input and output
file descriptors, and then
.code exec .
No changes to the program being exec-ed
.code ( cat
in our example)
are required.
If
.code fork
and
.code exec
were combined into a single
system call, some other (probably more complex) scheme would be required for the
shell to redirect standard input and output, or the program itself would have to
understand how to redirect I/O.
.PP
Although
.code fork
copies the file descriptor table, each underlying file offset is shared
between parent and child.
Consider this example:
.P1
if(fork() == 0) {
  write(1, "hello ", 6);
  exit();
} else {
  wait();
  write(1, "world\en", 6);
}
.P2
At the end of this fragment, the file attached to file descriptor 1
will contain the data
.code hello
.code world .
The
.code write
in the parent
(which, thanks to
.code wait ,
runs only after the child is done)
picks up where the child's
.code write
left off.
This behavior helps produce sequential output from sequences
of shell commands, like
.code (echo
.code hello;
.code echo
.code world)
.code >output.txt .
.PP
The
.code dup
system call duplicates an existing file descriptor,
returning a new one that refers to the same underlying I/O object.
Both file descriptors share an offset, just as the file descriptors
duplicated by
.code fork
do.
This is another way to write
.code hello
.code world
into a file:
.P1
fd = dup(1);
write(1, "hello ", 6);
write(fd, "world\en", 6);
.P2
.PP
Two file descriptors share an offset if they were derived from
the same original file descriptor by a sequence of
.code fork
and
.code dup
calls.
Otherwise file descriptors do not share offsets, even if they
resulted from 
.code open
calls for the same file.  
.code Dup 
allows shells to implement commands like this:
.code ls
.code existing-file
.code non-existing-file
.code >
.code tmp1
.code 2>&1 .
The
.code 2>&1
tells the shell to give the command a file descriptor 2 that
is a duplicate of descriptor 1.
Both the name of the existing file and the error message for the
non-existing file will show up in the file
.code tmp1.
The xv6 shell doesn't support I/O redirection for the error file
descriptor, but now you know how to implement it.
.PP
File descriptors are a powerful abstraction,
because they hide the details of what they are connected to:
a process writing to file descriptor 1 may be writing to a
file, to a device like the console, or to a pipe.
.\"
.\"	Pipes
.\"
.section "Pipes"
.PP
A 
.italic-index pipe 
is a small kernel buffer exposed to processes as a pair of
file descriptors, one for reading and one for writing.
Writing data to one end of the pipe
makes that data available for reading from the other end of the pipe.
Pipes provide a way for processes to communicate.
.PP
The following example code runs the program
.code wc
with standard input connected to
the read end of a pipe.
.P1
int p[2];
char *argv[2];

argv[0] = "wc";
argv[1] = 0;

pipe(p);
if(fork() == 0) {
  close(0);
  dup(p[0]);
  close(p[0]);
  close(p[1]);
  exec("/bin/wc", argv);
} else {
  close(p[0]);
  write(p[1], "hello world\en", 12);
  close(p[1]);
}
.P2
The program calls
.code pipe ,
which creates a new pipe and records the read and write
file descriptors in the array
.code p .
After
.code fork ,
both parent and child have file descriptors referring to the pipe.
The child dups the read end onto file descriptor 0,
closes the file descriptors in
.code p ,
and execs
.code wc .
When 
.code wc
reads from its standard input, it reads from the pipe.
The parent closes the read side of the pipe,
writes to the pipe,
and then closes the write side.
.PP
If no data is available, a
.code read
on a pipe waits for either data to be written or all
file descriptors referring to the write end to be closed;
in the latter case,
.code read
will return 0, just as if the end of a data file had been reached.
The fact that
.code read
blocks until it is impossible for new data to arrive
is one reason that it's important for the child to
close the write end of the pipe
before executing
.code wc
above: if one of
.code wc 's
file descriptors referred to the write end of the pipe,
.code wc
would never see end-of-file.
.PP
The xv6 shell implements pipelines such as
.code "grep fork sh.c | wc -l"
in a manner similar to the above code
.line sh.c:/case.PIPE/ .
The child process creates a pipe to connect the left end of the pipeline
with the right end. Then it calls
.code fork
and
.code runcmd
for the left end of the pipeline
and 
.code fork
and
.code runcmd
for the right end, and waits for both to finish.
The right end of the pipeline may be a command that itself includes a
pipe (e.g.,
.code a
.code |
.code b
.code |
.code c) , 
which itself forks two new child processes (one for
.code b
and one for
.code c ).
Thus, the shell may
create a tree of processes.  The leaves of this tree are commands and
the interior nodes are processes that wait until the left and right
children complete.  In principle, you could have the interior nodes
run the left end of a pipeline, but doing so correctly would complicate the
implementation.
.PP
Pipes may seem no more powerful than temporary files:
the pipeline
.P1
echo hello world | wc
.P2
could be implemented without pipes as
.P1
echo hello world >/tmp/xyz; wc </tmp/xyz
.P2
Pipes have at least four advantages over temporary files
in this situation.
First, pipes automatically clean themselves up;
with the file redirection, a shell would have to
be careful to remove
.code /tmp/xyz
when done.
Second, pipes can pass arbitrarily long streams of
data, while file redirection requires enough free space
on disk to store all the data.
Third, pipes allow for parallel execution of pipeline stages,
while the file approach requires the first program to finish
before the second starts.
Fourth, if you are implementing inter-process communication,
pipes' blocking reads and writes are more efficient
than the non-blocking semantics of files.
.\"
.\"	File system
.\"
.section "File system"
.PP
The xv6 file system provides data files,
which are uninterpreted byte arrays,
and directories, which
contain named references to data files and other directories.
The directories form a tree, starting
at a special directory called the 
.italic-index root .
A 
.italic-index path 
like
.code /a/b/c
refers to the file or directory named
.code c
inside the directory named
.code b
inside the directory named
.code a
in the root directory
.code / .
Paths that don't begin with
.code /
are evaluated relative to the calling process's
.italic-index "current directory" ,
which can be changed with the
.code chdir
system call.
Both these code fragments open the same file
(assuming all the directories involved exist):
.P1
chdir("/a");
chdir("b");
open("c", O_RDONLY);

open("/a/b/c", O_RDONLY);
.P2
The first fragment changes the process's current directory to
.code /a/b ;
the second neither refers to nor changes the process's current directory.
.PP
.PP
There are multiple system calls to create a new file or directory:
.code mkdir
creates a new directory,
.code open
with the
.code O_CREATE
flag creates a new data file,
and
.code mknod
creates a new device file.
This example illustrates all three:
.P1
mkdir("/dir");
fd = open("/dir/file", O_CREATE|O_WRONLY);
close(fd);
mknod("/console", 1, 1);
.P2
.code Mknod
creates a file in the file system,
but the file has no contents.
Instead, the file's metadata marks it as a device file
and records the major and minor device numbers
(the two arguments to 
.code mknod ),
which uniquely identify a kernel device.
When a process later opens the file, the kernel
diverts
.code read
and
.code write
system calls to the kernel device implementation
instead of passing them to the file system.
.PP
.code fstat
retrieves information about the object a file
descriptor refers to.
It fills in a
.code struct
.code stat ,
defined in
.code stat.h
as:
.P1
.so ../xv6/stat.h
.P2
.PP
A file's name is distinct from the file itself;
the same underlying file, called an 
.italic-index inode , 
can have multiple names,
called 
.italic-index links .
The
.code link
system call creates another file system name 
referring to the same inode as an existing file.
This fragment creates a new file named both
.code a
and
.code b .
.P1
open("a", O_CREATE|O_WRONLY);
link("a", "b");
.P2
Reading from or writing to
.code a
is the same as reading from or writing to
.code b .
Each inode is identified by a unique
.italic inode
.italic number .
After the code sequence above, it is possible
to determine that
.code a
and
.code b
refer to the same underlying contents by inspecting the
result of 
.code fstat :
both will return the same inode number 
.code ino ), (
and the
.code nlink
count will be set to 2.
.PP
The
.code unlink
system call removes a name from the file system.
The file's inode and the disk space holding its content
are only freed when the file's link count is zero and
no file descriptors refer to it.
Thus adding
.P1
unlink("a");
.P2
to the last code sequence leaves the inode
and file content accessible as
.code b .
Furthermore,
.P1
fd = open("/tmp/xyz", O_CREATE|O_RDWR);
unlink("/tmp/xyz");
.P2
is an idiomatic way to create a temporary inode 
that will be cleaned up when the process closes 
.code fd
or exits.
.PP
Shell commands for file system operations are implemented
as user-level programs such as
.code mkdir ,
.code ln ,
.code rm ,
etc. This design allows anyone to extend the shell with new user commands by
just adding a new user-level program.  In hindsight this plan seems obvious,
but other systems designed at the time of Unix often built such commands into
the shell (and built the shell into the kernel).
.PP
One exception is
.code cd ,
which is built into the shell
.line sh.c:/if.buf.0..==..c./ .
.code cd
must change the current working directory of the
shell itself.  If
.code cd
were run as a regular command, then the shell would fork a child
process, the child process would run
.code cd ,
and
.code cd
would change the 
.italic child 's 
working directory.  The parent's (i.e.,
the shell's) working directory would not change.
.\"
.\"	Real world
.\"
.section "Real world"
.PP
Unix's combination of the ``standard'' file
descriptors, pipes, and convenient shell syntax for
operations on them was a major advance in writing
general-purpose reusable programs.
The idea sparked a whole culture of ``software tools'' that was
responsible for much of Unix's power and popularity,
and the shell was the first so-called ``scripting language.''
The Unix system call interface persists today in systems like
BSD, Linux, and Mac OS X.
.PP
The Unix system call interface has been standardized through the Portable
Operating System Interface (POSIX) standard.
Xv6 is
.italic not
POSIX compliant.  It misses system calls (including basic ones such as
.code lseek ),
it implements systems calls only partially, etc.  Our main goals for xv6 are
simplicity and clarity while providing a simple UNIX-like system-call interface.
Several people have extended xv6 with a few more basic system calls and a simple
C library so that they can run basic Unix programs.  Modern kernels, however,
provide many more system calls, and many more kinds of kernel services, than
xv6.  For example, they support networking, Window systems, user-level threads,
drivers for many devices, and so on.  Modern kernels evolve continuously and
rapidly, and offer many features beyond POSIX.
.PP
For the most part, modern Unix-derived operating systems
have not followed the early
Unix model of exposing devices as special files, like the
.code console
device file discussed above.
The authors of Unix went on to build Plan 9,
which applied the ``resources are files''
concept to modern facilities,
representing networks, graphics, and other resources
as files or file trees.
.PP
The file system abstraction has been a powerful
idea, most recently applied to network resources in the form of the
World Wide Web.
Even so, there are other models for operating system interfaces.
Multics, a predecessor of Unix,
abstracted file storage in a way that made it look like memory,
producing a very different flavor of interface.
The complexity of the Multics design had a direct influence
on the designers of Unix, who tried to build something simpler.
.ig
XXX can we cut this, since its point is the same as the next paragraph?
An operating system interface that went out of fashion
decades ago but has recently returned is the idea of a virtual machine monitor.
Such systems provide a superficially different interface from xv6,
but the basic concepts are still the same:
a virtual machine, like a process, consists of some memory and
one or more register sets;
the virtual machine has access to one large file called
a virtual disk instead of a file system;
virtual machines send messages to each other
and the outside world using virtual network devices
instead of pipes or files.
..
.PP
This book examines how xv6 implements its Unix-like interface,
but the ideas and concepts apply to more than just Unix.
Any operating system must multiplex processes onto
the underlying hardware, isolate processes from each
other, and provide mechanisms for controlled
inter-process communication.
After studying xv6, you should be able to
look at other, more complex operating systems
and see the concepts underlying xv6 in those systems as well.
