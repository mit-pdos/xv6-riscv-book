SRC=xv6-riscv-src/

T=latex.out

TEX=\
	$(T)/acks.tex\
	$(T)/unix.tex\
	$(T)/first.tex\
	$(T)/mem.tex\
	$(T)/trap.tex\
	$(T)/lock.tex\
	$(T)/sched.tex\
	$(T)/fs.tex\
	$(T)/sum.tex\

all: book.pdf
.PHONY: all

$(T)/%.tex: %.tex
	mkdir -p latex.out
	./lineref $(notdir $@) $(SRC) > $@

src:
	if [ ! -d $(SRC) ]; then \
		git clone git@github.com:kaashoek/xv6-risc-v.git $(SRC) ; \
	fi; \
	cd $(SRC); git pull; true

book.pdf: book.tex $(TEX) src
	pdflatex book.tex
	bibtex book
	pdflatex book.tex
	pdflatex book.tex

clean:
	rm -f book.aux book.idx book.ilg book.ind book.log\
	 	book.toc book.bbl book.blg book.out
	rm -rf latex.out
	rm -rf $(SRC)

