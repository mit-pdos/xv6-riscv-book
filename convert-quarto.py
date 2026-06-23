#!/usr/bin/env python3
"""Convert the xv6 LaTeX book (latex.out/*.tex) into a Quarto book (per-chapter .qmd).

Strategy:
  1. Preprocess each chapter: pull out lstlisting blocks (computing line-label
     numbers exactly as LaTeX would), strip \\index, expand a few custom macros,
     and rewrite figure includes to the web SVG assets.
  2. Concatenate all chapters into one standalone LaTeX document so that a single
     pandoc run resolves every \\ref (chapters, sections, figures) to its number.
  3. Split pandoc's markdown back into per-chapter files, retarget cross-page
     anchor links, and splice the cleaned code listings back in.
"""
import re, subprocess, os, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(ROOT, "latex.out")
OUT  = os.path.join(ROOT, "quarto.out")
GH   = "https://github.com/mit-pdos/xv6-riscv/blob/riscv/"

def basename(path):
    return path.rsplit('/', 1)[-1]

# chapter tex basename -> output qmd basename (book.tex order)
CHAPTERS = ["acks","unix","first","mem","trap","pgfault","interrupt",
            "lock","sched","sleep","fs","lock2","sum"]
QMD = {"acks":"index"}   # acks becomes the book landing page

# ---------------------------------------------------------------------------
# Listing handling
# ---------------------------------------------------------------------------
linemap = {}            # line:label -> line number (global; labels are unique)
listings = []           # collected code blocks, referenced by placeholder index
inlines  = []           # collected inline-code snippets (verbatim)

def take_inline(text):
    idx = len(inlines)
    inlines.append(text)
    return "ZZICODE%dZZ" % idx

def clean_escape(inner):
    """Resolve a (*@ ... @*) listings escape into plain code text.

    These escapes carry line \\label{}s, \\hl{} highlights, and \\textcolor{}{}
    around fragments of code; unwrap them in place, keeping any surrounding text.
    """
    inner = re.sub(r'\\label\{[^}]*\}', '', inner)
    inner = re.sub(r'\\hl\{((?:[^{}]|\{[^{}]*\})*)\}', r'\1', inner)
    inner = re.sub(r'\\textcolor\{[^}]*\}\{((?:[^{}]|\{[^{}]*\})*)\}', r'\1', inner)
    return inner

def take_listing(m):
    opts = m.group(1) or ''
    body = m.group(2)
    first = 1
    mo = re.search(r'firstnumber=(\d+)', opts)
    if mo: first = int(mo.group(1))
    raw = body.split('\n')
    # drop the single newline artifact right after \begin{lstlisting}
    if raw and raw[0].strip() == '':
        raw = raw[1:]
    if raw and raw[-1].strip() == '':
        raw = raw[:-1]
    has_label = False
    out = []
    n = first
    for ln in raw:
        for lbl in re.findall(r'\(\*@\\label\{(line:[^}]*)\}@\*\)', ln):
            linemap[lbl] = n
            has_label = True
        ln = re.sub(r'\(\*@(.*?)@\*\)', lambda mm: clean_escape(mm.group(1)), ln)
        ln = ln.replace('\\&', '&').replace('\\%', '%').replace('\\#', '#')
        out.append(ln.rstrip())
        n += 1
    numbered = ('numbers=left' in opts) or has_label
    idx = len(listings)
    listings.append({'code': '\n'.join(out), 'numbered': numbered, 'start': first})
    return f"\n\nZZLSTBLOCK{idx}ZZ\n\n"

# ---------------------------------------------------------------------------
# Code references -> hyperlinks
# ---------------------------------------------------------------------------
# A resolved reference macro is one of:
#   \showfileref{path}{booklet}             -> a whole file
#   \showlineref{path}{line}{booklet}       -> one line
#   \showlinerefs{path}{s}{e}{bs}{be}       -> a line range
# The GitHub blob URL is built from path (+ #Lline[-Lend]); the booklet number(s)
# are the old visible link text and are discarded by code_refs() below.

