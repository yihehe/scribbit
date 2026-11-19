import test from "node:test";
import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { JSDOM } from "jsdom";
await mkdir("../../build", { recursive: true });
const script = await readFile(
  "../../Sources/Scribbit/Resources/MilkdownEditor.js",
  "utf8",
);
const html = await readFile(
  "../../Sources/Scribbit/Resources/MilkdownIndex.html",
  "utf8",
);
async function setup(source = "Hello\n") {
  const dom = new JSDOM(html.replace(/<script.*?<\/script>/s, ""), {
    url: "scribbit-milkdown://editor/MilkdownIndex.html?token=fixture-token&test=1",
    runScripts: "outside-only",
    pretendToBeVisual: true,
  });
  const win = dom.window,
    messages = [];
  win.TextEncoder = TextEncoder;
  win.TextDecoder = TextDecoder;
  win.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
  win.IntersectionObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
  win.matchMedia = () => ({
    matches: false,
    addEventListener() {},
    removeEventListener() {},
  });
  win.Range.prototype.getClientRects = () => [];
  win.Range.prototype.getBoundingClientRect = () => ({
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    width: 0,
    height: 0,
  });
  win.HTMLElement.prototype.scrollIntoView = () => {};
  win.scrollTo = () => {};
  win.webkit = {
    messageHandlers: { richEditor: { postMessage: (v) => messages.push(v) } },
  };
  win.eval(script);
  for (let i = 0; i < 300 && !messages.some((m) => m.type === "ready"); i++)
    await new Promise((r) => setTimeout(r, 10));
  assert.ok(
    messages.some((m) => m.type === "ready"),
    JSON.stringify(messages),
  );
  win.scribbit.load({ generation: "generation-1", source, readOnly: false });
  const loaded = messages.findLast((m) => m.type === "loaded");
  return {
    dom,
    win,
    messages,
    loaded,
    get api() {
      return win.milkdownTest;
    },
    close: () => dom.window.close(),
  };
}
function flush(
  f,
  id = "request-1",
  inspection = false,
  committed = f.loaded.document,
) {
  f.win.scribbit.flush(id, inspection, {
    generation: "generation-1",
    document: committed,
  });
  return f.messages.findLast((m) =>
    ["snapshot", "flushError"].includes(m.type),
  );
}
function type(f, text) {
  const v = f.api.view();
  v.dispatch(
    v.state.tr.insertText(text, v.state.selection.from, v.state.selection.to),
  );
}
function enter(f) {
  return pressKey(f, "Enter");
}
function pressKey(f, key, modifiers = {}) {
  const v = f.api.view();
  let handled = false;
  v.someProp("handleKeyDown", (fn) => {
    if (
      fn(
        v,
        new f.win.KeyboardEvent("keydown", {
          key,
          keyCode: { Enter: 13, Tab: 9, Backspace: 8, Delete: 46 }[key],
          bubbles: true,
          ...modifiers,
        }),
      )
    ) {
      handled = true;
      return true;
    }
  });
  return handled;
}
function selectText(f, text, offset = 0) {
  const v = f.api.view();
  let position;
  v.state.doc.descendants((node, pos) => {
    if (node.isText && position === undefined && node.text.includes(text))
      position = pos + node.text.indexOf(text) + offset;
  });
  assert.notEqual(position, undefined, `Missing fixture text: ${text}`);
  v.dispatch(
    v.state.tr.setSelection(
      v.state.selection.constructor.near(v.state.doc.resolve(position)),
    ),
  );
}
test("empty notes and empty paragraphs have no placeholder prompt", async () => {
  for (const source of ["", "An existing paragraph\n"]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true);
      if (source) {
        const v = f.api.view();
        v.dispatch(
          v.state.tr.setSelection(
            v.state.selection.constructor.near(
              v.state.doc.resolve(v.state.doc.content.size - 1),
            ),
          ),
        );
        enter(f);
      }
      assert.equal(
        f.api
          .view()
          .state.plugins.some((plugin) =>
            plugin.key.startsWith("CREPE_PLACEHOLDER"),
          ),
        false,
      );
      assert.equal(
        f.win.document.querySelector(".crepe-placeholder, [data-placeholder]"),
        null,
      );
      type(f, "A new thought");
      assert.ok(f.api.view().state.doc.textContent.includes("A new thought"));
    } finally {
      f.close();
    }
  }
});
test("native committed tree bypasses serializer for unchanged punctuation and Undo", async () => {
  const f = await setup("A * literal\n");
  try {
    assert.equal(f.loaded.accepted, true);
    let result = flush(f);
    assert.equal(result.type, "snapshot");
    assert.equal(Object.hasOwn(result, "source"), false);
    f.win.scribbit.unlock();
    type(f, "X");
    f.win.scribbit.undo();
    result = flush(f);
    assert.equal(Object.hasOwn(result, "source"), false);
    assert.equal(f.api.view().editable, false);
  } finally {
    f.close();
  }
});
test("schema uses the bundled Milkdown nodes and marks", async () => {
  const f = await setup();
  try {
    console.log(
      "MILKDOWN_SCHEMA",
      Object.keys(f.api.view().state.schema.nodes),
      Object.keys(f.api.view().state.schema.marks),
    );
    assert.ok(f.api.view().state.schema.nodes.bullet_list);
    assert.ok(f.api.view().state.schema.marks.strong);
  } finally {
    f.close();
  }
});
test("common Markdown corpus loads without broad escape/table/link rejection", async () => {
  const corpus = [
    "# Heading\n\n**bold** *emphasis*.\n",
    "- one\n- two\n",
    "- [ ] task\n- [x] done\n",
    "```python\ndef hi():\n    return True\n```\n",
    "A * literal\n",
    "\\#\n",
    "# Title \\#\\#\n",
    "[link](https://example.invalid)\n",
    "[link][id]\n\n[id]: https://example.invalid\n",
    "| A | B |\n| - | - |\n| a | b |\n",
    "Hello 👋 café é 漢字\n",
    "> a quote\n\n---\n",
    "- parent\n  - nested\n",
  ];
  const results = [];
  for (const source of corpus) {
    const f = await setup(source);
    try {
      results.push({
        source,
        accepted: f.loaded.accepted,
        reason: f.loaded.reason,
      });
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      const s = flush(f);
      assert.equal(s.type, "snapshot");
      assert.equal(Object.hasOwn(s, "source"), false);
    } finally {
      f.close();
    }
  }
  await writeFile(
    "../../build/milkdown-corpus.json",
    JSON.stringify(results, null, 2) + "\n",
  );
});
test("actual keyboard input produces lists/code and snapshots are guarded", async () => {
  for (const [prefix, expected] of [
    ["-", "bullet_list"],
    ["```", "code_block"],
  ]) {
    const f = await setup("");
    try {
      type(f, prefix);
      const v = f.api.view(),
        { from, to } = v.state.selection;
      let handled = false;
      v.someProp("handleTextInput", (fn) => {
        if (fn(v, from, to, " ")) {
          handled = true;
          return true;
        }
      });
      assert.equal(handled, true, prefix);
      assert.equal(v.state.doc.firstChild.type.name, expected);
      const s = flush(f);
      console.log("INPUT_SNAPSHOT", prefix, s.type, s.message ?? s.source);
      assert.equal(s.type, "snapshot", JSON.stringify(s));
    } finally {
      f.close();
    }
  }
});
test("ordinary paragraph Enter and populated-list empty-next-item can save", async () => {
  for (const source of [
    "Paragraph\n",
    "- populated\n",
    "- [ ] populated\n",
    "1. populated\n",
    "```python\nprint(1)\n```\n",
  ]) {
    const f = await setup(source);
    try {
      const v = f.api.view();
      v.dispatch(
        v.state.tr.setSelection(
          v.state.selection.constructor.near(
            v.state.doc.resolve(v.state.doc.content.size - 1),
          ),
        ),
      );
      assert.equal(enter(f), true);
      const s = flush(f);
      console.log("ENTER_SNAPSHOT", source, s.type, s.message ?? s.source);
      assert.equal(s.type, "snapshot", JSON.stringify(s));
    } finally {
      f.close();
    }
  }
});
test("image/HTML sources fall back before becoming the editable rich document", async () => {
  for (const source of [
    "![alt](assets/x.png)\n",
    "<!-- comment -->\n\nText\n",
    "<script>bad()</script>\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, false);
      assert.ok(f.loaded.reason);
    } finally {
      f.close();
    }
  }
});
test("inspection bypasses export and stale generation cannot authorize source-less save", async () => {
  const f = await setup();
  try {
    type(f, "more");
    const inspect = flush(f, "inspect", true);
    assert.equal(inspect.type, "snapshot");
    assert.equal(Object.hasOwn(inspect, "source"), false);
    f.win.scribbit.unlock();
    f.win.scribbit.flush("stale", false, {
      generation: "old",
      document: f.api.documentJSON(),
    });
    const s = f.messages.at(-1);
    assert.equal(s.type, "snapshot");
    assert.equal(typeof s.source, "string");
  } finally {
    f.close();
  }
});

