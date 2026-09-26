// Housecall relay: a Supabase Edge Function.
//
// It holds what must never be in the public script -- the Anthropic API key
// and the Google Authenticator secret -- and does the following, chosen by
// the "action" field of a JSON POST:
//
//   unlock      a 6-digit Authenticator code -> a session token (4 hours)
//   chat        one round of the AI chat: forwards the conversation to Claude
//               with Housecall's system prompt and tools, returns the reply
//   visit_get   the last visits recorded for a PC
//   visit_save  records a visit
//   visit_delete  removes one visit of a PC (its invoice is kept)
//   settings_get / settings_save   business details and prices for invoices
//   invoice_create  numbers and stores an invoice, totals worked out here
//   health      which secrets are set (booleans only), for setup
//
// Everything except health and unlock needs the token. The token is signed
// with a key derived from the Authenticator secret, so nothing else has to
// be configured. The PowerShell client runs the checks on the client's PC;
// this function never sees more than the problem text and the check results.
//
// Secrets (Supabase dashboard > Edge Functions > Secrets):
//   ANTHROPIC_API_KEY       from console.anthropic.com
//   HOUSECALL_TOTP_SECRET   made by tools/setup-ai.ps1 on Shamil's PC
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-5";
const TOKEN_HOURS = 4;
const MAX_FAILED_UNLOCKS = 10; // in 15 minutes, for everyone together
const CODES = [
  "A1", "A2", "A3", "A4", "B1", "B2", "B3", "C1", "C2", "C3",
  "D1", "D2", "D3", "D4", "E1", "E2", "E3", "F1", "F2", "F3",
];

// ------------------------------------------------------------ plumbing --

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

const encoder = new TextEncoder();

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function sameString(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function base32Decode(text: string): Uint8Array {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = text.toUpperCase().replace(/[^A-Z2-7]/g, "");
  const out: number[] = [];
  let bits = 0;
  let value = 0;
  for (const c of clean) {
    value = ((value << 5) | alphabet.indexOf(c)) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

// RFC 6238: HMAC-SHA1, 30-second steps, 6 digits -- what Google Authenticator uses.
async function totpAt(secret: string, step: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", base32Decode(secret), { name: "HMAC", hash: "SHA-1" }, false, ["sign"],
  );
  const counter = new DataView(new ArrayBuffer(8));
  counter.setUint32(0, Math.floor(step / 2 ** 32));
  counter.setUint32(4, step >>> 0);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, counter.buffer));
  const o = mac[19] & 0x0f;
  const n = (((mac[o] & 0x7f) << 24) | (mac[o + 1] << 16) | (mac[o + 2] << 8) | mac[o + 3]) % 1_000_000;
  return n.toString().padStart(6, "0");
}

async function tokenKey(secret: string): Promise<CryptoKey> {
  const raw = await crypto.subtle.digest("SHA-256", encoder.encode("housecall-session:" + secret));
  return crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
}

async function makeToken(secret: string): Promise<{ token: string; expires: string }> {
  const exp = Date.now() + TOKEN_HOURS * 3600 * 1000;
  const payload = b64url(encoder.encode(JSON.stringify({ exp })));
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await tokenKey(secret), encoder.encode(payload)));
  return { token: `${payload}.${b64url(sig)}`, expires: new Date(exp).toISOString() };
}

async function tokenValid(secret: string, token: unknown): Promise<boolean> {
  if (typeof token !== "string" || !token.includes(".")) return false;
  const [payload, sig] = token.split(".");
  const expected = new Uint8Array(await crypto.subtle.sign("HMAC", await tokenKey(secret), encoder.encode(payload)));
  if (!sameString(b64url(expected), sig)) return false;
  try {
    const { exp } = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return typeof exp === "number" && exp > Date.now();
  } catch {
    return false;
  }
}

function database() {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
  return createClient(Deno.env.get("SUPABASE_URL") ?? "", key, { auth: { persistSession: false } });
}

// ------------------------------------------------------------ the AI --

