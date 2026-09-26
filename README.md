# Housecall

Finds and fixes computer problems at the client's desk. Paste one line into
PowerShell on the PC with the problem:

```powershell
irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex
```

Pick a letter for the area and a number for the problem (`A1` = no internet),
or `?` to describe it in your own words. Housecall checks that part of the PC,
says what it found in plain English or Dutch, and says what to do about it.

- **Read-only until you say yes.** Checking never changes anything. After the
  findings, Housecall offers fixes; each one asks first, is checked again
  afterwards, and can be undone with `U`. Or press `S` for step-by-step
  instructions to do it by hand.
- **Nothing is installed.** Close the window and it's gone.
- **Works offline.** The menu and the checks don't need internet, which matters
  when the internet is the problem.

## Options

`iex` can't pass options, so they need the longer form:

```powershell
$s = 'github.com/Shamilimanuel/Housecall/raw/main/setup.ps1'
& ([scriptblock]::Create((irm $s))) -DryRun     # check only, never fix
& ([scriptblock]::Create((irm $s))) -Lang nl    # Dutch or English (default: the Windows language)
```

## What's built

| | Area | Status |
|---|---|---|
| A | Internet & Wi-Fi | A1 no internet, A2 slow or dropping, A3 one website: working. A4 email: planned |
| B | Sound, screen & video calls | planned |
| C | Printer & devices | C1 printer won't print, C2 mouse, keyboard or USB stick, C3 Bluetooth: working |
| D | Slow or freezing | planned |
| E | Windows & updates | planned |
| F | Safety & scams | F1 fake virus pop-up, F2 someone got into my PC (AnyDesk, TeamViewer, …), F3 full check: working |
| ? | AI chat | planned |

## Development

`setup.ps1` is generated, so don't edit it by hand. Edit `dev.ps1` and the
files in `src\`, then rebuild:

```powershell
powershell -ExecutionPolicy Bypass -File .\dev.ps1 -Lang nl                 # run from source
powershell -ExecutionPolicy Bypass -Command "Invoke-Pester .\tests"         # tests (Pester 3.4, built into Windows)
powershell -ExecutionPolicy Bypass -File .\build.ps1                        # writes setup.ps1
```

Windows PowerShell 5.1, plain ASCII source files. See `TASK.md` for the plan.
