# HTML Report Format

The architectural review is rendered as a single self-contained HTML file in the OS temp directory. Tailwind and Mermaid both come from CDNs. Mermaid handles graph-shaped diagrams reliably; hand-built divs and inline SVG handle the more editorial visuals (mass diagrams, cross-sections). Mix the two — don't lean on Mermaid for everything, it'll start to look generic.

## Language

The report is **written in Chinese (中文)**. The discipline from [LANGUAGE.md](LANGUAGE.md) survives translation via a fixed Chinese↔English glossary.

**Render in Chinese:** all headings, prose, badge text, callouts, legends, button labels, and bullet content.

**Keep in English:** code identifiers (module names, file paths, function names, e.g. `OrderHandler`, `PricingClient`, `src/order/intake.ts`); Mermaid keywords and `classDef` names; and the canonical English term in parentheses on **first mention** of each architecture noun (one-time inline tooltip, e.g. *接口（Interface）*).

### Architecture glossary (use these translations consistently)

| 中文 | English | 严禁替换为 |
|---|---|---|
| 模块 | Module | 组件 / 服务 / 单元 |
| 接口 | Interface | API / 签名（这两个只指类型层面） |
| 实现 | Implementation | — |
| 深度 / 深 / 浅 | Depth / Deep / Shallow | — |
| 接缝 | Seam | 边界（与 DDD bounded context 冲突） |
| 适配器 | Adapter | — |
| 杠杆 | Leverage | — |
| 局部性 | Locality | — |
| 泄漏 | Leakage | 渗透 / 越界 |

Render this glossary in the report header as a compact `<dl>` (definition list) or two-column grid so the reader sees the mapping once at the top. After the glossary block, prose uses only the Chinese term.

## Scaffold

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <title>架构评审 — {{repo name}}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      /* small custom layer for things Tailwind doesn't cover cleanly:
         dashed seam lines, hand-drawn-feeling arrow heads, etc. */
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: #dc2626; }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, date, the **architecture glossary** (the table above, rendered as a compact `<dl>` or grid), and a compact legend rendered in Chinese — e.g. *实线方框 = 模块, 虚线 = 接缝, 红色箭头 = 泄漏, 深色加粗方框 = 深模块*. No introduction paragraph — straight into the candidates.

## Candidate card

The diagrams carry the weight. Prose is sparse, plain Chinese, and uses the glossary terms ([LANGUAGE.md](LANGUAGE.md) + the Chinese mapping above) without ceremony.

Each candidate is one `<article>`:

- **Title (标题)** — short Chinese phrase, names the deepening (e.g. *"收拢 Order intake 流水线"*).
- **Badge row** — recommendation strength rendered as Chinese badges: `强烈推荐` = emerald, `值得探索` = amber, `推测性` = slate. Plus a Chinese tag for the dependency category: `进程内` (in-process) / `本地可替代` (local-substitutable) / `端口与适配器` (ports & adapters) / `Mock`.
- **涉及文件 (Files)** — monospaced list, `font-mono text-sm`. File paths stay in English.
- **前 / 后 对比图 (Before / After diagram)** — the centrepiece. Two columns, side by side. See patterns below.
- **问题 (Problem)** — one Chinese sentence. What hurts.
- **方案 (Solution)** — one Chinese sentence. What changes.
- **收益 (Wins)** — bullets, ≤8 Chinese characters each where possible. e.g. *"测试只打一个接口"*, *"Pricing 逻辑不再泄漏"*, *"删除 4 个浅包装"*.
- **ADR 警示 (ADR callout)** (if applicable) — one Chinese line in an amber-tinted box.

No paragraphs of explanation. If the diagram needs a paragraph to be understood, redraw the diagram.

## Diagram patterns

Pick the pattern that fits the candidate. Mix them. Don't make every diagram look the same — variety is part of the point.

### Mermaid graph (the workhorse for dependencies / call flow)

