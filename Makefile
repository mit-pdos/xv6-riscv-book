CONTENTS=\
	unix\
	boot\
	mem\
	trap\
	lock\
	sched\
	disk\
	fsdata\
	fscrash\
	fscall\
	index\

ORDER=\
	title\
	contents\
	acks\
	$(CONTENTS)\

SCRIPTS=\
	run1\
	twopage\
	savelast\
	figures\
	runfig\

PS=$(patsubst %,%.ps,$(ORDER))
PDF=$(patsubst %,%.pdf,$(ORDER))
DIT=$(patsubst %,%.dit,$(ORDER))

all: book.pdf
pdf: $(PDF)
ps: $(PS)
dit: $(DIT)
.PHONY: all pdf ps dit

book.ps: $(DIT)
	/usr/ucb/dpost $(DIT) >book.ps || rm -f book.ps

%.dit: book.mac %.t z.%.first $(SCRIPTS)
	./run1 $*

%.ps: %.dit
	/usr/ucb/dpost $*.dit >$*.ps || rm -f $*.ps

%.pdf: %.ps
	ps2pdf $*.ps $*.pdf

clean:
	rm -f $(PS) $(PDF) $(DIT) z.* contents.t

xv6-code.pdf: ../xv6/xv6.pdf
	cp $^ $@

include $(shell ./make-pageorder $(ORDER))

contents.dit: contents0.t

contents.t: mkcontents $(patsubst %,%.t,$(CONTENTS)) $(patsubst %,z.%.first,$(CONTENTS))
	./mkcontents $(CONTENTS) >$@ || rm -f $@

bootstrap: $(patsubst %,z.%.first,$(ORDER))
