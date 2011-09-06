.chapterlike "Contents
.ds CF "
.ds RF "
.ds LF "
.nr PS 14
.PS
.in +1i
.ad l
.de TOC
.ll 5i
.ad l
.if !'\\$1'' \\$1\\h'|0.25i'\c
.ie !'\\$1'' \T'toc-\\$1'\\$3\T
.el \T'toc-\\$3'\\$3\T
.sp -1
.ad r
\s-2\fI\\$2\fR\s+2
.sp
..
.so contents1.t
