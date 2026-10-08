#!/usr/bin/env node
// Checks every Anthropic structured-output schema (`output_config.format`) in
// functions/src/index.ts against the documented limits, and optionally against
// the live Messages API.
//
//   node scripts/check-anthropic-schemas.js                 lint only — free, offline
//   node scripts/check-anthropic-schemas.js --live          lint + one tiny real call per schema (~$0.01 total)
//   node scripts/check-anthropic-schemas.js --live --only parseInsuranceCard
//   node scripts/check-anthropic-schemas.js --file path/to/index.ts     check a different copy
//
// Why this exists: Anthropic rejects some JSON Schema features with a 400 that
// only a real request surfaces — e.g. `maxItems` on an array. suggestServiceReminders
// shipped with one and failed on every call, because the compiler cannot see it.
// Run with --live before deploying any function that calls Anthropic for the first
// time, or after touching one of its schemas.
//
// Credentials for --live: ANTHROPIC_API_KEY if set, otherwise the `ant` CLI's OAuth
// profile (`brew install anthropics/tap/ant && ant auth login`).
// Exit code: 0 = all checks passed, 1 = a schema failed, 2 = could not run.

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const zlib = require("zlib");
const { execSync } = require("child_process");

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n) => (args.includes(n) ? args[args.indexOf(n) + 1] : undefined);
const live = flag("--live");
const only = opt("--only");
const file = path.resolve(opt("--file") || path.join(__dirname, "../functions/src/index.ts"));
const src = fs.readFileSync(file, "utf8");

// ---- extraction: pull the real schema literals out of the source ---------------

// Index of the "}" matching the "{" at `open`, skipping strings and comments.
function matchBrace(s, open) {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i], n = s[i + 1];
    if (c === "/" && n === "/") { i = s.indexOf("\n", i); if (i < 0) break; continue; }
    if (c === "/" && n === "*") { i = s.indexOf("*/", i) + 1; continue; }
    if (c === '"' || c === "'" || c === "`") {
      for (i++; i < s.length && s[i] !== c; i++) if (s[i] === "\\") i++;
      continue;
    }
    if (c === "{") depth++;
    if (c === "}" && --depth === 0) return i;
  }
  throw new Error("unbalanced braces");
}
const evalLiteral = (text) => vm.runInNewContext("(" + text + ")");

function findFunctions() {
  const re = /^export const (\w+) = (?:onCall|functions\.https\.onRequest|functionsV1[\w.]*)\(/gm;
  const starts = [];
  for (let m; (m = re.exec(src)); ) starts.push({ name: m[1], at: m.index });
  const found = [];
  starts.forEach((s, i) => {
    const region = src.slice(s.at, i + 1 < starts.length ? starts[i + 1].at : src.length);
    const oc = region.indexOf("output_config:");
    if (oc < 0) return; // no structured output here (e.g. askMarque)
    const open = region.indexOf("{", oc);
    // `model:` is usually a named constant (HAIKU_MODEL, MARQUE_MODEL), not a
    // string literal — resolve it against the file's own `const NAME = "..."`.
    const modelRef = region.match(/model:\s*(?:"([^"]+)"|(\w+))/);
    const model = modelRef?.[1]
      || (modelRef?.[2] && (src.match(new RegExp(`const ${modelRef[2]}\\s*=\\s*"([^"]+)"`)) || [])[1])
      || "claude-haiku-4-5";
    found.push({
      name: s.name,
      model,
      hasImage: /type:\s*"image"/.test(region),
      outputConfig: evalLiteral(region.slice(open, matchBrace(region, open) + 1)),
    });
  });
  return found;
}

// ---- lint: the documented structured-output limits -----------------------------

const UNSUPPORTED = ["maxItems", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
  "multipleOf", "minLength", "maxLength", "uniqueItems"];

function lint(node, where, out) {
  if (!node || typeof node !== "object" || Array.isArray(node)) return;
  for (const k of UNSUPPORTED) if (k in node) out.push({ level: "ERROR", where, msg: `\`${k}\` is not supported` });
  if ("minItems" in node && node.minItems > 1) out.push({ level: "ERROR", where, msg: "`minItems` above 1 is not supported" });
  if (Array.isArray(node.type)) out.push({ level: "WARN", where, msg: "type union — use `anyOf`; unions are not listed as supported" });
  if (node.type === "object" && node.additionalProperties !== false)
    out.push({ level: "ERROR", where, msg: "object must set `additionalProperties: false`" });
  for (const [k, v] of Object.entries(node.properties || {})) lint(v, `${where}.${k}`, out);
  if (node.items) lint(node.items, `${where}[]`, out);
  for (const key of ["anyOf", "allOf"]) (node[key] || []).forEach((v, i) => lint(v, `${where}.${key}[${i}]`, out));
  for (const [k, v] of Object.entries(node.$defs || {})) lint(v, `${where}.$defs.${k}`, out);
}

// ---- live: one tiny real request per schema ------------------------------------

function blankPng() { // 32x32 white PNG, no dependencies
  const chunk = (t, d) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(d.length);
    const td = Buffer.concat([Buffer.from(t), d]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(32, 0); ihdr.writeUInt32BE(32, 4); ihdr[8] = 8; ihdr[9] = 2;
  const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(96, 255)]);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(Buffer.concat(Array(32).fill(row)))), chunk("IEND", Buffer.alloc(0))]).toString("base64");
}

