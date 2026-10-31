"""Build an offline, single-file HTML design collection. Python standard library only."""
from pathlib import Path
import base64
import json

root = Path(__file__).resolve().parent.parent
symbols = {p.stem: 'data:image/png;base64,' + base64.b64encode(p.read_bytes()).decode()
           for p in sorted((root / 'assets/symbols').glob('*.png'))}
if len(symbols) < 30:
    raise RuntimeError('SF Symbol assets are missing. Run export-symbols.swift first.')
html = (root / 'source/shell.html').read_text()
html = html.replace('/*__CSS__*/', (root / 'source/style.css').read_text())
html = html.replace('/*__SYMBOLS__*/', json.dumps(symbols, ensure_ascii=False))
screens = (root / 'source/screens.js').read_text()
screens = screens.replace('/*__STATION_SELECTION__*/', (root / 'source/station-selection.js').read_text())
html = html.replace('/*__JS__*/', screens)
target = root / 'index.html'
target.write_text(html)
print(f'Built {target} ({target.stat().st_size:,} bytes, {len(symbols)} SF Symbols)')
