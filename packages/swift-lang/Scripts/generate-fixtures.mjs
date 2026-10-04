// Regenerates the conformance fixtures in Tests/OpenUILangTests/Fixtures from
// the TypeScript implementation, which is the source of truth.
//
//   pnpm run build:packages
//   node packages/swift-lang/Scripts/generate-fixtures.mjs
//
// Each fixture pairs an input with what @openuidev/lang-core produces for it.
// The Swift tests feed the same input to the Swift port and compare.

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const packages = join(here, "..", "..");
const fixtures = join(here, "..", "Tests", "OpenUILangTests", "Fixtures");

// Fixture generation is not product usage, so keep lang-core's telemetry off.
process.env.OPENUI_TELEMETRY_DISABLED = "1";

const core = await import(join(packages, "lang-core", "dist", "index.mjs"));
const ui = await import(join(packages, "react-ui", "dist", "genui-lib", "index.mjs"));

// ── Schemas ───────────────────────────────────────────────────────────────

const chatSchema = ui.openuiChatLibrary.toJSONSchema();

// Small hand-written schema that exercises validation paths the chat library
// doesn't: defaults, const, integer, nested required keys, enum defaults.
const testSchema = {
  $defs: {
    Card: {
      properties: {
        children: {
          type: "array",
          items: { anyOf: [{ $ref: "#/$defs/Text" }, { $ref: "#/$defs/Button" }, { $ref: "#/$defs/Chart" }] },
        },
        title: { type: "string" },
      },
      required: ["children"],
    },
    Text: {
      properties: {
        text: { type: "string" },
        size: { type: "string", enum: ["s", "m", "l"], default: "m" },
      },
      required: ["text"],
    },
    Button: {
      properties: {
        label: { type: "string" },
        action: {},
        variant: { type: "string", enum: ["primary", "secondary"] },
      },
      required: ["label"],
    },
    Input: {
      properties: { name: { type: "string" }, value: { type: "string" } },
      required: ["name"],
    },
    Chart: {
      properties: {
        labels: { type: "array", items: { type: "string" } },
        values: { type: "array", items: { type: "number" } },
        meta: {
          type: "object",
          properties: { unit: { type: "string" }, scale: { type: "number", default: 1 } },
          required: ["unit"],
        },
      },
      required: ["labels", "values"],
    },
    Tagged: {
      properties: {
        count: { type: "integer" },
        flag: { type: "boolean" },
        kind: { const: "x" },
        tone: { type: "string", default: "neutral" },
      },
      required: ["tone"],
    },
  },
};

const schemas = { chat: { schema: chatSchema, root: "Card" }, test: { schema: testSchema, root: "Card" } };

// ── Corpus ────────────────────────────────────────────────────────────────

const chatExamples = ui.openuiChatPromptOptions.examples.map((text, i) => ({
  name: `chat-example-${i + 1}`,
  schema: "chat",
  input: text,
}));

const t = (name, input) => ({ name, schema: "test", input });