test("characterize actual keyboard document versus serialized Markdown", async () => {
  const rows = [];
  for (const [source, action] of [
    ["Paragraph\n", "enter"],
    ["Paragraph\n", "two-enter"],
    ["- populated\n", "enter"],
    ["- [ ] populated\n", "enter"],
    ["1. populated\n", "enter"],
    ["```python\nprint(1)\n```\n", "enter"],
    ["", "bullet"],
    ["", "code"],
  ]) {
    const f = await setup(source);
    try {
      const v = f.api.view();
      if (action === "bullet" || action === "code") {
        const prefix = action === "bullet" ? "-" : "```";
        type(f, prefix);
        const { from, to } = v.state.selection;
        v.someProp("handleTextInput", (fn) => fn(v, from, to, " "));
      } else {
        v.dispatch(
          v.state.tr.setSelection(
            v.state.selection.constructor.near(
              v.state.doc.resolve(v.state.doc.content.size - 1),
            ),
          ),
        );
        enter(f);
        if (action === "two-enter") enter(f);
      }
      const serialized = f.api.crepe.getMarkdown();
      rows.push({
        source,
        action,
        document: v.state.doc.toJSON(),
        serialized,
        reparsed: f.api.parse(serialized).toJSON(),
      });
    } finally {
      f.close();
    }
  }
  await writeFile(
    "../../build/milkdown-keyboard-characterization.json",
    JSON.stringify(rows, null, 2) + "\n",
  );
});

