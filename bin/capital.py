#!/bin/python

import re
import sys

# look for uncapitalized xv6
regexsmall = re.compile(r'\.\s+(xv6)')

with open(sys.argv[1], 'r') as f:
    d = f.read()
    for w in re.findall(regexsmall, d):
        print("Error smallcaps %s: %s" % (sys.argv[1], w))

# look for capitalized code names (e.g., \lstinline{Exec}), but
# names that are all caps
regexbig = re.compile(r'\\(lstinline|indexcode){([A-Z][a-z]+[a-zA-Z_]+)')

with open(sys.argv[1], 'r') as f:
    line = f.readline()
    cnt = 1
    while line:
        for w in re.findall(regexbig, line):
            print("%s:%d: error: %s" % (sys.argv[1], cnt, w[1]))
        line = f.readline()
        cnt += 1
