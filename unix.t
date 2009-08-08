.so book.mac
.chapter CH:UNIX "Operating system interfaces
.PP
Computers are simple machines of enormous complexity.
On the one hand, a processor can do very little: it just executes
a single instruction from memory and repeats, billions of times
per second.
On the other hand, the details of how it does this and how software
is expected to interact with the hardware vary wildly.
The job of an operating system is to address both of these problems.
An operating system creates the illusion of a simple machine that does
quite a bit for the programs that it runs.
It manages the low-level hardware, so that, for example,
a word processor need not concern itself with which video card
is being used.
It also multiplexes the hardware, allowing many programs
to share the computer and run (or appear to run) at the same time.
Finally, operating systems provide controlled ways for programs
to interact with each other, so that programs can share data or work together.
.PP
This description of an operating system does not say exactly what interface
the operating system provides to user programs.   Operating systems
researchers have experimented and continue to experiment with 
a variety of interfaces.
Although the interfaces differ from system to system, the basic ideas
and concepts are the same.
This book uses a single operating system as a concrete example to illustrate
those basic ideas and concepts.
That operating system, xv6, provides the basic interfaces
introduced by Ken Thompson and Dennis Ritchie's Unix operating system,
as well as mimicing Unix's internal design.
Many modern operating sytems—BSD, Linux, Mac OS X, Sun's Solaris,
and even, to a lesser extent, Microsoft's Windows—have Unix-like interfaces.
Understanding xv6 is a good start toward understanding any of these systems
and many others.
To illustrate the xv6 interface, this chapter examines the source code
of a user program, the shell, that uses most of it.
.PP
Xv6 takes the form of a
.italic kernel ,
a special program that provides
services to running programs.
Each running program, called a
.italic process ,
has memory containing
instructions, data, and a stack.
When a process needs to invoke a kernel service,
it makes a
.italic system
.italic call
to enter the kernel;
the kernel performs the service and returns.
Thus a process alternates between executing in
.italic user
.italic space
and
.italic kernel
.italic space .
.PP
The kernel uses the cpu's hardware protection mechanisms to
ensure that each process executing in user space can only access
its own memory.
The kernel executes with the hardware privileges required to
implement these protections; user programs execute without
those privileges.
When the user programs invokes a system call, the hardware
raises the privilege level and starts executing a pre-arranged
function in the kernel.
Chapter \*[CH:TRAP] examines this sequence in more detail.
.PP
The collection of system calls that a kernel provides
is the interface that user programs see.
The xv6 kernel provides a subset of the services and system calls
that Unix kernels traditionally offer.
The rest of this chapter outlines xv6's services—\c
processes, memory, file descriptors, pipes, and a file system—\c
and illustrate these services with code from the shell.
.PP
The shell is an ordinary program that
reads commands from the user
and executes them.
It is the main interactive way that users use traditional Unix-like systems.
The fact that the shell is a user program, not part of the kernel, means
that it is easily replaced.  In fact, modern Unix systems have a variety of
shells to choose from, each with its own syntax and semantics.
The xv6 shell is a simple implementation of the essence of
the Unix Bourne shell.
.\"
.\"	Processes and memory
.\"
.section "Code: Processes and memory
.PP
An xv6 process consists of user-space memory (instructions, data, and stack)
along with some state inside the kernel.
Xv6 provides time-sharing: it transparently switches the available CPUs
among the set of processes waiting to execute.
When a process is not executing, xv6 saves its CPU registers,
restoring them when it next runs the process.
Each process has a unique numeric non-zero process identifier, or
.italic pid .
.PP
One process may create another using the
.code fork
system call.
.code Fork
creates a new process, called the child, with exactly the same memory contents
as the calling process, called the parent.
.code Fork
returns in both the parent and the child.
In the parent,
.code fork
returns the child's pid;
in the child, it returns zero.
For example, consider the following program fragment:
.P1
int pid;

