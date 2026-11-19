import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

export const fixtures = JSON.parse(await readFile(
  "../../Tests/Fixtures/markdown-parity.json", "utf8",
));

// Test-only observable contract. This intentionally does not call production's
// exportDifference/layoutProjection, strip text, or move whitespace/marks.
// It ignores visual list labels/spread, but retains semantic list starts/tasks,
// table alignment, headings/language, every text code point, mark and break.
export function observableBlocks(doc) {
  const blocks = [];
  const visit = (node, ancestry) => {
    const context = { type: node.type.name };
    for (const key of ["order", "checked", "alignment", "level", "language"])
      if (Object.hasOwn(node.attrs, key)) context[key] = node.attrs[key];
    const parents = [...ancestry, context];
    if (node.isTextblock) {
      const runs = [];
      const marksOf = (child) => Array.from(child.marks, (mark) => mark.type.name === "link"
        ? { type: "link", href: mark.attrs.href, title: mark.attrs.title }
        : { type: mark.type.name }).sort((a, b) => a.type.localeCompare(b.type));
      node.forEach((child) => {
        if (child.isText) {
          runs.push({
            text: child.text,
            marks: marksOf(child),
          });
        } else if (child.type.name === "hardbreak") {
          const marks = marksOf(child);
          runs.push({ break: child.attrs.isInline ? "soft" : "hard", ...(marks.length ? { marks } : {}) });
        } else {
          // Unknown inline nodes must not silently disappear from expectations.
          runs.push({ node: child.type.name, attrs: { ...child.attrs } });
        }
      });
      blocks.push({ ancestry: parents, runs });
    } else {
      node.forEach((child) => visit(child, parents));
    }
  };
  visit(doc, []);
  return blocks;
}

export function expectedEdit(doc, fixture, offset, insertion) {
  const blocks = observableBlocks(doc);
  const index = blocks.findIndex((block) => block.runs[0]?.text === "first");
  assert.ok(index >= 0, fixture.id);
  assert.deepEqual(blocks[index].ancestry.map((node) => node.type), fixture.ancestry);
  assert.deepEqual(blocks[index].runs, fixture.runs, fixture.id);
  // Expected content is fixture-defined, not inferred from exported Markdown.
  blocks[index].runs = structuredClone(fixture.runs);
  if (Object.hasOwn(fixture, "boundaryMarks") && (offset === 0 || offset === 5)) {
    const inserted = { text: insertion, marks: structuredClone(fixture.boundaryMarks) };
    if (offset === 0) blocks[index].runs.unshift(inserted);
    else blocks[index].runs.push(inserted);
  } else {
    blocks[index].runs[0].text = "first".slice(0, offset) + insertion + "first".slice(offset);
  }
  return blocks;
}
