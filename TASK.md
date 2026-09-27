# Housecall — status and checklist

<!-- progress:start -->
**Progress: 88%** `██████████████████░░` 67 of 76 done · 0 in progress · 9 open · 0 blocked · 0 waiting on a decision

| Section | | Done |
|---|---|---|
| Done | `██████████` | 100% (5/5) |
| Next up | `█████░░░░░` | 47% (8/17) |
| Blocked on Shamil | `░░░░░░░░░░` | (none) |
| Recently done | `██████████` | 100% (44/44) |
| Found in testing | `██████████` | 100% (10/10) |

*Updated by hand for now; a small script can take this over once the list grows. Parked ideas do not count.*
<!-- progress:end -->

Working notes, kept so a new chat can pick up without re-deriving anything.
Last updated: **26 September 2026, late**: all planned code done and pushed; testing on other PCs is next.

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

**Where we stopped (26 Sep, late):** everything on the code side that was
planned is built, tested (248 tests) and pushed. The relay is on version 8.
The database is clean (test invoices deleted, counter reset), so the first
real invoice is **2026-0001**. Settings: EUR 20 per hour, starting price EUR 15
for the first 30 min, then EUR 5 per quarter begun. GitHub 2FA is on. The
keep-awake job pings the relay every 3 days.

**Waiting on Shamil:**
- **USB stick**: buy one, then run `tools\make-usb.ps1` once.
- **Anthropic credit**: not yet. Until then `?` says there is no credit;
  everything else works without it.

**Next session:** set up **VirtualBox with Windows 10 + a McAfee trial**,
step by step (see *Next up*). ← recommended

**Decided 26 Sep:**
- **Not on the school PC** (McAfee + BitLocker, managed by school IT):
  running scripts with Bypass there breaks school rules and can alert IT.
  Use a virtual PC instead.
- **Father's laptop (Windows 8 or so)** is still worth one try, but expect
  "PowerShell te oud" (Windows 8 has PowerShell 4) or a TLS error from the
  one-liner. Check the version first with `winver`. The USB stick route
  avoids the TLS error.
- **Portable printer: not decided.** Cheap portable printers are receipt
  printers (58/80 mm), not A4, and any printer needs a driver on the
  client's PC. Alternatives: Microsoft Print to PDF and email/WhatsApp the
  invoice, or an "Opslaan als PDF" button that saves straight to the USB
  stick (parked below).

## Where things stand

| | |
|---|---|
| Version | none yet. **0.1.0** = the menu, sections A–F with offline checks, fixes, proof and the client note |
| Entry point | one PowerShell line, `irm … \| iex`, run on the client's PC |
| Interface | **console menu** inside PowerShell. A window with buttons is parked |
| Runs on | Windows 10 / 11, Windows PowerShell 5.1. Do **not** assume PowerShell 7 |
| Language | **Dutch and English**, picked from the Windows display language, with a switch |
| Brain | the menu + rule-based checks (offline). AI chat (`?`) on top: Claude Opus 5 through the Supabase relay, unlocked with a Google Authenticator code |
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

**Phase 5b: more problems (decided 27 Sep, before the window)**
Shamil researched common problems of 65+ Windows users and proposed 15 new
codes and an area G. Compared against the code (no changes made yet):

| Proposed | Already in Housecall? | Read-only diagnosis in PS 5.1 | Advice |
|---|---|---|---|
| E5 activation | **Yes**: E2 checks activation (`Get-HcErrorFacts`) | yes | nothing new; maybe clearer steps |
| D5 too many startup programs | **Yes**: D2 (`Get-HcStartupItems`, `manyStartup`, fix `disableStartup`) | yes | nothing new |
| E4 date/time/time zone | **Partly**: E2 checks the clock against a server (`syncClock`) but compares UTC, so a wrong **time zone** is missed | yes | extend E2 |
| B4 everything huge | **Partly**: B3 sees the magnifier (`closeMagnifier`) and shows scale/text size, but never flags them | yes (scale, text size, resolution; browser zoom no) | extend B3 |
| G2 keyboard wrong characters | **No**, C2 only checks that a keyboard exists | yes (`Get-WinUserLanguageList`, layouts) | extend C2 |
| G3 desktop icons gone, G4 taskbar/search gone, G5 Explorer not responding | No | yes (HideIcons, search box mode, auto-hide, explorer responding) | **merge into one** new code, fix = restart Explorer / show icons |
| G9 temporary profile | No | yes (profile path, User Profile Service events) | detect inside the merged desktop code; fix = steps only (admin + registry) |
| G7/G8 OneDrive | No | partly (running, signed in, folders moved into OneDrive; real sync errors no) | **merge** into one "files missing / not everywhere" code |
| G10 download not found | No, but `Get-HcDownloadFolders` exists (F) | yes (newest files in Downloads) | merge with G6 |
| G6 file opens with wrong program | No | yes to read (UserChoice); **cannot be set by script** (hash-protected) | merge with G10; fix = open Default apps + steps |
| C4 battery | No | yes (Win32_Battery, design vs full capacity) | new; shares code with Pc-overzicht |
| G1 cannot sign in | No | barely: Housecall can't run on a locked-out account | **not a check**; a step-by-step guide |

