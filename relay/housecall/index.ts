// Housecall relay: a Supabase Edge Function.
//
// It holds what must never be in the public script -- the Anthropic API key
// and the Google Authenticator secret -- and does the following, chosen by
// the "action" field of a JSON POST:
//
//   unlock      a 6-digit Authenticator code -> a session token (4 hours)
//   chat        one round of the AI chat: forwards the conversation to Claude
//               with Housecall's system prompt and tools, returns the reply
//   visit_get   the last visits recorded for a PC; with all: true, every
//               client's (the history's "Alle klanten", on Shamil's own devices)
//   visit_save  records a visit
//   visit_delete  removes one visit of a PC (its invoice is kept)
//   settings_get / settings_save   business details and prices for invoices
//   invoice_create  numbers and stores an invoice, totals worked out here
//   mail_status / mail_start / mail_finish / mail_disconnect
//               connect Shamil's Outlook once (Microsoft's device-code
//               sign-in); the refresh token stays in the database here
//   mail_send   mails a note, receipt or invoice (PDF): through Resend from
//               his own domain when RESEND_API_KEY and MAIL_FROM are set, else
//               through Gmail when GMAIL_USER and GMAIL_APP_PASSWORD are, else
//               that Outlook
//   doc_save    keeps the PDF a visit ended with (invoice, receipt, note) in
//               the private bucket "documents", one per visit (same id = replaced)
//   doc_list    the kept documents: one PC's, or all of them (the overview)
//   doc_get     one kept PDF
//   doc_delete  removes one kept PDF, file and all (a document made by mistake)
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
//   RESEND_API_KEY, MAIL_FROM   Resend's sending key and the address on his
//                           domain that mail comes from (tools/setup-mail.ps1)
//   GMAIL_USER, GMAIL_APP_PASSWORD   a Gmail instead (the v12 way, still works)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-opus-5";
const TOKEN_HOURS = 4;
// Wrong codes allowed. Per address in 15 minutes, so one stranger who knows
// the (public) relay URL cannot lock Shamil out by himself; and for everyone
// together in 24 hours, against guessing spread over many addresses. With
// three codes valid at a time, 20 a day makes a lucky guess take about 45
// years on average (50 per 15 minutes took about two months). The price: a
// determined attacker can lock Shamil out for a day, so he gets a mail at
// WARN_AT wrong codes and at the lock (8 Oct).
const MAX_FAILED_PER_IP = 5;
const MAX_FAILED_PER_DAY = 20;
const WARN_AT = 10;
const CODES = [
  "A1", "A2", "A3", "A4", "B1", "B2", "B3", "C1", "C2", "C3", "C4",
  "D1", "D2", "D3", "D4", "E1", "E2", "E3", "F1", "F2", "F3",
  "G1", "G2", "G3",
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
B1 no sound | B2 microphone or camera for video calls | B3 screen suddenly huge (low resolution, scale, text size), too small, dark, grey or turned
C1 printer will not print | C2 mouse, keyboard (wrong characters: layouts, Sticky/Filter Keys, NumLock) or USB stick | C3 Bluetooth | C4 laptop battery will not charge or runs out fast
D1 whole PC slow | D2 slow to start | D3 program freezes or crashes, blue screens | D4 disk full
E1 Windows Update stuck or failing, Windows 10 support | E2 error message on screen (activation, clock and time zone, recent crashes) | E3 will not shut down or restart
F1 pop-up says there is a virus | F2 someone called and got into the PC (remote-access programs) | F3 full security check
G1 desktop icons, taskbar or search gone, File Explorer stuck, temporary profile | G2 files gone or not on every device (OneDrive, Desktop/Documents/Pictures, Recycle Bin) | G3 a file cannot be found (Downloads, where the browser saves, Windows Search) or opens in the wrong program`,
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
    // No credit on the Anthropic account arrives as a 400 about the credit balance.
    if (error instanceof Anthropic.APIError && /credit balance/i.test(error.message)) return json({ error: "ai_credit" }, 402);
    if (error instanceof Anthropic.BadRequestError) return json({ error: "ai_request", detail: error.message }, 502);
    if (error instanceof Anthropic.APIError) return json({ error: "ai_error", status: error.status }, 502);
    return json({ error: "ai_unreachable" }, 502);
  }
}

// ------------------------------------------------------------ actions --

// The caller's address, only ever kept as a keyed hash (for at most a day).
async function ipHash(secret: string, req: Request): Promise<string> {
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode("housecall-ip:" + secret + ":" + ip));
  return b64url(new Uint8Array(digest)).slice(0, 22);
}

// Mails Shamil (the address in the business details) about wrong codes.
// Never in the way of unlock: a mail that cannot go is simply not sent.
async function warnOwner(total: number): Promise<void> {
  if (!resendReady()) return;
  try {
    const { data: s } = await database().from("settings").select("email").eq("id", 1).maybeSingle();
    if (!s?.email || !EMAIL.test(s.email)) return;
    const locked = total >= MAX_FAILED_PER_DAY;
    const text = locked
      ? `${total} wrong Authenticator codes were typed for Housecall in the last 24 hours, so Housecall now refuses every code for a day.\n\n` +
        "Was it you? Then wait, or ask Claude to unlock it early.\n" +
        "Was it not you? Then someone is guessing. Your clients' data is safe: the lock stops them."
      : `${total} wrong Authenticator codes were typed for Housecall in the last 24 hours.\n\n` +
        `Was it you? Then nothing is wrong. Was it not you? Then someone may be guessing; at ${MAX_FAILED_PER_DAY} Housecall locks itself for a day.`;
    await resendSend(resendKey(), {
      fromName: "Housecall", from: mailFrom(), to: s.email,
      subject: locked ? "Housecall is locked: too many wrong codes" : "Housecall: wrong Authenticator codes",
      text,
    });
  } catch { /* the lock works without the mail */ }
}

async function failedUnlock(db: ReturnType<typeof database>, ip: string, before: number): Promise<Response> {
  await db.from("failed_unlocks").insert({ failed_at: new Date().toISOString(), ip_hash: ip });
  const total = before + 1;
  if (total === WARN_AT || total === MAX_FAILED_PER_DAY) await warnOwner(total);
  return json({ error: "wrong_code" }, 401);
}

async function unlock(secret: string, code: unknown, ip: string): Promise<Response> {
  const db = database();
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const today = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const [mine, all] = await Promise.all([
    db.from("failed_unlocks").select("id", { count: "exact", head: true }).eq("ip_hash", ip).gte("failed_at", since),
    db.from("failed_unlocks").select("id", { count: "exact", head: true }).gte("failed_at", today),
  ]);
  const before = all.count ?? 0;
  if (before >= MAX_FAILED_PER_DAY) return json({ error: "locked_day" }, 429);
  if ((mine.count ?? 0) >= MAX_FAILED_PER_IP) return json({ error: "locked" }, 429);
  if (typeof code !== "string" || !/^\d{6}$/.test(code)) return failedUnlock(db, ip, before);

  const now = Math.floor(Date.now() / 1000 / 30);
  let matched: number | null = null;
  for (const step of [now - 1, now, now + 1]) {
    if (sameString(await totpAt(secret, step), code)) matched = step;
  }
  if (matched === null) return failedUnlock(db, ip, before);
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

async function visitGet(pc: unknown, all: unknown): Promise<Response> {
  if (all === true) {
    // Every client's, newest first, each with its PC so a visit can be deleted there.
    const db = database();
    const { data, error } = await db.from("visits")
      .select("id, pc, visited_at, label, lang, problems, changes, invoice_number")
      .order("visited_at", { ascending: false }).limit(100);
    if (error) return json({ error: "database" }, 500);
    const docs = await db.from("documents").select(DOC_FIELDS).order("created_at", { ascending: false }).limit(300);
    return json({ visits: data, documents: docs.error ? [] : docs.data });
  }
  if (typeof pc !== "string" || !PC.test(pc)) return json({ error: "bad_pc" }, 400);
  const { data, error } = await database().from("visits")
    .select("id, visited_at, label, lang, problems, changes, invoice_number")
    .eq("pc", pc).order("visited_at", { ascending: false }).limit(5);
  if (error) return json({ error: "database" }, 500);
  const docs = await database().from("documents").select(DOC_FIELDS)
    .eq("pc", pc).order("created_at", { ascending: false }).limit(20);
  return json({ visits: data, documents: docs.error ? [] : docs.data });
}

// deno-lint-ignore no-explicit-any
async function visitSave(body: any): Promise<Response> {
  const { pc, label, lang, os, problems, changes, invoice_number } = body;
  if (typeof pc !== "string" || !PC.test(pc)) return json({ error: "bad_pc" }, 400);
  if (label != null && (typeof label !== "string" || label.length > 80)) return json({ error: "bad_label" }, 400);
  if (lang !== "nl" && lang !== "en") return json({ error: "bad_lang" }, 400);
  if (!Array.isArray(problems) || problems.length > 20) return json({ error: "bad_problems" }, 400);
  for (const p of problems) {
    if (typeof p?.code !== "string" || !/^[A-G]\d$/.test(p.code)) return json({ error: "bad_problems" }, 400);
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
  for (const key of ["hourly_rate", "callout_fee", "start_fee"]) {
    if (!(key in input)) continue;
    const v = input[key];
    if (v !== null && (typeof v !== "number" || v < 0 || v > 10000)) return json({ error: "bad_settings", field: key }, 400);
    row[key] = v;
  }
  if ("start_minutes" in input) {
    const v = input.start_minutes;
    if (v !== null && (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 240)) return json({ error: "bad_settings", field: "start_minutes" }, 400);
    row.start_minutes = v;
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
  if (!["pin", "cash", "transfer", "tikkie"].includes(payment)) return json({ error: "bad_payment" }, 400);
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

// ----------------------------------------------------------- documents --

// The PDF a visit ended with, for Shamil's administration (7 Oct): the file
// in the private bucket, what it is about in the table. The client sends
// one id per visit, so printing, mailing and a corrected amount replace the
// same document instead of adding one.
const DOC_FIELDS = "id, created_at, pc, visit_id, kind, client_name, invoice_number, total, payment, lang";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

// deno-lint-ignore no-explicit-any
async function docSave(body: any): Promise<Response> {
  const { id, pc, visit_id, kind, client_name, invoice_number, total, payment, lang, pdf_base64 } = body;
  if (typeof id !== "string" || !UUID.test(id)) return json({ error: "bad_doc", field: "id" }, 400);
  if (pc != null && (typeof pc !== "string" || !PC.test(pc))) return json({ error: "bad_pc" }, 400);
  if (visit_id != null && (typeof visit_id !== "number" || !Number.isInteger(visit_id))) return json({ error: "bad_doc", field: "visit_id" }, 400);
  if (!["invoice", "receipt", "note"].includes(kind)) return json({ error: "bad_doc", field: "kind" }, 400);
  if (client_name != null && (typeof client_name !== "string" || client_name.length > 100)) return json({ error: "bad_doc", field: "client_name" }, 400);
  if (invoice_number != null && (typeof invoice_number !== "string" || !/^\d{4}-\d{4,}$/.test(invoice_number))) return json({ error: "bad_doc", field: "invoice_number" }, 400);
  if (total != null && (typeof total !== "number" || !Number.isFinite(total) || total < 0 || total > 100000)) return json({ error: "bad_doc", field: "total" }, 400);
  if (payment != null && !["pin", "cash", "transfer", "tikkie"].includes(payment)) return json({ error: "bad_doc", field: "payment" }, 400);
  if (lang !== "nl" && lang !== "en") return json({ error: "bad_lang" }, 400);
  if (typeof pdf_base64 !== "string" || pdf_base64.length > 4_000_000 || !/^[A-Za-z0-9+/=]+$/.test(pdf_base64)) return json({ error: "bad_doc", field: "pdf" }, 400);
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(pdf_base64), (c) => c.charCodeAt(0));
  } catch {
    return json({ error: "bad_doc", field: "pdf" }, 400);
  }
  if (new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") return json({ error: "bad_doc", field: "pdf" }, 400);

  const db = database();
  const { data: before } = await db.from("documents").select("path, created_at").eq("id", id).maybeSingle();
  const path = before?.path ?? `${new Date().getUTCFullYear()}/${id}.pdf`;
  const stored = await db.storage.from("documents").upload(path, bytes, { contentType: "application/pdf", upsert: true });
  if (stored.error) return json({ error: "storage", detail: stored.error.message }, 500);
  const { error } = await db.from("documents").upsert({
    id, pc: pc ?? null, visit_id: visit_id ?? null, kind, client_name: client_name || null,
    invoice_number: invoice_number ?? null, total: total ?? null, payment: payment ?? null, lang,
    path, size: bytes.length, updated_at: new Date().toISOString(),
  });
  if (error) return json({ error: "database" }, 500);
  return json({ saved: true, id });
}

async function docList(pc: unknown): Promise<Response> {
  if (pc != null && (typeof pc !== "string" || !PC.test(pc))) return json({ error: "bad_pc" }, 400);
  let query = database().from("documents").select(DOC_FIELDS).order("created_at", { ascending: false });
  query = pc ? query.eq("pc", pc).limit(20) : query.limit(1000);
  const { data, error } = await query;
  if (error) return json({ error: "database" }, 500);
  return json({ documents: data });
}

async function docGet(id: unknown): Promise<Response> {
  if (typeof id !== "string" || !UUID.test(id)) return json({ error: "bad_doc", field: "id" }, 400);
  const db = database();
  const { data: doc, error } = await db.from("documents").select(DOC_FIELDS + ", path").eq("id", id).maybeSingle();
  if (error) return json({ error: "database" }, 500);
  if (!doc) return json({ error: "not_found" }, 404);
  const file = await db.storage.from("documents").download(doc.path);
  if (file.error || !file.data) return json({ error: "storage", detail: file.error?.message ?? "" }, 500);
  const { path: _path, ...about } = doc;
  return json({ document: about, pdf_base64: bytesToBase64(new Uint8Array(await file.data.arrayBuffer())) });
}

// A document made by mistake (8 Oct: a receipt with the wrong payment, made
// again on another PC). Storage files cannot be deleted with SQL, so here.
async function docDelete(id: unknown): Promise<Response> {
  if (typeof id !== "string" || !UUID.test(id)) return json({ error: "bad_doc", field: "id" }, 400);
  const db = database();
  const { data: doc, error } = await db.from("documents").select("path").eq("id", id).maybeSingle();
  if (error) return json({ error: "database" }, 500);
  if (!doc) return json({ deleted: 0 });
  const removed = await db.storage.from("documents").remove([doc.path]);
  if (removed.error) return json({ error: "storage", detail: removed.error.message }, 500);
  const gone = await db.from("documents").delete().eq("id", id);
  if (gone.error) return json({ error: "database" }, 500);
  return json({ deleted: 1 });
}

// ---------------------------------------------------------------- mail --

// Microsoft's sign-in for personal accounts (outlook.com). Housecall has its
// own app registration (a public client, no secret); Shamil signs in once
// with the device-code flow and the refresh token is kept in mail_account.
const MS_LOGIN = "https://login.microsoftonline.com/consumers/oauth2/v2.0";
const MAIL_SCOPE = "offline_access https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/User.Read";
const MAIL_PER_HOUR = 20;
const MAIL_PER_DAY = 60;
const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[a-z]{2,}$/i;

async function msPost(path: string, form: Record<string, string>) {
  const r = await fetch(`${MS_LOGIN}/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  });
  return { status: r.status, data: await r.json().catch(() => ({})) };
}

