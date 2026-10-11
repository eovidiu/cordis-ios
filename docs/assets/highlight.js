// Syntax highlighting shared by the landing page and the docs. Code stays
// readable unhighlighted if the CDN is unreachable.
const CDN = "https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.11.1/es";

let ready;
function load() {
  ready ??= (async () => {
    const [{ default: hljs }, swift, json, bash] = await Promise.all([
      import(`${CDN}/core.min.js`),
      import(`${CDN}/languages/swift.min.js`),
      import(`${CDN}/languages/json.min.js`),
      import(`${CDN}/languages/bash.min.js`),
    ]);
    hljs.registerLanguage("swift", swift.default);
    hljs.registerLanguage("json", json.default);
    hljs.registerLanguage("bash", bash.default);
    hljs.registerAliases(["sh", "shell"], { languageName: "bash" });
    return hljs;
  })();
  return ready;
}

/** Highlights `pre > code` blocks under `root` that name a known language. */
export async function highlight(root = document) {
  const blocks = [...root.querySelectorAll("pre > code[class*='language-']")]
    .filter((code) => /language-(swift|json|bash|sh|shell)\b/.test(code.className));
  if (!blocks.length) return;
  try {
    const hljs = await load();
    for (const code of blocks) hljs.highlightElement(code);
  } catch {
    // offline or CDN blocked: leave plain code
  }
}