test("one terminal caret and list spread are the ONLY export projections", async () => {
  const f = await setup();
  try {
    const p = (text) => ({
      type: "paragraph",
      ...(text ? { content: [{ type: "text", text }] } : {}),
    });
    const doc = (content) => ({ type: "doc", content });
    const equal = f.api.sameExportDocument;
    assert.equal(equal(doc([p("a"), p()]), doc([p("a")])), true);
    assert.equal(equal(doc([p("a"), p(), p()]), doc([p("a")])), false);
    assert.equal(
      equal(doc([p("a"), p(), p("b")]), doc([p("a"), p("b")])),
      false,
    );
    assert.equal(equal(doc([p("a"), p("b")]), doc([p("a")])), false);
    assert.equal(
      equal(
        doc([
          {
            type: "code_block",
            attrs: { language: "python" },
            content: [{ type: "text", text: "x\n" }],
          },
        ]),
        doc([
          {
            type: "code_block",
            attrs: { language: "python" },
            content: [{ type: "text", text: "x" }],
          },
        ]),
      ),
      false,
    );
    assert.equal(
      equal(
        doc([{ type: "unknown", attrs: { x: 1 } }]),
        doc([{ type: "unknown", attrs: { x: 2 } }]),
      ),
      false,
    );
    assert.equal(
      equal(
        doc([{ type: "ordered_list", attrs: { order: 1, spread: true } }]),
        doc([{ type: "ordered_list", attrs: { order: 1, spread: false } }]),
      ),
      true,
    );
    assert.equal(
      equal(
        doc([{ type: "ordered_list", attrs: { order: 1, spread: true } }]),
        doc([{ type: "ordered_list", attrs: { order: 2, spread: false } }]),
      ),
      false,
    );
  } finally {
    f.close();
  }
});
test("exact empty-line placeholders reopen and no-edit repeated cycles retain authority", async () => {
  for (const placeholder of ["<br>", "<br/>", "<br />"]) {
    const source = `Paragraph\n\n${placeholder}\n`;
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      let baseline = f.loaded.document;
      for (let i = 0; i < 5; i++) {
        const s = flush(f, `cycle-${i}`, false, baseline);
        assert.equal(s.type, "snapshot");
        assert.equal(Object.hasOwn(s, "source"), false);
        f.win.scribbit.unlock();
        f.win.scribbit.load({
          generation: "generation-1",
          source,
          readOnly: false,
        });
        baseline = f.messages.findLast((m) => m.type === "loaded").document;
      }
    } finally {
      f.close();
    }
  }
  for (const source of [
    '<br onclick="bad()">\n',
    "Text <br /> inline\n",
    '<br class="x"/>\n',
    "<div>text</div>\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, false, source);
    } finally {
      f.close();
    }
  }
});
test("edited empty items/code whitespace are saved and can reopen; unrepresentable changes stay retained", async () => {
  for (const source of [
    "- populated\n",
    "- [ ] populated\n",
    "1. populated\n",
    "```python\nline\n\n```\n",
    "Paragraph\n",
  ]) {
    const f = await setup(source);
    try {
      const v = f.api.view();
      v.dispatch(
        v.state.tr.setSelection(
          v.state.selection.constructor.near(
            v.state.doc.resolve(v.state.doc.content.size - 1),
          ),
        ),
      );
      enter(f);
      if (source === "Paragraph\n") enter(f);
      const result = flush(f);
      assert.equal(result.type, "snapshot", JSON.stringify(result));
      f.win.scribbit.unlock();
      f.win.scribbit.load({
        generation: "generation-2",
        source: result.source,
        readOnly: false,
      });
      const loaded = f.messages.findLast((m) => m.type === "loaded");
      assert.equal(loaded.accepted, true, JSON.stringify(loaded));
    } finally {
      f.close();
    }
  }
});
test("read-only snapshots and save locks reject toolbar/transaction mutations", async () => {
  const f = await setup("Protected\n");
  try {
    const before = f.api.documentJSON();
    flush(f);
    type(f, "blocked");
    assert.deepEqual(f.api.documentJSON(), before);
    f.win.scribbit.unlock();
    f.win.scribbit.readOnly(true);
    type(f, "blocked");
    assert.deepEqual(f.api.documentJSON(), before);
  } finally {
    f.close();
  }
});

test("code language, literal escapes and table edits preserve actual semantic state", async () => {
  for (const source of [
    "A * literal\n",
    "\\#\n",
    "# Title \\#\\#\n",
    "[link][id]\n\n[id]: https://example.invalid\n",
    "| A | B |\n| - | - |\n| a | b |\n",
    '```python\nvalue = "👋"\n\n```\n',
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      const v = f.api.view();
      const at = source.startsWith("|") ? 4 : source.startsWith("```") ? 1 : 1;
      v.dispatch(v.state.tr.insertText("X", at));
      const s = flush(f);
      assert.equal(
        s.type,
        "snapshot",
        JSON.stringify({
          input: source,
          ...s,
          document: v.state.doc.toJSON(),
          serialized: f.api.crepe.getMarkdown(),
          reparsed: f.api.parse(f.api.crepe.getMarkdown()).toJSON(),
        }),
      );
      assert.ok(s.source.includes("X"));
      const before = v.state.doc.toJSON(),
        reparsed = f.api.parse(s.source).toJSON();
      assert.equal(f.api.sameExportDocument(before, reparsed), true);
    } finally {
      f.close();
    }
  }
});
test("pending composition, image paste, and stale clears do not authorize data loss", async () => {
  const f = await setup("Retain\n");
  try {
    const before = f.api.documentJSON();
    const paste = new f.win.Event("paste", { bubbles: true, cancelable: true });
    Object.defineProperty(paste, "clipboardData", {
      value: { files: [{ type: "image/png" }], getData: () => "" },
    });
    f.api.view().dom.dispatchEvent(paste);
    assert.deepEqual(f.api.documentJSON(), before);
    assert.match(f.messages.at(-1).message, /Image paste is not supported/);
    f.win.scribbit.clear("old-generation");
    assert.deepEqual(f.api.documentJSON(), before);
    f.win.scribbit.load({
      generation: "generation-2",
      source: "New document\n",
      readOnly: false,
    });
    f.win.scribbit.clear("generation-1");
    assert.equal(f.api.view().state.doc.textContent, "New document");
    f.win.scribbit.clear("generation-2");
    assert.equal(f.api.view().state.doc.textContent, "");
    assert.equal(f.api.view().editable, false);
  } finally {
    f.close();
  }
});
test("normal rich history and read-only restore do not overwrite latest content", async () => {
  const f = await setup("Original\n");
  try {
    type(f, "A");
    const edited = f.api.documentJSON();
    f.win.scribbit.undo();
    assert.deepEqual(f.api.documentJSON(), f.loaded.document);
    f.win.scribbit.redo();
    assert.deepEqual(f.api.documentJSON(), edited);
    const checkpoint = f.api.documentJSON();
    f.win.scribbit.restore({
      generation: "recovered",
      revision: 7,
      document: checkpoint,
    });
    assert.deepEqual(f.api.documentJSON(), checkpoint);
    assert.equal(f.messages.at(-1).type, "restored");
    f.win.scribbit.clear("generation-1");
    assert.deepEqual(f.api.documentJSON(), checkpoint);
  } finally {
    f.close();
  }
});

