// The Planner example's backend: keeps the OpenUI Cloud key and the Razorpay
// secret off the device. No dependencies; run with `node server.mjs`.
//
//   POST /api/chat              streams a chat completion from OpenUI Cloud
//   POST /api/payments/order    creates a Razorpay order
//   POST /api/payments/verify   checks a Razorpay payment signature
//   GET  /api/payments/status   whether an order was paid, asked of Razorpay
//   GET  /api/payments/checkout serves Razorpay's web checkout (used on macOS)
//   POST /api/payments/callback  where that checkout reports the payment
import { createHmac, timingSafeEqual } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { hostname } from "node:os";

loadEnv(new URL("./.env", import.meta.url));
const port = Number(process.env.PORT ?? 8787);
const thesysKey = process.env.THESYS_API_KEY;
const razorpayKeyId = process.env.RAZORPAY_KEY_ID;
const razorpaySecret = process.env.RAZORPAY_KEY_SECRET;
const model = process.env.MODEL ?? "google/gemini-3.6-flash-free";
// Tests point this at a fake to exercise failure handling.
const upstreamURL = process.env.UPSTREAM_URL ?? "https://api.thesys.dev/v1/embed/chat/completions";
// Development: `REPLAY=first.sse,second.sse` answers a conversation's first
// turn with the first recording, its second with the second and so on (the
// last one repeats), instead of calling the model. `REPLAY=replays.json` picks
// the list by the first message instead: {"words in it": ["a.sse", ...]}. A
// "live" entry sends that turn to the model.
const replays = process.env.REPLAY?.split(",").filter(Boolean) ?? [];
// Read on every request, so edits to the map apply without a restart.
const replayMap = () =>
  replays[0]?.endsWith(".json") ? JSON.parse(readFileSync(replays[0], "utf8")) : null;

// The recordings for this conversation, or null when none match (the
// request then goes to the model, so a manual test never gets an unrelated
// recorded answer).
function replayFiles(messages) {
  const map = replayMap();
  if (!map) return replays;
  const first = messages.find((message) => message.role === "user")?.content;
  const text = Array.isArray(first) ? first.map((part) => part.text ?? "").join(" ") : String(first ?? "");
  const key = Object.keys(map).find((words) => text.toLowerCase().includes(words.toLowerCase()));
  return key ? map[key] : null;
}
// Development: `RECORD=dir` saves each streamed answer there, for REPLAY.
const record = process.env.RECORD;

function loadEnv(url) {
  if (!existsSync(url)) return;
  for (const line of readFileSync(url, "utf8").split("\n")) {
    const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (match && process.env[match[1]] === undefined) process.env[match[1]] = match[2];
  }
}

function json(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(body));
}

