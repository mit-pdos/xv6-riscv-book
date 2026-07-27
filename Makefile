SRC=xv6-riscv-src/

T=latex.out

TEX=$(patsubst %,$(T)/%,$(wildcard *.tex))
TIKZ_SVGS=$(patsubst fig/%.tex,fig/%.svg,$(wildcard fig/*.tex))
SPELLTEX=$(wildcard *.tex)
# Figure sources the book includes (\input for *.tex, \includegraphics for *.pdf)
FIGS=$(wildcard fig/*.tex) $(wildcard fig/*.pdf)

all: book.pdf xv6-src-booklet.pdf
.PHONY: all src clean

$(T)/%.tex: %.tex xv6-riscv-src-booklet/fmt | $(SRC)
	@mkdir -p $(@D)
	./lineref $(notdir $@) $(SRC)  xv6-riscv-src-booklet/fmt > $@

$(SRC):
	if [ ! -d $(SRC) ]; then \
		git clone https://github.com/mit-pdos/xv6-riscv.git $(SRC) ; \
	else \
		git -C $(SRC) pull ; \
	fi; \
	true

xv6-src-booklet.pdf xv6-riscv-src-booklet/fmt: $(SRC)
	(cd xv6-riscv-src-booklet; make)
	mv xv6-riscv-src-booklet/xv6-src-booklet.pdf .

book.pdf: book.tex $(TEX) $(FIGS)
	pdflatex book.tex
	bibtex book
	pdflatex book.tex
	pdflatex book.tex


lineref: $(TEX)
	@echo done

clean:
	rm -f book.aux book.idx book.ilg book.ind book.log\
	 	book.toc book.bbl book.blg book.out
	rm -rf latex.out
	rm -rf quarto.out
	rm -rf $(SRC)

spell:
	@ for i in $(SPELLTEX); do aspell --mode=tex -p ./aspell.words -c $$i; done
	@ for i in $(SPELLTEX); do perl bin/double.pl $$i; done
	@ for i in $(SPELLTEX); do perl bin/capital.py $$i; done
	@ ( head -1 aspell.words ; tail -n +2 aspell.words | sort ) > aspell.words~
	@ mv aspell.words~ aspell.words

fig/%.png: fig/%.svg
	inkscape -z --export-area-drawing --export-text-to-path --export-dpi=300 --export-filename=$@ $<

fig/%.svg: fig/%.tex
	./fig/tikz-to-svg.sh $(shell realpath $<) $@

quarto.out: $(TEX) $(TIKZ_SVGS)
	rm -rf quarto.out
	./convert-quarto.py
	ln -s ../fig quarto.out/
	cp _quarto.yml quarto.out/
	cp references.qmd quarto.out/
	cp coderef-panel.html quarto.out/
	cp sidebar-toc.html quarto.out/
	cp book.bib quarto.out/
	cp styles.css quarto.out/

html.out: quarto.out
	( cd quarto.out && quarto render )
