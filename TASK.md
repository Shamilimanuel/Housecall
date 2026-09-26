# Housecall — status and checklist

<!-- progress:start -->
**Progress: 48%** `██████████░░░░░░░░░░` 20 of 42 done · 0 in progress · 19 open · 0 blocked · 3 waiting on a decision

| Section | | Done |
|---|---|---|
| Done | `██████████` | 100% (5/5) |
| Next up | `░░░░░░░░░░` | 0% (0/19) |
| Blocked on Shamil | `░░░░░░░░░░` | 0% (0/3) |
| Recently done | `██████████` | 100% (15/15) |

*Updated by hand for now; a small script can take this over once the list grows. Parked ideas do not count.*
<!-- progress:end -->

Working notes, kept so a new chat can pick up without re-deriving anything.
Last updated: **26 September 2026**, after areas A and F, fixes with undo and guides, the client note, and restarting as admin.

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
worked, and shows the client a short note that disappears when it's closed.

```powershell
irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex
```

**Clickable preview + competitor deep dive:**
<https://claude.ai/artifact/28ctzpjkWt3r6K14d46TzT>

### Picking this up again

**Right now (26 Sep, end of day):** Phase 0 and **area A** are built and
tested (see *Recently done*). A1, A2 and A3 run real read-only checks, give a
finding and say what to do, in English and Dutch. **Area F** (the scam
check) is built too: F1, F2 and F3 are live on GitHub. A4 (email) and areas
B–E still show "not built yet".

**Phase 2 has started:** after every report comes **Wat nu?**: numbered
fixes (pick one, confirm with J/N, and the same check runs again as proof)
and **[S] Stap voor stap**, a guide shown one step at a time. **U** on the
menu undoes the session's fixes. Five fixes exist so far; see *Recently done*.

**Also done:** the **client note** opens by itself on Q (large text,
Afdrukken / Sluiten, nothing saved), and an admin fix now offers to
**restart Housecall as administrator** at the same problem, also offline.

Next, recommended: **areas B–E** with the same pattern (checks → finding →
fixes → steps), starting with **C** (printer: very common with older
clients). Shamil still has to fill in `$script:Contact` in `src/note.ps1`.

**Seen on real Wi-Fi (26 Sep):** on Shamil's laptop A1 showed the Wi-Fi
name and **95%** signal correctly. The drop-out count in A2 has not been
judged on a real laptop yet.

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
| Leaves behind | nothing. The client note opens in its own window and is gone when closed. No install, no task, no service, no files |

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
2. **Client note.** It says what was wrong, what was changed and how to
   reach Shamil. It opens by itself at the end and is gone when closed
   (decided 26 Sep: no file on the desktop). The job record for the invoice
   lives on Shamil's side (visit memory), not in the note.
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
- [ ] **A4** email: which mail program or webmail, then reach its servers (IMAP/SMTP ports). Needs a question first, like A3
- [ ] **B** audio default device, mute, audio service; camera/mic privacy per app; display scale
- [ ] **C** spooler, stuck jobs, default printer; USB devices with errors; Bluetooth radio
- [ ] **D** disk space, memory and CPU hogs, startup programs, recent crashes, uptime
- [ ] **E** Windows Update service, last success, pending reboot

**Phase 2: fixes, proof and the note**
- [ ] More fixes. Done: disable task, close remote tool, proxy off, flush DNS, renew IP. Still to do: reset Winsock, restart adapter; set default audio; restart spooler + clear queue; restart audio service; uninstall a remote-access tool (through its own uninstaller); block a notification site (the browser must be closed first, or it overwrites the change)
- [ ] Restore point before any admin fix, where Windows allows one

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

**Phase 2, part 2: the client note and restarting as admin** *(26 Sep)*
- [x] **Client note** (`src/note.ps1`): opens by itself when Housecall is
      closed with Q, if a problem was opened. Its own window (WinForms), with
      large Segoe UI text in the client's language: *Waar u hulp bij vroeg*,
      *Wat er gevonden is* (the latest finding per problem, so after a fix
      it shows the fixed state), *Wat er is gedaan* (in past tense:
      "AnyDesk afgesloten"), *Vragen?* (only when `$script:Contact` is set),
      and "this note is not saved anywhere". **Afdrukken** prints through
      the normal Windows dialog, page by page (Microsoft Print to PDF makes
      a PDF), **Sluiten** closes it and nothing is left. With no one at the
      console, it prints to the console instead of waiting for a click.
      Checked on screen once with sample data
- [x] **Restart as admin**: an admin fix (renew IP) asks "Housecall nu
      opnieuw starten als beheerder?" and opens an admin window at the same
      problem, in the same language (and dry run). Housecall now keeps its
      own code in `$HcSource` (the build stores it as a here-string), writes
      it to a temp file, and the new window reads it, **deletes it at once**
      and runs it. So it works after `irm | iex` and without internet.
      Saying No to Windows' question cleans up the file and carries on.
      Tested end to end without the Windows prompt itself: the real start-up
      command opened A1 and deleted the file. 7 new tests

**Phase 2, part 1: fixes, proof, undo, step by step** *(26 Sep)*
- [x] **The shape of a fix** (`src/fixes.ps1`): the only code that changes
      the PC. Each fix has a label, a note (*can be undone* / *safe* /
      *program can be started again*), an admin flag, Apply and Undo. A
      report offers fixes (`Add-HcAction`); the list shows under **Wat nu?**;
      nothing runs without a J/Y. `-DryRun` stops at the confirmation. Fixes
      only disable and close, never delete or uninstall