**Decided:** built before the window, so the window gets them straight away:
- [x] **G1** "Bureaublad, taakbalk of mappen doen raar" (27 Sep): `src/checks/desktop.ps1`. Reads the temporary profile, Explorer running/responding, desktop icons and Recycle Bin, Desktop in OneDrive with OneDrive off, taskbar auto-hide, search box, tablet mode (Win10). Fixes: restart Explorer (always offered, first when it is the cause), show icons / Recycle Bin / search box, keep the taskbar visible, each undoable and each restarting Explorer; temp profile and tablet mode = steps. 9 tests (257 in total). Ran read-only on Shamil's PC: it found his own icons-off, auto-hide and hidden search. **Found in his test:** "show icons" did nothing, because Windows keeps the real setting in the desktop's view flags (`Shell\Bags\Desktop` FFlags, bit 0x1000) and rewrites HideIcons from it when Explorer starts. The fix now changes both and the check reads the flags; verified on his PC (still shown 5 s after the restart). **Also found:** "keep the taskbar visible" did not hold: changing StuckRects3 and restarting Explorer let his Windhawk mod (taskbar-auto-hide-when-maximized, which needs auto-hide on) switch it straight back. Now done live through SHAppBarMessage, the same call as the Settings switch, without an Explorer restart; the check reads the live state. Verified on his PC: off, still off after 8 s, undo puts it back. Search box fix + undo verified by Shamil. Show Recycle Bin: not tested for real (it is not hidden on his PC). **Not pushed yet**; the AI relay does not know G1 yet (add G1-G3 to CODES in one redeploy)
- [x] **G2** "Mijn bestanden zijn weg of staan niet overal" (27 Sep): temporary profile; Desktop/Documents/Pictures (where, exists, item count only); OneDrive installed (its own Run entry or the usual places), signed in (only whether, never the address), running; free disk space (< 2 GB stops syncing); Recycle Bin count. Findings in order: temp profile, **OneDrive removed while the folders still live in its folder**, folder points nowhere, signed out, not running, disk full, files local only, items in the Recycle Bin. Fixes: start OneDrive, open the Recycle Bin. 6 tests (265 in total). Ran on Shamil's PC: found exactly his case (OneDrive removed, folders still in C:\Users\shami\OneDrive); open Recycle Bin verified for real. Start OneDrive not tested for real (not installed on his PC)
- [x] **G3** "Ik kan een bestand niet vinden, of het opent verkeerd" (27 Sep): Windows Search running; Downloads (count, newest: when and file type, **never names**, so nothing personal reaches the AI); where Edge and Chrome save and whether they ask each time (their own Preferences file); which program opens PDF, .jpg, .docx, .mp4 (user choice, else Windows default; app names via SHLoadIndirectString). Fixes: open Downloads / the browser's folder, open Default apps (through explorer.exe: a bare Start-Process of ms-settings did not reliably open Settings on Shamil's PC), start Windows Search (admin). 5 tests (270 in total). On Shamil's PC it found no program for Word files; open folder and Default apps verified for real. Start Search not tested for real (running, needs admin)
- [x] **Relay v9** (27 Sep): the AI knows G1-G3, and visit_save accepts area G. It only accepted A-F, so **a visit that used G would not have been saved**
- [x] **C4** "Laptopaccu laadt niet op of is snel leeg" (27 Sep): laptop or desktop (chassis type), battery found, wear (full vs design capacity from root/wmi: < 50% worn, < 70% ageing), plugged in / charging / charge, **a stop at 55-85% while plugged in counts as the maker's battery care, not a fault**, time left, power plan. Fix: open battery settings; the rest is advice (a battery is hardware). 5 tests (275 in total). On Shamil's desktop it says "no battery (desktop)". **Needs a real laptop to test** (father's laptop or a client). The AI does not know C4 yet: add it to CODES with the next relay deploy (visit_save already accepts it)
- [x] **B3** "Scherm te groot of klein, te donker of verkeerd" (27 Sep): now also the resolution against each screen's own preferred mode (WmiMonitorListedSupportedSourceModes; below 80% of the smallest screen = huge and blurry, so a smaller second screen does not count), scale >= 200% and text size >= 150% as warnings ("ask first: some clients like it big"). Steps only, on purpose: changing the resolution by script can leave a screen black. Read correctly on Shamil's two screens (2560x1440 + 1920x1080). 276 tests
- [x] **C2** keyboard types wrong characters (27 Sep): keyboard layouts (the language list's own, else the session's via GetKeyboardLayoutList; names via the layout's display name), **the "Nederlands" layout that swaps keys on Dutch-sold US-style keyboards**, several layouts (Alt+Shift / Win+Space switching), US-International dead keys, Sticky Keys and Filter Keys (both switched on by accident with Shift), NumLock off. Fixes: remove an extra layout (never a language's last one: that would remove the language and can change the display language; undo restores the whole list), switch NumLock on (+ undo). 5 tests (281 in total). On Shamil's PC: one US layout, NumLock off; the NumLock fix and its undo verified for real. Remove layout not tested for real (only one layout on his PC)
- [x] **E2** time zone and automatic time (27 Sep): the zone is compared with the country (Geo) **by offset and summer time, not by name** (Berlin is fine for NL; unknown countries are not judged), because the existing clock check compares universal time and so missed a wrong zone. Automatic time off (W32Time NoSync) = warning. Fix: set the right zone, undoable. **Found in the real test:** Set-TimeZone needs admin ("a required privilege is not held"), so the fix is Admin; his zone never changed. Also cleaned crash names ("userinit" instead of the full path, in D3 and E2). E2 found userinit crashing 14 times in 3 days on Shamil's PC. 282 tests
**Real test round (27 Sep, then pushed):** relay v10 deployed (knows C4 and the wider B3/C2/E2). Shamil verified show Recycle Bin + undo, set time zone as admin, start Windows Search, invoice to PDF, and a full run of the built `setup.ps1`. **C2 found two gaps:** (1) his language (English (Netherlands)) had *no* keyboards in its list, so Windows loaded layouts itself and Housecall could see them but not remove them: now "open the language and keyboard settings" is offered whenever a layout cannot be removed directly; (2) what Windows added was **United Kingdom**, which swaps @ and " on the US-style keyboards sold in NL: the finding is now `wrongLayout` (Dutch or UK) and its steps name the layout. He switched to US-International; C2 green. **Start language:** Dutch when Windows is Dutch *or* the country is NL (an English Windows in Almere is still a Dutch client). 285 tests. Still untested for real: start OneDrive (not installed), C4 on a real battery.
Not adopted: sign-in (G1 in the research) as a guide, and nothing new for E5/D5 (already in E2/D2).

**Phase 6: Housecall as a window (decided 27 Sep)**
Mockup: <https://claude.ai/artifact/A6UPo4oH3LQjrxN5RcKLQJ>. A WPF window built by
PowerShell itself (like WinUtil), no install. Decisions:
- Window by default; the text menu stays for no desktop, `-Console`, and the tests
- Light (brand colours) and dark, with a switch in the window
- Tabs: **Problemen** (A-F as fold-out groups, one click per problem, plus
  "Alles controleren"), **Veiligheid** (F1-F3), **Bezoek** (clock, done,
  history, note/invoice), **Pc-overzicht** (new, read-only: model and age,
  Windows and support end, disk type/fullness/health, memory, battery, plus
  upgrade advice such as an SSD), **AI-hulp** (the ? chat)
- Every check, fix, undo, note and invoice stays the same code; only the front changes
- [ ] Step 1: the window shell (XAML, tabs, theme switch, clock) + Problemen with results and fixes
- [ ] Step 2: Veiligheid and Bezoek (history, note, invoice window reused)
- [ ] Step 3: Pc-overzicht: new read-only checks + advice rules, with tests
- [ ] Step 4: AI-hulp tab (once there is credit)

**Phase 5: testing before real clients**
- [ ] **VirtualBox + Windows 10 + McAfee trial** ← recommended. Windows 10 is
      what most older clients have. Free: VirtualBox, the Windows 10 download
      (runs unactivated for testing), a McAfee/Norton trial. About 4 GB RAM and
      50 GB disk. Use snapshots. Tests start-up, the antivirus, D/E/F, fixes,
      undo and the invoice to PDF. It cannot test Wi-Fi, sound, printer or
      Bluetooth (virtual hardware)
- [ ] Break the VM on purpose (bad DNS, stopped spooler, AnyDesk installed)
      and check each one is found, fixed and proven
- [ ] **Father's laptop**: one try, mostly to see how an old PC fails
- [ ] **USB stick**: `make-usb.ps1`, then one round with the internet off
- [ ] Use it at one real client visit

## Blocked on Shamil

---

## Recently done

**Lockout per address** *(26 Sep, relay v8)*. 5 wrong codes in 15 minutes
lock only that internet address (kept as a keyed hash, deleted after a
day); 50 in total lock everyone, against spread-out guessing. Before, 10
wrong codes from anyone locked Shamil out too, and the relay URL is public.
Checked live: two wrong codes were stored under one hash.

**Offline visits and the USB stick** *(26 Sep)*
- [x] **Online is measured again** before Q, H and the AI, and after a fix,
      when the PC was offline at the start. Before, an A1 visit that fixed
      the internet still skipped the invoice and the history
- [x] **USB stick:** `tools/make-usb.ps1` rebuilds and writes
      `Housecall\setup.ps1` + `Housecall.cmd` to the stick. Each build has a
      fingerprint (`$HcBuild`, also in `version.txt`); a copy run from a file
      warns when GitHub has a different one. Waiting for Shamil to buy a stick
- [x] **`-Lang` never worked when run as a file** (and so from the stick):
      loading `strings.ps1` reset `$script:Lang`, the same variable as the
      option. The options are now saved before the code loads. Test added
- [x] **End of input no longer loops forever** (stdin redirected): it quits
      like a run without a console

**GitHub two-factor authentication is on** *(26 Sep)*. Every push is live
on clients' PCs at once, so the GitHub account is the key to all of them.
Codes in Google Authenticator, recovery codes kept outside the PC.

**Cleaner invoice and the clock** *(26 Sep)*
- [x] **The invoice is a drawn A4 page** (layout B, chosen from three in a
      preview): "Factuur", number and date, the seller on the right; the
      client next to *Betreft* (the Hulpvraag); one table with "Computerhulp
      aan huis" and its ticks, the costs, the total; how it was paid. The
      window and the printer draw the same steps (`src/invoice-page.ps1`),
      more pages when it is long. Tests and no desktop keep the text version
- [x] **The clock** under the banner: "Bezig sinds 14:05, 35 min", yellow
      with "vraag de klant of u verder mag" once the starting price's
      minutes are used up (30 until the settings are read at Q)
- [x] **Extra time per quarter begun** after the starting price, so the
      amounts stay round (50 min = EUR 25), and the first line names the
      total time. The empty "Wat er gevonden is" heading is gone

**Pricing and the work list** *(26 Sep)*
- [x] **Starting price.** Settings `start_fee` and `start_minutes` (Supabase
      columns, relay, `setup-invoice.ps1`). Now set: EUR 15 for the first
      30 min, then EUR 20 per hour. `Get-HcLabourLines` makes the lines
      ("Starttarief (eerste 30 min)" + "Extra tijd: 45 min, ..."); 0
      minutes = no labour, for a fixed-price job as an extra line. Tests added
- [x] **What was done / not fixed** in the invoice window: pick one of 18
      options or type your own, then *Opgelost* or *Niet opgelost* (Enter =
      Opgelost), remove with a button. Shows on the note and invoice under
      "Wat er is gedaan" and "Nog niet opgelost", and goes into the visit
      history. Window only: the console fallback does not ask for it

**The relay, visit memory and the AI chat** *(26 Sep)*
- [x] **Decisions:** Claude Opus 5; the relay on a new free Supabase project
      `housecall` (Frankfurt, separate from Leeromgeving's database, which
      holds student data); access through a **Google Authenticator code**
      (Shamil's idea): one code per visit, valid until Housecall closes and
      at most 4 hours; visit memory before the AI chat
- [x] **Relay** (`relay/housecall/index.ts`, Edge Function `housecall`,
      deployed; JWT check off because it has its own login). Holds the
      Anthropic key and the Authenticator secret as Supabase secrets.
      `unlock` checks the 6-digit code (RFC 6238, one step either side),
      lets each code work once (`used_codes`), and locks for everyone after
      10 wrong codes in 15 minutes (`failed_unlocks`); it returns a token
      signed with a key derived from the secret. `chat` sends one round to
      Claude with Housecall's system prompt and two tools (`run_check`,
      `give_answer`, both strict), prompt caching, and
      `fallbacks: "default"`. `visit_get` / `visit_save`. `health` says which
      secrets are set. Tables have RLS on, no policies, and no grants for
      anon/authenticated (checked)
- [x] **Visit memory** (`src/relay.ps1`): the PC is known by a SHA-256 of its
      BIOS serial and machine UUID (MachineGuid added when both are
      placeholders), never a name. After unlocking: "Bekende pc (label):
      laatste bezoek ...". **H** on the menu shows the last 5 visits. On
      **Q**, Housecall offers to save the visit (asks the code if needed,
      and an optional name or note for the invoice); not in a dry run
- [x] **AI chat** (`src/ai.ps1`, `?` or a typed sentence): the loop runs in
      PowerShell, one relay round at a time. Claude picks checks, Housecall
      runs them (the same read-only checks as the menu; A3/A4 get the site
      or address the AI passes) and sends back the lines, finding, advice and
      offered fix ids. `give_answer` gives a plain summary, certainty, manual
      steps, the problem, and fix ids, which Housecall filters to the ones
      the check really offered (`Select-HcActions`) and runs through the
      normal Wat nu? with J/N, proof and undo. At most 6 checks and 10
      rounds. Each turn's content goes back byte for byte (thinking
      blocks). Only the problem text and check results leave the PC
