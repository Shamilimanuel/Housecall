# Housecall — status and checklist

<!-- progress:start -->
**Progress: 32%** `██████░░░░░░░░░░░░░░` 13 of 41 done · 0 in progress · 25 open · 0 blocked · 3 waiting on a decision

| Section | | Done |
|---|---|---|
| Done | `██████████` | 100% (5/5) |
| Next up | `░░░░░░░░░░` | 0% (0/25) |
| Blocked on Shamil | `░░░░░░░░░░` | 0% (0/3) |
| Recently done | `██████████` | 100% (8/8) |

*Updated by hand for now; a small script can take this over once the list grows. Parked ideas do not count.*
<!-- progress:end -->

Working notes, kept so a new chat can pick up without re-deriving anything.
Last updated: **26 September 2026**, after Phase 0 and area A of Phase 1.

**How we work this list:** items are worked top to bottom. Pick one, say the
name, and it gets built. When it is done it moves to *Recently done* and we go
to the next. New ideas go in *Ideas, parked* until they earn a place in *Next
up*. Anything marked **← recommended** is what I would do next if it were
my call.

### What this is

Shamil is starting out on his own, fixing and building computers for people.
Housecall is the **fixing** half. Picture an elderly client saying "my computer
won't connect to the internet." Shamil opens PowerShell on their machine,
pastes **one line**, and picks the problem from a lettered menu (or describes
it to the AI chat). Housecall checks that part of the system read-only, says
what it found, fixes it after a **yes** (or gives the steps), proves the fix
worked, and leaves a short note for the client.

```powershell
irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex
```

**Clickable preview + competitor deep dive:**
<https://claude.ai/artifact/28ctzpjkWt3r6K14d46TzT>

### Picking this up again

**Right now (26 Sep, end of day):** Phase 0 and **area A** are built and
tested (see *Recently done*). A1, A2 and A3 run real read-only checks, give a
finding and say what to do, in English and Dutch. A4 (email) and areas B–F
still show "not built yet". Next: the rest of Phase 1. **F** is the
recommended next area, because it's the standout feature. The open decisions
(AI provider, hosting) still don't block anything in Phase 1.

**Not yet seen on real Wi-Fi.** Shamil's PC uses a cable and has no Wi-Fi
adapter, so the Wi-Fi paths (SSID, signal, drop-outs) are covered only by
tests with fake facts. Run A1 and A2 once on a laptop on Wi-Fi.

Try it: the one-liner above in any PowerShell, or from source:
`powershell -ExecutionPolicy Bypass -File .\dev.ps1` (add `-DryRun` or `-Lang nl`).

