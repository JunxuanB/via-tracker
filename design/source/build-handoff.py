"""Render the editable Markdown handoff as an offline HTML document."""
from pathlib import Path
from html import escape
import re

from markdown_it import MarkdownIt

root = Path(__file__).resolve().parent.parent
source = (root / 'DEVELOPMENT_HANDOFF.md').read_text()
md = MarkdownIt('commonmark', {'html': False}).enable('table')
tokens = md.parse(source)
toc = []
for i, token in enumerate(tokens):
    if token.type == 'heading_open' and token.tag == 'h2':
        title = tokens[i + 1].content
        match = re.match(r'(\d+)\.', title)
        anchor = f'section-{match.group(1)}' if match else f'section-{len(toc) + 1}'
        token.attrSet('id', anchor)
        toc.append(f'<a href="#{anchor}">{escape(title)}</a>')
body = md.renderer.render(tokens, md.options, {})
style = '''
:root{color-scheme:light;--paper:#fffefa;--ink:#252622;--muted:#66675f;--line:#e7e4d8;--yellow:#ffcc00}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:28px}
body{margin:0;background:#f5f4ed;color:var(--ink);font:15px/1.9 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif}
a{color:#705600;text-decoration-thickness:1px;text-underline-offset:3px}a:hover{color:#252622}
a:focus-visible{outline:3px solid #a68200;outline-offset:4px;border-radius:2px}
.top{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:18px 32px;background:var(--paper);border-bottom:1px solid var(--line)}
.brand{display:flex;align-items:center;gap:12px;font-weight:650;font-size:17px}.mark{display:grid;place-items:center;background:var(--yellow);width:36px;height:36px;border-radius:11px;font-size:13px;font-weight:800}
.top-links{display:flex;gap:24px;font-size:13px}.layout{max-width:1500px;margin:auto;display:grid;grid-template-columns:258px minmax(0,1fr)}
aside{padding:32px 20px 40px 26px;position:sticky;top:0;height:100vh;overflow:auto}.nav-label{font-size:11px;color:var(--muted);letter-spacing:1px;margin-bottom:16px}
aside a{display:block;text-decoration:none;color:#57584f;font-size:12px;line-height:1.65;padding:7px 9px;border-radius:6px}aside a:hover{background:#ffeaa0}
main{min-width:0;margin:32px 30px 48px 0;padding:44px 52px;background:var(--paper);border:1px solid var(--line);border-radius:18px;box-shadow:0 8px 40px #34301b05}
article{max-width:980px;margin:auto}h1{font-size:31px;line-height:1.4;letter-spacing:-.8px;margin:0 0 18px}h2{font-size:22px;line-height:1.5;margin:48px 0 18px;padding-top:26px;border-top:1px solid var(--line);letter-spacing:-.4px}h2:first-of-type{border-top:4px solid var(--yellow);padding-top:24px;margin-top:32px}h3{font-size:17px;margin:28px 0 12px}p{margin:14px 0}p:first-of-type{font-size:12px;color:var(--muted)}
strong{font-weight:650}ul,ol{padding-left:25px}li{padding-left:3px;margin:9px 0}blockquote{border-left:3px solid var(--yellow);margin:14px 0;padding:1px 18px;background:#fff9dd;border-radius:0 7px 7px 0}blockquote p{font-size:14px!important;color:var(--ink)!important}
code{font:12px/1.8 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f1f0e8;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}pre{background:#f1f0e8;border:1px solid #e7e4d8;border-radius:10px;padding:18px 20px;white-space:pre-wrap;overflow-wrap:anywhere}pre code{padding:0;background:none}
table{border-collapse:collapse;width:100%;margin:20px 0;font-size:13px;line-height:1.8;table-layout:fixed}th,td{text-align:left;vertical-align:top;border-bottom:1px solid var(--line);padding:12px 13px;overflow-wrap:anywhere}th{background:#f5f2e5;font-weight:650}th:first-child,td:first-child{width:27%}tr:last-child td{border-bottom:2px solid var(--line)}
footer{margin:46px 0 0;padding-top:18px;border-top:1px solid var(--line);font-size:12px;color:var(--muted);display:flex;justify-content:space-between;gap:18px}
@media(max-width:1100px){.layout{grid-template-columns:220px minmax(0,1fr)}main{padding:32px 30px;margin-right:20px}aside{padding-left:16px}}
@media(max-width:760px){.top{padding:14px 18px}.top-links{gap:16px;font-size:12px}.brand{font-size:15px}.layout{display:block}aside{position:static;height:auto;padding:20px 18px;border-bottom:1px solid var(--line)}.nav-label{margin-bottom:8px}aside nav{display:flex;overflow:auto;gap:6px}aside a{white-space:nowrap;padding:9px;background:#eeece1}main{margin:16px 10px 28px;padding:25px 20px;border-radius:12px}h1{font-size:25px}h2{font-size:20px;margin-top:36px}body{font-size:14px}table{font-size:12px}th,td{padding:10px 7px}th:first-child,td:first-child{width:30%}code{font-size:11px}pre{padding:14px 12px}footer{display:block}footer a{display:block;margin-top:10px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
@media print{body{background:white;font-size:10pt}.top,aside,.top-links,footer{display:none}.layout{display:block}main{border:0;box-shadow:none;padding:0;margin:0}article{max-width:none}h2{break-after:avoid}pre,blockquote,tr{break-inside:avoid}a{color:inherit}h1{font-size:24pt}}
'''
html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>VIA Tracker · Developer handoff</title><style>{style}</style></head>
<body><header class="top"><div class="brand"><span class="mark" aria-hidden="true">VIA</span>VIA Tracker</div><nav class="top-links" aria-label="Documentation links"><a href="index.html#journey">UI designs ↗</a><a href="DEVELOPMENT_HANDOFF.md" download>Markdown source</a></nav></header>
<div class="layout"><aside aria-label="Contents"><div class="nav-label">DEVELOPER HANDOFF · CONTENTS</div><nav>{''.join(toc)}</nav></aside><main><article>{body}<footer><span>Product rules and source observations · Independent and unofficial</span><a href="index.html#journey">View all UI designs ↗</a></footer></article></main></div></body></html>'''
target = root / 'handoff.html'
target.write_text(html)
print(f'Built {target} ({target.stat().st_size:,} bytes, {len(toc)} sections)')