// Kept identical on every request (no dates, no per-request values) so the
// prompt cache can reuse it.
const SYSTEM = `You are the diagnostic assistant inside Housecall, a tool that a computer technician, Shamil, runs on a client's Windows PC during a home visit. Clients are often older people who are not technical. Shamil types the client's problem in their own words.

You can only act through two tools. run_check runs one of Housecall's read-only checks on this PC and returns what it saw, Housecall's own finding and advice, and the fixes Housecall can offer for it. You cannot run commands, read files, or change anything yourself: a change only happens when Shamil picks one of the offered fixes and confirms it.

How to work:
- Choose the checks that match the problem, usually one to three. Do not run checks that have nothing to do with it. At most six checks in total.
- Read the results. Housecall's finding is usually right, but combine results when the problem spans areas.
- Finish by calling give_answer once. Do not write the answer as plain text.

In give_answer:
- summary: two to four calm, plain sentences a non-technical client understands, saying what is wrong and what will help. No jargon, no blame.
- problem_code: the check whose result best explains the problem, or "none" if no check explains it.
- fix_ids: only fix ids that the check results listed as offered and that address the cause, most useful first. Leave it empty if none fits.
- steps: short manual steps, at most six, when no offered fix covers it or as follow-up. Empty if the fixes cover it.
- confidence: honest. Use "low" when the checks do not show the cause.

Write summary and steps in the language given at the start of the first message (nl = Dutch, formal "u"; en = English). If the problem is outside what the checks can see (a password, an account at a website, a broken screen), say so and give steps. Never suggest calling a phone number from a pop-up, installing remote-access software, or sharing a password or bank code.`;

const TOOLS = [
  {
    name: "run_check",
    description: `Runs one of Housecall's read-only checks on the client's PC and returns the result lines, Housecall's finding and advice, and the fixes it offers (as "fixId: label").
Codes:
A1 no internet at all | A2 Wi-Fi slow or drops | A3 one website or app will not load (input: the web address) | A4 email will not send or arrive (input: the email address or its domain)
B1 no sound | B2 microphone or camera for video calls | B3 screen too small, dark, grey or turned
C1 printer will not print | C2 mouse, keyboard or USB stick | C3 Bluetooth
D1 whole PC slow | D2 slow to start | D3 program freezes or crashes, blue screens | D4 disk full
E1 Windows Update stuck or failing, Windows 10 support | E2 error message on screen (activation, clock, recent crashes) | E3 will not shut down or restart
F1 pop-up says there is a virus | F2 someone called and got into the PC (remote-access programs) | F3 full security check`,
    strict: true,
    input_schema: {
      type: "object",
      properties: {
        code: { type: "string", enum: CODES },
        input: { type: "string", description: "For A3 the web address, for A4 the email address or domain; an empty string for every other code." },
      },
      required: ["code", "input"],
      additionalProperties: false,
    },
  },
  {
    name: "give_answer",
    description: "Ends the diagnosis with the answer Housecall shows to Shamil and the client. Call it exactly once, after the checks.",
    strict: true,
    input_schema: {
      type: "object",
      properties: {
        summary: { type: "string" },
        confidence: { type: "string", enum: ["low", "medium", "high"] },
        problem_code: { type: "string", enum: [...CODES, "none"] },
        fix_ids: { type: "array", items: { type: "string" } },
        steps: { type: "array", items: { type: "string" } },
      },
      required: ["summary", "confidence", "problem_code", "fix_ids", "steps"],
      additionalProperties: false,
    },
  },
];

type Incoming = { role: "user" | "assistant"; content_json: string };

// The client keeps each turn's content exactly as the API returned it (as a
// JSON string), so thinking blocks go back unchanged.
function readMessages(raw: unknown): Anthropic.Beta.BetaMessageParam[] | string {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 40) return "messages must be 1 to 40 turns";
  let total = 0;
  const messages: Anthropic.Beta.BetaMessageParam[] = [];
  for (const m of raw as Incoming[]) {
    if ((m.role !== "user" && m.role !== "assistant") || typeof m.content_json !== "string") return "bad message";
    total += m.content_json.length;
    if (total > 400_000) return "conversation too long";
    try {
      messages.push({ role: m.role, content: JSON.parse(m.content_json) });
    } catch {
      return "content_json is not JSON";
    }
  }
  if (messages[0].role !== "user") return "first message must be from the user";
  return messages;
}

