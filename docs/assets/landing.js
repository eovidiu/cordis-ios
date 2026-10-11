import { highlight } from "./highlight.js";

// Install snippet tabs (WAI-ARIA tabs pattern: arrow keys move between tabs).
for (const group of document.querySelectorAll("[data-tabs]")) {
  const tabs = [...group.querySelectorAll("[role=tab]")];
  const select = (tab) => {
    for (const other of tabs) {
      const selected = other === tab;
      other.setAttribute("aria-selected", String(selected));
      other.tabIndex = selected ? 0 : -1;
      document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
    }
  };
  for (const [index, tab] of tabs.entries()) {
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", (event) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
      if (!step) return;
      const next = tabs[(index + step + tabs.length) % tabs.length];
      select(next);
      next.focus();
    });
  }
}

// Copy buttons copy the visible snippet of their group.
for (const button of document.querySelectorAll("[data-copy-from]")) {
  button.addEventListener("click", async () => {
    const code = button.closest("[data-tabs]").querySelector(button.dataset.copyFrom);
    try {
      await navigator.clipboard.writeText(code.textContent.trim());
      button.textContent = "Copied";
    } catch {
      button.textContent = "Press ⌘C";
      getSelection().selectAllChildren(code);
    }
    setTimeout(() => (button.textContent = "Copy"), 1600);
  });
}

highlight();
