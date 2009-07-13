PDF=\
	unix.pdf\
	boot.pdf\
	mem.pdf\
	trap.pdf\
	lock.pdf\
	sched.pdf\
	disk.pdf\
	fsdata.pdf\
	fscall.pdf\
	exec.pdf\

all: $(PDF)

%.ps: %.t book.mac line xv6-code.pdf
	./run1 $*.t > $@ || rm -f $@

%.pdf: %.ps
	ps2pdf $*.ps $*.pdf

clean:
	rm -f $(PDF) *.ps

xv6-code.pdf: ../xv6/xv6.pdf
	cp $^ $@

push: index.html $(PDF) xv6-code.pdf
	scp $^ am.lcs.mit.edu:~rsc/public_html/xv6-book