**Releasing:** `setup.ps1` is what clients download, and it only changes when
`build.ps1` rebuilds it. Run the tests (they rebuild it), commit `setup.ps1`
with the source change, and push. The one-liner serves the new version
within a few minutes (GitHub's raw cache). Repo:
<https://github.com/Shamilimanuel/Housecall> (public).

### Running the checks

```powershell
powershell -ExecutionPolicy Bypass -Command "Invoke-Pester .\tests"   # 75 tests, Pester 3.4 ships with Windows
powershell -ExecutionPolicy Bypass -File .\build.ps1                  # writes setup.ps1
```

The tests also build the bundle and run it under a real `Get-Content | iex`,
because that path behaves differently from running the file (see *Known
caveats*).

Reveille (`../Reveile/setup.ps1`) is the reference for the one-line
`irm | iex` entry point, the coloured `Write-Step` / `Write-Ok` output, and the
`[scriptblock]::Create((irm $s))` form for passing options.

---

## Where things stand

| | |
|---|---|
| Version | none yet. **0.1.0** = the menu, sections A–F with offline checks, fixes, proof and the client note |
| Entry point | one PowerShell line, `irm … \| iex`, run on the client's PC |
| Interface | **console menu** inside PowerShell. A window with buttons is parked |
| Runs on | Windows 10 / 11, Windows PowerShell 5.1. Do **not** assume PowerShell 7 |
| Language | **Dutch and English**, picked from the Windows display language, with a switch |
| Brain | the menu + rule-based checks (offline). AI chat (`?`) on top, provider not chosen |
| Leaves behind | only the client note on the desktop. No install, no task, no service |

### The menu

Letter = area, number = problem. Typing `A` opens the area, and typing `A1`
jumps straight to the problem. `?` opens the AI chat, which comes after the
letters for anything the menu doesn't cover.

| | Area | Problems |
|---|---|---|
| **A** | Internet & Wi-Fi | A1 no internet at all · A2 Wi-Fi slow or drops · A3 one website or app won't load · A4 email won't send or arrive |
| **B** | Sound, screen & video calls | B1 no sound · B2 microphone or camera · B3 screen too small, dark or wrong |
| **C** | Printer & devices | C1 printer won't print · C2 mouse, keyboard or USB · C3 Bluetooth |
| **D** | Slow or freezing | D1 whole PC slow · D2 slow to start · D3 program freezes or crashes · D4 disk full |
| **E** | Windows & updates | E1 update stuck or failing · E2 error message on screen · E3 won't shut down or restart |
| **F** | Safety & scams | F1 pop-up says I have a virus · F2 someone called and got into my PC · F3 full security check |
| **?** | Describe it yourself | AI chat. Picks from the same checks and the same approved fixes |

### What makes it different

Researched 26 Sep. Full table in the preview. In short:

- **WinUtil** (Chris Titus, `irm christitus.com/win | iex`, ~48k stars):
  the famous one-liner, but it's for tweaks and installs. It doesn't diagnose.
- **FixWin / Tweaking Windows Repair**: long lists of one-click fixes. You
  pick the fix without knowing what's wrong.
- **Windows Get Help / Agent in Settings**: built in, but the Settings agent
  is Copilot+ PCs only and English/French only, and Get Help mostly needs internet.
- **AI RMMs** (Atera, NinjaOne, Breeze): diagnose well, but need a
  permanent agent and cost $109–209 per technician per month. Made for fleets.
- **AI terminals** (Intelligent Terminal, Copilot CLI): developer tools that
  need an install and can run any command.

**Housecall's own ground** (all four chosen for version 1):
1. **Scam check (F).** People over 60 lost more than $1 billion to
   tech-support scams in 2025 (FBI IC3). No repair tool checks for AnyDesk or
   TeamViewer installed by a scammer, or for fake-virus notification sites.
2. **Client note on the desktop.** It says what was wrong, what was changed and
   how to reach Shamil. It doubles as the job note for the invoice.
3. **Before/after proof.** The check that found the problem runs again after the fix.
4. **Visit memory.** Shamil's side only: each client's PC and past fixes.

Plus: it works when the internet *is* the problem, and every change is undoable.

**Things not to change by accident:**

- **Nothing changes on the client's PC without a "yes" first.** Diagnosis is
  read-only. Every fix is shown in plain language and waits for Y/N. This is
  someone else's computer.
- **The AI never writes commands.** It chooses checks and fixes from the
  approved lists. Anything else becomes manual steps for Shamil.
- **No API key in the script.** Anything downloaded by `irm` is public. The key
  sits behind a small relay Shamil controls.
- **Windows PowerShell 5.1 syntax only.** No `??`, no `?.`, no ternary, no `&&`.
- **Personal data stays on the machine.** Send the AI only diagnostic output,
  never files, browser history, passwords or Wi-Fi keys
  (`netsh wlan show profile key=clear` is off limits).
- **Visit memory lives on Shamil's side, never on the client's PC.**
- **Every fix is undoable, or says clearly that it is not.**
- **All user-facing text goes through the string table (NL + EN).** No
  hard-coded sentences in the checks or fixes.

---

## Done

**Design, 26 Sep**
- [x] Competitor deep dive: WinUtil, FixWin, Get Help / Agent in Settings, AI RMMs, AI terminals
- [x] Interface: **console menu** (window with buttons parked)
- [x] Menu structure: **letter = area, number = problem**, `?` = AI chat after the letters
- [x] Version 1 standouts: **scam check, client note, before/after proof, visit memory**
- [x] Language: **Dutch and English**, auto-detected, with a switch

---

## Next up

**Phase 1: checks (offline, read-only)**
- [ ] **F** ← recommended, next: remote-access tools (AnyDesk, TeamViewer, UltraViewer, RustDesk, …) with install date and running state; browser notification permissions; Defender state; unknown scheduled tasks
- [ ] **A4** email: which mail program or webmail, then reach its servers (IMAP/SMTP ports). Needs a question first, like A3
- [ ] **B** audio default device, mute, audio service; camera/mic privacy per app; display scale
- [ ] **C** spooler, stuck jobs, default printer; USB devices with errors; Bluetooth radio
- [ ] **D** disk space, memory and CPU hogs, startup programs, recent crashes, uptime
- [ ] **E** Windows Update service, last success, pending reboot

**Phase 2: fixes, proof and the note**
- [ ] The shape of a fix: description (NL + EN), needs-admin, reversible, apply, undo
- [ ] First fixes: renew IP, flush DNS, reset Winsock, restart adapter; set default audio; restart spooler + clear queue; restart audio service; remove a remote-access tool; block a notification site
- [ ] If admin is needed: explain, then relaunch elevated and continue where it was
- [ ] Restore point before any admin fix, where Windows allows one
- [ ] **Before/after proof**: rerun the check that found the problem
- [ ] **Change log + undo** for the session
- [ ] **Client note**: `Housecall <date>.txt` on the desktop in the client's language: problem, found, changed, Shamil's contact

**Phase 3: the AI chat (`?`)**
- [ ] Relay: small serverless function holding the key, with its own token (see decisions)
- [ ] Send the problem text; the model calls checks as tools and reads the results
- [ ] The model answers in a fixed shape: finding, confidence, fix id from the approved list *or* manual steps
- [ ] Cap the loop (max tool calls), with a clear "couldn't find it" ending
- [ ] With no internet, `?` says so and points to the menu

**Phase 4: visit memory**
- [ ] A PC fingerprint that is not personal (e.g. a hash of the BIOS serial)
- [ ] After each visit, send a short record to Shamil's side (the relay, or a file he keeps). Never stored on the client's PC
- [ ] On start: "Known PC: last visit 3 Mar, C1 printer spooler"

**Phase 5: the one-liner and 0.1.0**
- [ ] Test the one-liner on a clean Windows 11 with Defender on (hosting itself is done, see *Recently done*)
- [ ] Options via the `[scriptblock]::Create((irm $s))` form: `-DryRun`, `-NoAI`, `-Lang nl`
- [ ] Break a test PC or VM on purpose (adapter off, bad DNS, stopped spooler, AnyDesk installed) and check each one is found, fixed and proven
- [ ] Use it at one real client visit

## Blocked on Shamil

- [?] **Which AI, and who pays?** Claude API is the natural choice. It needs a
      key and a monthly spending cap. Only blocks Phase 3.
- [?] **Where does the relay live?** Supabase (already used in Leeromgeving) or
      Cloudflare Workers, both with a free tier. It also stores visit memory in
      Phase 4.
- [?] **Your contact line for the client note.** Name, phone, and the business
      name if there is one yet.

---

## Recently done

**Hosting** *(26 Sep)*
- [x] **Decided: GitHub**, public repo `Shamilimanuel/Housecall`, file
      `setup.ps1` (Shamil's choice of name, matching Reveille). The one-liner
      `irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex` was
      run from GitHub in a fresh PowerShell and worked. The dev entry point was
      renamed `housecall.ps1` → `dev.ps1`, and the build writes `setup.ps1` to
      the root (no more `dist\`). Added `README.md` and `.gitignore`

**Phase 1, area A: Internet & Wi-Fi** *(26 Sep)*
- [x] **The shape of a check** (`src/checks/common.ps1`): *facts* (reads the
      PC, the only part that touches Windows) → *verdict* (pure: facts in,
      report out) → *print*. A report is result lines (`[ OK ]` `[ !! ]`
      `[ !  ]` `[ -- ]`) plus one finding id, shown as **Gevonden:** and **Wat te
      doen:** with word-wrapping. The first broken link is the finding and
      everything after it is skipped. Handlers register in
      `$script:ProblemHandlers`; codes without one keep the "not built yet" screen
- [x] **A1, A2, A3** (`src/checks/network.ps1`). A1 walks adapter → Wi-Fi or
      cable → address (169.254 = none) → router → internet → DNS → test page
      (catches login pages and proxies). 14 findings, each with advice.
      A2 adds 10 router pings (loss) and Wi-Fi drop-outs from the event log.
      A3 asks for the site, then checks the hosts file, name, port 443 and
      the page (403 still counts as alive). Live on Shamil's PC (cable): A1
      in 4 s, all correct; A3 caught a made-up site name. 43 new tests, one
      per scenario
- [x] `housecall.ps1`: HOUSECALL block banner (drawn from `[char]` codes like
      Reveille's), a status line (Windows edition · PowerShell version ·
      admin or not · online or offline), and a refusal on non-Windows or
      PowerShell below 5
- [x] The menu: letters A–F, jump codes (`A1` from anywhere, a bare `1` inside
      an area), `?` for the AI chat, `0` back, `L` language, `Q` quit. A
      sentence of three or more words goes to the AI chat screen. Picking a
      problem shows which checks it *will* run (placeholder until Phase 1)
- [x] String table in `src/strings.ps1`, English and Dutch (formal *u*), picked
      from the Windows language and switched with `L`. A test fails if the
      two drift apart
- [x] `-DryRun` shows a magenta PROEFDRAAI / DRY RUN line; it has nothing to
      skip yet, and the fixes in Phase 2 must check `$script:DryRun`
- [x] `build.ps1` bundles everything into one file (renamed `setup.ps1` later that day),
      refusing non-ASCII or a parse error. 32 Pester tests, including the
      bundle run under a real `iex`

---

## Ideas, parked

- [ ] **Window with big buttons** (WPF, like WinUtil). The checks and fixes stay the same; only the front changes
- [ ] **Arrow-key navigation** in the console menu, next to typed codes
- [ ] **Hardware health**: SMART disk status, battery wear, temperatures
- [ ] **Remote mode**: a client pastes the line themselves while you're on the phone
- [ ] **Printable report** (HTML) next to the `.txt` note

### Considered and deliberately not doing

- **Letting the model run any command it writes.** Too risky on someone else's
  PC. Fixes come from a reviewed approved list only.
- **Installing anything permanently.** It runs, helps, and leaves only the note.
- **Grouped codes (A1 = "Wi-Fi and audio", then choose).** Decided 26 Sep for
  letter = area, number = problem, so `A1` always means one exact problem.

---

## Known caveats

- **`irm | iex` looks alarming** and antivirus can block it. Test on a stock
  Windows 11 with Defender. Also: F teaches clients to distrust strangers
  running things on their PC. Say who you are before you paste the line.
- **The AI can't be reached if the problem *is* the internet.** That's why
  A and the whole menu work offline. A phone hotspot is the backup.
- **Windows is not always in English.** Parse objects (`Get-NetAdapter`,
  `Get-Printer`, `Get-CimInstance`), never the text output of `ipconfig` or
  `netsh`, which is localised (Dutch Windows says different words).
- **AnyDesk and TeamViewer are also used legitimately**, maybe by a grandchild.
  F reports what it finds and asks. It never removes a tool on its own.
- **Under `iex`, the `param()` block turns into plain variables.** So no
  `[ValidateSet]` or other validation attributes on the script's parameters:
  the empty default fails them and the one-liner crashes before the banner.
  (Found and fixed on 26 Sep, and there's a test for it.) Validate inside
  `Start-Housecall` instead.
- **`iex` runs in the client's own session.** The functions and
  `$ErrorActionPreference = 'Stop'` stay behind in that PowerShell window
  until it's closed. Harmless, but close the window when you're done.
- **Wi-Fi drop-outs count sleep and shutdown too** (event 8003 doesn't
  separate them without reading translated text). That's why A2 only calls
  it a problem at 50+ in a week. If that proves too high or too low on real
  laptops, the event's reason code is the next thing to look at.
- **`netsh wlan` is the one place text is parsed.** Only "SSID" and a
  number followed by "%" are matched, which Windows doesn't translate. If the
  signal ever reads wrong on a Dutch laptop, look here first.
- **Keep every source file plain ASCII.** PowerShell 5.1 reads a `.ps1`
  without a byte-order mark as ANSI. `build.ps1` and a test both refuse
  anything else, so Dutch text avoids accents (or uses `[char]` codes).

## Where the important pieces live

| | |
|---|---|
| Entry point | `dev.ps1`: options and the list of source files; runs straight from `src\` |
| What clients get | `setup.ps1`: built, never edited by hand |
| Strings | `src/strings.ps1`: every sentence in `en` and `nl`, plus `T` and the language pick |
| Console output | `src/ui.ps1`: `Write-Step` and friends, `Write-Option`, the banner and status line, `Read-HcLine` |
| PC facts | `src/environment.ps1`: Windows edition, admin, online (TCP to 1.1.1.1 / 8.8.8.8, no DNS needed) |
| Menu | `src/menu.ps1`: area and problem codes, `Resolve-HcChoice` (input to decision), the screens, `Start-Housecall` |
| Build | `build.ps1` → `setup.ps1` |
| Tests | `tests/Housecall.Tests.ps1` |
| Check shape | `src/checks/common.ps1`: reports, findings, `Write-HcReport`, the handler list |
| Area A | `src/checks/network.ps1`: facts, `Test-HcInternet` (A1), `Test-HcConnectionQuality` (A2), `Test-HcSite` (A3) |
| Next areas | `src/checks/<area>.ps1`, one file per letter, registering its own handlers |
| Fixes | `fixes/` *(planned)*: the approved list, each with its undo |
| Relay | `relay/` *(planned)*: holds the API key and visit memory |
| Preview | <https://claude.ai/artifact/28ctzpjkWt3r6K14d46TzT> |
| Reference | `../Reveile/setup.ps1` for the one-line install pattern |

**Adding a source file:** add its dot-source line between the `>>> sources`
and `<<< sources` markers in `dev.ps1`, and add it to the test file's
dot-sources at the top. `build.ps1` reads the marker block, so nothing else
needs to change.
