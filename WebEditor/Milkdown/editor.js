import { Crepe } from "@milkdown/crepe";
import {
  editorViewCtx,
  editorViewOptionsCtx,
  parserCtx,
  remarkCtx,
  remarkStringifyOptionsCtx,
  serializerCtx,
} from "@milkdown/kit/core";
import { Fragment, Slice } from "@milkdown/kit/prose/model";
import { Plugin, EditorState, TextSelection } from "@milkdown/kit/prose/state";
import { undo, redo, undoDepth, redoDepth } from "@milkdown/kit/prose/history";
import { $prose } from "@milkdown/kit/utils";
import { headingIdGenerator } from "@milkdown/kit/preset/commonmark";
import { blockConfig } from "@milkdown/kit/plugin/block";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/classic-dark.css";
import "./style.css";

const token = new URL(location.href).searchParams.get("token");
let generation = null,
  revision = 0,
  locked = true,
  loading = true,
  readOnly = false;
let crepe = null,
  pendingFlush = null,
  checkpointTimer = null;
const maxImportSource = 1024 * 1024,
  maxSource = 64 * 1024 * 1024,
  maxJSON = 2 * 1024 * 1024;
const bytes = (value) => new TextEncoder().encode(value).length;
const stable = (value) =>
  Array.isArray(value)
    ? value.map(stable)
    : value && typeof value === "object"
      ? Object.fromEntries(
          Object.entries(value)
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([k, v]) => [k, stable(v)]),
        )
      : value;
const sameTree = (a, b) =>
  JSON.stringify(stable(a)) === JSON.stringify(stable(b));
const emptyParagraph = (node) =>
  node?.type === "paragraph" && !node.content?.length;
function layoutProjection(value, parent = null, index = 0) {
  if (Array.isArray(value))
    return value.map((entry) => layoutProjection(entry));
  if (!value || typeof value !== "object") return value;
  const result = Object.fromEntries(
    Object.entries(value).map(([k, v]) => [
      k,
      k === "content" && Array.isArray(v)
        ? v.map((child, childIndex) =>
            layoutProjection(child, value, childIndex),
          )
        : layoutProjection(v),
    ]),
  );
  // Spread changes Markdown spacing, not list text, nesting, order or checkbox state.
  if (
    ["bullet_list", "ordered_list", "list_item"].includes(result.type) &&
    result.attrs
  ) {
    result.attrs = { ...result.attrs };
    delete result.attrs.spread;
  }
  // Pinned Milkdown stores a rendered marker on each item, but Markdown's list
  // kind/start come from the containing list. Its public order-sync plugin does
  // not clear a lifted ordered item's stale marker under a bullet parent.
  // Derive ONLY recognized upstream marker metadata; never normalize checked,
  // list order, nesting/content, or arbitrary/custom attributes.
  if (
    result.type === "list_item" &&
    ["bullet_list", "ordered_list"].includes(parent?.type) &&
    ["bullet", "ordered"].includes(result.attrs?.listType) &&
    /^(?:•|\d+\.)$/.test(result.attrs?.label ?? "")
  ) {
    const ordered = parent.type === "ordered_list",
      order = parent.attrs?.order ?? 1;
    if (!ordered || (Number.isSafeInteger(order) && order >= 0)) {
      result.attrs.listType = ordered ? "ordered" : "bullet";
      result.attrs.label = ordered ? `${order + index}.` : "•";
    }
  }
  return result;
}
function exportDifference(document, reparsed) {
  let left = layoutProjection(document);
  const right = layoutProjection(reparsed);
  if (sameTree(left, right)) return null;
  // Pinned upstream docSchema explicitly omits ONE terminal empty typing area.
  // Never remove nested/list empty items, middle paragraphs or code whitespace.
  if (
    left.type === "doc" &&
    emptyParagraph(left.content?.at(-1)) &&
    left.content.length === (right.content?.length ?? 0) + 1
  )
    left = { ...left, content: left.content.slice(0, -1) };
  return firstDifference(left, right);
}
const safePathKeys = new Set([
  "type",
  "content",
  "attrs",
  "marks",
  "text",
  "order",
  "checked",
  "label",
  "listType",
  "level",
  "language",
  "href",
  "title",
  "isInline",
  "align",
  "colspan",
  "rowspan",
  "colwidth",
  "id",
]);
function firstDifference(left, right, path = "$") {
  if (sameTree(left, right)) return null;
  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length)
      return { category: "child-count", path: `${path}.length` };
    for (let i = 0; i < left.length; i++) {
      const difference = firstDifference(left[i], right[i], `${path}[${i}]`);
      if (difference) return difference;
    }
  } else if (
    left &&
    right &&
    typeof left === "object" &&
    typeof right === "object"
  ) {
    for (const key of new Set([...Object.keys(left), ...Object.keys(right)])) {
      const difference = firstDifference(
        left[key],
        right[key],
        `${path}.${safePathKeys.has(key) ? key : "field"}`,
      );
      if (difference) return difference;
    }
  }
  let category = path.endsWith(".text")
    ? "text"
    : path.includes(".attrs.")
      ? "attribute"
      : "structure";
  if (
    category === "text" &&
    typeof left === "string" &&
    typeof right === "string" &&
    left.replace(/[ \t]+$/g, "") === right.replace(/[ \t]+$/g, "")
  )
    category = "trailing-whitespace";
  return { category, path };
}
const sameExportDocument = (document, reparsed) =>
  !exportDifference(document, reparsed);