test("composition settlement waits for real ProseMirror DOM composition events", async () => {
  const f = await setup("Committed\n");
  try {
    const v = f.api.view();
    v.dom.dispatchEvent(
      new f.win.CompositionEvent("compositionstart", {
        bubbles: true,
        data: "",
      }),
    );
    assert.equal(v.composing, true);
    f.win.scribbit.flush("composing", false, {
      generation: "generation-1",
      document: f.loaded.document,
    });
    assert.equal(
      f.messages.some((m) => m.id === "composing"),
      false,
    );
    v.dom.dispatchEvent(
      new f.win.CompositionEvent("compositionend", { bubbles: true, data: "" }),
    );
    await new Promise((r) => setTimeout(r, 80));
    const result = f.messages.find((m) => m.id === "composing");
    assert.equal(result?.type, "snapshot");
    assert.equal(Object.hasOwn(result, "source"), false);
  } finally {
    f.close();
  }
});

test("unused and duplicate reference definitions fall back instead of disappearing", async () => {
  for (const source of [
    "Text\n\n[future]: https://example.invalid\n",
    "[use][id]\n\n[id]: https://first.invalid\n[id]: https://second.invalid\n",
    "[use][id]\n\n[id]: https://example.invalid\n[orphan]: https://keep.invalid\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, false, source);
      assert.ok(f.loaded.reason);
    } finally {
      f.close();
    }
  }
  const f = await setup('[use][id]\n\n[id]: https://example.invalid "title"\n');
  try {
    assert.equal(f.loaded.accepted, true);
    type(f, "X");
    const s = flush(f);
    assert.equal(s.type, "snapshot");
    assert.ok(s.source.includes("https://example.invalid"));
    assert.ok(s.source.includes("title"));
  } finally {
    f.close();
  }
});
test("multiline clipboard text and code whitespace use actual upstream-compatible slices", async () => {
  for (const source of ["Start\n", "```python\npass\n```\n"]) {
    const f = await setup(source);
    try {
      const v = f.api.view();
      const paste = new f.win.Event("paste", {
        bubbles: true,
        cancelable: true,
      });
      Object.defineProperty(paste, "clipboardData", {
        value: {
          files: [],
          getData: (kind) =>
            kind === "text/plain" ? "one\r\n  two\r\nthree" : "",
        },
      });
      v.dom.dispatchEvent(paste);
      const s = flush(f);
      assert.equal(s.type, "snapshot", JSON.stringify(s));
      assert.ok(s.source.includes("one"));
      assert.ok(s.source.includes("three"));
      if (source.startsWith("```"))
        assert.ok(s.source.includes("one\n  two\nthree"));
    } finally {
      f.close();
    }
  }
});

test("empty table cells and task toggles survive edited Markdown and reopen", async () => {
  for (const source of [
    "| A | B |\n| - | - |\n|  | value |\n",
    "|  | B |\n| - | - |\n| a |  |\n",
    "- [ ] task\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      const v = f.api.view();
      if (source.startsWith("-")) {
        let item;
        v.state.doc.descendants((node, pos) => {
          if (node.type.name === "list_item" && item === undefined)
            item = { node, pos };
        });
        v.dispatch(
          v.state.tr.setNodeMarkup(item.pos, undefined, {
            ...item.node.attrs,
            checked: true,
          }),
        );
      } else {
        v.dispatch(v.state.tr.insertText("X", 4));
      }
      const s = flush(f);
      assert.equal(s.type, "snapshot", JSON.stringify(s));
      if (source.startsWith("-")) assert.ok(s.source.includes("[x]"));
      f.win.scribbit.unlock();
      f.win.scribbit.load({
        generation: "generation-2",
        source: s.source,
        readOnly: false,
      });
      assert.equal(
        f.messages.findLast((m) => m.type === "loaded").accepted,
        true,
      );
    } finally {
      f.close();
    }
  }
});

test("loaded native baseline includes upstream caret settlement; focus does not create dirty intent or undo", async () => {
  for (const source of [
    "Paragraph\n",
    "- item\n",
    "```python\nx\n```\n",
    "| A |\n| - |\n| value |\n",
  ]) {
    const f = await setup(source);
    try {
      const loaded = f.messages.findLastIndex((m) => m.type === "loaded"),
        v = f.api.view();
      v.focus();
      v.dispatch(v.state.tr.setSelection(v.state.selection));
      await new Promise((r) => setTimeout(r, 20));
      assert.equal(
        f.messages.slice(loaded + 1).some((m) => m.type === "changed"),
        false,
        source,
      );
      assert.deepEqual(f.api.documentJSON(), f.loaded.document);
      const snapshot = flush(f);
      assert.equal(snapshot.type, "snapshot");
      assert.equal(Object.hasOwn(snapshot, "source"), false, source);
      f.win.scribbit.unlock();
      const before = f.api.documentJSON();
      f.win.scribbit.undo();
      assert.deepEqual(f.api.documentJSON(), before);
      f.win.scribbit.load({
        generation: "generation-new",
        source: "Next note\n",
        readOnly: false,
      });
      const newBaseline = f.api.documentJSON();
      f.win.scribbit.clear("generation-1");
      await new Promise((r) => setTimeout(r, 100));
      assert.deepEqual(f.api.documentJSON(), newBaseline);
    } finally {
      f.close();
    }
  }
});

test("actual Tab and Shift-Tab indent/outdent a list without losing content", async () => {
  const f = await setup("- parent\n- child\n");
  try {
    const v = f.api.view();
    let childPosition;
    v.state.doc.descendants((node, pos) => {
      if (node.isText && node.text === "child") childPosition = pos;
    });
    v.dispatch(
      v.state.tr.setSelection(
        v.state.selection.constructor.near(
          v.state.doc.resolve(childPosition + 2),
        ),
      ),
    );
    const press = (shift) => {
      let handled = false;
      v.someProp("handleKeyDown", (fn) => {
        if (
          fn(
            v,
            new f.win.KeyboardEvent("keydown", {
              key: "Tab",
              keyCode: 9,
              shiftKey: shift,
              bubbles: true,
            }),
          )
        ) {
          handled = true;
          return true;
        }
      });
      return handled;
    };
    assert.equal(press(false), true);
    let s = flush(f);
    assert.equal(s.type, "snapshot", JSON.stringify(s));
    assert.ok(s.source.includes("child"));
    f.win.scribbit.unlock();
    assert.equal(press(true), true);
    s = flush(f, "outdent");
    assert.equal(s.type, "snapshot", JSON.stringify(s));
    assert.equal(v.state.doc.textContent, "parentchild");
  } finally {
    f.close();
  }
});