async function chat(messages: Anthropic.Beta.BetaMessageParam[]): Promise<Response> {
  const anthropic = new Anthropic({ timeout: 120_000, maxRetries: 1 });
  try {
    // fallbacks "default": if a safety classifier declines, the API re-runs
    // the request on Anthropic's recommended fallback model.
    const params = {
      model: MODEL,
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      cache_control: { type: "ephemeral" },
      system: SYSTEM,
      tools: TOOLS,
      messages,
    };
    // deno-lint-ignore no-explicit-any
    const response = await anthropic.beta.messages.create(params as any);
    return json({
      stop_reason: response.stop_reason,
      content: response.content,
      content_json: JSON.stringify(response.content),
      model: response.model,
    });
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) return json({ error: "ai_key" }, 502);
    if (error instanceof Anthropic.RateLimitError) return json({ error: "ai_busy" }, 503);
    if (error instanceof Anthropic.BadRequestError) return json({ error: "ai_request", detail: error.message }, 502);
    if (error instanceof Anthropic.APIError) return json({ error: "ai_error", status: error.status }, 502);
    return json({ error: "ai_unreachable" }, 502);
  }
}

// ------------------------------------------------------------ actions --

async function unlock(secret: string, code: unknown): Promise<Response> {
  if (typeof code !== "string" || !/^\d{6}$/.test(code)) return json({ error: "wrong_code" }, 401);
  const db = database();
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await db.from("failed_unlocks").select("id", { count: "exact", head: true }).gte("failed_at", since);
  if ((count ?? 0) >= MAX_FAILED_UNLOCKS) return json({ error: "locked" }, 429);

  const now = Math.floor(Date.now() / 1000 / 30);
  let matched: number | null = null;
  for (const step of [now - 1, now, now + 1]) {
    if (sameString(await totpAt(secret, step), code)) matched = step;
  }
  if (matched === null) {
    await db.from("failed_unlocks").insert({ failed_at: new Date().toISOString() });
    return json({ error: "wrong_code" }, 401);
  }
  const { error } = await db.from("used_codes").insert({ step: matched });
  if (error) {
    if (error.code === "23505") return json({ error: "code_used" }, 401);
    return json({ error: "database" }, 500);
  }
  const day = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  await db.from("used_codes").delete().lt("used_at", day);
  await db.from("failed_unlocks").delete().lt("failed_at", day);
  return json(await makeToken(secret));
}

const PC = /^[0-9a-f]{64}$/;

async function visitGet(pc: unknown): Promise<Response> {
  if (typeof pc !== "string" || !PC.test(pc)) return json({ error: "bad_pc" }, 400);
  const { data, error } = await database().from("visits")
    .select("id, visited_at, label, lang, problems, changes, invoice_number")
    .eq("pc", pc).order("visited_at", { ascending: false }).limit(5);
  if (error) return json({ error: "database" }, 500);
  return json({ visits: data });
}

