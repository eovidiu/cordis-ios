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
nav = re.findall(r'data-page="([\w-]+)"', (docs / "docs.html").read_text())
if routed != nav:
    problems.append(f"docs.html nav {nav} differs from site.js PAGES {routed}")

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

# Landing page and 404: every local link and asset exists, every docs.html
# deep link names a routed page and an existing heading, and the sharing
# metadata is complete.
import struct
for html_name in ["index.html", "404.html"]:
    html = (docs / html_name).read_text()
    for target in re.findall(r'(?:href|src)="([^"]+)"', html):
        if re.match(r"https?:|mailto:|#", target):
            continue
        path, _, fragment = target.partition("#")
        path = re.sub(r"^/cordis-ios/", "", path) or "index.html"
        if path.endswith("/") or path == "./":
            path += "index.html"
        if not (docs / path).exists():
            problems.append(f"{html_name}: missing file {target}")
        if path == "docs.html" and fragment:
            route = fragment.lstrip("/").split("/", 1)
            if route[0] not in routed:
                problems.append(f"{html_name}: unrouted docs page {target}")
            elif len(route) == 2 and route[1] not in anchors.get(route[0], set()):
                problems.append(f"{html_name}: anchor not found {target}")
    for anchor in re.findall(r'href="#([\w-]+)"', html):
        if f'id="{anchor}"' not in html:
            problems.append(f"{html_name}: in-page anchor #{anchor} has no target")

landing = (docs / "index.html").read_text()
for meta in ['property="og:title"', 'property="og:description"', 'property="og:image"', 'name="twitter:card"', 'rel="canonical"', 'name="description"']:
    if meta not in landing:
        problems.append(f"index.html: missing {meta}")
og = (docs / "assets/og.png").read_bytes()[:24]
if struct.unpack(">II", og[16:24]) != (1200, 630):
    problems.append("assets/og.png must be 1200x630")

# privacy.html is the App Store privacy URL; it must say what pages/privacy.md says.
def words(text):
    text = re.sub(r"<(https?://[^>]+)>", r" \1 ", text)  # Markdown autolinks keep their URL
    text = re.sub(r"<[^>]+>|\[([^\]]*)\]\([^)]*\)|[*_#]", r"\1", text)
    return re.findall(r"[a-z0-9']+", text.lower().replace("&#39;", "'"))
static = (docs / "privacy.html").read_text()
static = re.search(r"<main>(.*)</main>", static, flags=re.S).group(1)
if words(static) != words((pages_dir / "privacy.md").read_text()):
    problems.append("privacy.html differs from pages/privacy.md")

# README images render on GitHub only if the files exist in the repo.
repo = docs.resolve().parent
readme = (repo / "README.md").read_text()
readme_images = re.findall(r'<img[^>]*src="([^"]+)"', readme) + re.findall(r"!\[[^\]]*\]\(([^)\s]+)\)", readme)
for src in readme_images:
    if not src.startswith("http") and not (repo / src).exists():
        problems.append(f"README.md: missing image {src}")

# Cordis Showcase is live on the App Store; every entry point links to it.
app_store = "https://apps.apple.com/us/app/cordis-showcase/id6821575918"
for name, text in [("index.html", landing), ("pages/showcase.md", (pages_dir / "showcase.md").read_text()), ("README.md", readme)]:
    if app_store not in text:
        problems.append(f"{name}: no link to the App Store listing")
if "Coming to the App Store" in landing:
    problems.append("index.html: still says the app is coming to the App Store")

for problem in problems:
    print(f"docs/check.sh: {problem}", file=sys.stderr)
if problems:
    sys.exit(1)
print(f"docs ok: {len(routed)} pages, links, images and anchors resolve, C4 views present")
PY