# An inline-code identifier sitting immediately before a reference, in the LaTeX
# form it still has at this point (\lstinline/\indexcode are not yet placeholders).
TOKEN = (r'(?:\\lstinline\{[^}]*\}|\\lstinline![^!]*!|\\indexcode\{[^}]*\}'
         r'|\\texttt\{[^{}]*\}|\{\\tt\s+[^{}]*\})')

def _url(path, a=None, b=None):
    u = GH + path
    if a is not None:
        u += r'\#L' + a + (('-L' + b) if b is not None else '')
    return u

def code_refs(tex):
    """Turn each resolved reference into a GitHub hyperlink.

    When the reference is glued to a code identifier in the prose (a function,
    struct, or file name -- the book always writes the name right before its
    reference), the identifier itself becomes the link, e.g. "[`kfork`]".
    Otherwise there is no name to anchor on, so the link text is the source
    location "(basename:line)", e.g. "(proc.c:260)".

    Must run before \\lstinline/\\indexcode are turned into placeholders, so the
    preceding identifier is still in its LaTeX form and can be wrapped."""
    # drop LaTeX grouping braces around a reference (e.g. "{\showlineref{..}{..}{..}}")
    # so the macro sits directly after the identifier the prose just used.
    tex = re.sub(r'\{(\\show(?:line|file)refs?(?:\{[^}]*\})+)\}', r'\1', tex)
    # 1. reference glued to a code identifier -> wrap that identifier
    tex = re.sub(r'(?P<t>' + TOKEN + r')[~\s]*\\showlineref\{(?P<p>[^}]*)\}\{(?P<l>[^}]*)\}\{[^}]*\}',
                 lambda m: r'\href{%s}{%s}' % (_url(m['p'], m['l']), m['t']), tex)
    tex = re.sub(r'(?P<t>' + TOKEN + r')[~\s]*\\showlinerefs\{(?P<p>[^}]*)\}\{(?P<s>[^}]*)\}\{(?P<e>[^}]*)\}\{[^}]*\}\{[^}]*\}',
                 lambda m: r'\href{%s}{%s}' % (_url(m['p'], m['s'], m['e']), m['t']), tex)
    tex = re.sub(r'(?P<t>' + TOKEN + r')[~\s]*\\showfileref\{(?P<p>[^}]*)\}\{[^}]*\}',
                 lambda m: r'\href{%s}{%s}' % (_url(m['p']), m['t']), tex)
    # 2. otherwise -> "(basename:line)" file:line label
    tex = re.sub(r'\\showlineref\{([^}]*)\}\{([^}]*)\}\{[^}]*\}',
                 lambda m: r'\href{%s}{(%s:%s)}' % (_url(m[1], m[2]), basename(m[1]), m[2]), tex)
    tex = re.sub(r'\\showlinerefs\{([^}]*)\}\{([^}]*)\}\{([^}]*)\}\{[^}]*\}\{[^}]*\}',
                 lambda m: r'\href{%s}{(%s:%s-%s)}' % (_url(m[1], m[2], m[3]), basename(m[1]), m[2], m[3]), tex)
    tex = re.sub(r'\\showfileref\{([^}]*)\}\{[^}]*\}',
                 lambda m: r'\href{%s}{(%s)}' % (_url(m[1]), basename(m[1])), tex)
    return tex

