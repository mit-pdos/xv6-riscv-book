PDF=\
	unix.pdf\
	boot.pdf\
	disk.pdf\

all: $(PDF)

%.ps: %.t book.mac
	./run1 $*.t > $@ || rm -f $@

%.pdf: %.ps
	ps2pdf $*.ps


push: index.html $(PDF)
	scp $^ am.lcs.mit.edu:~rsc/public_html/xv6book

