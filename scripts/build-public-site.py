#!/usr/bin/env python3
"""Render the public privacy and support pages from their Markdown sources.
Requires markdown-it-py (also used by the design documentation renderer).
"""
from pathlib import Path
from markdown_it import MarkdownIt

root = Path(__file__).resolve().parent.parent
out = root / 'build' / 'public-site'
md = MarkdownIt('commonmark', {'html': False})
css = 'body{font:17px/1.65 system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 24px;color:#252622;background:#fffefa}a{color:#705600}nav{display:flex;gap:24px}h1,h2{line-height:1.2}li{margin:8px 0}hr{margin:40px 0;border:0;border-top:1px solid #ddd}footer{margin-top:48px}'
for slug, source, title in [('privacy', 'PRIVACY.md', 'Privacy policy'), ('support', 'SUPPORT.md', 'Support')]:
    content = md.render((root / 'docs' / source).read_text().replace('(PRIVACY.md)', '(/privacy/)'))
    page = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · Train Tracker</title><style>{css}</style></head><body><nav><a href="/support/">Support</a><a href="/privacy/">Privacy</a><a href="https://junxuanb.com/#contact">Contact</a></nav><main>{content}</main><footer>Train Tracker · Independent and unofficial</footer></body></html>\n'
    folder = out / slug
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'index.html').write_text(page)
(out / 'index.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=/support/"><title>Train Tracker</title></head><body><a href="/support/">Train Tracker support</a></body></html>\n')
(out / '_headers').write_text('/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: no-referrer\n  Content-Security-Policy: default-src \'none\'; style-src \'unsafe-inline\'; base-uri \'none\'; frame-ancestors \'none\'\n')
print(out)