test("upstream anchor sanitizer neutralizes unsafe schemes without mutating stored destinations", async () => {
  const f = await setup("A link\n");
  try {
    const v = f.api.view();
    for (const href of [
      "javascript:alert(1)",
      "JaVaScRiPt:alert(1)",
      "vbscript:msgbox(1)",
      "data:text/html,test",
      "file:///tmp/note",
      "java\tscript:alert(1)",
      "java\nscript:alert(1)",
      "java\u0000script:alert(1)",
      "java\u200bscript:alert(1)",
      "\ufeffjavascript:alert(1)",
    ]) {
      const mark = v.state.schema.marks.link.create({
        href,
        title: "Retained title",
      });
      v.dispatch(v.state.tr.removeMark(1, 7).addMark(1, 7, mark));
      const anchor = v.dom.querySelector("a");
      assert.ok(anchor, href);
      assert.equal(anchor.getAttribute("href"), "", href);
      let stored;
      v.state.doc.descendants((node) => {
        if (node.isText)
          stored =
            node.marks.find((m) => m.type.name === "link")?.attrs.href ??
            stored;
      });
      assert.equal(stored, href);
    }
    for (const href of [
      "https://example.invalid/x",
      "http://example.invalid",
      "mailto:test@example.invalid",
      "../assets/note.md",
      "#heading",
      "?query=value",
      "javascript%3Aalert(1)",
      "%6aavascript:alert(1)",
    ]) {
      v.dispatch(
        v.state.tr
          .removeMark(1, 7)
          .addMark(1, 7, v.state.schema.marks.link.create({ href })),
      );
      const anchor = v.dom.querySelector("a");
      assert.equal(anchor.getAttribute("href"), href);
      // Encoded protocol punctuation/letters are relative URL text, not schemes.
      assert.ok(
        !["javascript:", "data:", "vbscript:", "file:"].includes(
          anchor.protocol,
        ),
        href,
      );
    }
  } finally {
    f.close();
  }
});

test("unsafe source links retain destinations and literal code URLs stay code", async () => {
  for (const source of [
    "[link](javascript:alert)\n",
    "[link](java&#x73;cript:alert)\n",
    "[link](data:text/html,test)\n",
    "[link](file:///tmp/note)\n",
    "[link][id]\n\n[id]: vbscript:alert\n",
    "`javascript:alert(1)`\n\n```text\ndata:text/html,test\n```\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      for (const anchor of f.api.view().dom.querySelectorAll("a"))
        assert.equal(anchor.getAttribute("href"), "", source);
      assert.equal(Object.hasOwn(flush(f), "source"), false, source);
      f.win.scribbit.unlock();
      type(f, "X");
      const result = flush(f, "edited");
      assert.equal(result.type, "snapshot", JSON.stringify(result));
      if (source.startsWith("`"))
        assert.ok(result.source.includes("javascript:alert(1)"));
      else assert.match(result.source, /(?:javascript|data|file|vbscript):/);
    } finally {
      f.close();
    }
  }
});

test("mode replacement imports latest unsaved source and rejects a departed generation", async () => {
  const f = await setup("Original note\n");
  try {
    type(f, "Rich ");
    const exported = flush(f, "to-source");
    assert.equal(exported.type, "snapshot");
    assert.ok(exported.source.includes("Rich Original note"));
    f.win.scribbit.clear("generation-1");
    const nativeDraft = exported.source + "\nNewest native edit\n";
    f.win.scribbit.load({
      generation: "generation-2",
      source: nativeDraft,
      readOnly: false,
    });
    const loaded = f.messages.findLast((m) => m.type === "loaded");
    assert.equal(loaded.accepted, true);
    assert.equal(f.api.view().editable, true);
    assert.ok(
      f.api.view().state.doc.textContent.includes("Newest native edit"),
    );
    const newestTree = f.api.documentJSON();
    f.win.scribbit.clear("generation-1");
    assert.deepEqual(f.api.documentJSON(), newestTree);
    f.win.scribbit.flush("no-edit-after-mode", false, {
      generation: "generation-2",
      document: loaded.document,
    });
    const snapshot = f.messages.findLast((m) => m.type === "snapshot");
    assert.equal(Object.hasOwn(snapshot, "source"), false);
    f.win.scribbit.unlock();
    f.win.scribbit.undo();
    assert.deepEqual(f.api.documentJSON(), newestTree);
  } finally {
    f.close();
  }
});

test("oversized rich paste is rejected before mutation and the existing draft stays saveable", async () => {
  const f = await setup("Original\n");
  try {
    const v = f.api.view();
    const original = f.api.documentJSON();
    const paste = new f.win.Event("paste", { bubbles: true, cancelable: true });
    Object.defineProperty(paste, "clipboardData", {
      value: {
        files: [],
        getData: (kind) =>
          kind === "text/plain" ? "x".repeat(2 * 1024 * 1024) : "",
      },
    });
    v.dom.dispatchEvent(paste);
    assert.deepEqual(f.api.documentJSON(), original);
    assert.equal(v.editable, true);
    assert.ok(
      f.messages.some(
        (m) => m.type === "error" && m.message.includes("Switch to Source"),
      ),
    );
    const result = flush(f, "after-rejected-paste");
    assert.equal(result.type, "snapshot");
    assert.equal(Object.hasOwn(result, "source"), false);
  } finally {
    f.close();
  }
});

test("a loaded rich draft can grow past import threshold and export completely", async () => {
  for (const character of ["x", "/"]) {
    const f = await setup("Original\n");
    try {
      const addition = character.repeat(1024 * 1024 + 32);
      type(f, addition);
      const result = flush(f, "grown-rich-draft");
      assert.equal(result.type, "snapshot");
      assert.ok(result.source.startsWith(addition + "Original"));
      assert.ok(Buffer.byteLength(result.source) > 1024 * 1024);
      assert.equal(
        result.document.content[0].content[0].text.length,
        addition.length + 8,
      );
      f.win.scribbit.unlock();
      f.win.scribbit.load({
        generation: "next-open",
        source: result.source,
        readOnly: false,
      });
      const rejected = f.messages.findLast((m) => m.type === "loaded");
      assert.equal(rejected.accepted, false); // On next open native Source owns larger files.
      assert.match(rejected.reason, /1 MiB/);
    } finally {
      f.close();
    }
  }
});

