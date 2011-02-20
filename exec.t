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
The user memory image of an executing process looks like:
.P1
      _________
640K: |       |
      | ...   |
      | heap  |
      | stack |
      | data  |
0:    | text  |
      ---------
.P2
The heap is above the stack so that it can expand (with
.code sbrk ).
The stack is a single page—4096 bytes—long.
Strings containing the command-line arguments, as well as an
array of pointers to them, are at the very top of the stack.
Just under that the kernel places values that allow a program
to start at
.code main
as if the function call
.code main(argc,
.code argv)
had just started.
Here are the values that
.code exec
places at the top of the stack:
.P1
"argument0"
 ...
"argumentN"                      -- nul-terminated string
0                                -- argv[argc]
address of argumentN             
 ...
address of argument0             -- argv[0]
address of address of argument0  -- argv argument to main()
argc                             -- argc argument to main()
0xffffffff                       -- return PC for main() call
.P2
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
.line syscall.c:/static.int...syscalls/ .
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
Then it allocates a new page table with no user mappings with
.code setupkvm
.line exec.c:/setupkvm/ ,
allocates memory for each ELF segment with
.code allocuvm
.line exec.c:/allocuvm/ ,
and loads each segment into memory with
.code loaduvm
.line exec.c:/loaduvm/ .
.code allocuvm
checks that the virtual addresses requested
are within the 640 kilobytes that user processes are allowed to use.
.code loaduvm
.line vm.c:/^loaduvm/
uses
.code walkpgdir
to find the physical address of the allocated memory at which to write
each page of the ELF segment, and
.code readi
to read from the file.
The ELF file may contain data segments that contain
global variables that should start out zero, represented with a
.code memsz
that is greater than the segment's
.code filesz ;
the result is that 
.code allocuvm
allocates zeroed physical memory, but
.code loaduvm
does not copy anything from the file.
.PP
Now
.code exec
allocates and initializes the user stack.
It assumes that one page of stack is enough.
If not,
.code copyout
will return \-1, as will 
.code exec .
.code Exec
first copies the argument strings to the top of the stack
one at a time, recording the pointers to them in 
.code ustack .
It places a null pointer at the end of what will be the
.code argv
list passed to
.code main .
The first three entries in 
.code ustack
are the fake return PC,
.code argc ,
and
.code argv
pointer.
.PP
During the preparation of the new memory image,
if 
.code exec
detects an error like an invalid program segment,
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
can install the new image
.line exec.c:/switchuvm/
and free the old one
.line exec.c:/freevm/ .
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