- [x] **Setup** (`tools/setup-ai.ps1`, run by Shamil): makes the secret,
      shows a QR code (drawn in the browser on his PC) and the key, checks
      the phone's code, puts the secret on the clipboard for Supabase and
      clears it, opens the Anthropic key and spending-limit pages, and asks
      the relay. `-Check` only asks the relay. The secret never passes
      through Claude's chat. A test against the RFC 6238 values caught a
      real bug here: in PowerShell a `[byte]` shifted left stays a byte
- [x] A3, A4 and F checks can now be built without prompting
      (`New-HcSiteCheck`, `New-HcMailCheck`, `Invoke-HcSecurityCheck`, built
      from text with a validated value, never a closure). 10 new tests, 230
      in total

**A4, the last fixes, restore point, -NoAI** *(26 Sep)*
- [x] **A4 email** (`src/checks/email.ps1`): asks for the address and uses
      only the part after the @. Checks that the domain receives mail, that
      the provider's receiving and sending servers answer (Ziggo, KPN incl.
      xs4all/planet/hetnet/telfort, Outlook.com, Gmail, iCloud, Yahoo), a
      typo of a known provider ("zigo.nl: did you mean ziggo.nl?"), which
      mail program is installed, and the old Windows Mail app that stopped
      working at the end of 2024. Opens webmail where the address is certain
