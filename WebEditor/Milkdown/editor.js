import { Crepe } from "@milkdown/crepe";
import {
  editorViewCtx,
  editorViewOptionsCtx,
  parserCtx,
  remarkCtx,
  serializerCtx,
} from "@milkdown/kit/core";
import { Fragment, Slice } from "@milkdown/kit/prose/model";
import { Plugin, EditorState, TextSelection } from "@milkdown/kit/prose/state";
import { undo, redo, undoDepth, redoDepth } from "@milkdown/kit/prose/history";
import { $prose } from "@milkdown/kit/utils";
import { headingIdGenerator } from "@milkdown/kit/preset/commonmark";
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
function layoutProjection(value) {
  if (Array.isArray(value)) return value.map(layoutProjection);
  if (!value || typeof value !== "object") return value;
  const result = Object.fromEntries(
    Object.entries(value).map(([k, v]) => [k, layoutProjection(v)]),
  );
  // Spread changes Markdown spacing, not list text, nesting, order or checkbox state.
  if (
    ["bullet_list", "ordered_list", "list_item"].includes(result.type) &&
    result.attrs
  ) {
    result.attrs = { ...result.attrs };
    delete result.attrs.spread;
  }
  return result;
}
function sameExportDocument(document, reparsed) {
  const left = layoutProjection(document),
    right = layoutProjection(reparsed);
  if (sameTree(left, right)) return true;
  // Pinned upstream docSchema explicitly omits ONE terminal empty typing area.
  // Never remove nested/list empty items, middle paragraphs or code whitespace.
  if (left.type === "doc" && emptyParagraph(left.content?.at(-1)))
    return sameTree({ ...left, content: left.content.slice(0, -1) }, right);
  return false;
}
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
    if (!sameExportDocument(document, reparsed))
      throw new Error(
        "This rich edit cannot currently be represented as Markdown without changing structure. No file was written; continue editing or Undo.",
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
      "This edit is too large for rich editing. Switch to Source and paste again. Nothing was inserted.",
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
function handlePaste(_view, event) {
  if (locked || readOnly) return true;
  if (event.clipboardData?.files.length) {
    event.preventDefault();
    fail("Image paste is not supported yet. Nothing was inserted or written.");
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
    // Derived DOM ids are not Markdown content. Disable the upstream decoration
    // publicly instead of relaxing the document's attribute-equivalence guard.
    ctx.set(headingIdGenerator.key, () => "");
    ctx.update(editorViewOptionsCtx, (options) => ({
      ...options,
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
      boundedDocumentJSON,
      admitTransaction,
    };
  send("ready");
}
boot().catch((error) => fail(error.message));
