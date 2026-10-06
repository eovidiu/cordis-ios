#!/usr/bin/env bash
# Static checks for the docs site: every page the site routes to exists,
# every relative link, image and heading anchor resolves, and the
# architecture page carries each C4 view. Exits non-zero on the first report.
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
import re, sys, pathlib

docs = pathlib.Path(".")
pages_dir = docs / "pages"
problems = []

def slug(text):
    # GitHub's heading anchors (mirrored by slug() in assets/site.js)
    text = re.sub(r"`|\*\*|\*|\[|\]\([^)]*\)", "", text).strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return re.sub(r"\s", "-", text)

def strip_code(markdown):
    return re.sub(r"```.*?```", "", markdown, flags=re.S)

site_js = (docs / "assets/site.js").read_text()
routed = re.search(r"const PAGES = \[(.*?)\]", site_js).group(1)
routed = re.findall(r'"([\w-]+)"', routed)
nav = re.findall(r'data-page="([\w-]+)"', (docs / "index.html").read_text())
if routed != nav:
    problems.append(f"index.html nav {nav} differs from site.js PAGES {routed}")

anchors = {}
for name in routed:
    path = pages_dir / f"{name}.md"
    if not path.exists():
        problems.append(f"routed page missing: {path}")
        continue
    headings = re.findall(r"^#{1,4} (.+)$", strip_code(path.read_text()), flags=re.M)
    anchors[name] = {slug(h) for h in headings}

for name in routed:
    path = pages_dir / f"{name}.md"
    if not path.exists():
        continue
    text = strip_code(path.read_text())
    targets = re.findall(r"\]\(([^)\s]+)\)", text) + re.findall(r'(?:src|href)="([^"]+)"', text)
    for target in targets:
        if re.match(r"https?:|mailto:", target):
            continue
        file, _, anchor = target.partition("#")
        if file == "":
            page = name
        elif file.endswith(".md") and (pages_dir / file).parent == pages_dir:
            page = file[:-3]
            if page not in anchors:
                problems.append(f"{path}: link to unrouted page {target}")
                continue
        else:
            page = None
            if not (pages_dir / file).resolve().exists():
                problems.append(f"{path}: broken link or image {target}")
        if anchor and page is not None and anchor not in anchors.get(page, set()):
            problems.append(f"{path}: anchor not found {target}")

architecture = (pages_dir / "architecture.md").read_text()
for view in ["C4Context", "C4Container", "C4Component", "classDiagram", "stateDiagram-v2", "sequenceDiagram", "C4Deployment"]:
    if f"```mermaid\n{view}" not in architecture:
        problems.append(f"architecture.md: no {view} diagram")

if not (docs / ".nojekyll").exists():
    problems.append(".nojekyll missing: GitHub Pages would run Jekyll over docs/")

for problem in problems:
    print(f"docs/check.sh: {problem}", file=sys.stderr)
if problems:
    sys.exit(1)
print(f"docs ok: {len(routed)} pages, links, images and anchors resolve, C4 views present")
PY