# ---------------------------------------------------------------------------
# Per-chapter preprocessing (LaTeX -> cleaner LaTeX)
# ---------------------------------------------------------------------------
def preprocess(tex, chapnum):
    # number each figure caption "Figure C.N:" in source order (== \caption order,
    # which is exactly how LaTeX/pandoc assign the figure numbers used by \ref).
    fc = [0]
    def number_caption(m):
        fc[0] += 1
        return r'\caption{Figure %d.%d: ' % (chapnum, fc[0])
    tex = re.sub(r'\\caption\{', number_caption, tex)
    # listings first (protect their contents from later substitutions)
    tex = re.sub(r'\\begin\{lstlisting\}(?:\[([^\]]*)\])?(.*?)\\end\{lstlisting\}',
                 take_listing, tex, flags=re.S)
    # code references must wrap the preceding identifier *before* it is turned into
    # a placeholder below, so resolve them here.
    tex = code_refs(tex)
    # inline code -> verbatim placeholders (avoids LaTeX escaping of %, &, _, etc.)
    tex = re.sub(r'\\lstinline\{([^}]*)\}', lambda m: take_inline(m.group(1)), tex)
    tex = re.sub(r'\\lstinline!([^!]*)!',   lambda m: take_inline(m.group(1)), tex)
    tex = re.sub(r'\\indexcode\{([^}]*)\}', lambda m: take_inline(m.group(1)), tex)
    # any unresolved bare \fileref (should not occur after lineref) -> plain text
    tex = re.sub(r'\\fileref\{([^}]*)\}', lambda m: '(%s)' % m.group(1), tex)
    # index macros
    tex = re.sub(r'\\indextextx\{([^}]*)\}', r'\1', tex)
    tex = re.sub(r'\\indextext\{([^}]*)\}', r'\\textit{\1}', tex)
    tex = re.sub(r'\\indexcode\{([^}]*)\}', r'\\texttt{\1}', tex)
    # drop bare index entries entirely (incl. one level of nested braces)
    tex = re.sub(r'\\index\{(?:[^{}]|\{[^{}]*\})*\}', '', tex)
    # tikz figure inputs -> rendered svg images
    tex = re.sub(r'\\input\{fig/(switch|sleep|trap|order)\.tex\}',
                 r'\\includegraphics{fig/\1.svg}', tex)
    # figure image extensions -> web svg
    tex = re.sub(r'\\includegraphics(\[[^\]]*\])?\{fig/([^}]*?)\.(pdf|png)\}',
                 r'\\includegraphics{fig/\2.svg}', tex)
    # editorial note macros (no-ops; none present but be safe)
    tex = re.sub(r'\\(note|rtm|mfk)\{(?:[^{}]|\{[^{}]*\})*\}', '', tex)
    return tex

# ---------------------------------------------------------------------------
# Build combined document and run pandoc
# ---------------------------------------------------------------------------
bodies = []
for i, c in enumerate(CHAPTERS):
    raw = open(os.path.join(SRC, c + ".tex")).read()
    bodies.append("%% ==CHAPTER:%s==\n" % c + preprocess(raw, i))

# resolve code-line references now that every listing has been scanned
combined = "\n\n".join(bodies)
combined = re.sub(r'\\ref\{(line:[^}]*)\}',
                  lambda m: str(linemap.get(m.group(1), '??')), combined)

PREAMBLE = r"""\documentclass{book}
\usepackage{graphicx,xcolor,booktabs,hyperref}
\newcommand{\github}{%s}
\frenchspacing
\begin{document}
""" % GH
doc = PREAMBLE + combined + "\n\\end{document}\n"
open("/tmp/combined.tex", "w").write(doc)

md = subprocess.run(["quarto","pandoc","/tmp/combined.tex","-f","latex",
                     "-t","markdown-raw_attribute","--wrap=none"],
                    capture_output=True, text=True)
if md.returncode != 0:
    sys.stderr.write(md.stderr); sys.exit(1)
text = md.stdout

# ---------------------------------------------------------------------------
# Post-process the combined markdown
# ---------------------------------------------------------------------------
# strip pandoc's cross-reference attribute spans, keep the link
text = re.sub(r'\)\{reference-type="[^"]*"\s+reference="[^"]*"\}', ')', text)
# strip any stray {reference=...} on figures/headers
text = re.sub(r'\{#([^ }]+)\s+reference-type="[^"]*"\s+reference="[^"]*"\}', r'{#\1}', text)

