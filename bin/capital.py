#!/bin/python

import re
import sys

regex = re.compile('\.\s+([a-z]+[a-zA-Z0-9]+)')

with open(sys.argv[1], 'r') as f:
    line = f.readline()
    cnt = 1
    while line:
        for w in re.findall(regex, line):
            print("%s:%d %s" % (sys.argv[1], cnt, w))
        line = f.readline()
        cnt += 1