function makeClient() {
  const Sdk = require(path.join(__dirname, "../functions/node_modules/@anthropic-ai/sdk"));
  const Anthropic = Sdk.default || Sdk.Anthropic || Sdk;
  if (process.env.ANTHROPIC_API_KEY) return { Anthropic, client: new Anthropic() };
  let token;
  try { token = execSync("ant auth print-credentials --access-token", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
  catch { throw new Error("no credentials: set ANTHROPIC_API_KEY or run `ant auth login`"); }
  return { Anthropic, client: new Anthropic({ apiKey: null, authToken: token, defaultHeaders: { "anthropic-beta": "oauth-2025-04-20" } }) };
}

async function liveCheck(fn, { Anthropic, client }) {
  const content = fn.hasImage
    ? [{ type: "image", source: { type: "base64", media_type: "image/png", data: blankPng() } },
       { type: "text", text: "Extract the fields from this image. If it is blank or unreadable, leave fields empty and explain in the error field." }]
    : "Return one plausible example that fits the schema.";
  try {
    const r = await client.messages.create({ model: fn.model, max_tokens: 1024, messages: [{ role: "user", content }], output_config: fn.outputConfig });
    JSON.parse((r.content.find((b) => b.type === "text") || {}).text || "");
    return { ok: true, note: `200, valid JSON, ${r.usage.input_tokens} in / ${r.usage.output_tokens} out` };
  } catch (e) {
    if (e instanceof Anthropic.BadRequestError) {
      const detail = (e.error && e.error.error && e.error.error.message) || e.message;
      return { ok: false, note: `400 ${detail}` };
    }
    throw e;
  }
}

// ---- main ----------------------------------------------------------------------

(async () => {
  const fns = findFunctions().filter((f) => !only || f.name === only);
  if (!fns.length) { console.error(`no structured-output schemas found${only ? ` for ${only}` : ""} in ${file}`); process.exit(2); }
  const clients = live ? makeClient() : null;
  let failed = false;
  for (const fn of fns) {
    const findings = [];
    lint(fn.outputConfig.format && fn.outputConfig.format.schema, "schema", findings);
    const lintOk = !findings.some((f) => f.level === "ERROR");
    console.log(`${lintOk ? "PASS" : "FAIL"}  lint  ${fn.name} (${fn.model})`);
    for (const f of findings) console.log(`        ${f.level}  ${f.where}: ${f.msg}`);
    if (!lintOk) failed = true;
    if (live) {
      const r = await liveCheck(fn, clients);
      console.log(`${r.ok ? "PASS" : "FAIL"}  live  ${fn.name}: ${r.note}`);
      if (!r.ok) failed = true;
    }
  }
  if (!live) console.log("\n(lint only — pass --live to also send each schema to the API)");
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error("could not run:", e.message); process.exit(2); });
