CONTENTS_INDEXED=\
	unix\
	mem\
	trap\
	lock\
	sched\
	fs\
	apphw\
	appboot\

CONTENTS=\
	$(CONTENTS_INDEXED)\
	index\

ORDER_INDEXED=\
	title\
	contents\
	acks\

ORDER=\
	$(ORDER_INDEXED)\
	$(CONTENTS)\

INDEXED=\
	$(ORDER_INDEXED)\
	$(CONTENTS_INDEXED)\

SCRIPTS=\
	run1\
	twopage\
	savelast\
	figures\
	runfig\
	ditspaces\

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
	rm -f $(PS) $(PDF) $(DIT) z.*

xv6-code.pdf: ../xv6/xv6.pdf
	cp $^ $@

include $(shell ./make-pageorder $(ORDER))
include $(shell ./make-figdeps $(ORDER))

contents.dit: contents1.t
index.dit: index1.t

contents1.t: mkcontents $(patsubst %,%.t,$(CONTENTS)) $(patsubst %,z.%.first,$(CONTENTS))
	./mkcontents $(CONTENTS) >$@ || rm -f $@

INDEXED_DIT=$(patsubst %,%.dit,$(INDEXED))
index1.t: mkindex $(INDEXED_DIT)
	./mkindex $(INDEXED_DIT) >$@ || rm -f $@

bootstrap: $(patsubst %,z.%.first,$(ORDER))
