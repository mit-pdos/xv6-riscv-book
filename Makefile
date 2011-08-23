PDF=\
	unix.pdf\
	boot.pdf\
	mem.pdf\
	trap.pdf\
	lock.pdf\
	sched.pdf\
	disk.pdf\
	fsdata.pdf\
        fscrash.pdf\
	fscall.pdf\

all: $(PDF)


%.ps: %.t book.mac line
	./run1 $*.t > $@ || rm -f $@

%.pdf: %.ps
	ps2pdf $*.ps $*.pdf

clean:
	rm -f $(PDF) *.ps

xv6-code.pdf: ../xv6/xv6.pdf
	cp $^ $@

