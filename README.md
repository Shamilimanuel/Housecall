# Housecall

Finds and fixes computer problems at the client's desk. Run on the PC with the
problem, in PowerShell:

```powershell
irm housecall.shamilimanuel.nl | iex
```

The long form does the same:
`irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex`.

Checking never changes anything; every fix asks first and can be undone.
Nothing is installed: close the window and it is gone.

This repository only holds the files a PC downloads to run Housecall. It is
public so that the one-liner works; it is **not** open source. See
[LICENSE](LICENSE): all rights reserved.
