#!/usr/bin/perl

# Detects duplicated words even when they are
# are repeated between lines.
# Taken from the ORA regex book

$/ = ".\n";
while (<>) {
    next if !s/\b([a-z]+)((\s|<[^>]+>)+)(\1\b)/\e[7m$1\e[m$2\e[7m$4\e[m/ig;
								      
    s/^([^\e]*\n)+//mg;
    s/^/$ARGV: /mg;
    print;
}

# also test for things like
# [^\w+]a\w+[aeiou] and [^\w+]an\w+[!aeiou]