async function readBody(req, limit = 8_000_000) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw Object.assign(new Error("Request too large"), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function readJSON(req) {
  return JSON.parse((await readBody(req)) || "{}");
}

async function chat(req, res) {
  const { messages } = await readJSON(req);
  if (!Array.isArray(messages)) return json(res, 400, { error: "messages must be an array" });
  const files = replays.length ? replayFiles(messages) : null;
  const turn = messages.filter((message) => message.role === "user").length - 1;
  const file = files?.[Math.min(Math.max(turn, 0), files.length - 1)];
  if (file && file !== "live") return replayStream(res, file);
  // Automated runs ask never to reach the model, so a missing recording
  // fails loudly instead of spending a call.
  if (req.headers["x-replay-only"] && file !== "live") {
    return json(res, 409, { error: "No recording matches this message (replay only)." });
  }
  if (!thesysKey) return json(res, 500, { error: "Set THESYS_API_KEY in server/.env" });
  console.log(`chat: ${describe(messages)}`);
  const controller = new AbortController();
  res.on("close", () => controller.abort());

  // The prompt lists the tools, and the model sometimes calls one as a
  // function instead of writing a Query: an answer with no content. Ask once
  // more, telling it to answer with the program; the app sees one stream.
  let body = "";
  let failure = null;
  for (const attempt of [messages, [...messages, { role: "user", content: answerWithProgram }]]) {
    const result = await streamAnswer(attempt, res, controller.signal);
    if (!result) return; // The app stopped the answer.
    body += result.body;
    failure = result.failure;
    if (failure || !/"tool_calls"/.test(result.body) || hasContent(result.body)) break;
    console.log("chat: the model called a tool instead of answering; asking again");
  }
  if (!failure && !hasContent(body)) {
    failure = "The model sent back an empty answer. Try again, or rephrase.";
  } else if (!failure && /"finish_reason":"length"/.test(body)) {
    failure = "The answer was too long and got cut off.";
  }
  if (failure && !res.headersSent) return json(res, 502, { error: failure });
  if (failure) res.write(`data: ${JSON.stringify({ error: { message: failure } })}\n\n`);
  res.end();
  console.log(`chat: answer ${body.length} bytes${failure ? ` (${failure})` : ""}`);
  if (record) {
    mkdirSync(record, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    writeFileSync(`${record}/${stamp}.sse`, body);
    // A failed answer keeps its request, to see what was sent.
    if (failure) writeFileSync(`${record}/${stamp}.request.json`, JSON.stringify({ messages }, null, 1));
  }
}

const answerWithProgram =
  "Answer with the openui-lang program itself. Don't call functions: tools are used through Query(...) and Mutation(...) statements in the program.";

function hasContent(body) {
  return /"content":"(?!")/.test(body);
}

// Streams one answer from OpenUI Cloud into `res`, passing the events through
// untouched. Returns what arrived and why it failed, if it did, or null when
// the app stopped the answer.
async function streamAnswer(messages, res, signal) {
  let upstream;
  try {
    upstream = await fetch(upstreamURL, {
      method: "POST",
      signal,
      headers: { Authorization: `Bearer ${thesysKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model, messages, stream: true, max_completion_tokens: 8000 }),
    });
  } catch (error) {
    if (error.name === "AbortError") return null;
    return { body: "", failure: "Couldn't reach OpenUI Cloud. Check this Mac's internet connection." };
  }
  if (!upstream.ok || !upstream.body) {
    const failure = await upstreamError(upstream);
    console.log(`chat: OpenUI Cloud error: ${failure}`);
    return { body: "", failure };
  }
  if (!res.headersSent) {
    res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store" });
  }
  const chunks = [];
  try {
    for await (const chunk of upstream.body) {
      chunks.push(chunk);
      res.write(chunk);
    }
  } catch (error) {
    if (error.name === "AbortError") return null;
    return {
      body: Buffer.concat(chunks).toString("utf8"),
      failure: "The connection to OpenUI Cloud dropped in the middle of the answer.",
    };
  }
  return { body: Buffer.concat(chunks).toString("utf8"), failure: null };
}

// A one-line summary of a request for the log: roles, text sizes, images.
function describe(messages) {
  return messages
    .map((m) =>
      Array.isArray(m.content)
        ? `${m.role}[${m.content.map((p) => (p.type === "text" ? `text ${p.text.length}` : "image")).join(", ")}]`
        : `${m.role}(${String(m.content).length})`,
    )
    .join(" ");
}

async function upstreamError(upstream) {
  if (upstream.status === 429) {
    return "OpenUI Cloud is limiting requests right now (plan limit). Wait a minute and try again.";
  }
  if (upstream.status === 401 || upstream.status === 403) {
    return "OpenUI Cloud rejected the API key. Check THESYS_API_KEY in server/.env.";
  }
  const text = await upstream.text().catch(() => "");
  let message = text.slice(0, 300);
  try {
    const parsed = JSON.parse(text);
    message = parsed?.error?.message ?? parsed?.error ?? parsed?.message ?? message;
  } catch {}
  return `OpenUI Cloud returned HTTP ${upstream.status}${message ? `: ${message}` : ""}`;
}

async function replayStream(res, replay) {
  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store" });
  const events = readFileSync(replay, "utf8").split("\n\n").filter((event) => event.trim());
  await new Promise((resolve) => setTimeout(resolve, 900));
  // REPLAY_DELAY (ms between chunks) mimics faster or slower streams.
  const delay = Number(process.env.REPLAY_DELAY ?? 120);
  for (const event of events) {
    res.write(`${event}\n\n`);
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
  res.end();
  console.log(`chat: replayed ${events.length} events from ${replay}`);
}

function razorpayConfigured(res) {
  if (razorpayKeyId && razorpaySecret) return true;
  json(res, 500, { error: "Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in server/.env" });
  return false;
}

function razorpayAuth() {
  return `Basic ${Buffer.from(`${razorpayKeyId}:${razorpaySecret}`).toString("base64")}`;
}

async function createOrder(req, res) {
  if (!razorpayConfigured(res)) return;
  const { amount, currency = "INR", receipt, notes } = await readJSON(req);
  if (!Number.isInteger(amount) || amount < 100) {
    return json(res, 400, { error: "amount must be an integer in paise, at least 100" });
  }
  const upstream = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: { Authorization: razorpayAuth(), "Content-Type": "application/json" },
    body: JSON.stringify({ amount, currency, receipt, notes }),
  });
  const order = await upstream.json();
  if (!upstream.ok) return json(res, 502, { error: order?.error?.description ?? "Order failed" });
  json(res, 200, { orderId: order.id, amount: order.amount, currency: order.currency, keyId: razorpayKeyId });
}

function signatureMatches(orderId, paymentId, signature) {
  const expected = createHmac("sha256", razorpaySecret).update(`${orderId}|${paymentId}`).digest("hex");
  return (
    typeof signature === "string" &&
    signature.length === expected.length &&
    timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
  );
}

async function verifyPayment(req, res) {
  if (!razorpayConfigured(res)) return;
  const { orderId, paymentId, signature } = await readJSON(req);
  json(res, 200, { verified: signatureMatches(orderId, paymentId, signature) });
}

// The payment that went through on an order, asked of Razorpay with the
// secret, so the answer can be trusted like a verified signature. Checkout
// can close without reporting a payment it did take; the app asks this
// before treating a payment as cancelled or failed.
async function orderStatus(req, res) {
  if (!razorpayConfigured(res)) return;
  const orderId = new URL(req.url, "http://localhost").searchParams.get("orderId") ?? "";
  if (!/^order_[A-Za-z0-9]+$/.test(orderId)) return json(res, 400, { error: "orderId is required" });
  const upstream = await fetch(`https://api.razorpay.com/v1/orders/${orderId}/payments`, {
    headers: { Authorization: razorpayAuth() },
  });
  const body = await upstream.json();
  if (!upstream.ok) return json(res, 502, { error: body?.error?.description ?? "Order lookup failed" });
  const paid = (body.items ?? []).find((p) => p.status === "captured" || p.status === "authorized");
  console.log(`payments: ${orderId} ${paid ? `paid by ${paid.id}` : "not paid"}`);
  json(res, 200, paid ? { paid: true, paymentId: paid.id } : { paid: false });
}

// Where the web checkout ends in redirect mode: Razorpay posts the payment (or
// its error) here, and the page hands the result to the app.
async function paymentCallback(req, res) {
  if (!razorpayConfigured(res)) return;
  const form = new URLSearchParams(await readBody(req));
  const paymentId = form.get("razorpay_payment_id");
  const orderId = form.get("razorpay_order_id");
  const signature = form.get("razorpay_signature");
  const result = paymentId
    ? signatureMatches(orderId, paymentId, signature)
      ? { status: "paid", paymentId, orderId, signature }
      : { status: "failed", reason: "The payment couldn't be verified." }
    : { status: "failed", reason: form.get("error[description]") ?? "The payment didn't go through." };
  const target = `planner-payment://result?${new URLSearchParams(result)}`;
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
  res.end(`<!doctype html><script>location.href = ${JSON.stringify(target).replace(/</g, "\\u003c")};</script>`);
}

// Razorpay's web checkout for platforms without the native SDK. It runs in
// redirect mode: inside a web view, the bank pages can't open as popups the
// way checkout.js expects, so the whole page goes to the bank and the result
// comes back through /api/payments/callback. The app intercepts the custom
// planner-payment:// URL the page finally opens.
function checkoutPage(req, res) {
  if (!razorpayConfigured(res)) return;
  const url = new URL(req.url, "http://localhost");
  const options = {
    key: razorpayKeyId,
    order_id: url.searchParams.get("orderId"),
    amount: Number(url.searchParams.get("amount")),
    currency: url.searchParams.get("currency") ?? "INR",
    name: url.searchParams.get("name") ?? "Planner",
    description: url.searchParams.get("description") ?? "",
    theme: { color: "#5B6CF0" },
    redirect: true,
    callback_url: `http://${req.headers.host}/api/payments/callback`,
  };
  // A known contact skips checkout's phone number step.
  const contact = url.searchParams.get("contact");
  if (contact) options.prefill = { contact };
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
const options = ${JSON.stringify(options).replace(/</g, "\\u003c")};
const done = (params) => { location.href = "planner-payment://result?" + new URLSearchParams(params); };
options.modal = { ondismiss: () => done({ status: "dismissed" }) };
const checkout = new Razorpay(options);
checkout.on("payment.failed", (r) => done({ status: "failed", reason: r.error.description }));
checkout.open();
</script>`);
}

const routes = {
  "POST /api/chat": chat,
  "POST /api/payments/order": createOrder,
  "POST /api/payments/verify": verifyPayment,
  "GET /api/payments/status": orderStatus,
  "GET /api/payments/checkout": checkoutPage,
  "POST /api/payments/callback": paymentCallback,
  "GET /api/health": (req, res) =>
    json(res, 200, {
      chat: Boolean(thesysKey),
      payments: Boolean(razorpayKeyId && razorpaySecret),
      // Razorpay test keys start with rzp_test_; their payments move no money.
      paymentsTestMode: Boolean(razorpayKeyId?.startsWith("rzp_test_")),
      model,
    }),
};

createServer(async (req, res) => {
  const handler = routes[`${req.method} ${new URL(req.url, "http://localhost").pathname}`];
  if (!handler) return json(res, 404, { error: "Not found" });
  try {
    await handler(req, res);
  } catch (error) {
    if (error.name === "AbortError") return;
    if (!res.headersSent) json(res, error.status ?? 500, { error: error.message });
    else res.end();
  }
}).listen(port, () => {
  // A phone on the same Wi-Fi reaches the Mac by its Bonjour name. (iOS
  // blocks plain HTTP to IP addresses, but allows it to .local names.)
  const name = hostname().endsWith(".local") ? hostname() : `${hostname()}.local`;
  console.log(`Planner server on http://localhost:${port}`);
  console.log(`  from a phone on this Wi-Fi: http://${name}:${port}`);
});