const isEmptyLineHTML = (node) =>
  node?.type === "html" && /^<br\s*\/?>$/i.test((node.value ?? "").trim());
function sameSourceSemantics(left, right) {
  if (sameTree(left, right)) return true;
  if (
    left.type === "root" &&
    left.children?.at(-1)?.type === "paragraph" &&
    !left.children.at(-1).children?.length
  )
    return sameTree({ ...left, children: left.children.slice(0, -1) }, right);
  return false;
}
const send = (type, payload = {}) =>
  window.webkit?.messageHandlers?.richEditor?.postMessage({
    type,
    token,
    generation,
    ...payload,
  });
const fail = (message) =>
  send("error", { message: String(message).slice(0, 1000) });
const view = () => crepe.editor.action((ctx) => ctx.get(editorViewCtx));
const parse = (source) =>
  crepe.editor.action((ctx) => ctx.get(parserCtx)(source));
function boundedDocumentJSON(document) {
  const doc = document.toJSON();
  // Match native validation before mutation, including small but deeply nested
  // documents. Root depth is zero on both sides of the bridge.
  const pending = [[doc, 0]];
  while (pending.length) {
    const [node, depth] = pending.pop();
    if (depth >= 100)
      throw new Error("Rich document exceeds its nesting limit.");
    for (const child of node.content ?? []) pending.push([child, depth + 1]);
  }
  if (bytes(JSON.stringify(doc)) > maxJSON)
    throw new Error(
      "Milkdown document exceeds its 2 MiB canonical JSON limit; draft retained.",
    );
  return doc;
}
const documentJSON = () => boundedDocumentJSON(view().state.doc);
function replaceDocument(value) {
  const v = view(),
    doc = v.state.schema.nodeFromJSON(value);
  doc.check();
  v.updateState(
    EditorState.create({
      schema: v.state.schema,
      doc,
      plugins: v.state.plugins,
    }),
  );
}
function lock(value) {
  locked = value;
  crepe?.setReadonly(locked || readOnly);
}
function sourceAST(source) {
  const root = crepe.editor.action((ctx) => ctx.get(remarkCtx).parse(source));
  const definitions = new Map(),
    usedDefinitions = new Set();
  function collect(node) {
    if (node.type === "definition") {
      if (definitions.has(node.identifier))
        throw new Error(
          "Duplicate reference definitions require the source editor.",
        );
      definitions.set(node.identifier, node);
    }
    if (node.type === "linkReference") usedDefinitions.add(node.identifier);
    for (const child of node.children ?? []) collect(child);
  }
  collect(root);
  function normalize(node) {
    if (Array.isArray(node))
      return node
        .filter(
          (n) => n?.type !== "definition" || !usedDefinitions.has(n.identifier),
        )
        .map(normalize);
    if (!node || typeof node !== "object") return node;
    if (isEmptyLineHTML(node)) return { type: "paragraph", children: [] };
    if (
      ["paragraph", "tableCell"].includes(node.type) &&
      node.children?.length === 1 &&
      isEmptyLineHTML(node.children[0])
    )
      return { type: node.type, children: [] };
    if (node.type === "linkReference") {
      const def = definitions.get(node.identifier);
      if (!def)
        throw new Error(
          "Unresolved reference link requires the native source editor.",
        );
      return normalize({
        type: "link",
        url: def.url,
        title: def.title ?? null,
        children: node.children,
      });
    }
    return Object.fromEntries(
      Object.entries(node)
        .filter(([key]) => !["position", "spread"].includes(key))
        .map(([key, value]) => [key, normalize(value)]),
    );
  }
  return normalize(root);
}
function rejectUnsupportedSource(source) {
  if (
    /\r(?!\n)/.test(source) ||
    (source.includes("\r\n") && /(?<!\r)\n/.test(source))
  )
    throw new Error(
      "Mixed or legacy line endings remain in the native source editor.",
    );
  if (
    /^(---|\+\+\+)\r?\n/.test(source) &&
    /^---\s*$|^\+\+\+\s*$/m.test(source.split("\n").slice(1).join("\n"))
  )
    throw new Error(
      "Possible frontmatter is preserved in the native source editor.",
    );
  const ast = crepe.editor.action((ctx) => ctx.get(remarkCtx).parse(source));
  function visit(node, parent = null) {
    if (["image", "imageReference"].includes(node.type))
      throw new Error(
        "Notes containing images open in Source because rich image editing is not supported yet.",
      );
    const emptyPlaceholder =
      isEmptyLineHTML(node) &&
      (["root", "listItem", "blockquote"].includes(parent?.type) ||
        (["paragraph", "tableCell"].includes(parent?.type) &&
          parent.children.length === 1));
    if (
      !emptyPlaceholder &&
      [
        "html",
        "yaml",
        "toml",
        "footnoteDefinition",
        "footnoteReference",
        "mdxJsxFlowElement",
        "mdxjsEsm",
      ].includes(node.type)
    )
      throw new Error(
        "This source construct is not enabled in Milkdown; the native source editor preserves it.",
      );
    for (const child of node.children ?? []) visit(child, node);
  }
  visit(ast);
}
function supportedDocument(doc) {
  doc.descendants((node) => {
    if (["image", "image-block", "html"].includes(node.type.name))
      throw new Error(
        "Image/HTML insertion is not enabled. Your draft is retained; Undo or use source mode.",
      );
  });
}
function safeImport(source) {
  if (bytes(source) > maxImportSource)
    throw new Error(
      "Files larger than 1 MiB open in the native source editor.",
    );
  rejectUnsupportedSource(source);
  const parsed = parse(source);
  const document = boundedDocumentJSON(parsed);
  supportedDocument(parsed);
  const serialized = crepe.editor.action((ctx) =>
    ctx.get(serializerCtx)(parsed),
  );
  if (!sameExportDocument(parsed.toJSON(), parse(serialized).toJSON()))
    throw new Error(
      "Milkdown cannot preserve this document structure on roundtrip; using source mode.",
    );
  if (!sameSourceSemantics(sourceAST(source), sourceAST(serialized)))
    throw new Error(
      "The source contains unsupported Markdown semantics; using native source mode.",
    );
  return document;
}
function currentSnapshot(committed) {
  const document = documentJSON();
  const unchanged =
    committed?.generation === generation &&
    sameTree(document, committed.document);
  let source;
  if (!unchanged) {
    supportedDocument(view().state.doc);
    source = crepe.getMarkdown();
    if (bytes(source) > maxSource)
      throw new Error(
        "Edited Markdown exceeds the 64 MiB file limit; draft retained.",
      );
    const reparsed = parse(source).toJSON();
    const difference = exportDifference(document, reparsed);
    if (difference)
      throw new Error(
        `This rich edit cannot currently be represented as Markdown without changing structure (${difference.category} at ${difference.path.slice(0, 180)}). No file was written; your draft is still here. ${
          difference.category === "trailing-whitespace"
            ? "Remove the trailing spaces/indentation or Undo the last edit."
            : "Continue editing or Undo the last edit."
        }`,
      );
  }
  const selection =
    view().state.selection.toJSON().type === "text"
      ? { from: view().state.selection.from, to: view().state.selection.to }
      : null;
  return {
    ...(unchanged ? {} : { source }),
    document,
    revision,
    selection,
    scroll: window.scrollY,
  };
}
function completeFlush() {
  if (!pendingFlush || view().composing) return;
  const { id, inspection, committed } = pendingFlush;
  pendingFlush = null;
  lock(true);
  try {
    send("snapshot", {
      id,
      ...(inspection
        ? { revision, document: documentJSON() }
        : currentSnapshot(committed)),
    });
  } catch (error) {
    send("flushError", { id, message: error.message });
    lock(false);
  }
}
function admitTransaction(tr) {
  if (!tr.docChanged || loading) return true;
  if (locked || readOnly) return false;
  try {
    boundedDocumentJSON(tr.doc);
    return true;
  } catch {
    fail(
      "This edit exceeds the rich editor's size or nesting limit. Switch to Source and try again. Nothing was inserted.",
    );
    return false;
  }
}
const integration = $prose(
  () =>
    new Plugin({
      filterTransaction: admitTransaction,
      view: () => ({
        update(next, previous) {
          if (loading || next.state.doc.eq(previous.doc)) return;
          revision++;
          send("changed", {
            revision,
            canUndo: undoDepth(next.state) > 0,
            canRedo: redoDepth(next.state) > 0,
          });
          clearTimeout(checkpointTimer);
          const expected = generation;
          checkpointTimer = setTimeout(() => {
            checkpointTimer = null;
            if (generation !== expected) return;
            try {
              send("checkpoint", { revision, document: documentJSON() });
            } catch (error) {
              fail(error.message);
            }
          }, 80);
        },
      }),
      props: {
        handleDOMEvents: {
          compositionend: () => {
            if (pendingFlush) setTimeout(completeFlush, 30);
            return false;
          },
        },
      },
    }),
);
function handlePaste(_view, event, parsedSlice) {
  if (locked || readOnly) return true;
  if (event.clipboardData?.files.length) {
    event.preventDefault();
    fail("Image paste is not supported yet. Nothing was inserted or written.");
    return true;
  }
  // ProseMirror has already parsed clipboard HTML through the editor schema
  // and upstream transforms. Preserve that slice instead of flattening it.
  // Code blocks still use literal plain text, and unsupported image/HTML nodes
  // remain rejected before any insertion.
  if (
    event.clipboardData?.getData("text/html") &&
    !_view.state.selection.$from.parent.type.spec.code &&
    parsedSlice
  ) {
    event.preventDefault();
    try {
      supportedDocument(parsedSlice.content);
      _view.dispatch(_view.state.tr.replaceSelection(parsedSlice).scrollIntoView());
    } catch {
      fail("This clipboard content is not supported. Nothing was inserted.");
    }
    return true;
  }
  const text = event.clipboardData?.getData("text/plain");
  if (text != null) {
    event.preventDefault();
    const v = view(),
      normalized = text.replace(/\r\n?/g, "\n");
    if (
      v.state.selection.$from.parent.type.name === "code_block" ||
      !normalized.includes("\n")
    )
      v.dispatch(v.state.tr.insertText(normalized));
    else {
      const paragraphs = normalized
        .split("\n")
        .map((line) =>
          v.state.schema.nodes.paragraph.create(
            null,
            line ? v.state.schema.text(line) : null,
          ),
        );
      v.dispatch(
        v.state.tr.replaceSelection(
          new Slice(Fragment.fromArray(paragraphs), 1, 1),
        ),
      );
    }
    return true;
  }
  return true;
}
window.scribbit = {
  load(payload) {
    loading = true;
    generation = payload.generation;
    pendingFlush = null;
    clearTimeout(checkpointTimer);
    lock(true);
    try {
      const doc = safeImport(payload.source);
      replaceDocument(doc);
      // Settle Milkdown's documented appended typing-area transaction before
      // native establishes the committed tree. A later focus/selection event
      // must not turn a read-only open into a synthetic source edit.
      const settledView = view();
      settledView.dispatch(settledView.state.tr.setMeta("addToHistory", false));
      revision = 0;
      readOnly = payload.readOnly;
      if (payload.position?.selection) {
        try {
          const v = view(),
            max = v.state.doc.content.size;
          v.dispatch(
            v.state.tr.setSelection(
              TextSelection.create(
                v.state.doc,
                Math.max(0, Math.min(max, payload.position.selection.from)),
                Math.max(0, Math.min(max, payload.position.selection.to)),
              ),
            ),
          );
        } catch {}
      }
      loading = false;
      lock(false);
      requestAnimationFrame(() =>
        window.scrollTo(0, payload.position?.scroll ?? 0),
      );
      send("loaded", { accepted: true, revision, document: documentJSON() });
    } catch (error) {
      loading = false;
      send("loaded", { accepted: false, reason: error.message });
    }
  },
  flush(id, inspection = false, committed = null) {
    if (pendingFlush) {
      send("flushError", { id, message: "A flush is already pending." });
      return;
    }
    pendingFlush = { id, inspection, committed };
    if (view().composing) {
      view().dom.blur();
      return;
    }
    completeFlush();
  },
  unlock() {
    pendingFlush = null;
    lock(false);
  },
  focus() {
    if (!locked && !readOnly) view().focus();
  },
  undo() {
    if (!locked && !readOnly) {
      const v = view();
      undo(v.state, v.dispatch);
    }
  },
  redo() {
    if (!locked && !readOnly) {
      const v = view();
      redo(v.state, v.dispatch);
    }
  },
  readOnly(value) {
    readOnly = value;
    lock(locked);
  },
  clear(expected) {
    if (generation !== expected) return;
    generation = null;
    pendingFlush = null;
    clearTimeout(checkpointTimer);
    loading = true;
    lock(true);
    view().dom.blur();
    replaceDocument({ type: "doc", content: [{ type: "paragraph" }] });
  },
  restore(payload) {
    loading = true;
    generation = payload.generation;
    replaceDocument(payload.document);
    revision = payload.revision;
    loading = false;
    lock(false);
    send("restored", { revision });
  },
};
async function boot() {
  crepe = new Crepe({
    root: "#editor",
    defaultValue: "",
    features: {
      [Crepe.Feature.Latex]: false,
      [Crepe.Feature.AI]: false,
      [Crepe.Feature.TopBar]: false,
      [Crepe.Feature.ImageBlock]: false,
      [Crepe.Feature.Placeholder]: false,
    },
  });
  crepe.editor.config((ctx) => {
    // Pinned Milkdown's text fast path emits trailing/all-space text verbatim,
    // which Markdown can trim or reinterpret as an empty item/hard break.
    // Let the existing Markdown safety encoder preserve those boundary spaces
    // with character references. Code/inline-code use their own handlers.
    ctx.update(remarkStringifyOptionsCtx, (options) => ({
      ...options,
      handlers: {
        ...options.handlers,
        text: (node, _parent, state, info) => state.safe(node.value, info),
      },
    }));
    // Crepe's BlockEdit also supplies slash commands, so keep that feature.
    // Override its earlier default target filter through the public block API;
    // no eligible block means the floating grip/add handle never activates.
    ctx.update(blockConfig.key, (config) => ({
      ...config,
      filterNodes: () => false,
    }));
    // Derived DOM ids are not Markdown content. Disable the upstream decoration
    // publicly instead of relaxing the document's attribute-equivalence guard.
    ctx.set(headingIdGenerator.key, () => "");
    ctx.update(editorViewOptionsCtx, (options) => ({
      ...options,
      // Leave ProseMirror's rich HTML serialization intact. Plain-text-only
      // destinations receive readable text, not Milkdown's Markdown fallback.
      clipboardTextSerializer: (slice) =>
        slice.content.textBetween(0, slice.content.size, "\n"),
      handlePaste,
      handleDrop: (_view, event) => {
        event.preventDefault();
        fail("File/image drops are not enabled.");
        return true;
      },
    }));
  });
  crepe.editor.use(integration);
  await crepe.create();
  lock(true);
  if (new URL(location.href).searchParams.has("test"))
    window.milkdownTest = {
      crepe,
      view,
      parse,
      safeImport,
      currentSnapshot,
      sourceAST,
      sameTree,
      documentJSON,
      sameExportDocument,
      exportDifference,
      boundedDocumentJSON,
      admitTransaction,
    };
  send("ready");
}
boot().catch((error) => fail(error.message));