pid = fork();
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
.code exit
system call causes the calling process to exit (stop executing).
The
.code wait
system call waits for one of the calling process's children to exit
and returns the pid of the child that exited.
In the example, the output lines
.P1
parent: child=1234
child: exiting
.P2
might come out in either order, depending on whether the
parent or child gets to its
.code printf
call first.
After those two, the child exits, and then the parent's
.code wait
returns, causing the parent to print
.P1
parent: child 1234 is done
.P2
Note that the parent and child were executing with
different memory and different registers:
changing a variable in the parent does not affect the
same variable in the child, nor does the child affect the parent.
The main form of direct communication between parent and child 
.code wait
and
.code exit .
.PP
The
.code exec
system call
replaces the calling process's memory with a new memory
image loaded from an ELF-format executable stored in the file system.
If all goes well,
.code exec
does not return to the calling program;
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
.code /bin/hello
running with the argument list
.code echo
.code hello .
(Most programs ignore the first argument, which is 
conventionally the name of the program.)
.PP
Xv6 allocates most user-space memory
implicitly:
.code fork
allocates the memory required for the child's copy of the
parent's memory, and 
.code exec
allocates enough memory to hold the executable file.
A process that needs more memory at run-time (perhaps for
.code malloc )
can call
.code sbrk(n)
to grow its data memory by
.code n
bytes;
.code sbrk
returns the location of the new memory.
.PP
Xv6 does not provide a notion of users or of protecting
one user from another; in Unix terms, all xv6 processes
run as root.
.\"
.\"	File descriptors
.\"
.section "Code: File descriptors
.PP
A file descriptor is a small integer representing a kernel-managed object
that a process may read from or write to.
That object may be a data file, a directory, a pipe, or the console.
It is conventional to call whatever object a file
descriptor refers to a file.
Internally, the xv6 kernel uses the file descriptor
as an index into a per-process table,
so that every process has a private space of file descriptors
starting at zero.
By convention, a process reads from file descriptor 0 (standard input),
writes output to file descriptor 1 (standard output), and
writes error messages to file descriptor 2 (standard error).
The shell exploits the convention to implement I/O redirection
and pipelines.
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
bytes from the open file corresponding to the file descriptor
.code fd ,
copies them into
.code buf ,
and returns the number of bytes copied.
Every file descriptor has an offset associated with it.
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
to the open file named by the file descriptor
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
The following program fragment copies data from its standard input
to its standard output.  If an error occurs, it writes a message
on standard error.
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
The kernel always allocates the lowest-numbered
file descriptor that is unused by the calling process.
.PP
.code Fork
copies the parent's file descriptor table along with its memory,
so that the child starts with exactly the same open files as the parent.
.code Exec
replaces the calling process's memory but preserves its file table.
This behavior allows the shell to
implement I/O redirection by forking, reopening chosen file descriptors,
and then execing the new program.
Here is a simplified version of the code a shell runs for the
command
.code cat
.code <input.txt :
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
open is guaranteed to use that file descriptor
for the newly opened
.code input.txt :
0 will be the smallest available file descriptor.
.code Cat
then executes with file descriptor 0 referring to
.code input.txt .
.PP
Although
.code fork
copies the file descriptor table, each underlying file offset is shared
between parent and child.
Consider this example:
.P1
if(fork() == 0) {
  write(1, "hello ");
  exit();
} else {
  wait();
  write(1, "world\en");
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
This behavior helps produce useful results from sequences
of shell commands, like
.code (echo
.code hello;
.code echo
.code world)
.code >output.txt .
.PP
The
.code dup
system call duplicates an existing file descriptor onto a new one.
Both file descriptors share an offset, just as the file descriptors
duplicated by
.code fork
do.
This is another way to write
.code hello
.code world
into a file:
.P1
close(2);
dup(1);  // uses 2, assuming 0 is not available
write(1, "hello ");
write(2, "world\en");
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
.PP
File descriptors are a powerful abstraction,
because they hide the details of what they are connected to:
a process writing to file descriptor 1 may be writing to a
file, to a device like the console, or to a pipe.
.\"
.\"	Pipes
.\"
.section "Code: Pipes
.PP
A pipe is a small kernel buffer exposed to processes as a pair of
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
  write(p[1], "hello world\en", 12);
  close(p[0]);
  close(p[1]);
}
.P2
The program calls
.code pipe
to create a new pipe and record the read and write
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
The parent writes to the write end of the pipe
and then closes both of its file descriptors.
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
Pipes may seem no more powerful than temporary files:
the pipeline
.P1
echo hello world | wc
.P2
could also be implemented without pipes as
.P1
echo hello world >/tmp/xyz; wc </tmp/xyz
.P2
There are at least three key differences between
pipes and temporary files.
First, pipes automatically clean themselves up;
with the file redirection, a shell would have to
be careful to remove
.code /tmp/xyz
when done.
Second, pipes can pass arbitrarily long streams of
data, while file redirection requires enough free space
on disk to store all the data.
Third, pipes allow for synchronization:
two processes can use a pair of pipes to
send messages back and forth to each other,
with each
.code read
blocking its calling process until the other process has
sent data with
.code write .
.\"
.\"	File system
.\"
.section "Code: File system
.PP
Xv6 provides data files,
which are uninterpreted byte streams,
and directories, which
contain references to other data files and directories.
Xv6 implements directories as a special kind of file.
The directories are arranged into a tree, starting
at a special directory called the root.
A path like
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
.italic current
.italic directory ,
which can be changed with the
.code chdir
system call.
Both these code fragments open the same file:
.P1
chdir("/a");
chdir("b");
open("c", O_RDONLY);