# Tag every GitHub source-reference link so the side-by-side code panel can pick
# it up: attach a .coderef class plus data-path / data-line / data-end attributes
# parsed straight out of the blob URL. The href is left untouched so the link
# still works as a plain GitHub link (e.g. on ctrl/cmd-click) when JS is off.
GH_BLOB = re.escape(GH)
def coderef_attr(m):
    url, path, frag = m.group(1), m.group(2), m.group(3) or ''
    attrs = ['.coderef', 'data-path="%s"' % path]
    mm = re.match(r'#L(\d+)(?:-L(\d+))?$', frag)
    if mm:
        attrs.append('data-line="%s"' % mm.group(1))
        if mm.group(2):
            attrs.append('data-end="%s"' % mm.group(2))
    return '](%s){%s}' % (url, ' '.join(attrs))
text = re.sub(r'\]\((' + GH_BLOB + r'([^#)]*)(#[^)]*)?)\)', coderef_attr, text)

# Pandoc collects every footnote definition at the end of the (single) document;
# pull them out so each can be re-attached to the chapter that references it.
def extract_footnotes(t):
    lines = t.split('\n'); out = []; defs = {}; i = 0
    while i < len(lines):
        m = re.match(r'^\[\^([^\]]+)\]:', lines[i])
        if m:
            block = [lines[i]]; i += 1
            while i < len(lines) and (lines[i].strip() == '' or lines[i][:1] in ' \t'):
                block.append(lines[i]); i += 1
            while block and block[-1].strip() == '':
                block.pop()
            defs[m.group(1)] = '\n'.join(block)
        else:
            out.append(lines[i]); i += 1
    return '\n'.join(out), defs
text, footdefs = extract_footnotes(text)

# split at the chapter markers we embedded (pandoc keeps comments? no) -> instead
# split on level-1 headings in document order.
parts = re.split(r'\n(?=# )', text)
# the first part may be empty/front matter before first heading
chunks = [p for p in parts if p.strip()]
assert len(chunks) == len(CHAPTERS), "got %d chunks, expected %d" % (len(chunks), len(CHAPTERS))

# map every defined id (#id) to its output html file
def outfile(c):
    return QMD.get(c, c) + ".html"

idfile = {}
for c, chunk in zip(CHAPTERS, chunks):
    for m in re.finditer(r'\{#([^}]+)\}', chunk):
        idfile[m.group(1)] = outfile(c)

# write each chapter
for c, chunk in zip(CHAPTERS, chunks):
    body = chunk
    # retarget anchor links to the owning page
    def retarget(m):
        anchor = m.group(1)
        f = idfile.get(anchor)
        return '](%s#%s)' % (f, anchor) if f else m.group(0)
    body = re.sub(r'\]\(#([^)]+)\)', retarget, body)
    # splice listings back in
    def put_listing(m):
        b = listings[int(m.group(1))]
        if b['numbered']:
            fence = '``` {.numberLines startFrom="%d"}' % b['start']
        else:
            fence = '```'
        return fence + "\n" + b['code'] + "\n```"
    body = re.sub(r'ZZLSTBLOCK(\d+)ZZ', put_listing, body)
    # restore inline code as markdown code spans (verbatim)
    def put_inline(m):
        s = inlines[int(m.group(1))]
        if '`' in s:
            return '`` ' + s + ' ``'
        return '`' + s + '`'
    body = re.sub(r'ZZICODE(\d+)ZZ', put_inline, body)
    # re-attach the footnote definitions this chapter references
    used = [k for k in re.findall(r'\[\^([^\]]+)\]', body) if k in footdefs]
    seen = []
    for k in used:
        if k not in seen: seen.append(k)
    if seen:
        body = body.rstrip() + "\n\n" + "\n\n".join(footdefs[k] for k in seen)
    qmd = QMD.get(c, c) + ".qmd"
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, qmd), "w").write(body.strip() + "\n")
    print("wrote", qmd)

print("done; %d listings, %d line-labels" % (len(listings), len(linemap)))
