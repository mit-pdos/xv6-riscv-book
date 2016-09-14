.F1
.TS
center ;
lB lB
l l .
Lock	Description
bcache.lock	Serializes allocation of a struct buffer in buf cache
console.lock	Serializes several cores writing to console and interrupts
ftable.lock	Serializes allocation of a struct file in file table
icache.lock	Serializes allocation of a struct inode in inode cache
idelock	Serializes operations on disk queue
kmem.lock	Serializes allocation of memory
log.lock	Serializes operations on the transaction log
pipe lock	Serializes operations on a pipe
ptable.lock	Serializes context switching, and operations on proc->state and proctable
tickslock	Serializes operations on ticks.
sleeplocks	Serializes operations on blocks in the buffer cache and inodes
.TE
.F2
Locks in xv6
.F3