- [x] **Before/after proof**: handlers now return the check as a
      scriptblock, and `Invoke-HcProblem` runs it again after every fix. Live
      on Shamil's PC: a test task went Ready → Disabled, and the second
      report showed it as OK
- [x] **Undo**: every applied fix is logged; **U** on the menu (only shown
      once something changed) undoes them, newest first. Live: Disabled →
      U → Ready. The goodbye now says how many approved changes stay
- [x] **Step-by-step guides** *(Shamil's idea)*: **[S]** under every
      finding shows the manual route one step at a time (Enter = next, 0 =
      stop), with the real Windows 11 menu names, and the Dutch Windows
      labels in Dutch. 34 guides, same number of steps in both languages
      (tested). Also: Reveille and Courier tasks are recognised as known
      tools by name *and* script, so a look-alike name doesn't pass. 16 new tests

**Phase 1, area F: Safety & scams** *(26 Sep)*
- [x] **F1, F2, F3** (`src/checks/security.ps1`), all without admin, 1–2 s
      each on Shamil's PC. *Remote-access tools*: 21 of them (AnyDesk,
      TeamViewer, UltraViewer, RustDesk, ScreenConnect, Quick Assist, …), each
      found as installed (with date), downloaded to Downloads or the Desktop,
      running now, starting with Windows, or used before (the settings folder
      AnyDesk, TeamViewer and RustDesk leave behind even after removal).
      Running = someone may be connected now; within 30 days = fits a scam;
      older = worth asking. *Notification sites* from every Chrome, Edge,
      Brave, Opera and Opera GX profile, with the date allowed. Well-known
      sites (Gmail, WhatsApp Web, …) get an OK line, so only unfamiliar ones
      are flagged. Look-alikes such as `mail.google.com.evil.example` don't
      pass. *Antivirus* from Windows Security, and Defender's update age and
      threats from the last 30 days. *Scheduled tasks* in two levels:
      encoded or downloading commands = problem, a plain hidden script =
      "check this". *Proxy* and *hosts file*. One finding by urgency:
      running remote tool first. Nothing is ever removed here. 32 new tests

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
- [x] ~~Save the note as PDF~~: covered by Afdrukken > Microsoft Print to PDF

### Considered and deliberately not doing

- **Letting the model run any command it writes.** Too risky on someone else's
  PC. Fixes come from a reviewed approved list only.
- **Installing anything permanently.** It runs, helps, and leaves nothing behind.
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
- **F can't read Firefox's notification permissions yet.** They sit in a
  SQLite database, not a JSON file. Chrome, Edge, Brave and Opera are covered.
- **Hidden-script tasks are only "check this"**, because legitimate tools do
  it too: on Shamil's own PC, F2 lists the Reveille and Courier agents. That's
  correct, and it's why they don't count as a problem.
- **The known-sites list is a judgment call** (`$script:KnownNotificationSites`).
  Add a site there when clients keep allowing it on purpose. Never add one
  just because it's popular with scammers' victims.
- **The Windows permission prompt itself hasn't been clicked through yet.**
  Everything around it is tested (the command, the temp file, No). The first
  time a client PC needs *renew IP*, watch it once.
- **After the admin restart, the note only covers the admin window.** What was
  found in the first window isn't carried over (only the problem code is).
- **No source line may start with `'@`**: it would end the `$HcSource`
  here-string. `build.ps1` refuses it.
- **Undo only covers the current session.** Once Housecall is closed, a
  disabled task has to be switched back on in Task Scheduler. The step-by-step
  guide says where.
- **No closures (`.GetNewClosure()`) for checks.** Under the options form
  (`& ([scriptblock]::Create(...)) -Lang nl`) a closure can't see Housecall's
  functions. Pass values through `$script:` variables, as A3 and F do.
- **A Dutch accent in a string** is built from its char code, like
  `'Taak be' + [char]0xEB + 'indigen'`: the button text has to match exactly
  what the client sees.
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
| Fixes | `src/fixes.ps1`: `$script:Fixes` (the only changes Housecall makes), the **Wat nu?** menu, the step-by-step viewer, undo |
| Guides | `steps.<finding id>` in `src/strings.ps1`, steps separated by `\|` |
| Note | `src/note.ps1`: `$script:Contact` (fill in!), the visit record, `Get-HcNoteBlocks` (content), the window and printing |
| Admin restart | `Start-HcElevated` in `src/fixes.ps1`; `$HcSource` in `dev.ps1` and `setup.ps1` |
| Area F | `src/checks/security.ps1`: the remote-tool list, known notification sites, `Test-HcSecurity` (F1–F3 share it; `$script:SecurityChecks` says which parts each runs) |
| Next areas | `src/checks/<area>.ps1`, one file per letter, registering its own handlers |
| Fixes | `fixes/` *(planned)*: the approved list, each with its undo |
| Relay | `relay/` *(planned)*: holds the API key and visit memory |
| Preview | <https://claude.ai/artifact/28ctzpjkWt3r6K14d46TzT> |
| Reference | `../Reveile/setup.ps1` for the one-line install pattern |

**Adding a source file:** add its dot-source line between the `>>> sources`
and `<<< sources` markers in `dev.ps1`, and add it to the test file's
dot-sources at the top. `build.ps1` reads the marker block, so nothing else
needs to change.
