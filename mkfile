GS_FONTPATH=$HOME/plan9/4e/sys/lib/postscript/font:$HOME/lib/postscript:$PLAN9/postscript/font
TROFFONTS=.:$HOME/font/Adobe/TypeClassics/MinionPro:$HOME/font/BellLabs:$HOME/font/Adobe/TypeClassics/AdobeCaslonPro

tfiles=`{ls *.t}
base=${tfiles:%.t=%}
pdf=${base:%=%.pdf}

all:V: $pdf

%.ps:D: %.t book.mac
	/usr/ucb/tbl $stem.t | /usr/ucb/troff | /usr/ucb/dpost > $stem.ps

%.pdf:D: %.ps
	ps2pdf $stem.ps $stem.pdf

PUSH=\
	boot.pdf\
	disk.pdf\
	index.html

push: $PUSH
	scp $PUSH am.lcs.mit.edu:~rsc/public_html/xv6book