Use a Mermaid `flowchart` or `graph` when the point is "X calls Y calls Z, and look at the mess." Wrap it in a Tailwind-styled card so it doesn't feel parachuted in. Style with classDef to colour leakage edges red and the deep module dark. Sequence diagrams work well for "before: 6 round-trips; after: 1."

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrderHandler] --> B[OrderValidator]
      B --> C[OrderRepo]
      C -.leak.-> D[PricingClient]
      classDef leak stroke:#dc2626,stroke-width:2px;
      class C,D leak
  </pre>
</div>
```

### Hand-built boxes-and-arrows (when Mermaid's layout fights you)

Modules as `<div>`s with borders and labels. Arrows as inline SVG `<line>` or `<path>` elements positioned absolutely over a relative container. Reach for this when you want the "after" diagram to feel like one thick-bordered deep module with greyed-out internals — Mermaid won't render that with the right weight.

### Cross-section (good for layered shallowness)

Stack horizontal bands (`h-12 border-l-4`) to show layers a call passes through. Before: 6 thin layers each doing nothing. After: 1 thick band labelled with the consolidated responsibility.

### Mass diagram (good for "interface as wide as implementation")

Two rectangles per module — one for interface surface area, one for implementation. Before: interface rectangle is nearly as tall as the implementation rectangle (shallow). After: interface rectangle is short, implementation rectangle is tall (deep).

### Call-graph collapse

Before: a tree of function calls rendered as nested boxes. After: the same tree collapsed into one box, with the now-internal calls shown faded inside it.

## Style guidance

- Lean editorial, not corporate-dashboard. Generous whitespace. Serif optional for headings (`font-serif` works well with stone/slate).
- Colour sparingly: one accent (emerald or indigo) plus red for leakage and amber for warnings.
- Keep diagrams ~320px tall so before/after sits comfortably side by side without scrolling.
- Use `text-xs uppercase tracking-wider` for module labels inside diagrams — they should read as schematic, not as UI.
- The only scripts are the Tailwind CDN and the Mermaid ESM import. The report is otherwise static — no app code, no interactivity beyond Mermaid's own rendering.

## Top recommendation section

One larger card titled **首选推荐 (Top recommendation)**. Candidate name (Chinese), one Chinese sentence on why, anchor link to its card. That's it.

## Tone

Plain Chinese, concise — but the architectural nouns and verbs come straight from the glossary at the top of this file (which mirrors [LANGUAGE.md](LANGUAGE.md)). Concision is not an excuse to drift.

**Use exactly:** 模块, 接口, 实现, 深度, 深, 浅, 接缝, 适配器, 杠杆, 局部性, 泄漏.

**Never substitute:** 组件 / 服务 / 单元 (for 模块) · API / 签名 (for 接口, except when referring strictly to the type-level surface) · 边界 (for 接缝 — conflicts with DDD bounded context) · 层 / 包装器 (for 模块, when you mean 模块) · 渗透 / 越界 (for 泄漏).

**English code identifiers stay in code form.** Don't translate `OrderHandler` to *订单处理器* or `PricingClient` to *定价客户端* — these are names in the codebase. Surrounding prose is Chinese; the identifier is monospaced English.

**Phrasings that fit the style:**

- *"Order intake 模块过浅 —— 接口几乎和实现一样宽。"*
- *"Pricing 越过接缝泄漏。"*
- *"加深：一个接口，一处测试。"*
- *"两个适配器才证成接缝：生产用 HTTP，测试用内存版。"*

**收益 bullets** name the gain in glossary terms: *"局部性：bug 集中到一个模块"*, *"杠杆：一个接口 N 个调用点"*, *"接口收窄；实现吸收掉包装层"*. Don't write *"更易维护"* or *"代码更整洁"* — these aren't in the glossary and don't earn their place.

No hedging, no throat-clearing, no "值得一提的是…" / "需要注意…". If a sentence could be a bullet, make it a bullet. If a bullet could be cut, cut it. If a term isn't in the glossary above, reach for one that is before inventing a new one.