// ---- Gmail (v12, 6 Oct): the Microsoft app registration was too much of a
// hurdle, so mail goes out through a Gmail account with an app password,
// set as two secrets. Supabase blocks ports 25 and 587, so SMTP over TLS on
// 465, spoken here directly (Deno's own TLS; no mail library to break).
// Replies go to the email address in the business details (his Outlook).

function gmailUser(): string {
  return (Deno.env.get("GMAIL_USER") ?? "").trim();
}
function gmailPassword(): string {
  // Google shows the app password in groups of four: "abcd efgh ijkl mnop".
  return (Deno.env.get("GMAIL_APP_PASSWORD") ?? "").replace(/\s+/g, "");
}
function gmailReady(): boolean {
  return EMAIL.test(gmailUser()) && gmailPassword().length >= 16;
}

// ---- Resend (8 Oct): mail from his own domain looks better and lands in
// spam less than a Gmail. The domain is verified at Resend (DKIM and SPF);
// the key may only send, from that domain. Resend has a plain HTTPS API, so
// no SMTP here.

function resendKey(): string {
  return (Deno.env.get("RESEND_API_KEY") ?? "").trim();
}
function mailFrom(): string {
  return (Deno.env.get("MAIL_FROM") ?? "").trim();
}
function resendReady(): boolean {
  return resendKey().startsWith("re_") && EMAIL.test(mailFrom());
}

