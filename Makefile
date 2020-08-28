SRC=xv6-riscv-src/

T=latex.out

TEX=\
	$(T)/acks.tex\
	$(T)/unix.tex\
	$(T)/first.tex\
	$(T)/mem.tex\
	$(T)/trap.tex\
	$(T)/interrupt.tex\
	$(T)/lock.tex\
	$(T)/sched.tex\
	$(T)/fs.tex\
	$(T)/lock2.tex\
	$(T)/sum.tex\

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

