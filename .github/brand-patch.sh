#!/usr/bin/env bash
# PayHub brand patch — run by setup.yml + site.yml between "Generate site"
# and "GitHub Pages Deploy". The Upptime status-page is a Sapper SPA built
# from the @upptime/status-page npm package; nothing from the source repo
# reaches the build except via .upptimerc.yml. So we patch the *generated
# export tree* directly: replace the default icons + global.css with our
# branded versions, and inject favicon link tags + theme/UI enhancement
# scripts into the rendered <head>.
#
# Safe to re-run — overwriting files is idempotent; head injections are
# guarded by substring checks.

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

echo "→ Injecting favicon + theme/UI scripts into rendered <head>"
python3 - <<'PY'
import pathlib
p = pathlib.Path("site/status-page/__sapper__/export/index.html")
html = p.read_text()

# ── Favicon links ─────────────────────────────────────────────────────
favicon_marker = "apple-touch-icon"
favicon_tags = (
    '<link rel="icon" type="image/x-icon" href="/favicon.ico" sizes="any">'
    '<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">'
    '<link rel="icon" type="image/png" sizes="16x16" href="/favicon-16.png">'
    '<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">'
)
if favicon_marker not in html:
    html = html.replace("</head>", favicon_tags + "</head>", 1)
    print("  ✓ favicon links injected")
else:
    print("  ✓ favicon links already present")

# ── Early theme script (must run BEFORE first paint to avoid FOUC) ────
# Reads localStorage and applies data-theme synchronously. First-time
# visitors default to LIGHT mode (the brand's primary surface);
# explicit user choice is persisted and the "system" choice removes the
# attribute so the prefers-color-scheme media query in global.css takes
# over. Bumping the cache key version (v2) invalidates the previous
# default of "system" without surprising users who had explicitly chosen.
early_marker = "ph-theme-init"
early_script = """<script id="ph-theme-init">
(function(){var k="payhub-theme";var t=localStorage.getItem(k);
if(t!=="dark"&&t!=="light"&&t!=="system"){t="light";localStorage.setItem(k,t);}
if(t==="dark"||t==="light"){document.documentElement.setAttribute("data-theme",t);}
else{document.documentElement.removeAttribute("data-theme");}
window.__phTheme={get:function(){return localStorage.getItem(k)||"light";},
set:function(v){localStorage.setItem(k,v);
if(v==="dark"||v==="light"){document.documentElement.setAttribute("data-theme",v);}
else{document.documentElement.removeAttribute("data-theme");}}};
})();
</script>"""
if early_marker not in html:
    html = html.replace("</head>", early_script + "</head>", 1)
    print("  ✓ early theme script injected")
else:
    print("  ✓ early theme script already present")

# ── UI enhancements script (runs after SPA hydrates) ──────────────────
# Adds the theme-toggle button to the nav, tags the time-range tab
# container so global.css can style it as a segmented control, and
# tracks the active tab via a click listener. MutationObserver handles
# the SPA mounting/remounting elements during navigation.
ui_marker = "ph-ui-enhance"
ui_script = """<script id="ph-ui-enhance" defer>
(function(){
  // The Upptime status-page is a Sapper SPA — its DOM appears after
  // hydration. We tag stable DOM hooks (data-ph-* attributes) here so
  // global.css can target the segmented control + nav additions
  // without depending on Svelte's per-build class hashes.
  var ICONS={
    system:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>',
    light:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>',
    dark:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>'
  };
  var LABELS={system:"Theme: follow system",light:"Theme: light",dark:"Theme: dark"};
  var NEXT={light:"dark",dark:"system",system:"light"};

  function buildToggle(){
    var ul=document.querySelector("nav ul");
    if(!ul||ul.querySelector(".ph-theme-toggle"))return;
    var li=document.createElement("li");
    li.className="ph-theme-toggle-item";
    var btn=document.createElement("button");
    btn.className="ph-theme-toggle";
    btn.type="button";
    function render(){
      var t=window.__phTheme.get();
      btn.innerHTML=ICONS[t];
      btn.setAttribute("aria-label",LABELS[t]);
      btn.title=LABELS[t];
    }
    btn.addEventListener("click",function(){
      window.__phTheme.set(NEXT[window.__phTheme.get()]);
      render();
    });
    li.appendChild(btn);
    ul.appendChild(li);
    render();
  }

  function tagRangeTabs(){
    // The time-range "tabs" are rendered as a <form> holding five
    // <input type="radio"> + <label> pairs (one per duration). We
    // identify the form structurally — any <form> in <main> with
    // exactly five radios — and tag it so CSS can lay out a
    // segmented control via :checked + label.
    var forms=document.querySelectorAll("main form");
    for(var i=0;i<forms.length;i++){
      var f=forms[i];
      if(f.hasAttribute("data-ph-range-tabs"))continue;
      var radios=f.querySelectorAll('input[type="radio"]');
      if(radios.length===5){f.setAttribute("data-ph-range-tabs","");}
    }
  }

  function run(){buildToggle();tagRangeTabs();}

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded",run);
  }else{
    run();
  }
  // SPA re-renders main on hydration / route changes — re-tag as needed.
  var obs=new MutationObserver(function(){run();});
  obs.observe(document.body,{childList:true,subtree:true});
})();
</script>"""
if ui_marker not in html:
    html = html.replace("</head>", ui_script + "</head>", 1)
    print("  ✓ UI enhancement script injected")
else:
    print("  ✓ UI enhancement script already present")

p.write_text(html)
PY

echo "✓ PayHub brand applied."