// deno-lint-ignore no-explicit-any
async function visitSave(body: any): Promise<Response> {
  const { pc, label, lang, os, problems, changes, invoice_number } = body;
  if (typeof pc !== "string" || !PC.test(pc)) return json({ error: "bad_pc" }, 400);
  if (label != null && (typeof label !== "string" || label.length > 80)) return json({ error: "bad_label" }, 400);
  if (lang !== "nl" && lang !== "en") return json({ error: "bad_lang" }, 400);
  if (!Array.isArray(problems) || problems.length > 20) return json({ error: "bad_problems" }, 400);
  for (const p of problems) {
    if (typeof p?.code !== "string" || !/^[A-F]\d$/.test(p.code)) return json({ error: "bad_problems" }, 400);
    if (typeof p?.finding !== "string" || !/^\w{1,40}$/.test(p.finding)) return json({ error: "bad_problems" }, 400);
  }
  if (!Array.isArray(changes) || changes.length > 30 || changes.some((c) => typeof c !== "string" || c.length > 200)) {
    return json({ error: "bad_changes" }, 400);
  }
  if (invoice_number != null && (typeof invoice_number !== "string" || !/^\d{4}-\d{4,}$/.test(invoice_number))) {
    return json({ error: "bad_invoice_number" }, 400);
  }
  const { data, error } = await database().from("visits").insert({
    pc, label: label || null, lang, os: typeof os === "string" ? os.slice(0, 80) : null,
    problems: problems.map((p: { code: string; finding: string }) => ({ code: p.code, finding: p.finding })),
    changes, invoice_number: invoice_number ?? null,
  }).select("id").single();
  if (error) return json({ error: "database" }, 500);
  return json({ saved: true, id: data.id });
}

async function visitDelete(pc: unknown, id: unknown): Promise<Response> {
  if (typeof pc !== "string" || !PC.test(pc)) return json({ error: "bad_pc" }, 400);
  if (typeof id !== "number" || !Number.isInteger(id)) return json({ error: "bad_id" }, 400);
  // Only a visit of this same PC can be deleted from it.
  const { data, error } = await database().from("visits").delete().eq("id", id).eq("pc", pc).select("id");
  if (error) return json({ error: "database" }, 500);
  return json({ deleted: (data ?? []).length });
}

// ------------------------------------------------------------ invoices --

const SETTING_TEXT: Record<string, number> = {
  business_name: 100, owner_name: 100, address: 120, postcode_city: 120, kvk: 20,
  btw_number: 30, iban: 40, email: 120, phone: 30,
};

async function settingsGet(): Promise<Response> {
  const { data, error } = await database().from("settings").select("*").eq("id", 1).maybeSingle();
  if (error) return json({ error: "database" }, 500);
  return json({ settings: data });
}

// deno-lint-ignore no-explicit-any
async function settingsSave(input: any): Promise<Response> {
  if (typeof input !== "object" || input === null) return json({ error: "bad_settings" }, 400);
  const row: Record<string, unknown> = { id: 1, updated_at: new Date().toISOString() };
  for (const [key, max] of Object.entries(SETTING_TEXT)) {
    if (!(key in input)) continue;
    const v = input[key];
    if (v !== null && (typeof v !== "string" || v.length > max)) return json({ error: "bad_settings", field: key }, 400);
    row[key] = v === "" ? null : v;
  }
  for (const key of ["hourly_rate", "callout_fee"]) {
    if (!(key in input)) continue;
    const v = input[key];
    if (v !== null && (typeof v !== "number" || v < 0 || v > 10000)) return json({ error: "bad_settings", field: key }, 400);
    row[key] = v;
  }
  if ("btw_mode" in input) {
    if (!["unset", "kor", "21"].includes(input.btw_mode)) return json({ error: "bad_settings", field: "btw_mode" }, 400);
    row.btw_mode = input.btw_mode;
  }
  if ("payment_days" in input) {
    const v = input.payment_days;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 90) return json({ error: "bad_settings", field: "payment_days" }, 400);
    row.payment_days = v;
  }
  const { error } = await database().from("settings").upsert(row);
  if (error) return json({ error: "database" }, 500);
  return settingsGet();
}

const cents = (n: number) => Math.round(n * 100);

