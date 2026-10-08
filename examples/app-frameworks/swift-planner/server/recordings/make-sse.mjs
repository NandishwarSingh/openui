// Turns a program into a stream in the model's SSE format, for testing
// components without calling the model: node make-sse.mjs in.oui > out.sse
import { readFileSync } from "node:fs";

const text = readFileSync(process.argv[2], "utf8");
const chunk = (delta, extra = {}) =>
  `data: ${JSON.stringify({ object: "chat.completion.chunk", choices: [{ index: 0, delta, ...extra }] })}\n\n`;
let out = "";
for (let i = 0; i < text.length; i += 48) out += chunk({ content: text.slice(i, i + 48) });
out += chunk({}, { finish_reason: "stop" });
process.stdout.write(out);