- [x] **The remaining fixes**: reset Windows' network settings (Winsock,
      restart needed), restart the network adapter, uninstall a remote tool
      through its own uninstaller, and open the browser's notification
      settings page. *Decided:* Housecall does not edit the browser's
      settings file to block a site itself, because an open browser
      overwrites it and a damaged file can reset the client's profile
- [x] **Restore point** before the first admin fix of a session
      (`New-HcRestorePoint`): reports when Windows made one in the past 24
      hours or System Protection is off, and carries on either way
- [x] **`-NoAI`** hides the `?` chat; `?` and sentences then count as
      unknown input. Passed on when Housecall restarts as admin. 12 new
      tests, 220 in total, and a new guard: advice sentences may not
      contain `{0}`, because advice is shown without values

**Phase 1, areas D and E: Slow, freezing, Windows & updates** *(26 Sep)*
- [x] **D1–D4** (`src/checks/performance.ps1`). CPU from the
      Win32_PerfFormattedData classes, because Get-Counter's names are
      translated. *D1*: system disk space, HDD or SSD, memory in use and
      total, processor now and its busiest program, days since restart,
      startup programs. *D2*: startup programs, disk, memory. *D3*: programs
      that crashed or froze this week (Windows' own helpers such as dllhost
      are left out), blue screens and unexpected power-offs in 30 days.
      *D4*: Temp, Recycle Bin and Downloads sizes (about 10 s, so only in
      D4). Fixes: stop a program starting with Windows (the same
      StartupApproved switch as Task Manager, undoable; never antivirus,
      sound, touchpad or OneDrive), close a program hogging the PC
      (unsaved work lost, said so), delete temp files older than a day,
      empty the Recycle Bin (cannot be undone, said so)