test("canonical JSON quota counts exact UTF-8 bytes and many-node overhead", async () => {
  const f = await setup();
  try {
    const schema = f.api.view().state.schema;
    const doc = (text) =>
      schema.nodes.doc.create(null, [
        schema.nodes.paragraph.create(null, schema.text(text)),
      ]);
    const overhead = Buffer.byteLength(JSON.stringify(doc("x").toJSON())) - 1;
    const quota = 2 * 1024 * 1024;
    for (const unit of ["🐸", '/🐸\u2028\u2029\b\f\n\r\t"\\']) {
      const unitBytes = Buffer.byteLength(JSON.stringify(unit)) - 2;
      const repeats = Math.floor((quota - overhead) / unitBytes);
      const exact =
        unit.repeat(repeats) +
        "x".repeat(quota - overhead - repeats * unitBytes);
      assert.equal(
        Buffer.byteLength(
          JSON.stringify(f.api.boundedDocumentJSON(doc(exact))),
        ),
        quota,
      );
      assert.throws(() => f.api.boundedDocumentJSON(doc(exact + "x")), /2 MiB/);
    }
    const paragraph = schema.nodes.paragraph.create(null, schema.text("x"));
    const many = schema.nodes.doc.create(null, Array(40000).fill(paragraph));
    assert.throws(() => f.api.boundedDocumentJSON(many), /2 MiB/);
    const before = f.api.documentJSON();
    const v = f.api.view();
    v.dispatch(
      v.state.tr.replaceWith(0, v.state.doc.content.size, many.content),
    );
    assert.deepEqual(f.api.documentJSON(), before);
    f.win.scribbit.load({
      generation: "node-heavy-import",
      source: "x\n\n".repeat(40000),
      readOnly: false,
    });
    const rejected = f.messages.findLast((m) => m.type === "loaded");
    assert.equal(rejected.accepted, false);
    assert.match(rejected.reason, /2 MiB/);
    assert.deepEqual(f.api.documentJSON(), before); // Rejected before DOM replacement.
  } finally {
    f.close();
  }
});

test("transaction JSON admission component timings exclude DOM and whole-app claims", async () => {
  const cells = [];
  for (const size of [4096, 65536, 1048576]) {
    const f = await setup("x".repeat(size));
    try {
      const v = f.api.view();
      const tr = v.state.tr.insertText("x", 1);
      for (let i = 0; i < 5; i++)
        assert.equal(f.api.admitTransaction(tr), true);
      const samples = [];
      for (let i = 0; i < 30; i++) {
        const start = performance.now();
        assert.equal(f.api.admitTransaction(tr), true);
        samples.push(performance.now() - start);
      }
      samples.sort((a, b) => a - b);
      cells.push({
        sourceBytes: size,
        samples: samples.length,
        medianMilliseconds: samples[15],
        p95Milliseconds: samples[28],
      });
    } finally {
      f.close();
    }
  }
  await writeFile(
    "../../build/milkdown-admission-benchmark.json",
    JSON.stringify(
      {
        node: process.version,
        platform: process.platform,
        architecture: process.arch,
        scope:
          "Actual bundled transaction gate only. No DOM/layout/WebKit/whole-app claim.",
        cells,
      },
      null,
      2,
    ) + "\n",
  );
});

test("lifting an ordered child into a bullet sibling saves despite stale visual marker metadata", async () => {
  for (const source of [
    "- one\n  1. two\n",
    "- one\n\n  3. two\n",
    "- [ ] one\n  1. [x] two\n",
    "- [x] one\n  1. [ ] two\n",
  ]) {
    const f = await setup(source);
    try {
      assert.equal(f.loaded.accepted, true, JSON.stringify(f.loaded));
      selectText(f, "two");
      assert.equal(pressKey(f, "Tab", { shiftKey: true }), true);
      const actual = f.api.documentJSON();
      assert.equal(actual.content[0].type, "bullet_list");
      assert.equal(actual.content[0].content[1].attrs.listType, "ordered");
      const result = flush(f, "lift-into-bullet");
      assert.equal(result.type, "snapshot", JSON.stringify(result));
      const reopened = await setup(result.source);
      try {
        assert.equal(reopened.loaded.accepted, true);
        const list = reopened.api.view().state.doc.firstChild;
        assert.equal(list.type.name, "bullet_list");
        assert.equal(list.childCount, 2);
        assert.equal(list.child(0).textContent, "one");
        assert.equal(list.child(1).textContent, "two");
        const checks = [];
        list.forEach((item) => checks.push(item.attrs.checked));
        assert.deepEqual(
          checks,
          source.startsWith("- [ ]")
            ? [false, true]
            : source.startsWith("- [x]")
              ? [true, false]
              : [null, null],
        );
        assert.equal(Object.hasOwn(flush(reopened), "source"), false);
        f.win.scribbit.unlock();
        f.win.scribbit.undo();
        const undone = flush(f, "undo-mixed-lift");
        assert.equal(undone.type, "snapshot");
        assert.equal(Object.hasOwn(undone, "source"), false); // Exact native baseline, no edited serialization.
      } finally {
        reopened.close();
      }
    } finally {
      f.close();
    }
  }
});

