// A stand-in for OpenUI Cloud that answers with a function call first and a
// real answer second, to test the server's retry. node test/fake-upstream.mjs
import { createServer } from "node:http";

let calls = 0;
const event = (delta, extra = {}) =>
  `data: ${JSON.stringify({ choices: [{ index: 0, delta, ...extra }] })}\n\n`;
createServer((req, res) => {
  calls += 1;
  res.writeHead(200, { "Content-Type": "text/event-stream" });
  if (calls % 2 === 1) {
    res.write(event({ role: "assistant", tool_calls: [{ index: 0, id: "c1", type: "function", function: { name: "explore_nearby", arguments: "{}" } }] }));
    res.end(event({}, { finish_reason: "tool_calls" }));
  } else {
    res.write(event({ content: "root = Card([t])\n" }));
    res.end(event({ content: 't = TextContent("hi")' }, { finish_reason: "stop" }));
  }
}).listen(8799, () => console.log("fake upstream on 8799"));
