// Who may do what with a pass (25 Oct, after an independent review). Kept in
// its own file so the rules can be tested without starting the relay
// (auth_test.ts: deno test relay/housecall/auth_test.ts).
//
// A "full" pass comes from the technician's own devices (a registered device key);
// a "visit" pass is what a client's PC gets, tied to that PC's id.

// What a pass says about itself: s = the kind, pc = the client PC a visit
// pass is for, e = the cancel number it was made under, j = its own id (for
// the per-pass limits), exp = when it ends.
export type Claims = { exp: number; s: "full" | "visit"; pc: string | null; e: number; j: string };

// Only an own device may change the business details (the IBAN on every
// invoice, the address the warning mails go to), delete kept documents, or
// cancel every pass.
export const FULL_ONLY = ["settings_save", "doc_delete", "passes_revoke"];

export function allowedFor(claims: Claims, action: string): boolean {
  return claims.s === "full" || !FULL_ONLY.includes(action);
}

// Whether a pass may touch something that belongs to this PC: an own device
// anything, a visit pass only what has its own PC's id.
export function ownPc(claims: Claims, pc: unknown): boolean {
  if (claims.s === "full") return true;
  return typeof claims.pc === "string" && claims.pc !== "" && typeof pc === "string" && pc === claims.pc;
}