const edgeCases = [
  t("basic", 'root = Card([t1, b1])\nt1 = Text("Hi")\nb1 = Button("Go")'),
  t("missing-required", 'root = Card([t1, b1])\nt1 = Text()\nb1 = Button("Go")'),
  t("null-required-with-default", "root = Card([t1])\nt1 = Text(null)"),
  t("required-default-fills", 'root = Card([x])\nx = Tagged(1, true, "x", null)'),
  t("unknown-component", 'root = Card([Mystery("a"), Text("b")])'),
  t("excess-args", 'root = Card([Text("a", "m", "extra", 4)])'),
  t("type-mismatch-scalar", 'root = Card([Text(42)], 7)'),
  t("enum-mismatch", 'root = Card([Text("a", "xl"), Button("b", null, "tertiary")])'),
  t("enum-partial-deferred", 'root = Card([Text("a", "x'),
  t("integer-boolean-const", 'root = Card([x])\nx = Tagged(1.5, "yes", "y", "loud")'),
  t(
    "nested-object",
    'root = Card([c1, c2, c3])\nc1 = Chart(["a"], [1], {unit: "kg"})\nc2 = Chart(["a"], [1], {scale: 2})\nc3 = Chart(["a"], [1], {unit: 5, scale: "big"})',
  ),
  t("array-items-pruned", 'root = Card([Chart(["a", 2, "c"], [1, "x", 3])])'),
  t("element-in-data-slot", 'root = Card([Chart([Text("a")], [1])])'),
  t("unresolved-and-orphaned", "root = Card([a, missing])\na = Text(\"x\")\nlonely = Text(\"y\")"),
  t("cycle", "root = Card([a])\na = Card([b])\nb = Card([a])"),
  t("self-reference", "root = Card([root])"),
  t("no-root-first-component", 'x = 1\nmain = Card([Text("a")])\nother = Card([])'),
  t("root-name-statement", 'Card = Card([Text("named")])\nother = Card([])'),
  t("duplicate-ids", 'root = Card([a])\na = Text("first")\na = Text("second")'),
  t("only-prose", "Here is your UI, it will appear below."),
  t("empty", ""),
  t("whitespace", "   \n\t  \n"),
  t(
    "fences-and-prose",
    'Sure! Here it is:\n```openui\nroot = Card([a])\na = Text("fenced")\n```\nAnything else?',
  ),
  t("multiple-fences", '```\nroot = Card([a])\n```\nand\n```\na = Text("second block")\n```'),
  t("unclosed-fence", '```openui\nroot = Card([a])\na = Text("str'),
  t("fence-in-string", 'root = Card([a])\na = Text("use ``` to fence")'),
  t(
    "comments",
    'root = Card([a]) // trailing\n# full line\na = Text("not // a comment # here")\n// done',
  ),
  t("crlf", 'root = Card([a])\r\na = Text("windows")\r\n'),
  t(
    "string-escapes",
    'root = Card([a, b, c, d])\na = Text("tab\\tnew\\nquote\\" back\\\\ uni\\u00e9 pair\\ud83d\\ude00")\nb = Text(\'single \\\' quote \\n esc \\q\')\nc = Text("bad \\x escape")\nd = Text("emoji 😀 and é and 漢字")',
  ),
  t("emoji-outside-strings", 'root = Card([a]) 😀\na = Text("ok") ✅'),
  t("unterminated-string", 'root = Card([a])\na = Text("streaming tex'),
  t("unterminated-escape", 'root = Card([a])\na = Text("ends with \\'),
  t(
    "numbers",
    'root = Card([Chart(["a","b","c","d","e","f"], [-3, 1.5, 1e3, 007, -0, 2.5e-3])])\n$x = 1e\n$y = 1E+2\n$z = 3.',
  ),
  t(
    "operators",
    '$a = 1\n$b = "2"\nroot = Card([Text($a + $b * 2 - -1 > 3 && !$c || $a == "1" ? "yes" : "no")])',
  ),
  t(
    "multiline-ternary",
    '$on = true\nroot = Card([t])\nt = Text($on\n  ? "enabled"\n  : "disabled")',
  ),
  t(
    "member-index",
    '$data = {rows: [{name: "a"}, {name: "b"}], "key x": 1}\nroot = Card([Text($data.rows[1].name), Text($data.rows.name), Text($data["key x"])])',
  ),
  t(
    "builtins",
    '$items = [3, 1, 2]\nroot = Card([Text("" + @Count($items)), Text("" + @Sum($items)), Text(@Round(2.555, 2) + "")])\nbare = Count($items)',
  ),
  t(
    "actions",
    '$n = 0\nroot = Card([b1, b2, b3])\nb1 = Button("Inc", Action([@Set($n, $n + 1), @ToAssistant("Bumped", "ctx")]))\nb2 = Button("Reset", Action([@Reset($n)]))\nb3 = Button("Docs", Action([@OpenUrl("https://openui.com")]))',
  ),
  t(
    "each",
    '$todos = [{title: "a", done: false}, {title: "b", done: true}]\nroot = Card(@Each($todos, todo, Text(todo.title)))',
  ),
  t(
    "query-mutation",
    '$q = "x"\nusers = Query("list_users", {search: $q, page: $page}, {rows: []}, 30)\nsave = Mutation("save_user", {name: $q})\nroot = Card([Text(users.rows.length + " users"), Button("Save", Action([@Run(save), @Run(users)]))])',
  ),
  t("state-query", '$data = Query("get", {})\nroot = Card([Text("x")])'),
  t("inline-query", 'root = Card([Text(Query("get", {}))])'),
  t("assignment", '$v = ""\nroot = Card([Input("name", $v = $value)])'),
  t(
    "object-key-order",
    '$o = {b: 1, 2: "two", a: 3, 1: "one", "10": 10}\nroot = Card([Text("x")])',
  ),
  t("missing-commas", 'root = Card([Text("a") Text("b"), Text("c"),])'),
  t("lowercase-builtin-name", 'root = Card([Text(@first([1]))])'),
  t("unknown-tokens", "root = Card([Text(\"a\")]) ; ~ ^\n$ = 3\n= 4\nfoo"),
  t(
    "combining-characters",
    'root = Card([Text("e\\u0301 cafe\\u0301"), Text("한국어"), Text("ok")])',
  ),
  t("truncated-mid-call", 'root = Card([a, b])\na = Text("one")\nb = Button("tw'),
  t("truncated-mid-object", 'root = Card([Chart(["a"], [1], {unit: "k'),
];

