// deno test relay/housecall/auth_test.ts
import { allowedFor, type Claims, ownPc } from "./auth.ts";

const pcA = "a".repeat(64);
const pcB = "b".repeat(64);
const visit: Claims = { exp: Date.now() + 1000, s: "visit", pc: pcA, e: 1, j: "j1" };
const loose: Claims = { exp: Date.now() + 1000, s: "visit", pc: null, e: 1, j: "j2" };
const full: Claims = { exp: Date.now() + 1000, s: "full", pc: null, e: 1, j: "j3" };

function same(actual: unknown, expected: unknown, what: string) {
  if (actual !== expected) throw new Error(`${what}: got ${actual}, expected ${expected}`);
}

Deno.test("a client PC's pass cannot change settings, delete documents or cancel passes", () => {
  for (const action of ["settings_save", "doc_delete", "passes_revoke"]) {
    same(allowedFor(visit, action), false, action);
    same(allowedFor(full, action), true, action);
  }
  for (const action of ["chat", "visit_get", "invoice_create", "doc_save", "mail_send", "settings_get"]) {
    same(allowedFor(visit, action), true, action);
  }
});

Deno.test("a client PC's pass only reaches its own PC's records", () => {
  same(ownPc(visit, pcA), true, "own pc");
  same(ownPc(visit, pcB), false, "other pc");
  same(ownPc(visit, null), false, "no pc (all records)");
  same(ownPc(visit, undefined), false, "missing pc");
  // A pass made without a PC id reaches no PC's records at all.
  same(ownPc(loose, null), false, "loose pass, no pc");
  same(ownPc(loose, pcA), false, "loose pass, a pc");
  same(ownPc(full, pcB), true, "own device, any pc");
  same(ownPc(full, null), true, "own device, all records");
});
