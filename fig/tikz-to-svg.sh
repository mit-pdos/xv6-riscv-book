#!/bin/bash

if [ ! -e "$1" -o "$2" = "" ]; then
  echo "Usage: $0 /absolute/path/to/input.tex output.svg"
  exit 1
fi

TMP=$(mktemp -d)
trap "rm $TMP/convert.* && rmdir $TMP" 0

cat > $TMP/convert.tex <<EOF
\\documentclass[border=4pt]{standalone}
\\usepackage{tikz}\\usepackage{listings}\\usepackage{xcolor}
\\usetikzlibrary{arrows,positioning}
\\lstset{basicstyle=\\small\\ttfamily}
\\lstset{escapeinside={(*@}{@*)}}
\\begin{document}\\input{$1}\\end{document}
EOF

( cd $TMP && pdflatex -interaction=nonstopmode -halt-on-error convert.tex >/dev/null )
pdf2svg $TMP/convert.pdf $2
