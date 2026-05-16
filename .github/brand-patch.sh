#!/usr/bin/env bash
# PayHub brand patch — run by setup.yml + site.yml between "Generate site"
# and "GitHub Pages Deploy". The Upptime status-page is a Sapper SPA built
# from the @upptime/status-page npm package; nothing from the source repo
# reaches the build except via .upptimerc.yml. So we patch the *generated
# export tree* directly: replace the default icons + global.css with our
# branded versions, and add favicon link tags into the rendered <head>.
#
# Safe to re-run — overwriting files is idempotent; the head injection is
# guarded by a substring check.

set -euo pipefail

EXPORT="site/status-page/__sapper__/export"

if [ ! -d "$EXPORT" ]; then
    echo "❌ $EXPORT not found — did the 'Generate site' step run?"
    exit 1
fi

echo "→ Replacing default Upptime icons with PayHub mark"
cp assets/icon.png "$EXPORT/icon.png"
cp logo-192.png    "$EXPORT/logo-192.png"
# The default 512 icon is referenced from manifest.json — overwrite with
# the same 192 PNG (browsers downscale; no quality loss for a 192px file
# displayed at 192px).
cp logo-192.png    "$EXPORT/logo-512.png"
cp favicon.ico        "$EXPORT/favicon.ico"
cp favicon-16.png     "$EXPORT/favicon-16.png"
cp favicon-32.png     "$EXPORT/favicon-32.png"
cp apple-touch-icon.png "$EXPORT/apple-touch-icon.png"

echo "→ Overwriting global.css with PayHub-themed overrides"
cp global.css "$EXPORT/global.css"

echo "→ Injecting favicon link tags into rendered <head>"
python3 - <<'PY'
import pathlib
p = pathlib.Path("site/status-page/__sapper__/export/index.html")
html = p.read_text()
inject = (
    '<link rel="icon" type="image/x-icon" href="/favicon.ico" sizes="any">'
    '<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">'
    '<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16.png">'
    '<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">'
)
if "apple-touch-icon" not in html:
    html = html.replace("</head>", inject + "</head>", 1)
    p.write_text(html)
    print("  ✓ favicon links injected")
else:
    print("  ✓ favicon links already present (idempotent re-run)")
PY

echo "✓ PayHub brand applied."
