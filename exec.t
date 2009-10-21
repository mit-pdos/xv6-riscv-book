.so book.mac
.chapter CH:EXEC "Exec"
.PP
Chapter \*[CH:MEM] stopped with the 
.code initproc
invoking the kernel's
.code exec
system call.  
As a result, we took detours into interrupts,
multiprocessing, device drivers, and a file system.
With these taken care of, we can finally look at
the implementation of 
.code exec .
As we saw in Chapter \*[CH:UNIX], 
.code exec
replaces the memory and registers of the
current process with a new program, but it leaves the
file descriptors, process id, and parent process the same.
.code Exec
is thus little more than a binary loader, just like the one 
in the boot sector from Chapter \*[CH:BOOT].
The additional complexity comes from setting up the stack.
The memory image of an executing process looks like:
.P1
[XXX better picture: not ASCII art,
show individual argv pointers, show argc, 
show argument strings, show fake return address.]

+---------------------------------------+
| text | data | stack | args | heap ... |
+---------------------------------------+
                      ^
                      |
                  initial sp
.P2
In xv6, the stack is a single page—4096 bytes—long.
The command-line arguments follow the stack immediately
in memory, so that the program can start at
.code main
as if the function call
.code main(argc,
.code argv)
had just started.
The heap comes last so that expanding it does not require
moving any of the other sections.
.\"
.section "Code"
.\"
When the system call arrives,
.code syscall
invokes
.code sys_exec
via the 
.code syscalls
table
.line syscall.c:/syscalls.num/ .
.code Sys_exec
.line sysfile.c:/^sys_exec/
parses the system call arguments,
as we saw in Chapter \*[CH:TRAP],
and invokes
.code exec
.line sysfile.c:/exec.path/ .
.PP
.code Exec
.line exec.c:/^exec/
opens the named binary 
.code path
using
.code namei
.line exec.c:/namei/
and then reads the ELF header.
Like the boot sector, it uses
.code elf.magic
to decide whether the binary is an ELF binary
.line exec.c:/Check.ELF/,/ELF_MAGIC/+1 .
Then it makes two passes through the program segment
and argument lists.  The first computes the total amount
of memory needed, and the second creates the memory image.
The total memory size includes
the program segments
.lines exec.c:/Program.segments/,/}/ ,
the argument strings
.lines exec.c:/Arguments/,/sz.!+=.arglen/ ,
the argument vector pointed at by
.code argv
.line exec.c:/argv.data/ ,
the
.code argv
and
.code argc 
arguments to
.code main
.line exec.c:/4.*argv/,/argc/ ,
and the stack
.line exec.c:/Stack/,/./ .
.code Exec
then allocates and zeros the required amount of memory
.lines exec.c:/Allocate/,/memset/
and copies the data into the new memory image:
the program segments
.lines exec.c:/Load/,/iunlockput/ ,
the argument strings and pointers
.lines exec.c:/Initialize.stack/,/}/ ,
and
the stack frame for
.code main
.lines exec.c:/Stack.frame.for.main/,/fake/ .
.PP
Notice that when
.code exec
copies the program segments,
it makes sure that the data
being loaded into memory fits in the declared size
.code ph.memsz
.lines "'exec.c:/ph.va !+ ph.memsz < ph.va/,/goto/'" .
Without this check, a malformed ELF binary
could cause 
.code exec
to write past the end of the allocated memory image,
causing memory corruption and making the operating system unstable.
The boot sector neglected this check both to reduce
code size and because not checking doesn't change
the failure mode: either way the machine doesn't
boot if given a bad ELF image.
In contrast, in
.code exec
this check is the difference between making
one process fail 
and making the entire system fail.
.PP
During the preparation of the new memory image,
if 
.code exec
detected an error like an invalid program segment,
it jumps to the label
.code bad ,
frees the new image,
and returns \-1.
.code Exec
must wait to free the old image until it 
is sure that the system call will succeed:
if the old image is gone,
the system call cannot return \-1 to it.
The only error cases in
.code exec
happen during the creation of the image.
Once the image is complete, 
.code exec
can free the old image and install the new one
.line exec.c:/kfree/,/esp.=.sp/ .
After changing the image,
.code exec
must update the user segment registers to
refer to the new image, just as
.code sbrk
did
.line exec.c:/usegment/ .
Finally,
.code exec
returns 0.
Success!
.PP
Now the
.code initcode
.line initcode.S:1
is done.
.code Exec
has replaced it with the real
.code /init
binary, loaded out of the file system.
.code Init
.line init.c:/^main/
creates a new console device file
if needed
and then opens it as file descriptors 0, 1, and 2.
Then it loops,
starting a console shell, 
handles orphaned zombies until the shell exits,
and repeats.
The system is up.
.\"
.section "Real world"
.\"
.code Exec
is the most complicated code in xv6 in and in most operating systems.
It involves pointer translation
(in
.code sys_exec
too),
many error cases, and must replace one running process
with another.
Real world operationg systems have even more complicated
.code exec 
implementations.
They handle shell scripts (see exercise below),
more complicated ELF binaries, and even multiple
binary formats.
.PP
.ig
some kind of send-off, in lieu of a conclusion chapter?
..
.\"
.section "Exercises"
.\"
1. Unix implementations of 
.code exec
traditionally include special handling for shell scripts.
If the file to execute begins with the text
.code #! ,
then the first line is taken to be a program
to run to interpret the file.
For example, if
.code exec
is called to run
.code myprog
.code arg1
and
.code myprog 's
first line is
.code #!/interp ,
then 
.code exec
runs
.code /interp
with command line
.code /interp
.code myprog
.code arg1 .
Implement support for this convention in xv6.
