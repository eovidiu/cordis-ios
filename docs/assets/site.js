// Renders docs/pages/*.md client-side: Markdown with marked, diagrams with
// Mermaid. Routes are `#/<page>` or `#/<page>/<heading-id>`. The Markdown
// links between pages (`concepts.md#realms`) are rewritten to routes, and
// relative image paths are resolved against pages/, so the same files read
// correctly on GitHub and here.
import { marked } from "https://cdn.jsdelivr.net/npm/marked@15.0.12/lib/marked.esm.js";
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs";

const PAGES = ["home", "concepts", "architecture", "showcase"];
const TITLES = {
  home: "Overview",
  concepts: "Concepts",
  architecture: "Architecture (C4)",
  showcase: "Showcase app",
};
const content = document.getElementById("content");
const toc = document.getElementById("toc");

mermaid.initialize({
  startOnLoad: false,
  // C4 relation labels are unreadable in Mermaid's dark theme, so diagrams
  // always render in the default theme on a light panel (see site.css).
  theme: "default",
  securityLevel: "strict",
  c4: { diagramMarginY: 10 },
});

/** GitHub's heading anchor algorithm, so links work in both places. */
export function slug(text) {
  return text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s_-]/gu, "")
    .replace(/\s/g, "-");
}

function parseRoute() {
  const [, page = "home", anchor = ""] = location.hash.match(/^#\/([^/]*)\/?(.*)$/) ?? [];
  return { page: PAGES.includes(page) ? page : "home", anchor: decodeURIComponent(anchor) };
}

function rewriteLinks(root, page) {
  const pageBase = new URL(`pages/${page}.md`, location.href);
  for (const a of root.querySelectorAll("a[href]")) {
    const href = a.getAttribute("href");
    if (href.startsWith("#")) {
      a.setAttribute("href", `#/${page}/${href.slice(1)}`);
      continue;
    }
    const local = href.match(/^([\w-]+)\.md(?:#(.*))?$/);
    if (local && PAGES.includes(local[1])) {
      a.setAttribute("href", `#/${local[1]}${local[2] ? `/${local[2]}` : ""}`);
      continue;
    }
    if (/^https?:/.test(href)) {
      a.setAttribute("rel", "noopener");
      continue;
    }
    a.setAttribute("href", new URL(href, pageBase).href);
  }
  for (const img of root.querySelectorAll("img[src]")) {
    const src = img.getAttribute("src");
    if (!/^https?:/.test(src)) img.src = new URL(src, pageBase).href;
    img.loading = "lazy";
  }
}

function buildToc(root) {
  toc.replaceChildren();
  const headings = [...root.querySelectorAll("h2, h3")];
  if (headings.length < 2) return;
  const title = document.createElement("p");
  title.className = "toc-title";
  title.textContent = "On this page";
  const list = document.createElement("ul");
  for (const h of headings) {
    const item = document.createElement("li");
    item.className = h.tagName.toLowerCase();
    const link = document.createElement("a");
    link.href = `#/${parseRoute().page}/${h.id}`;
    link.textContent = h.textContent;
    item.append(link);
    list.append(item);
  }
  toc.append(title, list);
}

async function renderDiagrams(root) {
  const blocks = [...root.querySelectorAll("pre > code.language-mermaid")];
  const nodes = blocks.map((code) => {
    const div = document.createElement("div");
    div.className = "mermaid";
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
    return div;
  });
  if (nodes.length) await mermaid.run({ nodes, suppressErrors: true });
}

async function render() {
  const { page, anchor } = parseRoute();
  for (const link of document.querySelectorAll("nav.pages a")) {
    link.toggleAttribute("aria-current", link.dataset.page === page);
  }
  const response = await fetch(`pages/${page}.md`);
  if (!response.ok) {
    content.textContent = `Could not load ${page}.md (HTTP ${response.status}).`;
    return;
  }
  content.innerHTML = marked.parse(await response.text(), { gfm: true });
  for (const h of content.querySelectorAll("h1, h2, h3, h4")) h.id = slug(h.textContent);
  rewriteLinks(content, page);
  buildToc(content);
  document.title = `${TITLES[page]} · cordis-ios`;
  await renderDiagrams(content);
  content.dataset.rendered = page;
  const target = anchor && document.getElementById(anchor);
  if (target) target.scrollIntoView();
  else window.scrollTo(0, 0);
}

window.addEventListener("hashchange", render);
render();