open("/a/b/c", O_RDONLY);
.P2
The first changes the process's current directory to
.code /a/b ;
the second neither refers to nor modifies the process's current directory.
.PP
The
.code open
system call evalutes the path name of an existing file or directory
and prepares that file for I/O by the calling process.
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
The arguments to 
.code mknod
are the major and minor device number,
which uniquely identify the desired device to the kernel.
[TODO: Throw away minor device number?]
.PP
.code Mknod
creates a file in the file system,
but the file has no contents.
Instead, the file's metadata marks it as a device file
and records the major and minor device numbers.
When a process later opens the file, the kernel
diverts
.code read
and
.code write
system calls to the kernel device implementation
instead of passing them through to the file system.
.PP
The
.code fstat
system call queries an open file descriptor to find out
what kind of file it is.
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
In xv6, a file's name is separated from its content;
the same content, called an inode, can have multiple names,
called links.
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
Each inode is identified by a unique number, which
.code fstat
includes in the
.code stat
information.
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
field will be set to 2, 
.PP
The
.code unlink
system call removes a name from the file system,
but not necessarily the underlying inode.
Adding
.P1
unlink("a");
.P2
to the last code sequence will not remove the inode,
because it is still accessible as
.code b .
In fact, in order to remove or reuse an inode,
xv6 requires not only that all its names have been unlinked
but also that there are no file descriptors referring to it.
Thus,
.P1
fd = open("/tmp/xyz", O_CREATE|O_RDWR);
unlink("/tmp/xyz");
.P2
is an idiomatic way to create a temporary inode 
that will be cleaned up when the process closes 
.code fd
or exits.
.\"
.\"	Real world
.\"
.section "Real world
.PP
It is difficult today to remember that Unix's combination of the ``standard'' file
descriptors, pipes, and convenient syntax in the shell for
both redirection and pipes was a major advance in writing
general-purpose reusable programs.
The idea sparked a whole culture of ``software tools'' that was
responsible for much of Unix's power and popularity,
and the shell was the first so-called ``scripting language.''
The Unix system call interface persists in other Unix-like systems,
like today's BSD, Linux, and Mac OS X.
.PP
Xv6, like Unix before it, has a very simple interface.
It doesn't implement modern features like networking
or computer graphics.  The various Unix derivatives have
many more system calls, especially in those newer areas.
Unix's early devices, such as terminals, are modeled as 
special files, like the
.code console
device file discussed above.
The authors of Unix went on to build Plan 9,
which applied the ``resources are files''
concept to even these modern facilities,
representing networks, graphics, and other resources
as files or file trees.
.PP
The file system as an interface has been a very powerful
idea, most recently applied to network resources in the form of the
World Wide Web.
Even so, there are other models for operating system interfaces.
Multics, a predecessor of Unix, blurred the distinction
between data in memory and data on disk, producing
a very different flavor of interface.
The complexity of the Multics design had a direct influence
on the designers of Unix, who tried to build something simpler.
.PP
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
.PP
This book examines how xv6 implements its Unix-like interface,
but the ideas and concepts apply to more than just Unix.
Any operating system must multiplex processes onto
the underlying hardware, isolate processes from each
other, and provide mechanisms for controlled
inter-process communication.
After studying this book, you should be able to
look at other, more complex operating systems
and see the concepts underlying xv6 in those systems as well.
