import { $node, $remark } from "@milkdown/kit/utils";

// Serializer-only AST leaf. It emits references for whitespace, never arbitrary
// markup. Keeping it distinct from an mdast text node
// prevents the transformer from moving marked boundary whitespace outside marks.
export function encodeWhitespace(node) {
  if (!/^[^\S\r\n]+$/u.test(node.value))
    throw new Error("Invalid whitespace serialization node.");
  return Array.from(node.value, (character) =>
    `&#x${character.codePointAt(0).toString(16)};`,
  ).join("");
}

// Same public text-node schema contract, with a narrow serialization extension.
// Inline-code marks and code blocks have their own serializers.
export const whitespaceText = $node("text", () => ({
  group: "inline",
  parseMarkdown: {
    match: ({ type }) => type === "text",
    runner: (state, node) => state.addText(node.value),
  },
  toMarkdown: {
    match: (node) => node.type.name === "text",
    runner: (state, node) => {
      const text = node.text;
      const leading = text.match(/^[^\S\r\n]+/u)?.[0] ?? "";
      const rest = text.slice(leading.length);
      const trailing = rest.match(/[^\S\r\n]+$/u)?.[0] ?? "";
      if (leading) state.addNode("scribbitWhitespace", undefined, leading);
      const middle = rest.slice(0, rest.length - trailing.length);
      if (middle) state.addNode("text", undefined, middle);
      if (trailing) state.addNode("scribbitWhitespace", undefined, trailing);
    },
  },
}));

// The preset's soft-break transform consumes decoded spaces/tabs before LF.
// Preserve them as text and split only the actual line ending. Markdown itself
// has already distinguished real hard breaks during parsing.
export const preservingSoftBreaks = $remark(
  "scribbit-preserve-soft-break-whitespace",
  () => () => (tree) => {
    const visit = (parent) => {
      if (!parent.children) return;
      parent.children = parent.children.flatMap((child) => {
        if (child.type !== "text") {
          visit(child);
          return [child];
        }
        const pieces = child.value.split(/\r\n|\r|\n/);
        if (pieces.length === 1) return [child];
        return pieces.flatMap((value, index) => [
          ...(index ? [{ type: "break", data: { isInline: true } }] : []),
          ...(value ? [{ type: "text", value }] : []),
        ]);
      });
    };
    visit(tree);
  },
);
