SRC=xv6-riscv-src/

T=latex.out

TEX=$(wildcard $(T)/*.tex)
SPELLTEX=$(wildcard *.tex)

all: book.pdf
.PHONY: all src clean

$(T)/%.tex: %.tex | src
	mkdir -p latex.out
	./lineref $(notdir $@) $(SRC) > $@

src:
	if [ ! -d $(SRC) ]; then \
		git clone git@github.com:mit-pdos/xv6-riscv.git $(SRC) ; \
	else \
		git -C $(SRC) pull ; \
	fi; \
	true

book.pdf: src book.tex $(TEX)
	pdflatex book.tex
	bibtex book
	pdflatex book.tex
	pdflatex book.tex

clean:
	rm -f book.aux book.idx book.ilg book.ind book.log\
	 	book.toc book.bbl book.blg book.out
	rm -rf latex.out
	rm -rf $(SRC)

spell:
	@ for i in $(SPELLTEX); do aspell --mode=tex -p ./aspell.words -c $$i; done
	@ for i in $(SPELLTEX); do perl bin/double.pl $$i; done
	@ for i in $(SPELLTEX); do perl bin/capital.py $$i; done
	@ ( head -1 aspell.words ; tail -n +2 aspell.words | sort ) > aspell.words~
	@ mv aspell.words~ aspell.words