test("marker normalization never hides order, checkbox, text, nesting, paragraph or custom-attribute loss", async () => {
  const f = await setup("3. one\n4. two\n");
  try {
    const original = f.api.documentJSON();
    const check = (mutate) => {
      const changed = structuredClone(original);
      mutate(changed);
      assert.equal(f.api.sameExportDocument(changed, original), false);
      assert.ok(f.api.exportDifference(changed, original));
    };
    check((doc) => {
      doc.content[0].attrs.order = 7;
    });
    check((doc) => {
      doc.content[0].content[1].attrs.checked = false;
    });
    check((doc) => {
      doc.content[0].content[1].attrs.label = "custom-marker";
    });
    check((doc) => {
      doc.content[0].content[1].attrs.listType = "custom-list";
    });
    check((doc) => {
      doc.content[0].content[1].attrs.unrecognized = "keep";
    });
    check((doc) => {
      doc.content[0].content[1].content[0].content[0].text = "changed";
    });
    check((doc) => {
      doc.content[0].content[1].content.push({ type: "paragraph" });
    });
    check((doc) => {
      doc.content[0].content.push({
        type: "list_item",
        attrs: {
          label: "5.",
          listType: "ordered",
          checked: null,
          spread: false,
        },
        content: [{ type: "paragraph" }],
      });
    });
    check((doc) => {
      doc.content[0].content[0].content.push({
        type: "bullet_list",
        attrs: { spread: false },
        content: [doc.content[0].content.pop()],
      });
    });
  } finally {
    f.close();
  }
});

test("actual public list commands, split/merge, indent/lift and checkbox UI remain saveable", async () => {
  for (const source of [
    "- one\n- two\n",
    "* one\n* two\n",
    "+ one\n+ two\n",
    "3. one\n4. two\n",
    "- [ ] one\n- [x] two\n",
    "- **one** and `code`\n- [two](https://example.invalid)\n",
  ])
    for (const operation of [
      "split",
      "indent-lift",
      "merge",
      "empty-exit",
      "checkbox",
    ]) {
      const f = await setup(source);
      try {
        assert.equal(f.loaded.accepted, true);
        selectText(
          f,
          "two",
          operation === "split" ? 1 : operation === "empty-exit" ? 3 : 0,
        );
        if (operation === "split") assert.equal(enter(f), true);
        if (operation === "indent-lift") {
          assert.equal(pressKey(f, "Tab"), true);
          assert.equal(pressKey(f, "Tab", { shiftKey: true }), true);
        }
        if (operation === "merge") assert.equal(pressKey(f, "Backspace"), true);
        if (operation === "empty-exit") {
          assert.equal(enter(f), true);
          assert.equal(enter(f), true);
        }
        if (operation === "checkbox" && source.startsWith("- [")) {
          const target = f.api.view().dom.querySelectorAll(".label-wrapper")[1];
          assert.ok(target);
          target.dispatchEvent(
            new f.win.MouseEvent("pointerdown", {
              bubbles: true,
              cancelable: true,
            }),
          );
          assert.equal(
            f.api.view().state.doc.firstChild.child(1).attrs.checked,
            false,
          );
        }
        const result = flush(f, operation);
        assert.equal(
          result.type,
          "snapshot",
          `${source} ${operation}: ${JSON.stringify(result)}`,
        );
      } finally {
        f.close();
      }
    }
  for (const [command, nodeName] of [
    ["WrapInBulletList", "bullet_list"],
    ["WrapInOrderedList", "ordered_list"],
  ]) {
    const f = await setup("one\n\ntwo\n");
    try {
      selectText(f, "two");
      assert.equal(
        f.api.crepe.editor.action((ctx) => ctx.get("commands").call(command)),
        true,
      );
      assert.equal(f.api.view().state.doc.child(1).type.name, nodeName);
      assert.equal(flush(f).type, "snapshot");
    } finally {
      f.close();
    }
  }
});

test("real trailing-indent loss stays blocked with content-free diagnostics and Undo recovery", async () => {
  const fixture = "PRIVATE_TEST_FIXTURE";
  const ordinary = await setup(`- ${fixture}\n- next\n`);
  try {
    selectText(ordinary, fixture, fixture.length);
    assert.equal(pressKey(ordinary, "Tab"), true);
    const saved = flush(ordinary, "ordinary-end-indent");
    assert.equal(saved.type, "snapshot");
    assert.ok(saved.source.includes("&#x20;"));
    assert.equal(
      ordinary.api.parse(saved.source).firstChild.firstChild.textContent,
      fixture + "    ",
    );
  } finally {
    ordinary.close();
  }
  const f = await setup(`- ${fixture}\n  next\n`);
  try {
    selectText(f, fixture, fixture.length);
    assert.equal(pressKey(f, "Tab"), true);
    const before = f.api.documentJSON();
    const result = flush(f, "trailing-indent");
    assert.equal(result.type, "flushError");
    assert.match(result.message, /trailing-whitespace at \$\.content\[0\]/);
    assert.match(
      result.message,
      /Remove the trailing spaces\/indentation or Undo/,
    );
    assert.equal(result.message.includes(fixture), false);
    assert.deepEqual(f.api.documentJSON(), before);
    assert.equal(f.api.view().editable, true);
    f.win.scribbit.undo();
    assert.equal(flush(f, "undo-indent").type, "snapshot");
  } finally {
    f.close();
  }
});

test("seeded short public-key list edits either reopen safely or retain the guarded draft", async () => {
  const outcomes = { snapshots: 0, retained: 0, handledKeys: 0 };
  for (const source of [
    "- one\n- two\n",
    "3. one\n4. two\n",
    "- [ ] one\n- [x] two\n",
    "- one\n  1. two\n",
    "1. one\n   - two\n",
    "- **one** and `code`\n- [two](https://example.invalid)\n",
  ])
    for (let seed = 1; seed <= 4; seed++) {
      const f = await setup(source);
      let state = seed;
      const random = (limit) => {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return state % limit;
      };
      try {
        for (let step = 0; step < 18; step++) {
          const v = f.api.view(),
            positions = [];
          v.state.doc.descendants((node, pos) => {
            if (node.isText)
              for (let offset = 0; offset <= node.text.length; offset++)
                positions.push(pos + offset);
          });
          const position = positions.length
            ? positions[random(positions.length)]
            : 1;
          v.dispatch(
            v.state.tr.setSelection(
              v.state.selection.constructor.near(v.state.doc.resolve(position)),
            ),
          );
          const operation = [
            "Enter",
            "Tab",
            "ShiftTab",
            "Backspace",
            "Delete",
            "text",
          ][random(6)];
          if (operation === "text") type(f, "x");
          else if (
            pressKey(f, operation === "ShiftTab" ? "Tab" : operation, {
              shiftKey: operation === "ShiftTab",
            })
          )
            outcomes.handledKeys++;
          const before = f.api.documentJSON();
          const result = flush(f, `seed-${seed}-step-${step}`);
          if (result.type === "snapshot") {
            outcomes.snapshots++;
            if (Object.hasOwn(result, "source"))
              assert.ok(f.api.safeImport(result.source));
          } else {
            outcomes.retained++;
            assert.match(
              result.message,
              /(?:text|attribute|structure|child-count|trailing-whitespace) at \$/,
            );
            assert.deepEqual(f.api.documentJSON(), before);
          }
          f.win.scribbit.unlock();
          assert.equal(v.editable, true);
        }
      } finally {
        f.close();
      }
    }
  assert.ok(
    outcomes.snapshots > 0 && outcomes.retained > 0 && outcomes.handledKeys > 0,
  );
  await writeFile(
    "../../build/milkdown-seeded-list-outcomes.json",
    JSON.stringify(outcomes, null, 2) + "\n",
  );
});