// ── Fixture generation ────────────────────────────────────────────────────

function parseWith(schemaName, input) {
  const { schema, root } = schemas[schemaName];
  return core.createParser(schema, root).parse(input);
}

/** UTF-16 offsets that don't split a surrogate pair. */
function safeOffsets(text, step) {
  const offsets = [];
  for (let i = step; i < text.length; i += step) {
    let at = i;
    const code = text.charCodeAt(at - 1);
    if (code >= 0xd800 && code <= 0xdbff) at += 1;
    offsets.push(at);
  }
  offsets.push(text.length);
  return [...new Set(offsets)];
}

function streamCheckpoints(schemaName, input) {
  const { schema, root } = schemas[schemaName];
  const parser = core.createStreamingParser(schema, root);
  const step = Math.max(1, Math.ceil(input.length / 12));
  let last = 0;
  return safeOffsets(input, step).map((at) => {
    const result = parser.push(input.slice(last, at));
    last = at;
    return { at, expected: result };
  });
}

const parserCases = [...chatExamples, ...edgeCases].map((c) => ({
  ...c,
  expected: parseWith(c.schema, c.input),
}));

const streamingCases = [...chatExamples, ...edgeCases]
  .filter((c) => c.input.length > 0)
  .map((c) => ({ ...c, checkpoints: streamCheckpoints(c.schema, c.input) }));

// `set()` with appended text, then replaced text (which resets the parser).
const setCases = edgeCases.slice(0, 6).map((c) => {
  const { schema, root } = schemas[c.schema];
  const parser = core.createStreamingParser(schema, root);
  const half = c.input.slice(0, Math.floor(c.input.length / 2));
  const steps = [half, c.input, 'root = Card([Text("replaced")])'].map((text) => ({
    text,
    expected: parser.set(text),
  }));
  return { name: c.name, schema: c.schema, steps };
});

function write(name, data, indent = 1) {
  mkdirSync(fixtures, { recursive: true });
  writeFileSync(join(fixtures, name), JSON.stringify(data, null, indent) + "\n");
}

write("schemas.json", Object.fromEntries(Object.entries(schemas)));
write("parser.json", parserCases);
write("streaming.json", streamingCases, 0);
write("stream-set.json", setCases);

console.log(
  `wrote ${parserCases.length} parser, ${streamingCases.length} streaming, ${setCases.length} set fixtures`,
);