// The client composes the lines (it knows the language); the numbers, the
// totals, the BTW and the seller's details are decided here.
// deno-lint-ignore no-explicit-any
async function invoiceCreate(body: any): Promise<Response> {
  const db = database();
  const { data: settings } = await db.from("settings").select("*").eq("id", 1).maybeSingle();
  if (!settings?.business_name) return json({ error: "no_settings" }, 400);

  const { pc, lang, client, lines, payment, problems, changes } = body;
  if (pc != null && (typeof pc !== "string" || !PC.test(pc))) return json({ error: "bad_pc" }, 400);
  if (lang !== "nl" && lang !== "en") return json({ error: "bad_lang" }, 400);
  if (typeof client?.name !== "string" || client.name.trim() === "" || client.name.length > 100) return json({ error: "bad_client" }, 400);
  for (const k of ["address", "postcode_city", "email"]) {
    if (client[k] != null && (typeof client[k] !== "string" || client[k].length > 120)) return json({ error: "bad_client" }, 400);
  }
  if (!["pin", "cash", "transfer"].includes(payment)) return json({ error: "bad_payment" }, 400);
  if (!Array.isArray(lines) || lines.length === 0 || lines.length > 30) return json({ error: "bad_lines" }, 400);
  const clean: { description: string; amount: number }[] = [];
  for (const l of lines) {
    if (typeof l?.description !== "string" || l.description.trim() === "" || l.description.length > 120) return json({ error: "bad_lines" }, 400);
    if (typeof l?.amount !== "number" || !Number.isFinite(l.amount) || l.amount < 0 || l.amount > 100000) return json({ error: "bad_lines" }, 400);
    clean.push({ description: l.description.trim(), amount: cents(l.amount) / 100 });
  }

  // Prices include BTW when there is BTW: the total is what the client pays.
  const totalCents = clean.reduce((sum, l) => sum + cents(l.amount), 0);
  let subtotalCents = totalCents;
  let btwCents = 0;
  if (settings.btw_mode === "21") {
    subtotalCents = Math.round(totalCents / 1.21);
    btwCents = totalCents - subtotalCents;
  }
  let due: string | null = null;
  if (payment === "transfer") {
    const d = new Date(Date.now() + (settings.payment_days ?? 14) * 86400_000);
    due = d.toISOString().slice(0, 10);
  }
  const seller = {
    business_name: settings.business_name, owner_name: settings.owner_name, address: settings.address,
    postcode_city: settings.postcode_city, kvk: settings.kvk, btw_number: settings.btw_number,
    iban: settings.iban, email: settings.email, phone: settings.phone,
  };
  const { data, error } = await db.rpc("issue_invoice", {
    inv: {
      pc: pc ?? null, lang,
      client_name: client.name.trim(), client_address: client.address || null,
      client_postcode_city: client.postcode_city || null, client_email: client.email || null,
      lines: clean, btw_mode: settings.btw_mode,
      subtotal: subtotalCents / 100, btw_amount: btwCents / 100, total: totalCents / 100,
      payment, due_date: due,
      problems: Array.isArray(problems) ? problems.slice(0, 20) : [],
      changes: Array.isArray(changes) ? changes.filter((c: unknown) => typeof c === "string").slice(0, 30) : [],
      seller,
    },
  });
  if (error) return json({ error: "database" }, 500);
  return json({ invoice: data });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "post_only" }, 405);
  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  const secret = Deno.env.get("HOUSECALL_TOTP_SECRET") ?? "";

  if (body?.action === "health") {
    let db = false;
    try {
      const { error } = await database().from("visits").select("id", { head: true, count: "exact" });
      db = !error;
    } catch { /* stays false */ }
    return json({ anthropic_key: !!Deno.env.get("ANTHROPIC_API_KEY"), totp_secret: secret.length >= 16, database: db });
  }
  if (secret.length < 16) return json({ error: "not_set_up" }, 503);
  if (body?.action === "unlock") return unlock(secret, body.code);
  if (!(await tokenValid(secret, body?.token))) return json({ error: "locked_out" }, 401);

  switch (body?.action) {
    case "chat": {
      const messages = readMessages(body.messages);
      if (typeof messages === "string") return json({ error: "bad_messages", detail: messages }, 400);
      return chat(messages);
    }
    case "visit_get":
      return visitGet(body.pc);
    case "visit_save":
      return visitSave(body);
    case "visit_delete":
      return visitDelete(body.pc, body.id);
    case "settings_get":
      return settingsGet();
    case "settings_save":
      return settingsSave(body.settings);
    case "invoice_create":
      return invoiceCreate(body);
    default:
      return json({ error: "unknown_action" }, 400);
  }
});