test("splitting a restarted numbered list preserves both actual starting orders", async () => {
  const f = await setup("3. one\n4. two\n\nseparator\n\n9. three\n10. four\n");
  try {
    assert.equal(f.loaded.accepted, true);
    selectText(f, "three", 2);
    assert.equal(enter(f), true);
    const result = flush(f, "split-restarted-list");
    assert.equal(result.type, "snapshot", JSON.stringify(result));
    const reopened = await setup(result.source);
    try {
      assert.equal(reopened.loaded.accepted, true);
      const lists = [];
      reopened.api.view().state.doc.descendants((node) => {
        if (node.type.name === "ordered_list") {
          const items = [];
          node.forEach((item) => items.push(item.textContent));
          lists.push({ order: node.attrs.order, items });
        }
      });
      assert.deepEqual(lists, [
        { order: 3, items: ["one", "two"] },
        { order: 9, items: ["th", "ree", "four"] },
      ]);
    } finally {
      reopened.close();
    }
  } finally {
    f.close();
  }
});

test("actual block hover service cannot activate the floating handle while slash remains enabled", async () => {
  const f = await setup("- parent\n- child\n");
  try {
    const v = f.api.view();
    await new Promise((resolve) => f.win.requestAnimationFrame(resolve));
    await new Promise((resolve) => f.win.requestAnimationFrame(resolve));
    const handle = f.win.document
      .querySelector(".milkdown-block-handle .operation-item")
      ?.closest(".milkdown-block-handle");
    assert.ok(
      handle,
      "Upstream BlockEdit is still installed, not globally disabled",
    );
    assert.ok(
      v.state.plugins.some((plugin) => plugin.key.startsWith("CREPE_MENU")),
    );
    const ctx = f.api.crepe.editor.ctx;
    const original = ctx.get("blockConfig").filterNodes;
    const child = v.dom.querySelectorAll(".milkdown-list-item-block")[1];
    assert.ok(child);
    // JSDOM has no layout/hit-testing. Mock only geometry, leaving the actual
    // bundled pointer handler, target lookup/filter and provider intact.
    f.win.document.elementFromPoint = () => child;
    const originalCoords = v.posAtCoords;
    v.posAtCoords = () => ({ pos: 13, inside: 12 });
    let checks = 0;
    ctx.update("blockConfig", (config) => ({
      ...config,
      filterNodes: (pos, node) => {
        checks++;
        return original(pos, node);
      },
    }));
    const hover = async () => {
      v.dom.dispatchEvent(
        new f.win.MouseEvent("pointermove", {
          bubbles: true,
          clientX: 10,
          clientY: 10,
        }),
      );
      await new Promise((resolve) => setTimeout(resolve, 250));
    };
    await hover();
    assert.ok(checks > 0, "Actual service queried the configured filter");
    assert.equal(handle.dataset.show, "false");
    // Positive control: the same service/geometry must show a real handle when
    // targets are allowed; otherwise a permanently-hidden fixture proves nothing.
    ctx.update("blockConfig", (config) => ({
      ...config,
      filterNodes: () => true,
    }));
    await hover();
    assert.equal(handle.dataset.show, "true");
    ctx.update("blockConfig", (config) => ({
      ...config,
      filterNodes: original,
    }));
    await hover();
    assert.equal(handle.dataset.show, "false");
    v.posAtCoords = originalCoords;
    assert.equal(flush(f).type, "snapshot");
  } finally {
    f.close();
  }
});

test("slash menu still opens and runs real bullet, task and code-block actions", async () => {
  for (const [query, label, expected] of [
    ["/bullet", "Bullet List", "bullet_list"],
    ["/task", "Task List", "bullet_list"],
    ["/code", "Code", "code_block"],
  ]) {
    const f = await setup("");
    try {
      const v = f.api.view();
      v.focus();
      type(f, query);
      await new Promise((resolve) => setTimeout(resolve, 100));
      const menu = f.win.document.querySelector(".milkdown-slash-menu");
      assert.ok(menu);
      assert.equal(menu.dataset.show, "true", query);
      const item = [...menu.querySelectorAll(".menu-groups li")].find(
        (node) => node.textContent.trim() === label,
      );
      assert.ok(item, `Actual slash action ${label} is present`);
      item.dispatchEvent(
        new f.win.MouseEvent("pointerup", { bubbles: true, cancelable: true }),
      );
      assert.equal(v.state.doc.firstChild.type.name, expected);
      if (query === "/task")
        assert.equal(v.state.doc.firstChild.firstChild.attrs.checked, false);
      type(f, "created");
      const result = flush(f, `slash-${expected}`);
      assert.equal(result.type, "snapshot", JSON.stringify(result));
      assert.ok(result.source.includes("created"));
      assert.ok(
        [...f.win.document.querySelectorAll(".milkdown-block-handle")].every(
          (handle) => handle.dataset.show === "false",
        ),
      );
    } finally {
      f.close();
    }
  }
});