- [x] **E1–E3** (`src/checks/updates.ps1`). *E1*: Windows 10 (no security
      updates since 14 Oct 2025), the update service switched off, updates
      paused, last real update (Defender's daily definitions left out),
      failed updates with their error code, restart pending, space. *E2*:
      activation, the clock against internet time (a wrong clock gives
      certificate errors), restart pending, crashes in the last 3 days.
      *E3*: restart pending, fast startup, uptime. Fixes: switch the update
      service on, resume updates, reset Windows Update (the download folder
      is renamed, not deleted), set the clock, DISM + SFC repair (15–30
      min), fast startup off. Live on Shamil's PC: all correct. 36 guides,
      11 fixes, 30 tests

**Phase 1, area B: Sound, screen & video calls** *(26 Sep)*
- [x] **B1, B2, B3** (`src/checks/sound.ps1`, `src/checks/audio-interop.ps1`).
      Sound goes through Windows' own audio system (Core Audio) via a small
      piece of C#, compiled on first use in about 0.35 s. *B1*: sound
      service, sound hardware errors, the outputs in use, which one is the
      default, mute and volume, and "sound goes to a screen or digital
      output" when real speakers exist. Fixes: restart the sound service
      (admin), play through another output (speakers before screens,
      undoable), unmute, turn up (undoable), test sound (not listed on the
      note). *B2*: default microphone (muted, too low), cameras, and the
      three Windows privacy switches (whole PC, apps, desktop programs) plus
      the per-app switch for WhatsApp, Teams, Skype, Messenger, Zoom and
      Camera. Fixes: unmute, turn up, allow (undoable, the whole-PC switch
      needs admin). *B3*: brightness on laptops, colour filter (the grey
      screen from Windows + Ctrl + C), high contrast, Magnifier, the main
      screen standing upright, scale and text size. Fixes: brighter
      (undoable), close the Magnifier. Live on Shamil's PC: Realtek speakers
      at 30% with 5 other outputs offered, the Elgato microphone at 95%, "no
      camera" (correct), screen normal. The mute, volume and switch-output
      calls were each tried and put back. 18 guides, 10 fixes, 25 tests

**Contact line on the note** *(26 Sep)*
- [x] **Decided: the email only** (`Shamil: shamilimanuel@outlook.com`),
      because the repo is public. The phone number stays off GitHub on
      purpose, and a test checks that no phone number sneaks into
      `$script:Contact`. A test mail to the address was drafted for Shamil to
      send and confirm

**Phase 1, area C: Printer & devices** *(26 Sep)*
- [x] **C1, C2, C3** (`src/checks/devices.ps1`), no admin needed to check,
      under a second each on Shamil's PC. *C1*: print service; real printers
      apart from Print to PDF / XPS / OneNote / Fax; offline; network
      printers pinged on their IP port; the printer's own state (paper, ink,
      cover, jam); the default printer (Print to PDF as default is the
      classic "my printer does nothing"); documents stuck 10+ minutes.
      Fixes: start the print service, clear the queue (own documents, no
      admin) or clear it and restart the service (admin), make the real
      printer the default (also stops "let Windows manage my default
      printer", undoable), print a test page. *C2*: keyboard and mouse
      found, USB drives with their letter or without one, and every device
      Device Manager flags, with the reason (switched off, no driver, could
      not start, reported a problem). Fixes: switch it back on, restart it
      (both admin). *C3*: the Bluetooth adapter, the Bluetooth service, and
      paired devices with connected / not connected. Live on Shamil's PC:
      "no printer, only Microsoft Print to PDF" (correct), all devices OK,
      the TP-Link adapter with the JBL speaker and Pro Controller paired.
      17 new guides, 9 new fixes, 23 new tests

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

## Found in testing

- [x] **The invoice form as a window** *(Shamil, 26 Sep: select with the mouse,
      fix mistakes before making it)*. `Show-HcInvoiceWindow`: client fields, the
      minutes (suggested, in steps of 15) with the rate next to them, the
      call-out fee as a tick box (only when there is one), extra lines in an
      editable list, payment as buttons, a live total, and "Factuur maken" /
      "Geen factuur (briefje)". The fields go through `ConvertTo-HcInvoiceForm`,
      which names the mistake (no name, no payment, a bad amount on line n,
      nothing to invoice) instead of making the invoice. The console form stays
      for tests and PCs without a desktop. Every colour is set explicitly:
      Shamil's Windows theme has custom system colours, which first gave white
      labels on white and dark fields (checked on screen, fixed, checked again;
      the note window's buttons had the same problem)
- [x] **Card payments by phone (Tap to Pay)**: answered, not built. SumUp
      (1.49% Android / 1.90% iPhone, no subscription) is the easiest later on,
      but providers usually want business details (KvK). Until then the ASN
      betaalverzoek (option 4); card payments already have option 1 (pin)
- [x] **Payment request, and a shorter setup** *(Shamil, 26 Sep)*. Payment
      option [4] is a payment request: Tikkie, or the bank's own (Shamil uses
      the ASN *betaalverzoek*); the invoice says "Betaald via betaalverzoek".
      Internally the value is 'tikkie' (database constraint and relay updated).
      Bank transfer [3] only shows once an IBAN is set. No BTW line while BTW is
      not set. `setup-invoice.ps1` now asks only name, email, phone, rate and
      call-out fee; address, KvK, IBAN and BTW come after one question that is
      No by default. A dash (-) empties a field filled in by mistake
- [x] **A delete option in H** *(Shamil, 26 Sep)*: the history numbers the
      visits; a number, then J, deletes that visit (relay `visit_delete`,
      only for this same PC). Its invoice is kept, and Housecall says so
- [x] **A proper invoice instead of the note** *(Shamil, 26 Sep)*. Decided:
      one document (the invoice includes what was wrong and what was done);
      hourly rate + call-out fee; BTW a setting (not decided yet: the
      invoice then says so); payment asked each time. At Q: the code, then
      a form (client name, address, postcode and city, email, minutes
      suggested from how long Housecall ran rounded up to 15, call-out fee
      J/N, extra lines like "Draadloze muis 19,95", payment 1/2/3, confirm
      the total). The relay numbers it (`issue_invoice`: YYYY-NNNN,
      consecutive, in one transaction), works out subtotal/BTW/total from
      the settings, and stores it with a copy of the seller's details, in
      `invoices`, apart from `visits` (fiscale bewaarplicht, 7 years). The
      window shows seller, number, date, client, the visit, the costs in a
      fixed-width column, and paid-by-card/cash or transfer-before-date with
      the IBAN. Enter at the code, 0 in the form, or no settings: the plain
      note, as before. Business details come from
      `tools/setup-invoice.ps1` into Supabase `settings`, never the public
      script. Checked on screen once. 8 new tests, 239 in total

- [x] **No credit: a clear message.** Done 26 Sep, relay version 7. With an API key but no credit,
      Anthropic answers "credit balance too low" and the relay turns that
      into the vague `ai_request`. Make the relay return `ai_credit` for it
      (match the error type or message), map it in `Get-HcRelayMessage`, add
      the text in both languages ("Het Anthropic-account heeft geen tegoed:
      voeg tegoed toe via console.anthropic.com > Billing"), redeploy the
      function
- [x] **H said "the relay cannot be reached" right after a good unlock** (Shamil,
      26 Sep). The relay was fine: the PC had no visits yet, and in PowerShell an
      empty list returned from a function arrives as $null, which Housecall
      read as a failed request. Get-HcVisits now returns Ok / Visits /
      Error, and a real relay error shows its own message. Test added
- [x] **The QR page opened in Visual Studio Code**, not a browser (the
      `.html` handler on Shamil's PC is VS Code). Fixed: `setup-ai.ps1` opens
      it in the default https browser (Edge on his PC)
- [x] **"The argument to -File does not exist"**: not a bug, PowerShell
      opens in `C:\WINDOWS\system32`. The commands in this file now use the
      full path

## Ideas, parked

- [ ] **Arrow-key navigation** in the console menu, next to typed codes
- [ ] **Hardware health**: SMART disk status, battery wear, temperatures
- [ ] **Remote mode**: a client pastes the line themselves while you're on the phone
- [x] ~~Save the note as PDF~~: covered by Afdrukken > Microsoft Print to PDF
- [ ] **"Opslaan als PDF" button** on the invoice: straight to the USB stick, so no printer is needed at the client's

### Considered and deliberately not doing

- **Testing on the school PC.** Managed by school IT (McAfee, BitLocker);
  scripts with Bypass break the rules there. A virtual PC instead.

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
- **Printers on a WSD port can't be pinged** (no IP address in the port).
  Only printers on a standard TCP/IP port get the "does not answer on the
  network" check; for the rest, Windows' own offline flag is all there is.
- **Bluetooth switched off in Settings isn't detected.** The radio's on/off
  state needs a Windows API PowerShell 5.1 can't easily reach. The C3 guide
  starts with "check that Bluetooth is On" for that reason.
- **The C# in `audio-interop.ps1` must never contain `$` or a backtick**: it
  sits in a double-quoted here-string (a single-quoted one would end
  `$HcSource` early).
- **Switching the sound output uses IPolicyConfig**, which Microsoft never
  documented. It's what Settings uses itself and has been stable since
  Windows 7, but a future Windows could break it. Then the step-by-step
  guide still works.
- **Windows 11 feature versions also go out of support** (for example 24H2
  Home in October 2026). E1 only flags Windows 10, because the Windows 11
  dates move every year and would need updating in the code.
- **The DISM + SFC repair runs inside the Housecall window** and prints its
  own progress. It needs internet for DISM and takes 15–30 minutes.
- **Invoice numbers never go back.** A number is used the moment the relay
  makes the invoice, even if the window is then closed. A wrong invoice is
  corrected with a credit invoice, not by deleting it (not built yet).
- **No business registration yet (26 Sep).** Shamil works on his own, without
  a KvK number or BTW-id for now, and will say when that changes. The invoice
  handles it: empty fields are left off. Don't ask about it again until he
  brings it up.
- **BTW is "not set" until Shamil decides.** Check with the Belastingdienst
  (KOR or not) and set it in `setup-invoice.ps1` before the first real
  invoice.
- **Free Supabase projects pause after a week without use.** Then `?` and
  H say "the relay cannot be reached", and the project needs Restore in the
  Supabase dashboard. Using Housecall at least weekly avoids it.
- **The relay's system prompt and tools are in `index.ts`**: changing how the
  AI behaves means editing it and redeploying the function, not a new
  `setup.ps1`.
- **A lost phone means a new secret:** run `tools\setup-ai.ps1` again; the old
  Authenticator entry stops working at once.
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
| Area A | `src/checks/network.ps1`: facts, `Test-HcInternet` (A1), `Test-HcConnectionQuality` (A2), `Test-HcSite` (A3); `src/checks/email.ps1`: `Test-HcMail` (A4) and the provider list |
| Fixes | `src/fixes.ps1`: `$script:Fixes` (the only changes Housecall makes), the **Wat nu?** menu, the step-by-step viewer, undo |
| Guides | `steps.<finding id>` in `src/strings.ps1`, steps separated by `\|` |
| Note | `src/note.ps1`: `$script:Contact` (fill in!), the visit record, `Get-HcNoteBlocks` (content), the window and printing |
| Admin restart | `Start-HcElevated` in `src/fixes.ps1`; `$HcSource` in `dev.ps1` and `setup.ps1` |
| Relay | `relay/housecall/index.ts` (deployed to Supabase project `housecall`, id `btwbtxjawubtgeizcrir`); redeploy after editing it |
| Relay client, memory | `src/relay.ps1`: `Invoke-HcRelay`, `Unlock-HcRelay`, `Get-HcPcId`, `Show-HcHistory` (H), `Save-HcVisitRecord` (Q) |
| AI chat | `src/ai.ps1`: `Invoke-HcAiConversation` (the loop), `Invoke-HcAi` (the screen); the system prompt and tools live in the relay |
| Setup | `tools/setup-ai.ps1` (`-Check` to only test); `tools/setup-invoice.ps1` (business details, prices, BTW) |
| Invoice | `src/invoice.ps1`: the form (`Read-HcInvoiceForm`), `Invoke-HcInvoice` (at Q), `Get-HcInvoiceBlocks` (the document); the relay's `invoice_create` and the database function `issue_invoice` |
| Area B | `src/checks/sound.ps1`: `Test-HcSound` (B1), `Test-HcCalls` (B2), `Test-HcScreen` (B3); `src/checks/audio-interop.ps1`: the C# for Core Audio |
| Area C | `src/checks/devices.ps1`: `Test-HcPrinter` (C1), `Test-HcInputDevices` (C2), `Test-HcBluetooth` (C3), `Add-HcDeviceProblem` (shared by C2 and C3) |
| Area D | `src/checks/performance.ps1`: `Test-HcSlow` (D1), `Test-HcSlowStart` (D2), `Test-HcCrashes` (D3), `Test-HcDiskSpace` (D4) |
| Area E | `src/checks/updates.ps1`: `Test-HcUpdates` (E1), `Test-HcErrors` (E2), `Test-HcShutdown` (E3) |
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
