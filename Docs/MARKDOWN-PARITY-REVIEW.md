# Whitespace fix review and proposed parity gates

The follow-up implementation is documented in
[MARKDOWN-PARITY.md](MARKDOWN-PARITY.md). The findings and numbers below are the
historical review baseline, not the current test results.

Review date: November 18, 2026. Compared the committed editor at fd72c8e with
the local text-handler override on stephen.he/list-whitespace.

## Result

The change is a narrow public serializer override rather than a vendor patch or
weaker equivalence check. It preserves ordinary trailing and space-only list text
with character references; unchanged rich trees still reuse original source.
However, the override applies to all Markdown text nodes, not just lists, so its
regression surface includes headings, quotes, marks, links and table cells.

An additional before/after probe ran 72 synthetic edits: 12 source contexts,
three insertion positions, and one/two ASCII spaces. It used the actual committed
and regenerated bundles under JSDOM, not alternate serializer implementations.

| Outcome | Before | After |
| --- | ---: | ---: |
| Successful snapshot | 38 | 50 |
| Guarded refusal | 34 | 22 |
| Previously successful case newly refused | — | 0 |

These are fixture outcomes, not a real-user failure rate or exhaustive proof.
The remaining 22 cases comprise spaces inserted at the boundaries of strong,
emphasis, strikethrough and link text (16), table-cell boundaries (4), and before
a soft linebreak (2). All also failed before this fix. Mark boundary failures can
reflect whitespace moving outside a mark rather than lost visible text; table
and soft-break examples report text differences. Do not collapse these into one
generic rule that trims all whitespace.

Local ignored evidence: build/list-space-review.mjs,
build/list-space-baseline.js, build/list-space-review-before.json and
build/list-space-review-after.json. No user notes or GUI inspection were used.

## Findings about coverage

1. The seeded stress test accepts both successful export and retained refusal.
   That is a valuable integrity/recovery property, not an editability guarantee.
   Its aggregate assertion only requires some successes and some refusals, so
   many newly blocked ordinary edits could pass unnoticed.
2. The new list regression checks parsed results with the sameExportDocument
   comparator used by production. That exercises the integration but is not an
   independent oracle: a future overly broad normalization could fool both.
3. The WebKit whitespace fixture exercises encoded-space import, insertion,
   snapshot and reopen, but not a newly created empty item via physical keys or
   actual disk reopen. Layered tests should share cases with clearly different
   coverage rather than treating one synthetic browser test as full acceptance.

## Proposed prevention plan

These are recommendations, not completed new CI gates.

### Separate two required outcomes

- **Supported ordinary edit:** must export and reopen with the independently
  expected content/structure. A refusal fails the test.
- **Unsupported/unrepresentable input:** must retain the live draft, avoid file
  writes, explain the problem and permit recovery. Refusal is expected only for
  named, explicit cases.

Keep exploratory fuzzing separate; promote every minimized unexpected failure
into a deterministic named regression. Do not add arbitrary broad categories to
an expected-failure list or gate on a loosely defined success percentage.

### Use a shared semantic fixture matrix

Cover list type, nesting, empty items, marked/unmarked text, paragraphs/headings,
quotes, table cells and code. Cross those with start/middle/end, soft/hard breaks,
space/tab/newline/NBSP/Unicode, Enter, indent/outdent, paste, deletion and Undo.
Use pairwise coverage for the broad combinations plus explicit known regressions,
not an uncontrolled Cartesian-product suite.

Each fixture specifies observable expectations independently of the production
normalizer: exact text/code points, marks on relevant text, list type/start,
checkbox state, nesting and paragraph/break boundaries. Assert those after each
edit and reopen, alongside the strict production safety guard.

### Exercise the whole persistence path

Use the same small critical cases in bundled-JS tests and the real-WebKit harness:

    load -> edit -> native snapshot -> coordinated save -> close
         -> release editor -> reopen file -> assert expected semantics

Also test failed save/conflict, retry, mode switching, clean no-write and
Undo-to-baseline. Retain the faster pure/native tests for isolated failure paths.

### Make normalization a deliberate contract

Classify differences as exact source identity, harmless syntax normalization,
explicitly accepted presentation differences, or content loss. List spread and
known list marker metadata are already narrow allowed cases. Whether whitespace
at mark boundaries may move outside the mark needs its own explicit contract and
tests; blanket trimming or ignoring all marks is not acceptable.

### Gate upgrades and releases

Every serializer/parser/configuration change must run the must-save semantic
corpus and guard-negative corpus. Run the same before/after comparison for pinned
dependency upgrades, then regenerate resources/notices and check hashes.
Automate the WebKit gate on a validated GUI-capable macOS runner; until that
environment is verified, require and record a local run for editor changes.
The present workflow runs headless JS and Swift tests, not the GUI harness.

Prioritize deterministic must-save cases and independent assertions first,
then shared end-to-end fixtures. More test counts alone will not close the gap.