// Resend's error, without anything that was sent.
export class ResendError extends Error {
  status: number;
  kind: string;
  constructor(status: number, name: string, message: string) {
    super(message);
    this.status = status;
    this.kind = name;
  }
}

export async function resendSend(key: string, o: {
  fromName: string; from: string; to: string; replyTo?: string | null; subject: string; text: string;
  pdfBase64?: string | null; filename?: string | null;
}, fetcher: typeof fetch = fetch): Promise<string> {
  const name = o.fromName.replace(/[<>"\\\r\n]/g, "").trim();
  const payload: Record<string, unknown> = {
    from: name ? `${name} <${o.from}>` : o.from,
    to: [o.to],
    subject: o.subject,
    text: o.text,
  };
  if (o.replyTo && EMAIL.test(o.replyTo) && o.replyTo.toLowerCase() !== o.from.toLowerCase()) payload.reply_to = o.replyTo;
  if (o.pdfBase64) payload.attachments = [{ filename: o.filename ?? "document.pdf", content: o.pdfBase64.replace(/\s+/g, "") }];
  const r = await fetcher("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  // deno-lint-ignore no-explicit-any
  const data: any = await r.json().catch(() => ({}));
  if (!r.ok) throw new ResendError(r.status, String(data.name ?? ""), String(data.message ?? "").slice(0, 300));
  return String(data.id ?? "");
}

function base64Utf8(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
function wrap76(s: string): string {
  return s.replace(/.{1,76}/g, "$&\r\n").replace(/\r\n$/, "");
}
// A header value: plain when it is plain ASCII, else UTF-8 encoded words.
function headerText(s: string): string {
  if (/^[\x20-\x7e]*$/.test(s)) return s;
  const parts: string[] = [];
  for (const chunk of s.match(/.{1,30}/gsu) ?? []) parts.push(`=?UTF-8?B?${base64Utf8(chunk)}?=`);
  return parts.join("\r\n ");
}

export function buildMime(o: {
  fromName: string; from: string; to: string; replyTo?: string | null; subject: string; text: string;
  pdfBase64?: string | null; filename?: string | null; date: Date; id: string;
}): string {
  const name = /^[\x20-\x7e]*$/.test(o.fromName) ? `"${o.fromName.replace(/["\\]/g, "")}"` : headerText(o.fromName);
  const head = [
    `From: ${name} <${o.from}>`,
    `To: <${o.to}>`,
    ...(o.replyTo && o.replyTo.toLowerCase() !== o.from.toLowerCase() ? [`Reply-To: <${o.replyTo}>`] : []),
    `Subject: ${headerText(o.subject)}`,
    `Date: ${o.date.toUTCString()}`,
    `Message-ID: <${o.id}@housecall.relay>`,
    "MIME-Version: 1.0",
  ];
  const body = wrap76(base64Utf8(o.text.replace(/\r?\n/g, "\r\n")));
  if (!o.pdfBase64) {
    return [...head, "Content-Type: text/plain; charset=utf-8", "Content-Transfer-Encoding: base64", "", body].join("\r\n");
  }
  const boundary = `hc-${o.id}`;
  const file = o.filename ?? "document.pdf";
  const fileParam = /^[\x20-\x7e]*$/.test(file) ? `filename="${file.replace(/["\\]/g, "")}"` : `filename*=UTF-8''${encodeURIComponent(file)}`;
  return [
    ...head,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: base64",
    "",
    body,
    `--${boundary}`,
    "Content-Type: application/pdf",
    "Content-Transfer-Encoding: base64",
    `Content-Disposition: attachment; ${fileParam}`,
    "",
    wrap76(o.pdfBase64.replace(/\s+/g, "")),
    `--${boundary}--`,
  ].join("\r\n");
}

export interface SmtpConn {
  read(p: Uint8Array): Promise<number | null>;
  write(p: Uint8Array): Promise<number>;
}

// A refused step; never carries what was sent (the AUTH line holds the password).
export class SmtpError extends Error {
  step: string;
  code: number;
  reply: string;
  constructor(step: string, code: number, reply: string) {
    super(`${step} ${code}`);
    this.step = step;
    this.code = code;
    this.reply = reply;
  }
}

export async function smtpSend(conn: SmtpConn, user: string, password: string, to: string, mime: string): Promise<void> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  const reply = async (): Promise<{ code: number; text: string }> => {
    const lines: string[] = [];
    for (;;) {
      let end: number;
      while ((end = buffer.indexOf("\r\n")) < 0) {
        const chunk = new Uint8Array(4096);
        const n = await conn.read(chunk);
        if (n === null) throw new SmtpError("closed", 0, "");
        buffer += decoder.decode(chunk.subarray(0, n), { stream: true });
      }
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      lines.push(line);
      if (/^\d{3}( |$)/.test(line)) return { code: Number(line.slice(0, 3)), text: lines.join("\n") };
    }
  };
  const send = async (s: string) => {
    let data = encoder.encode(s);
    while (data.length) data = data.subarray(await conn.write(data));
  };
  const step = async (name: string, line: string, ok: number[]) => {
    await send(line + "\r\n");
    const r = await reply();
    if (!ok.includes(r.code)) throw new SmtpError(name, r.code, r.text.slice(0, 200));
  };
  const hello = await reply();
  if (hello.code !== 220) throw new SmtpError("connect", hello.code, hello.text.slice(0, 200));
  await step("EHLO", "EHLO housecall.relay", [250]);
  await step("AUTH", `AUTH PLAIN ${base64Utf8(`\0${user}\0${password}`)}`, [235]);
  await step("MAIL", `MAIL FROM:<${user}>`, [250]);
  await step("RCPT", `RCPT TO:<${to}>`, [250, 251]);
  await step("DATA", "DATA", [354]);
  // A line that starts with a dot gets a second one (dot-stuffing).
  await step("SEND", mime.replace(/(^|\r\n)\./g, "$1..") + "\r\n.", [250]);
  await send("QUIT\r\n").catch(() => {});
}

async function mailStatus(): Promise<Response> {
  if (resendReady()) return json({ connected: true, email: mailFrom(), via: "resend" });
  if (gmailReady()) return json({ connected: true, email: gmailUser(), via: "gmail" });
  const { data, error } = await database().from("mail_account").select("email, updated_at").eq("id", 1).maybeSingle();
  if (error) return json({ error: "database" }, 500);
  return json({ connected: !!data, email: data?.email ?? null });
}

async function mailStart(clientId: unknown): Promise<Response> {
  if (typeof clientId !== "string" || !GUID.test(clientId)) return json({ error: "bad_client_id" }, 400);
  const r = await msPost("devicecode", { client_id: clientId, scope: MAIL_SCOPE });
  if (r.status !== 200) return json({ error: "mail_ms", detail: r.data.error_description ?? r.data.error ?? r.status }, 502);
  return json({
    user_code: r.data.user_code, verification_uri: r.data.verification_uri, device_code: r.data.device_code,
    interval: r.data.interval ?? 5, expires_in: r.data.expires_in ?? 900,
  });
}

async function mailFinish(clientId: unknown, deviceCode: unknown): Promise<Response> {
  if (typeof clientId !== "string" || !GUID.test(clientId)) return json({ error: "bad_client_id" }, 400);
  if (typeof deviceCode !== "string" || deviceCode.length > 2000) return json({ error: "bad_device_code" }, 400);
  const r = await msPost("token", {
    grant_type: "urn:ietf:params:oauth:grant-type:device_code", client_id: clientId, device_code: deviceCode,
  });
  if (r.status !== 200) {
    const code = String(r.data.error ?? "");
    if (code === "authorization_pending" || code === "slow_down") return json({ pending: true });
    return json({ error: "mail_ms", detail: code || r.status }, 400);
  }
  let email: string | null = null;
  const me = await fetch("https://graph.microsoft.com/v1.0/me", { headers: { Authorization: `Bearer ${r.data.access_token}` } });
  if (me.ok) {
    const who = await me.json();
    email = who.mail ?? who.userPrincipalName ?? null;
  }
  const { error } = await database().from("mail_account").upsert({
    id: 1, client_id: clientId, refresh_token: r.data.refresh_token, email, updated_at: new Date().toISOString(),
  });
  if (error) return json({ error: "database" }, 500);
  return json({ connected: true, email });
}

async function mailDisconnect(): Promise<Response> {
  const { error } = await database().from("mail_account").delete().eq("id", 1);
  if (error) return json({ error: "database" }, 500);
  return json({ connected: false });
}

// deno-lint-ignore no-explicit-any
async function mailSend(body: any): Promise<Response> {
  const { to, subject, text, pdf_base64, filename } = body;
  if (typeof to !== "string" || to.length > 254 || !EMAIL.test(to)) return json({ error: "bad_mail", field: "to" }, 400);
  if (typeof subject !== "string" || subject.trim() === "" || subject.length > 200) return json({ error: "bad_mail", field: "subject" }, 400);
  if (typeof text !== "string" || text.length > 8000) return json({ error: "bad_mail", field: "text" }, 400);
  if (pdf_base64 != null) {
    if (typeof pdf_base64 !== "string" || pdf_base64.length > 3_000_000 || !/^[A-Za-z0-9+/=]+$/.test(pdf_base64)) return json({ error: "bad_mail", field: "pdf" }, 400);
    if (typeof filename !== "string" || filename.length > 100 || !/^[\p{L}\p{N} ._,()-]+\.pdf$/u.test(filename)) return json({ error: "bad_mail", field: "filename" }, 400);
  }

  const db = database();
  const hour = new Date(Date.now() - 3600 * 1000).toISOString();
  const day = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const [h, d] = await Promise.all([
    db.from("mail_log").select("id", { count: "exact", head: true }).gte("sent_at", hour),
    db.from("mail_log").select("id", { count: "exact", head: true }).gte("sent_at", day),
  ]);
  if ((h.count ?? 0) >= MAIL_PER_HOUR || (d.count ?? 0) >= MAIL_PER_DAY) return json({ error: "mail_limit" }, 429);

  if (resendReady()) {
    const { data: settings } = await db.from("settings").select("business_name, owner_name, email").eq("id", 1).maybeSingle();
    try {
      await resendSend(resendKey(), {
        fromName: settings?.business_name || settings?.owner_name || "Housecall",
        from: mailFrom(), to, replyTo: settings?.email ?? null, subject: subject.trim(), text,
        pdfBase64: pdf_base64 ?? null, filename: filename ?? null,
      });
    } catch (e) {
      // A key that was deleted or mistyped: set it again.
      if (e instanceof ResendError && (e.status === 401 || /api_key/.test(e.kind))) return json({ error: "mail_reconnect", detail: e.message }, 401);
      const detail = e instanceof ResendError ? `${e.status} ${e.kind} ${e.message}` : String(e).slice(0, 200);
      return json({ error: "mail_failed", detail }, 502);
    }
    await db.from("mail_log").insert({});
    return json({ sent: true, from: mailFrom() });
  }

  if (gmailReady()) {
    const { data: settings } = await db.from("settings").select("business_name, owner_name, email").eq("id", 1).maybeSingle();
    const mime = buildMime({
      fromName: settings?.business_name || settings?.owner_name || "Housecall",
      from: gmailUser(), to, replyTo: settings?.email ?? null, subject: subject.trim(), text,
      pdfBase64: pdf_base64 ?? null, filename: filename ?? null, date: new Date(), id: crypto.randomUUID(),
    });
    let conn: Deno.TlsConn | null = null;
    try {
      conn = await Deno.connectTls({ hostname: "smtp.gmail.com", port: 465 });
      await smtpSend(conn, gmailUser(), gmailPassword(), to, mime);
    } catch (e) {
      // A refused login: the app password was removed or mistyped.
      if (e instanceof SmtpError && e.step === "AUTH") return json({ error: "mail_reconnect", detail: e.reply }, 401);
      const detail = e instanceof SmtpError ? `${e.step} ${e.code} ${e.reply}` : String(e).slice(0, 200);
      return json({ error: "mail_failed", detail }, 502);
    } finally {
      try { conn?.close(); } catch { /* already closed */ }
    }
    await db.from("mail_log").insert({});
    return json({ sent: true, from: gmailUser() });
  }

  const { data: account } = await db.from("mail_account").select("*").eq("id", 1).maybeSingle();
  if (!account) return json({ error: "mail_not_set_up" }, 400);
  const t = await msPost("token", {
    grant_type: "refresh_token", client_id: account.client_id, refresh_token: account.refresh_token, scope: MAIL_SCOPE,
  });
  if (t.status !== 200) {
    if (t.data.error === "invalid_grant") return json({ error: "mail_reconnect" }, 401);
    return json({ error: "mail_ms", detail: t.data.error ?? t.status }, 502);
  }
  // Microsoft hands out a new refresh token now and then; keep the newest.
  if (t.data.refresh_token && t.data.refresh_token !== account.refresh_token) {
    await db.from("mail_account").update({ refresh_token: t.data.refresh_token, updated_at: new Date().toISOString() }).eq("id", 1);
  }

  const message: Record<string, unknown> = {
    subject: subject.trim(),
    body: { contentType: "Text", content: text },
    toRecipients: [{ emailAddress: { address: to } }],
  };
  if (pdf_base64) {
    message.attachments = [{ "@odata.type": "#microsoft.graph.fileAttachment", name: filename, contentType: "application/pdf", contentBytes: pdf_base64 }];
  }
  const sent = await fetch("https://graph.microsoft.com/v1.0/me/sendMail", {
    method: "POST",
    headers: { Authorization: `Bearer ${t.data.access_token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message, saveToSentItems: true }),
  });
  if (sent.status !== 202) {
    const detail = await sent.text().catch(() => "");
    return json({ error: "mail_failed", status: sent.status, detail: detail.slice(0, 300) }, 502);
  }
  await db.from("mail_log").insert({});
  return json({ sent: true, from: account.email });
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
    return json({ anthropic_key: !!Deno.env.get("ANTHROPIC_API_KEY"), totp_secret: secret.length >= 16, database: db, resend: resendReady(), gmail: gmailReady() });
  }
  if (secret.length < 16) return json({ error: "not_set_up" }, 503);
  if (body?.action === "unlock") return unlock(secret, body.code, await ipHash(secret, req));
  if (!(await tokenValid(secret, body?.token))) return json({ error: "locked_out" }, 401);

  switch (body?.action) {
    case "chat": {
      const messages = readMessages(body.messages);
      if (typeof messages === "string") return json({ error: "bad_messages", detail: messages }, 400);
      return chat(messages);
    }
    case "visit_get":
      return visitGet(body.pc, body.all);
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
    case "mail_status":
      return mailStatus();
    case "mail_start":
      return mailStart(body.client_id);
    case "mail_finish":
      return mailFinish(body.client_id, body.device_code);
    case "mail_disconnect":
      return mailDisconnect();
    case "mail_send":
      return mailSend(body);
    case "doc_save":
      return docSave(body);
    case "doc_list":
      return docList(body.pc);
    case "doc_get":
      return docGet(body.id);
    case "doc_delete":
      return docDelete(body.id);
    default:
      return json({ error: "unknown_action" }, 400);
  }
});
