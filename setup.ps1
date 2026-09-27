<#
    Housecall -- finds and fixes computer problems at a client's desk.

        irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex

    Pick a letter for the area and a number for the problem (A1 = no
    internet), or ? to describe it in your own words. Housecall checks that
    part of the PC read-only, and changes nothing without a yes.

    Options (these need the longer form, because `iex` cannot take arguments):

        $s = 'github.com/Shamilimanuel/Housecall/raw/main/setup.ps1'
        & ([scriptblock]::Create((irm $s))) -DryRun      # check, never fix
        & ([scriptblock]::Create((irm $s))) -Lang nl     # force Dutch or English

    setup.ps1 is built by build.ps1 from dev.ps1 and the files in src\.
    Edit those, never setup.ps1 by hand: the next build overwrites it.
#>

[CmdletBinding()]
param(
    # Diagnose only. Every fix is skipped, so it is safe to try on any PC.
    [switch]$DryRun,
    # Language for everything on screen: nl or en. Defaults to the Windows
    # language. No [ValidateSet] on purpose: under `irm | iex` this block runs
    # as plain variable declarations, and the empty default would fail it.
    [string]$Lang,
    # Open this problem straight away, e.g. A1. Used when Housecall restarts
    # itself as administrator, so it carries on where it was.
    [string]$Start,
    # Leave the AI chat (?) out of the menu, e.g. when the client does not
    # want anything sent over the internet.
    [switch]$NoAI
)

$ErrorActionPreference = 'Stop'

# Which build this is: build.ps1 puts a fingerprint of the code here, and
# writes the same one to version.txt. A copy run from a USB stick compares
# the two and says when it is out of date. 'dev' = straight from src\.
$HcBuild = '58cd973cbb66'

<#
    All of Housecall's code is kept as text in $HcSource and run from there.
    That way it can hand itself to a new administrator window (see
    Start-HcElevated in src\fixes.ps1) even when it came in through
    `irm | iex` and there is no file on disk, and even with no internet.
#>
$HcSource = @'

# ==================================================== src\strings.ps1 ==
<#
    Every sentence Housecall shows, in English and Dutch.

    Nothing user-facing is hard-coded anywhere else: code asks for a key with
    T 'some.key' and gets the current language. Both tables must have exactly
    the same keys -- tests/Housecall.Tests.ps1 fails when they drift.

    Dutch uses the formal "u": the person reading over your shoulder is often
    an older client.

    Keep this file plain ASCII. PowerShell 5.1 reads a .ps1 without a
    byte-order mark as ANSI, so an accented letter here would turn to mojibake.
#>

$script:Strings = @{
    en = @{
        'tagline'          = 'finds and fixes computer problems, always with your okay'
        'promise'          = 'Nothing changes on this PC without a yes.'

        'status.admin'     = 'admin'
        'status.notAdmin'  = 'not admin'
        'status.online'    = 'online'
        'status.offline'   = 'offline'
        'status.dryRun'    = 'DRY RUN: checks only, nothing gets fixed'
        'status.clock'     = 'Working since {0}, {1} min'
        'env.outdated'     = 'This copy of Housecall is out of date. Put the new one on the USB stick: on your own PC, run tools\make-usb.ps1.'
        'status.clockOver' = 'Working since {0}, {1} min: the starting price ({2} min) is used up, ask the client before you go on'

        'menu.question'    = 'What is the problem about?'
        'menu.ai'          = 'Something else: describe it yourself (AI chat)'
        'menu.hintHome'    = 'Type a letter, or jump straight to a problem, e.g. A1'
        'menu.back'        = 'Back'
        'menu.language'    = 'Nederlands'
        'menu.quit'        = 'Quit'
        'menu.prompt'      = 'Choose'
        'menu.unknown'     = '"{0}" is not an option. Try a letter such as A, or a code such as A1.'

        'area.question'    = '{0}  {1}: what is the problem?'
        'area.ai'          = 'None of these: describe it yourself (AI chat)'
        'area.hint'        = 'Type a number, e.g. 1, or the full code'

        'problem.notBuilt' = 'The checks for this problem are not built yet.'
        'problem.willLook' = 'It will look at:'
        'pressEnter'       = 'Press Enter to go back'

        'ai.title'         = 'Describe the problem in your own words'
        'ai.youTyped'      = 'You typed: {0}'
        'ai.notBuilt'      = 'The AI chat is not built yet. Choose a letter from the menu for now.'
        'ai.offline'       = 'This PC is offline, so the AI chat cannot be reached. The menu works without internet.'

        'goodbye'          = 'Housecall is closed. Nothing was left behind on this PC.'
        'goodbyeChanged'   = 'Housecall is closed. The {0} change(s) you approved stay in place; nothing else was left behind.'
        'env.notWindows'   = 'Housecall only runs on Windows.'
        'env.oldPowerShell' = 'Housecall needs PowerShell 5.1 or newer. This PC has {0}.'

        'area.A'  = 'Internet & Wi-Fi'
        'area.B'  = 'Sound, screen & video calls'
        'area.C'  = 'Printer & devices'
        'area.D'  = 'Slow or freezing'
        'area.E'  = 'Windows & updates'
        'area.F'  = 'Safety & scams'
        'area.G'  = 'Files, desktop & accounts'

        'looks.A' = 'network adapter, address from the router, router, DNS, internet, proxy, Wi-Fi signal'
        'looks.B' = 'default sound device, mute and volume, audio service, camera and microphone access, screen scale'
        'looks.C' = 'print service, stuck print jobs, default printer, USB devices with errors, Bluetooth'
        'looks.D' = 'free disk space, programs using memory and CPU, startup programs, recent crashes, time since restart'
        'looks.E' = 'Windows Update service, last successful update, waiting restart'
        'looks.F' = 'remote-access programs such as AnyDesk, sites allowed to send pop-ups, Microsoft Defender, unknown scheduled tasks'
        'looks.G' = 'temporary profile, File Explorer, desktop icons, taskbar and search, OneDrive, downloads, which program opens a file'

        'problem.A1' = 'No internet at all'
        'problem.A2' = 'Wi-Fi slow or keeps dropping'
        'problem.A3' = 'One website or app will not load'
        'problem.A4' = 'Email will not send or arrive'
        'problem.B1' = 'No sound'
        'problem.B2' = 'Microphone or camera (video calls)'
        'problem.B3' = 'Screen too small, too dark or wrong'
        'problem.C1' = 'Printer will not print'
        'problem.C2' = 'Mouse, keyboard or USB stick'
        'problem.C3' = 'Bluetooth'
        'problem.D1' = 'The whole computer is slow'
        'problem.D2' = 'Takes ages to start'
        'problem.D3' = 'A program freezes or crashes'
        'problem.D4' = 'The disk is full'
        'problem.E1' = 'Update stuck or failing'
        'problem.E2' = 'Error message on the screen'
        'problem.E3' = 'Will not shut down or restart'
        'problem.F1' = 'A pop-up says I have a virus'
        'problem.F2' = 'Someone called me and got into my computer'
        'problem.F3' = 'Full security check'
        'problem.G1' = 'The desktop, taskbar or folders act strange'
        'problem.G2' = 'My files are gone or not everywhere'
        'problem.G3' = 'I cannot find a file, or it opens wrong'

        # ---- running a check
        'run.checking' = 'Checking... nothing changes on this PC.'
        'run.found'    = 'Found:'
        'run.advice'   = 'What to do:'

        # ---- A: check lines
        'net.noAdapter'        = 'No network adapter found'
        'net.wifiDisabled'     = 'Wi-Fi adapter "{0}" is switched off'
        'net.adapterOff'       = 'Network adapter "{0}" is switched off'
        'net.wifiNotConnected' = 'Wi-Fi is on, but not connected to any network'
        'net.cableUnplugged'   = 'No network cable plugged in ("{0}")'
        'net.adapterUp'        = 'Network adapter "{0}" is on'
        'net.wifiConnected'    = 'Connected to Wi-Fi "{0}", signal {1}%'
        'net.wifiConnectedNoSignal' = 'Connected to Wi-Fi'
        'net.cableConnected'   = 'Connected by network cable'
        'net.weakSignal'       = 'The Wi-Fi signal is weak: {0}%'
        'net.proxy'            = 'Traffic goes through a proxy: {0}'
        'net.noAddress'        = 'No address from the router ({0})'
        'net.address'          = 'Address from the router: {0}'
        'net.addressStatic'    = 'Fixed address, set by hand: {0}'
        'net.noGateway'        = 'No router (gateway) set for this connection'
        'net.gatewayOk'        = 'Router {0} answers in {1} ms'
        'net.gatewayNoPing'    = 'Router {0} ignores test messages (that is fine)'
        'net.gatewayDown'      = 'Router {0} does not answer'
        'net.internetDown'     = 'Nothing gets past the router to the internet'
        'net.internetOk'       = 'Internet reachable, {0} ms'
        'net.dnsDown'          = 'Website names are not found (DNS server {0})'
        'net.dnsOk'            = 'Website names are found (DNS)'
        'net.webOk'            = 'Test page loads normally'
        'net.webIntercepted'   = 'A login page or another program catches web traffic'
        'net.webFailed'        = 'The test page does not load'
        'net.skipped'          = 'Remaining checks skipped'
        'net.lossOk'           = 'Router test: all {0} messages came back, {1} ms on average'
        'net.loss'             = 'Router test: {0} of {1} messages got lost'
        'net.drops'            = 'Wi-Fi disconnects in the past 7 days: {0} (sleep and shutdown included)'
        'net.internetWorks'    = 'The internet works on this PC'
        'net.none'             = 'none'

        # ---- A: findings, and what to do about each
        'finding.noAdapter'        = 'Windows sees no network adapter at all. The driver may be missing, or the adapter is broken.'
        'advice.noAdapter'         = 'Open Device Manager and look for a network adapter with a warning sign. Install the driver from the maker''s website, using a phone (USB tethering) or another PC.'
        'finding.wifiDisabled'     = 'The Wi-Fi adapter is switched off.'
        'advice.wifiDisabled'      = 'Turn Wi-Fi on: Settings > Network & internet > Wi-Fi, or the Wi-Fi key on the keyboard. Also check that airplane mode is off.'
        'finding.adapterOff'       = 'The network adapter is switched off.'
        'advice.adapterOff'        = 'Turn it on again: Settings > Network & internet > Advanced network settings > Enable.'
        'finding.wifiNotConnected' = 'Wi-Fi is on, but the PC is not connected to a network.'
        'advice.wifiNotConnected'  = 'Check that airplane mode is off. Then click the Wi-Fi icon at the bottom right and choose the home network. The password is often on a sticker on the router.'
        'finding.cableUnplugged'   = 'This PC uses a network cable, but the cable is not connected.'
        'advice.cableUnplugged'    = 'Push the cable in at both ends until it clicks. Try another port on the router, or another cable.'
        'finding.noAddress'        = 'The PC is connected, but the router gave it no address.'
        'advice.noAddress'         = 'Renew the address: ipconfig /release, then ipconfig /renew. If that does not help, restart the router: power off for 30 seconds, then wait 3 minutes.'
        'finding.noGateway'        = 'No router is set for this connection. Usually a fixed address that was set by hand.'
        'advice.noGateway'         = 'Set the connection back to automatic: Settings > Network & internet > (the connection) > IP assignment > Automatic (DHCP).'
        'finding.gatewayDown'      = 'The router does not answer.'
        'advice.gatewayDown'       = 'Check that the router''s lights are on. Restart it: power off for 30 seconds, then wait 3 minutes.'
        'finding.internetDown'     = 'The router works, but the router itself has no internet.'
        'advice.internetDown'      = 'Restart the modem and router. Look for an outage at the provider, on a phone (e.g. allestoringen.nl). Check the internet light on the router.'
        'finding.dnsDown'          = 'The internet works, but website names are not found (DNS).'
        'advice.dnsDown'           = 'Clear the DNS cache: ipconfig /flushdns. If the DNS servers were set by hand, set them back to automatic.'
        'finding.webIntercepted'   = 'Something catches web traffic: a Wi-Fi login page (hotel, guest network) or a program on this PC.'
        'advice.webIntercepted'    = 'Open a browser and look for a login page. If there is none, run F3 to look for unknown programs.'
        'finding.proxy'            = 'A proxy is set. On a home PC that is usually unwanted, and sometimes adware.'
        'advice.proxy'             = 'Turn it off: Settings > Network & internet > Proxy. Then run F3 to look for unknown programs.'
        'finding.weakSignal'       = 'The internet works, but the Wi-Fi signal here is weak.'
        'advice.weakSignal'        = 'Move closer to the router, keep the router out of cupboards, or add a Wi-Fi extender or mesh point.'
        'finding.allGood'          = 'The internet connection works on this PC.'
        'advice.allGood'           = 'If one website or app fails, choose A3. If the internet is slow or drops, choose A2.'
        'finding.unstable'         = 'The connection to the router is unstable: {0}% of the test messages got lost.'
        'advice.unstable'          = 'Restart the router and move closer to it. A network cable is steadier than Wi-Fi.'
        'finding.dropsMany'        = 'Wi-Fi dropped {0} times in the past 7 days, more than sleep and shutdown explain.'
        'advice.dropsMany'         = 'Update the Wi-Fi driver, turn off power saving for the Wi-Fi adapter in Device Manager, and restart the router.'
        'finding.connHealthy'      = 'The connection looks healthy right now. Slowness probably comes from the subscription or the provider.'
        'advice.connHealthy'       = 'Run a speed test (e.g. speedtest.net) and compare it with the subscription. Try again at another time of day.'

        # ---- A3: one website
        'site.ask'       = 'Which website? For example: marktplaats.nl'
        'site.invalid'   = '"{0}" does not look like a web address. Type it like this: whatsapp.com'
        'site.hosts'     = 'The hosts file sends {0} to {1}'
        'site.hostsOk'   = 'No special rule for {0} in the hosts file'
        'site.dnsOk'     = '{0} found: {1}'
        'site.dnsFail'   = '{0} not found'
        'site.tcpOk'     = '{0} answers on the secure port, {1} ms'
        'site.tcpFail'   = '{0} does not answer on the secure port'
        'site.httpOk'    = '{0} sends a page (status {1})'
        'site.httpError' = '{0} answers with an error (status {1})'
        'site.httpNone'  = '{0} sends no page'

        'finding.siteHosts'    = 'The hosts file points this site to another address: an old setting, or malware.'
        'advice.siteHosts'     = 'Remove the line for this site from C:\Windows\System32\drivers\etc\hosts (needs admin), then run F3.'
        'finding.siteNotFound' = 'The name {0} is not found. It may be misspelled, or the site no longer exists.'
        'advice.siteNotFound'  = 'Check the spelling. Try it on a phone: if it fails there too, the problem is the site.'
        'finding.siteBlocked'  = 'The site is found, but it does not answer this PC.'
        'advice.siteBlocked'   = 'Try it on a phone with Wi-Fi off. If it works there, security software or a firewall on this PC may block it.'
        'finding.siteError'    = 'The site answers with an error ({0}). The problem is probably at the site itself.'
        'advice.siteError'     = 'Try again later. Check on a phone whether it fails there too.'
        'finding.siteOk'       = 'The site works from this PC. The problem is probably in the browser or the app.'
        'advice.siteOk'        = 'Clear the browser cache and cookies for this site, try another browser, or turn off browser extensions. For an app: update or reinstall it.'

        # ---- F: check lines
        'sec.noRemote'         = 'No remote-access programs found'
        'sec.installed'        = 'installed {0}'
        'sec.installedUnknown' = 'installed, date unknown'
        'sec.downloaded'       = 'downloaded {0}'
        'sec.running'          = 'RUNNING NOW'
        'sec.autoStart'        = 'starts with Windows'
        'sec.lastUsed'         = 'last used {0}'
        'sec.noTasks'          = 'No suspicious scheduled tasks'
        'sec.task'             = 'Scheduled task "{0}" runs: {1}'
        'sec.avUnknown'        = 'Could not read the virus protection status'
        'sec.avOff'            = 'No virus protection is switched on'
        'sec.avOld'            = '{0} is on, but last updated {1} days ago'
        'sec.avOutdated'       = '{0} is on, but out of date'
        'sec.avOk'             = '{0} is on and up to date'
        'sec.threats'          = 'Threats stopped in the past 30 days: {0}'
        'sec.notifyNone'       = 'No websites may send pop-up notifications'
        'sec.notifyKnown'      = 'Well-known sites may send notifications: {0}'
        'sec.notifySite'       = '{0} may send notifications ({1}, since {2})'
        'sec.notifySiteNoDate' = '{0} may send notifications ({1})'
        'sec.noProxy'          = 'No proxy set'
        'sec.hostsOk'          = 'The hosts file is normal'
        'sec.hostsRedirect'    = 'The hosts file redirects {0} name(s): {1}'

        # ---- F: findings, and what to do about each
        'finding.remoteActive'   = '{0} is running right now. Someone may be connected to this PC at this moment.'
        'advice.remoteActive'    = 'Cut the internet first: Wi-Fi off or pull the cable. Then close the program and ask the client whether they know it. If not: remove it after their yes, call the bank, and change the email and bank passwords from another device.'
        'finding.remoteRecent'   = '{0} was put on this PC recently ({1}). If the client did not do that themselves, it fits a tech-support scam.'
        'advice.remoteRecent'    = 'Ask the client who installed it. If it was a stranger: remove it after their yes, call the bank straight away, and change the email and bank passwords from another device.'
        'finding.remoteOld'      = '{0} has been on this PC for a while. Probably on purpose, but worth asking.'
        'advice.remoteOld'       = 'Ask the client whether they or their family use it. If nobody does, removing it closes a door.'
        'finding.defenderOff'    = 'Virus protection is switched off.'
        'advice.defenderOff'     = 'Turn it on: Windows Security > Virus & threat protection. If another antivirus has expired, remove it so Microsoft Defender takes over.'
        'finding.avOld'          = 'Virus protection is on, but not up to date.'
        'advice.avOld'           = 'Windows Security > Virus & threat protection > Protection updates > Check for updates. If that fails, choose E1.'
        'finding.threatsFound'   = 'Virus protection stopped {0} threat(s) in the past 30 days.'
        'advice.threatsFound'    = 'Open Windows Security > Protection history to see what it was, and run a full scan.'
        'finding.suspiciousTask' = 'The scheduled task "{0}" starts a hidden or downloaded command. That is typical of malware.'
        'advice.suspiciousTask'  = 'After the client''s yes, Housecall can disable it below (it can be switched back on). Then run a full scan in Windows Security.'
        'finding.unknownTask'    = 'The scheduled task "{0}" starts a script in the background. Legitimate programs do this too, but so does malware.'
        'advice.unknownTask'     = 'Ask the client whether they know it. If not, Housecall can disable it below (it can be switched back on).'
        'finding.notifySites'    = '{0} website(s) may show pop-up notifications. That is how fake virus warnings get onto the screen.'
        'advice.notifySites'     = 'Block them in the browser: Settings > Privacy and security > Site settings > Notifications. Never call a phone number from such a pop-up.'
        'finding.hostsRedirect'  = 'The hosts file sends website names to other addresses.'
        'advice.hostsRedirect'   = 'Check C:\Windows\System32\drivers\etc\hosts. Lines the client does not recognise can go (needs admin).'
        'finding.cleanPopup'     = 'Nothing on this PC explains the pop-up. It was most likely a scam web page, not a real virus.'
        'advice.cleanPopup'      = 'Such a page is harmless once it is closed: close the browser (Alt+F4, or Task Manager if it will not close). Never call the number on it. If the client did call: choose F2.'
        'finding.cleanCall'      = 'No remote-access program or other trace of an intruder found.'
        'advice.cleanCall'       = 'If the caller asked for bank details or codes, call the bank anyway. Quick Assist is built into Windows and leaves nothing behind once closed.'
        'finding.cleanAll'       = 'No security problems found.'
        'advice.cleanAll'        = 'Keep Windows and the browser up to date. Real companies never call about a virus.'

        # ---- fixes and undo
        'fix.heading'      = 'What next?'
        'fix.steps'        = 'Step by step: how to do it by hand'
        'fix.stepOf'       = 'Step {0} of {1}:'
        'fix.stepNext'     = 'Enter = next step, 0 = stop'
        'fix.stepLast'     = 'Enter = done'
        'fix.enterBack'    = 'Enter = back to the menu'
        'fix.note.undo'    = '(can be undone)'
        'fix.note.safe'    = '(safe, changes nothing else)'
        'fix.note.restart' = '(the program can simply be started again)'
        'fix.needsAdmin'   = '(needs admin)'
        'fix.confirm'      = '{0}? (Y/N)'
        'fix.dryRun'       = 'DRY RUN: nothing was changed.'
        'fix.done'         = 'Done.'
        'fix.failed'       = 'That did not work: {0}'
        'fix.adminHow'     = 'This needs admin. Close this window, right-click the Start button, choose Terminal (Admin), and start Housecall again.'
        'fix.checkingAgain' = 'Checking again, to see whether it worked...'
        'fix.cancelled'    = 'Nothing was changed.'
        'fix.disableTask'  = 'Disable scheduled task "{0}"'
        'fix.stopRemote'   = 'Close {0} now'
        'fix.proxyOff'     = 'Turn off the proxy'
        'fix.flushDns'     = 'Clear the DNS cache'
        'fix.renewIp'      = 'Ask the router for a new address'
        'fix.disableTask.done' = 'Disabled scheduled task "{0}"'
        'fix.stopRemote.done'  = 'Closed {0}'
        'fix.proxyOff.done'    = 'Turned off the proxy'
        'fix.flushDns.done'    = 'Cleared the DNS cache'
        'fix.renewIp.done'     = 'Got a new address from the router'
        'menu.undo'        = 'Undo fixes'
        'undo.nothing'     = 'There is nothing to undo.'
        'undo.confirm'     = 'Undo {0} change(s) made in this session? (Y/N)'
        'undo.done'        = 'Undone: {0}'
        'undo.failed'      = 'Could not undo: {0}'
        'sec.taskKnown'    = 'Scheduled task "{0}" belongs to {1}, a known tool'
        'sec.taskDisabled' = 'Scheduled task "{0}" is disabled'

        # ---- step-by-step guides: steps.<finding id>, steps separated by |
        'steps.noAdapter'        = 'Right-click the Start button and choose Device Manager. | Open "Network adapters". Look for an entry with a yellow warning sign. If you see nothing, choose View > Show hidden devices. | Note the brand and model of the PC (often on a sticker underneath). | On a phone or another PC, download the network driver from the maker''s support website and copy it over on a USB stick. | Run the driver installer, restart the PC, and choose A1 again.'
        'steps.wifiDisabled'     = 'Click the network icon at the bottom right, next to the clock. | If the Wi-Fi tile is grey, click it so it turns blue. | If the Airplane mode tile is blue, click it to turn it off. | On a laptop, also try the Wi-Fi key on the keyboard (often Fn plus a key with an antenna). | Choose A1 again to check.'
        'steps.adapterOff'       = 'Open Settings (Windows key + I) and go to Network & internet. | Click Advanced network settings. | Find the adapter marked Disabled and click Enable next to it. | Choose A1 again to check.'
        'steps.wifiNotConnected' = 'Click the network icon at the bottom right, next to the clock. | Make sure Airplane mode is off. | Click the arrow next to the Wi-Fi tile to see the networks. | Choose the home network and click Connect. | Type the Wi-Fi password: it is often on a sticker on the router. | Choose A1 again to check.'
        'steps.cableUnplugged'   = 'Follow the cable from the PC to the router. | Push the plug in firmly at both ends until it clicks. The small light next to the port should start blinking. | No light? Try another port on the router. | Still nothing? Try another cable. | Choose A1 again to check.'
        'steps.noAddress'        = 'Choose the fix above to ask the router for a new address (needs admin), or carry on by hand. | Pull the power plug out of the router, and out of the modem if that is a separate box. | Wait 30 seconds, then plug it back in. | Wait about 3 minutes until the lights are steady. | Choose A1 again to check.'
        'steps.noGateway'        = 'Open Settings (Windows key + I) and go to Network & internet. | Click Wi-Fi or Ethernet, then the connection in use (for Wi-Fi: its properties). | Next to IP assignment, click Edit. | Choose Automatic (DHCP) and click Save. | Choose A1 again to check.'
        'steps.gatewayDown'      = 'Look at the router: are its lights on? | Pull the power plug out of the router, and out of the modem if that is a separate box. | Wait 30 seconds, then plug it back in. | Wait about 3 minutes until the lights are steady. | Choose A1 again. If the router stays dark, it may be broken: call the provider.'
        'steps.internetDown'     = 'Look at the router: the internet or WAN light is probably red or off. | Restart the modem and router: power off for 30 seconds, then wait 3 minutes. | On a phone with Wi-Fi off, check for an outage at the provider, for example on allestoringen.nl. | Still no internet? Call the provider: the problem is outside the house. | Choose A1 again to check.'
        'steps.dnsDown'          = 'Choose the fix above to clear the DNS cache, or carry on by hand. | Open Settings (Windows key + I) > Network & internet and click the connection in use. | Next to DNS server assignment, click Edit. | Choose Automatic (DHCP) and click Save. | Choose A1 again to check.'
        'steps.webIntercepted'   = 'Open a web browser and go to any website, for example nu.nl. | If a login or "accept the terms" page appears (hotel, library, guest Wi-Fi), fill it in. | If nothing appears, choose F3 to look for a proxy or unknown programs. | Choose A1 again to check.'
        'steps.proxy'            = 'Choose the fix above to turn the proxy off (it can be undone), or carry on by hand. | Open Settings (Windows key + I) > Network & internet > Proxy. | Under Manual proxy setup, click Edit and switch "Use a proxy server" off. | Under Automatic proxy setup, switch "Use setup script" off. | Choose F3 to look for the program that set it.'
        'steps.weakSignal'       = 'Take the laptop to the router and choose A1 again. Strong there? Then distance is the problem. | Take the router out of cupboards, off the floor, and away from metal. | If the router has two networks (2.4 and 5 GHz), use 2.4 GHz in rooms far away. | In a large house, a Wi-Fi extender or mesh point halfway helps.'
        'steps.unstable'         = 'Restart the router: power off for 30 seconds, then wait 3 minutes. | Sit closer to the router and choose A2 again. | Pause big downloads, streaming and video calls on other devices, and test again. | Still unstable? Use a network cable, or ask the provider for a new router.'
        'steps.dropsMany'        = 'Right-click the Start button and choose Device Manager. | Open Network adapters and double-click the Wi-Fi adapter. | On the Power Management tab, untick "Allow the computer to turn off this device to save power". | On the Driver tab, click Update driver > Search automatically for drivers. | Restart the router and the PC.'
        'steps.connHealthy'      = 'Close other programs and browser tabs. | Open speedtest.net on this PC and click Go. | Compare the download speed with the subscription (on the provider''s bill or website). | Much lower? Test again with a network cable. Still low: call the provider. | Only slow in the evening? Those are busy hours at the provider.'
        'steps.siteHosts'        = 'Open Notepad as administrator: type Notepad in Start, right-click it, choose Run as administrator. | Choose File > Open, set the file type to All files, and paste: C:\Windows\System32\drivers\etc\hosts | Delete the line with the site name and save. | Choose F3 to look for what put it there.'
        'steps.siteNotFound'     = 'Check the spelling of the address with the client. | Search for the name of the site in a search engine instead of typing the address. | Try it on a phone: if it fails there too, the site is down or gone.'
        'steps.siteBlocked'      = 'Try the site on a phone with Wi-Fi off. | Works there? Pause the antivirus or firewall on this PC for a moment and try again. | If that helps, add the site as an exception in that security program, and switch the protection back on.'
        'steps.siteError'        = 'Wait 15 minutes and try again. | Check on a phone whether the site gives an error there too. | Look for an outage of the site, for example on allestoringen.nl.'
        'steps.siteOk'           = 'Open the site in the browser and press Ctrl + F5 to reload it completely. | Still wrong? Try it in another browser, for example Edge. | Works there? In the first browser: Settings > Privacy > Clear browsing data (cookies and cache). | Still wrong? Switch off browser extensions one by one. | For an app: update it, or remove it and install it again.'
        'steps.remoteActive'     = 'Cut the internet: switch Wi-Fi off (network icon at the bottom right) or pull the network cable. | Choose the fix above to close the program. | Ask the client whether they know the program, and who asked them to install it. | If it was a stranger: call the bank straight away, on the number on the bank card. | Change the email and bank passwords from another device, not from this PC. | Choose F3 for a full check.'
        'steps.remoteRecent'     = 'Ask the client who installed the program, and when they last spoke to that person. | If it was a stranger: call the bank straight away, on the number on the bank card. | Remove the program: Settings > Apps, find it in the list, click the three dots next to it and choose Uninstall. | Change the email and bank passwords from another device. | Choose F2 again to check.'
        'steps.remoteOld'        = 'Ask the client whether they or their family use the program. | If nobody does: Settings > Apps, find it in the list, click the three dots next to it and choose Uninstall. | Choose F2 again to check.'
        'steps.defenderOff'      = 'Type Windows Security in Start and open it. | Click Virus & threat protection. | Is another antivirus listed that has expired? Remove it: Settings > Apps, find it in the list, three dots, Uninstall. | Under Virus & threat protection settings, click Manage settings and switch Real-time protection on. | Choose F3 again to check.'
        'steps.avOld'            = 'Type Windows Security in Start and open it. | Click Virus & threat protection. | Under Protection updates, click Check for updates. | Does that fail? Choose E1 to check Windows Update.'
        'steps.threatsFound'     = 'Type Windows Security in Start and open it. | Click Virus & threat protection > Protection history. | See what was found, and whether it says Removed or Quarantined. | Go back, click Scan options, choose Full scan and click Scan now. Let it finish.'
        'steps.suspiciousTask'   = 'Choose the fix above to disable the task (it can be switched back on). | Type Windows Security in Start and open it. | Click Virus & threat protection > Scan options, choose Microsoft Defender Offline scan and click Scan now. The PC restarts for this. | Afterwards, choose F3 again.'
        'steps.unknownTask'      = 'Ask the client whether they know the program the task "{0}" belongs to. | Search for the name "{0}" online to see which program it comes from. | Unknown and not needed? Choose the fix above to disable it (it can be switched back on).'
        'steps.notifySites'      = 'Open the browser named next to the site. | Chrome, Edge or Brave: Settings > Privacy and security > Site settings > Notifications. | Under "Allowed to send notifications", click the three dots next to each unknown site and choose Block or Remove. | Tell the client: a pop-up with a phone number is never real. Close it, and never call.'
        'steps.hostsRedirect'    = 'Open Notepad as administrator: type Notepad in Start, right-click it, choose Run as administrator. | Choose File > Open, set the file type to All files, and paste: C:\Windows\System32\drivers\etc\hosts | Delete the lines the client does not recognise and save. | Choose F3 again to check.'
        'steps.cleanPopup'       = 'Is the pop-up still on screen? Press Ctrl + Shift + Esc to open Task Manager. | Select the browser and click End task. | Open the browser again. If it offers to restore the tabs, say no. | Tell the client: such pages look scary but do nothing once closed. Never call the number.'
        'steps.cleanCall'        = 'Ask what the caller did: did they see the screen, or ask for codes or bank details? | If they asked for bank details or codes: call the bank on the number on the bank card. | Change the email password from another device. | Tell the client: banks and Microsoft never call about a virus.'

        # ---- the client note
        'note.title'          = 'Housecall, {0}'
        'note.asked'          = 'What you asked for help with'
        'note.found'          = 'What was found'
        'note.done'           = 'What was done'
        'note.nothingChanged' = 'Nothing was changed on this PC.'
        'note.notFixed'       = 'Not fixed yet'
        'note.notFixedItem'   = 'Not fixed: {0}'
        'note.contact'        = 'Questions?'
        'note.footer'         = 'This note is not saved anywhere: it disappears when you close it. Print it if you want to keep it.'
        'note.print'          = 'Print'
        'note.close'          = 'Close'
        'note.windowTitle'    = 'Housecall - note'

        # ---- restarting as administrator
        'fix.elevateAsk'      = 'This needs admin. Restart Housecall as administrator now? Windows will ask for permission. (Y/N)'
        'fix.elevated'        = 'Housecall carries on in the new administrator window. This window can be closed.'
        'fix.elevateFailed'   = 'Windows did not start the administrator window ({0}).'

        # ---- C: check lines
        'dev.spoolerStopped'     = 'The print service (Print Spooler) is not running'
        'dev.spoolerOk'          = 'The print service is running'
        'dev.noPrinter'          = 'No printer installed, only: {0}'
        'dev.printerReady'       = '{0} is ready'
        'dev.printerReadyDefault' = '{0} is ready, and is the default printer'
        'dev.printerOffline'     = '{0} is offline'
        'dev.printerUnreachable' = '{0} does not answer on the network ({1})'
        'dev.printerState'       = '{0}: {1}'
        'dev.state.3'            = 'paper is running low'
        'dev.state.4'            = 'out of paper'
        'dev.state.5'            = 'ink or toner is running low'
        'dev.state.6'            = 'out of ink or toner'
        'dev.state.7'            = 'a door or cover is open'
        'dev.state.8'            = 'paper jam'
        'dev.state.10'           = 'needs service'
        'dev.state.11'           = 'the output tray is full'
        'dev.defaultVirtual'     = '{0} is the default printer, so documents go there instead of to paper'
        'dev.noDefault'          = 'No default printer is set'
        'dev.jobsStuck'          = '{0} document(s) stuck in the queue, the oldest since {1}'
        'dev.jobsOk'             = 'The print queue is empty'
        'dev.keyboardOk'         = 'Keyboard found'
        'dev.noKeyboard'         = 'No keyboard found'
        'dev.pointerOk'          = 'Mouse or touchpad found'
        'dev.noPointer'          = 'No mouse or touchpad found'
        'dev.usbDrive'           = 'USB drive "{0}" is connected as {1}'
        'dev.usbNoLetter'        = 'USB drive "{0}" is connected but has no drive letter'
        'dev.noDeviceErrors'     = 'No devices with problems'
        'dev.deviceProblem'      = '{0}: {1}'
        'dev.code.10'            = 'could not start'
        'dev.code.22'            = 'switched off'
        'dev.code.28'            = 'no driver installed'
        'dev.code.43'            = 'reported a problem'
        'dev.codeOther'          = 'error code {0}'
        'dev.btAdapter'          = 'Bluetooth adapter "{0}" works'
        'dev.btNoAdapter'        = 'No Bluetooth adapter found'
        'dev.btServiceOk'        = 'The Bluetooth service is running'
        'dev.btServiceStopped'   = 'The Bluetooth service is not running'
        'dev.btPaired'           = 'Paired: {0}'
        'dev.btConnected'        = '{0} (connected)'
        'dev.btNotConnected'     = '{0} (not connected)'
        'dev.btNonePaired'       = 'No devices paired'

        # ---- C: findings, and what to do about each
        'finding.spoolerStopped'     = 'The print service is not running, so nothing can print.'
        'advice.spoolerStopped'      = 'Housecall can start it below (needs admin).'
        'finding.noPrinter'          = 'No printer is installed on this PC.'
        'advice.noPrinter'           = 'Add the printer: Settings > Bluetooth & devices > Printers & scanners > Add device. The steps below go through it.'
        'finding.printerUnreachable' = 'The printer {0} cannot be reached over the network.'
        'advice.printerUnreachable'  = 'Check that the printer is on and connected to the same Wi-Fi as this PC. Restarting the printer often helps.'
        'finding.printerOffline'     = 'Windows sees the printer {0} as offline.'
        'advice.printerOffline'      = 'Switch the printer off and on again and check the cable or Wi-Fi. Then choose C1 again.'
        'finding.printerAttention'   = 'The printer {0} reports: {1}.'
        'advice.printerAttention'    = 'Sort it out at the printer itself (paper, ink, cover, jam), then choose C1 again.'
        'finding.jobsStuck'          = 'Documents are stuck in the print queue and block everything behind them.'
        'advice.jobsStuck'           = 'Housecall can clear the queue below. The stuck documents then need printing again.'
        'finding.defaultVirtual'     = 'Documents go to {0} instead of to the printer.'
        'advice.defaultVirtual'      = 'Housecall can make the real printer the default below (it can be undone).'
        'finding.noDefault'          = 'No default printer is set, so programs do not know where to print.'
        'advice.noDefault'           = 'Housecall can set the printer as the default below (it can be undone).'
        'finding.printerReady'       = 'The printer looks ready.'
        'advice.printerReady'        = 'Housecall can print a test page below. If it comes out, the problem is in the program: check which printer it prints to.'
        'finding.deviceDisabled'     = '{0} is switched off in Windows.'
        'advice.deviceDisabled'      = 'Housecall can switch it back on below (needs admin, can be undone).'
        'finding.deviceNoDriver'     = 'Windows has no driver for {0}.'
        'advice.deviceNoDriver'      = 'Let Windows look for the driver, or get it from the maker''s website. The steps below go through it.'
        'finding.deviceError'        = '{0} has a problem: {1}.'
        'advice.deviceError'         = 'Unplug it, wait 10 seconds, and plug it into another USB port. Or Housecall can restart it below (needs admin).'
        'finding.usbNoLetter'        = '{0} is connected but has no drive letter, so it does not show in File Explorer.'
        'advice.usbNoLetter'         = 'Give it a letter in Disk Management. The steps below go through it.'
        'finding.noPointer'          = 'Windows finds no mouse or touchpad.'
        'advice.noPointer'           = 'Plug the mouse into another USB port. For a wireless mouse: new battery, and check the small receiver.'
        'finding.devicesOk'          = 'All connected devices work without errors.'
        'advice.devicesOk'           = 'Try another USB port. If a device still does nothing, try it on another PC to see whether the device itself is broken.'
        'finding.btNoAdapter'        = 'This PC has no working Bluetooth adapter.'
        'advice.btNoAdapter'         = 'Many desktop PCs have no Bluetooth. A small USB Bluetooth adapter solves that.'
        'finding.btServiceStopped'   = 'The Bluetooth service is not running.'
        'advice.btServiceStopped'    = 'Housecall can start it below (needs admin).'
        'finding.btOk'               = 'Bluetooth works on this PC.'
        'advice.btOk'                = 'If a device will not connect: remove it in Settings and pair it again. The steps below go through it.'

        # ---- C: fixes
        'fix.note.reprint'          = '(the stuck documents need printing again)'
        'fix.startSpooler'          = 'Start the print service'
        'fix.startSpooler.done'     = 'Started the print service'
        'fix.restartSpooler'        = 'Clear the print queue and restart the print service'
        'fix.restartSpooler.done'   = 'Cleared the print queue and restarted the print service'
        'fix.clearJobs'             = 'Remove the stuck documents from the queue'
        'fix.clearJobs.done'        = 'Removed the stuck documents from the queue'
        'fix.setDefault'            = 'Make {0} the default printer'
        'fix.setDefault.done'       = 'Made {0} the default printer'
        'fix.printTestPage'         = 'Print a test page on {0}'
        'fix.printTestPage.done'    = 'Printed a test page on {0}'
        'fix.enableDevice'          = 'Switch {0} back on'
        'fix.enableDevice.done'     = 'Switched {0} back on'
        'fix.restartDevice'         = 'Restart {0}'
        'fix.restartDevice.done'    = 'Restarted {0}'
        'fix.startBtService'        = 'Start the Bluetooth service'
        'fix.startBtService.done'   = 'Started the Bluetooth service'

        # ---- C: step-by-step guides
        'steps.spoolerStopped'     = 'Choose the fix above to start it (needs admin), or do it by hand. | Type Services in Start and open it. | Find Print Spooler and double-click it. | Set Startup type to Automatic, click Start, then OK. | Choose C1 again to check.'
        'steps.noPrinter'          = 'Switch the printer on and connect it: a USB cable, or the same Wi-Fi as this PC. | Open Settings (Windows key + I) > Bluetooth & devices > Printers & scanners. | Click Add device and wait until the printer appears, then click Add device next to it. | Not in the list? Click "Add manually", or install the software from the printer maker''s website. | Choose C1 again to check.'
        'steps.printerUnreachable' = 'Check that the printer is on and shows no error on its screen. | Check that it is on the same Wi-Fi as this PC (the printer''s menu, often under Network or Wi-Fi). | Switch the printer off, wait 10 seconds, and switch it on. Wait until it is ready. | Still no answer? Restart the router too. | Choose C1 again to check.'
        'steps.printerOffline'     = 'Switch the printer off and on again, and check the USB cable or Wi-Fi. | Open Settings > Bluetooth & devices > Printers & scanners and click the printer. | Click Open print queue. In the Printer menu, make sure "Use Printer Offline" is not ticked. | Choose C1 again to check.'
        'steps.printerAttention'   = 'Look at the printer''s screen or lights: they say what is wrong. | Add paper, replace the ink or toner, close every cover, or pull jammed paper out gently. | Switch the printer off and on again. | Choose C1 again to check.'
        'steps.jobsStuck'          = 'Choose a fix above to clear the queue, or do it by hand. | Open Settings > Bluetooth & devices > Printers & scanners, click the printer, then Open print queue. | In the Printer menu, click Cancel All Documents. | They will not go away? Restart the PC. | Print the document again.'
        'steps.defaultVirtual'     = 'Choose the fix above to make the real printer the default (it can be undone), or do it by hand. | Open Settings > Bluetooth & devices > Printers & scanners. | Switch off "Let Windows manage my default printer". | Click the real printer, then Set as default. | Print again.'
        'steps.noDefault'          = 'Choose the fix above to set a default printer (it can be undone), or do it by hand. | Open Settings > Bluetooth & devices > Printers & scanners. | Switch off "Let Windows manage my default printer". | Click the printer, then Set as default. | Print again.'
        'steps.printerReady'       = 'Choose the fix above to print a test page. | It comes out? Then the printer works: in the program, check which printer is chosen in the Print window. | Nothing comes out? Switch the printer off and on, and choose C1 again. | Still nothing? Remove the printer in Settings > Printers & scanners and add it again.'
        'steps.deviceDisabled'     = 'Choose the fix above to switch it back on (needs admin), or do it by hand. | Right-click the Start button and choose Device Manager. | Find the device (it has a small arrow pointing down), right-click it and choose Enable device. | Choose the same problem again to check.'
        'steps.deviceNoDriver'     = 'Right-click the Start button and choose Device Manager. | Right-click the device with the yellow warning sign and choose Update driver > Search automatically for drivers. | Not found? Download the driver from the maker''s website. | Restart the PC and choose the same problem again.'
        'steps.deviceError'        = 'Unplug the device, wait 10 seconds, and plug it into another USB port (on a desktop: one at the back). | Or choose the fix above to restart it (needs admin). | Still wrong? Right-click Start > Device Manager, right-click the device, choose Uninstall device, and restart the PC: Windows installs it again. | Choose the same problem again to check.'
        'steps.usbNoLetter'        = 'Right-click the Start button and choose Disk Management. | Find the USB drive in the lower half (it says Removable). | Right-click its partition, choose Change Drive Letter and Paths > Add, pick a letter and click OK. | Open File Explorer: the drive now shows. | Does it say Unallocated or RAW? Then the stick may be empty or damaged: do not format it before checking whether the files are needed.'
        'steps.noPointer'          = 'Plug the mouse into another USB port. | Wireless mouse: put in a new battery, and check that the small receiver is plugged in. | Laptop: press the touchpad key (often Fn plus a key with a touchpad picture). | Meanwhile, use the keyboard: Tab and the arrow keys move around, Enter clicks.'
        'steps.devicesOk'          = 'Unplug the device and plug it into another USB port. | Restart the PC with the device plugged in. | Try the device on another PC: if it fails there too, the device itself is broken. | Choose C2 again.'
        'steps.btNoAdapter'        = 'Check whether this PC has Bluetooth at all: many desktop PCs do not. | Laptop: make sure airplane mode is off (network icon at the bottom right). | No Bluetooth? A small USB Bluetooth adapter solves it: plug it in and choose C3 again.'
        'steps.btServiceStopped'   = 'Choose the fix above to start it (needs admin), or do it by hand. | Type Services in Start and open it. | Find Bluetooth Support Service and double-click it. | Set Startup type to Manual, click Start, then OK. | Choose C3 again to check.'
        'steps.btOk'               = 'Open Settings (Windows key + I) > Bluetooth & devices and check that Bluetooth is On. | Switch the device (headphones, speaker, mouse) off and on, and put it in pairing mode: often, hold its Bluetooth button until a light blinks. | In Settings, click the three dots next to the device and choose Remove device. | Click Add device > Bluetooth and choose the device from the list. | Choose C3 again to check.'

        # ---- B: check lines
        'snd.serviceStopped' = 'The sound service (Windows Audio) is not running'
        'snd.serviceOk'      = 'The sound service is running'
        'snd.noOutput'       = 'No speaker or headphones found'
        'snd.default'        = 'Sound goes to {0}, volume {1}%'
        'snd.muted'          = '{0} is muted'
        'snd.volumeLow'      = 'The volume of {0} is at {1}%'
        'snd.defaultScreen'  = '{0} is a screen or digital output: without speakers there, nothing is heard'
        'snd.others'         = 'Other outputs: {0}'
        'call.mic'           = 'Microphone: {0}, level {1}%'
        'call.noMic'         = 'No microphone found'
        'call.micMuted'      = 'Microphone {0} is muted'
        'call.micLow'        = 'Microphone {0} is set very low ({1}%)'
        'call.camera'        = 'Camera: {0}'
        'call.noCamera'      = 'No camera found'
        'call.privacyOk'     = 'Apps may use the {0}'
        'call.blocked'       = '{0} may not use the {1}'
        'priv.microphone'    = 'microphone'
        'priv.webcam'        = 'camera'
        'priv.all'           = 'No app on this PC'
        'priv.apps'          = 'Apps'
        'priv.desktop'       = 'Desktop programs (Zoom, Teams, Skype)'
        'scr.brightness'     = 'Brightness: {0}%'
        'scr.tooDark'        = 'The screen brightness is very low ({0}%)'
        'scr.colorFilter'    = 'A colour filter is on (for example black and white)'
        'scr.highContrast'   = 'High contrast is on'
        'scr.magnifier'      = 'The Magnifier is open'
        'scr.normal'         = 'No colour filter, high contrast or Magnifier on'
        'scr.rotated'        = 'The main screen stands upright (portrait)'
        'scr.scale'          = 'Scale {0}%, text size {1}%'

        # ---- B: findings, and what to do about each
        'finding.audioServiceStopped' = 'The sound service is not running, so no sound can play.'
        'advice.audioServiceStopped'  = 'Housecall can restart it below (needs admin).'
        'finding.noOutput'            = 'Windows finds no speaker or headphones.'
        'advice.noOutput'             = 'Check that the speakers are plugged in and switched on. A screen used for sound must be on.'
        'finding.muted'               = 'The sound is muted on {0}.'
        'advice.muted'                = 'Housecall can turn it back on below (it can be undone).'
        'finding.volumeLow'           = 'The volume of {0} is almost off ({1}%).'
        'advice.volumeLow'            = 'Housecall can turn it up below (it can be undone).'
        'finding.defaultScreen'       = 'Sound goes to {0}, which is probably not where the client listens.'
        'advice.defaultScreen'        = 'Choose the speakers or headphones below. It can be undone.'
        'finding.soundOk'             = 'Windows sends sound to {0}, and it is on.'
        'advice.soundOk'              = 'Play a test sound below. Hear nothing? Check the speaker''s power and volume knob, or choose another output below.'
        'finding.privacyBlocked'      = '{0} may not use the {1}. That is why the other person cannot hear or see the client.'
        'advice.privacyBlocked'       = 'Housecall can allow it below (it can be undone).'
        'finding.micMuted'            = 'The microphone {0} is muted.'
        'advice.micMuted'             = 'Housecall can unmute it below (it can be undone).'
        'finding.noMic'               = 'Windows finds no microphone.'
        'advice.noMic'                = 'Plug in the headset or webcam that has the microphone, or check its cable.'
        'finding.micLow'              = 'The microphone {0} is set very low.'
        'advice.micLow'               = 'Housecall can turn it up below (it can be undone).'
        'finding.noCamera'            = 'Windows finds no camera.'
        'advice.noCamera'             = 'Plug in the webcam. On a laptop, check for a small privacy slider over the lens, or a camera key.'
        'finding.callsOk'             = 'The microphone and camera work, and apps may use them.'
        'advice.callsOk'              = 'In the call app itself, check which microphone and camera are chosen (often under Settings > Audio & video).'
        'finding.tooDark'             = 'The screen is set very dark ({0}%).'
        'advice.tooDark'              = 'Housecall can make it brighter below (it can be undone).'
        'finding.colorFilter'         = 'A colour filter is on, which makes the screen black and white or oddly coloured. It is often switched on by accident with Windows key + Ctrl + C.'
        'advice.colorFilter'          = 'Press Windows key + Ctrl + C, or switch it off in Settings. The steps below go through it.'
        'finding.highContrast'        = 'High contrast is on: a black background and bright colours. It is often switched on by accident.'
        'advice.highContrast'         = 'Press Left Alt + Left Shift + Print Screen, or switch it off in Settings. The steps below go through it.'
        'finding.magnifier'           = 'The Magnifier is open: it makes everything big and follows the mouse.'
        'advice.magnifier'            = 'Housecall can close it below. Windows key + Esc also closes it.'
        'finding.rotated'             = 'The main screen is turned on its side.'
        'advice.rotated'              = 'Turn it back with the steps below. If the screen really stands upright, this is fine.'
        'finding.screenOk'            = 'Nothing is switched on that changes how the screen looks.'
        'advice.screenOk'             = 'To make everything bigger for the client, see the steps below.'

        # ---- B: fixes
        'fix.restartAudio'            = 'Restart the sound service'
        'fix.restartAudio.done'       = 'Restarted the sound service'
        'fix.setDefaultAudio'         = 'Play sound through {0}'
        'fix.setDefaultAudio.done'    = 'Sound now plays through {0}'
        'fix.unmute'                  = 'Unmute {0}'
        'fix.unmute.done'             = 'Unmuted {0}'
        'fix.setVolume'               = 'Turn up the volume of {0}'
        'fix.setVolume.done'          = 'Turned up the volume of {0}'
        'fix.testSound'               = 'Play a test sound'
        'fix.testSound.done'          = 'Played a test sound'
        'fix.allowAccess'             = 'Allow: {0}'
        'fix.allowAccess.done'        = 'Allowed: {0}'
        'fix.allowAccessMachine'      = 'Allow for the whole PC: {0}'
        'fix.allowAccessMachine.done' = 'Allowed for the whole PC: {0}'
        'fix.setBrightness'           = 'Make the screen brighter (80%)'
        'fix.setBrightness.done'      = 'Made the screen brighter'
        'fix.closeMagnifier'          = 'Close the Magnifier'
        'fix.closeMagnifier.done'     = 'Closed the Magnifier'

        # ---- B: step-by-step guides
        'steps.audioServiceStopped' = 'Choose the fix above to restart it (needs admin), or do it by hand. | Type Services in Start and open it. | Find Windows Audio, right-click it and choose Restart (or Start). | Choose B1 again to check.'
        'steps.noOutput'            = 'Check that the speakers or headphones are plugged in (the green socket on a desktop) and switched on. | Using the sound of a screen or TV? Switch it on, and check its own volume. | Bluetooth headphones: choose C3 to check the connection. | Restart the PC and choose B1 again.'
        'steps.muted'               = 'Choose the fix above to unmute it, or do it by hand. | Click the speaker icon at the bottom right, next to the clock. | Click the speaker symbol next to the volume slider, so it no longer shows a cross. | Play something to check.'
        'steps.volumeLow'           = 'Choose the fix above to turn it up, or do it by hand. | Click the speaker icon at the bottom right, next to the clock. | Drag the volume slider to about halfway. | Also check the volume knob on the speakers themselves.'
        'steps.defaultScreen'       = 'Choose the right output above (it can be undone), or do it by hand. | Click the speaker icon at the bottom right, then the arrow next to the volume slider. | Choose the speakers or headphones from the list. | Play something to check.'
        'steps.soundOk'             = 'Choose "Play a test sound" above and listen. | Hear nothing? Check the power, the cable and the volume knob of the speakers. | Try another output above, for example the headphones. | Sound only missing in one program (a browser tab, a video)? Check the volume inside that program, and right-click the speaker icon > Volume mixer.'
        'steps.privacyBlocked'      = 'Choose the fix above to allow it (it can be undone), or do it by hand. | Open Settings (Windows key + I) > Privacy & security > Microphone (or Camera). | Switch on "Microphone access", "Let apps access your microphone" and "Let desktop apps access your microphone" (for the camera: the same three). | In the list below it, switch on the call app (WhatsApp, Teams, ...). | Close the call app, open it again, and try a call.'
        'steps.micMuted'            = 'Choose the fix above to unmute it, or do it by hand. | Open Settings (Windows key + I) > System > Sound. | Under Input, click the microphone and make sure it is not muted. Set the volume to about 80. | Also check for a mute button on the headset or its cable.'
        'steps.noMic'               = 'Plug in the headset or webcam with the microphone. Headset with two plugs: the pink one is the microphone. | Open Settings > System > Sound and look under Input. | Still nothing? Choose C2 to look for devices with problems.'
        'steps.micLow'              = 'Choose the fix above to turn it up, or do it by hand. | Open Settings (Windows key + I) > System > Sound. | Under Input, click the microphone and set its volume to about 80. | Test it: the bar under "Test your microphone" moves when the client speaks.'
        'steps.noCamera'            = 'Plug in the webcam, if the PC uses one. | Laptop: look for a small slider over the camera lens, or a key with a camera picture. | Choose C2 to look for devices with problems. | Restart the PC and choose B2 again.'
        'steps.callsOk'             = 'Open the call app (WhatsApp, Teams, Zoom). | In its settings, often under Audio & video, choose the right microphone, speaker and camera. | Make a test call, for example to a family member. | Still silent in calls only? Close other programs that may be using the camera or microphone.'
        'steps.tooDark'             = 'Choose the fix above to make it brighter (it can be undone), or do it by hand. | Click the network or speaker icon at the bottom right: the brightness slider is at the bottom of that panel. | Drag it to the right. | Laptop: the keys with a sun symbol (often with Fn) also change brightness.'
        'steps.colorFilter'         = 'Press the Windows key + Ctrl + C together. | Still grey? Open Settings (Windows key + I) > Accessibility > Color filters. | Switch Color filters off. | Also switch off the "Keyboard shortcut for color filters", so it cannot happen by accident again.'
        'steps.highContrast'        = 'Press Left Alt + Left Shift + Print Screen together, and confirm with Yes if asked. | Or open Settings (Windows key + I) > Accessibility > Contrast themes. | Choose None and click Apply.'
        'steps.magnifier'           = 'Choose the fix above to close it, or press the Windows key + Esc. | So it does not come back: Settings > Accessibility > Magnifier, and switch off the keyboard shortcut and "start before sign-in". '
        'steps.rotated'             = 'Press Ctrl + Alt + the Up arrow key (works on some PCs). | Or open Settings (Windows key + I) > System > Display. | Click the right screen at the top, and under Display orientation choose Landscape. | Click Keep changes.'
        'steps.screenOk'            = 'Make the text bigger: Settings (Windows key + I) > Accessibility > Text size. Drag the slider and click Apply. | Make everything bigger: Settings > System > Display > Scale, choose 125% or 150%. | Check the resolution under Display resolution: the one marked (Recommended) is the sharpest. | Hard to see the mouse pointer? Settings > Accessibility > Mouse pointer and touch: make it bigger or a brighter colour.'

        # ---- D: check lines
        'perf.diskOk'      = 'Disk {0} {1} GB free ({2}%)'
        'perf.diskLow'     = 'Disk {0} is getting full: {1} GB free ({2}%)'
        'perf.diskFull'    = 'Disk {0} is full: {1} GB free ({2}%)'
        'perf.hdd'         = 'Windows is on an old-style hard disk (HDD) on {0}, which is slow'
        'perf.memory'      = 'Memory in use: {0}% of {1} GB'
        'perf.memoryFull'  = 'Memory is almost full: {0}% of {1} GB in use'
        'perf.lowRam'      = 'Only {0} GB of memory: little for Windows 11'
        'perf.cpu'         = 'Processor: {0}% busy'
        'perf.cpuBusy'     = 'The processor is {0}% busy, mostly with {1}'
        'perf.uptime'      = 'Last restart: {0} day(s) ago'
        'perf.uptimeLong'  = 'Not restarted for {0} days'
        'perf.startup'     = '{0} programs start with Windows'
        'perf.startupMany' = '{0} programs start with Windows: {1}'
        'perf.crashApp'    = '{0} crashed or froze {1} time(s) this week'
        'perf.noCrashes'   = 'No program crashed or froze this week'
        'perf.blueScreens' = 'Blue screens in the past 30 days: {0}'
        'perf.shutdowns'   = 'Switched off unexpectedly in the past 30 days: {0} time(s)'
        'perf.sizes'       = 'Temporary files {0} GB, Recycle Bin {1} GB, Downloads {2} GB'

        # ---- D: findings, and what to do about each
        'finding.diskFull'    = 'Disk {0} is full ({1} GB free). A full disk makes Windows slow and blocks updates.'
        'advice.diskFull'     = 'Choose D4: Housecall can free up space there.'
        'finding.diskLow'     = 'Disk {0} is getting full ({1} GB free).'
        'advice.diskLow'      = 'Choose D4: Housecall can free up space there.'
        'finding.spaceFull'   = 'Disk {0} is full ({1} GB free).'
        'advice.spaceFull'    = 'Housecall can delete temporary files and empty the Recycle Bin below. The steps show where the big files are.'
        'finding.spaceLow'    = 'Disk {0} is getting full ({1} GB free).'
        'advice.spaceLow'     = 'Housecall can delete temporary files and empty the Recycle Bin below. The steps show where the big files are.'
        'finding.memoryFull'  = 'The memory is almost full ({0}%). Windows then has to use the much slower disk.'
        'advice.memoryFull'   = 'Close programs and browser tabs that are not needed. If one program uses most of it, Housecall can close it below.'
        'finding.cpuBusy'     = 'The processor is very busy ({0}%), mostly with {1}.'
        'advice.cpuBusy'      = 'If Housecall offers it below, it can close that program (unsaved work in it is lost). Something unknown? Choose F3.'
        'finding.longUptime'  = 'The PC has not restarted for {0} days. Windows gets slower the longer it runs.'
        'advice.longUptime'   = 'Restart the PC: Start > Power > Restart (not Shut down). The steps below explain why.'
        'finding.hddSystem'   = 'Windows is on an old-style hard disk (HDD). That is the most common reason an older PC is slow.'
        'advice.hddSystem'    = 'Replacing it with an SSD makes the PC several times faster. That is a job for the technician.'
        'finding.lowRam'      = 'The PC has only {0} GB of memory, little for Windows 11.'
        'advice.lowRam'       = 'Keep few programs open at once. Adding memory, if the PC allows it, is a job for the technician.'
        'finding.manyStartup' = '{0} programs start with Windows, which slows starting and running.'
        'advice.manyStartup'  = 'Housecall can stop the ones not needed below (it can be undone).'
        'finding.slowOk'      = 'Nothing on this PC explains slowness right now.'
        'advice.slowOk'       = 'Slow only in the browser? Too many tabs or extensions. Slow at a certain moment? Choose D1 again at that moment.'
        'finding.startOk'     = 'Starting looks normal: few startup programs and a fast disk.'
        'advice.startOk'      = 'If Windows installs updates while starting, that takes a while once. Choose E1 to check.'
        'finding.crashes'     = '{0} crashed or froze {1} times this week.'
        'advice.crashes'      = 'Update or reinstall that program. The steps below go through it.'
        'finding.someCrashes' = '{0} crashed or froze once or twice this week.'
        'advice.someCrashes'  = 'Once in a while is normal. If it keeps happening, update or reinstall it.'
        'finding.blueScreens' = 'Windows stopped with a blue screen {0} time(s) in the past 30 days.'
        'advice.blueScreens'  = 'Usually a driver or failing hardware. Update Windows (E1) and the drivers. If it keeps happening, it is a job for the technician.'
        'finding.shutdowns'   = 'The PC switched off unexpectedly {0} time(s) in the past 30 days.'
        'advice.shutdowns'    = 'A power cut, a pulled plug, holding the power button, or overheating. On a laptop check the battery; on a desktop the power cable and dust in the fans.'
        'finding.crashOk'     = 'No crashes, freezes or blue screens this week.'
        'advice.crashOk'      = 'If one program freezes now and then, update it. Tell the client to save often.'
        'finding.diskOk'      = 'Disk {0} has enough space ({1} GB free).'
        'advice.diskOk'       = 'Nothing to clean up. If a program says the disk is full, it may mean another disk or a USB stick.'

        # ---- D: fixes
        'fix.note.temp'              = '(only temporary files, nothing personal)'
        'fix.note.noundo'            = '(cannot be undone: look at the contents first)'
        'fix.note.unsaved'           = '(unsaved work in it is lost)'
        'fix.disableStartup'         = 'Stop {0} from starting with Windows'
        'fix.disableStartup.done'    = 'Stopped {0} from starting with Windows'
        'fix.disableStartupMachine'  = 'Stop {0} from starting with Windows, for all users'
        'fix.disableStartupMachine.done' = 'Stopped {0} from starting with Windows, for all users'
        'fix.closeProcess'           = 'Close {0}'
        'fix.closeProcess.done'      = 'Closed {0}'
        'fix.emptyTemp'              = 'Delete temporary files ({0} GB)'
        'fix.emptyTemp.done'         = 'Deleted temporary files'
        'fix.emptyRecycleBin'        = 'Empty the Recycle Bin ({0} GB)'
        'fix.emptyRecycleBin.done'   = 'Emptied the Recycle Bin'

        # ---- D: step-by-step guides
        'steps.diskFull'    = 'Choose D4 to free up space with Housecall. | Or open Settings (Windows key + I) > System > Storage and click Cleanup recommendations. | Switch on Storage Sense on the same page, so Windows cleans up by itself. | Move big photos and videos to a USB drive or the cloud, after asking the client.'
        'steps.diskLow'     = 'Choose D4 to free up space with Housecall. | Open Settings (Windows key + I) > System > Storage and switch on Storage Sense, so Windows cleans up by itself.'
        'steps.spaceFull'   = 'Choose the fixes above: temporary files first, the Recycle Bin after checking its contents with the client. | Open Settings (Windows key + I) > System > Storage and click Cleanup recommendations. | Under "Show more categories", see what takes the most space (Apps, Documents, Pictures, Videos). | Uninstall programs the client no longer uses: Settings > Apps, find it in the list, three dots, Uninstall. | Switch on Storage Sense, so Windows cleans up by itself.'
        'steps.spaceLow'    = 'Choose the fixes above: temporary files first, the Recycle Bin after checking its contents with the client. | Open Settings (Windows key + I) > System > Storage and click Cleanup recommendations. | Switch on Storage Sense, so Windows cleans up by itself.'
        'steps.memoryFull'  = 'Press Ctrl + Shift + Esc to open Task Manager. | On the Processes tab, click the Memory column to sort by it. | Close programs that are not needed: select them and click End task. Save open work first. | Browser with many tabs? Close the tabs that are not needed. | Still full? Restart the PC.'
        'steps.cpuBusy'     = 'Press Ctrl + Shift + Esc to open Task Manager. | On the Processes tab, click the CPU column to sort by it. | Is the busiest program one the client knows? Save its work, select it and click End task. | Unknown name? Search for it online, and choose F3.'
        'steps.longUptime'  = 'Save open work and close programs. | Click Start > Power > Restart. Restart really starts fresh; Shut down (with fast startup) does not. | After the restart, choose D1 again.'
        'steps.hddSystem'   = 'Explain to the client: the disk is the slowest part of this PC. | Offer to replace it with an SSD (SATA SSD for older PCs, NVMe if the PC has an M.2 slot), cloning Windows across. | Until then: keep the startup list short (D2) and the disk tidy (D4).'
        'steps.lowRam'      = 'Keep few programs and browser tabs open at once. | Check whether the PC has a free memory slot or can be upgraded (maker and model on the sticker underneath). | If it can: adding memory is a job for the technician.'
        'steps.manyStartup' = 'Choose the fixes above to stop programs from starting with Windows (they still work when opened). | Or press Ctrl + Shift + Esc > Startup apps, select a program and click Disable. | Keep antivirus, sound, touchpad and OneDrive on. | Restart the PC and see whether it starts faster.'
        'steps.slowOk'      = 'Ask when it is slow: at startup (choose D2), in the browser, or in one program? | Browser: close tabs and remove extensions the client does not use. | Choose D1 again at the moment it is slow. | Also run F3: unwanted programs can slow a PC down.'
        'steps.startOk'     = 'Restart the PC and time it from pressing the button to a usable desktop. | Longer than 2 minutes? Choose E1: Windows may be busy with updates. | Still slow every time? Choose D1 while it is starting.'
        'steps.crashes'     = 'Update the program: often under Help > Check for updates, or via the Microsoft Store > Library > Get updates. | Still crashing? Settings > Apps, find it in the list, three dots, Advanced options (if shown) > Repair. | Otherwise: uninstall it, restart the PC and install it again from the maker''s website. | Choose D3 again after a few days.'
        'steps.someCrashes' = 'Update the program, often under Help > Check for updates. | Tell the client to save often. | If it keeps happening, choose D3 again.'
        'steps.blueScreens' = 'Choose E1 and install all Windows updates, including optional driver updates. | Note the error code on the blue screen the next time (for example MEMORY_MANAGEMENT): it points to the cause. | Recently added a device or program? Remove it and see whether it stops. | Keeps happening: a job for the technician (memory test, disk check).'
        'steps.shutdowns'   = 'Ask whether the power went out, or someone held the power button or pulled the plug. | Laptop: does it switch off at a certain battery level? Then the battery is worn. | Desktop: check the power cable, and have the dust cleaned out of the fans (overheating). | Keeps happening: a job for the technician.'
        'steps.crashOk'     = 'Ask which program freezes, and when. | Update that program. | Choose D3 again right after it happens.'
        'steps.diskOk'      = 'Ask which program says the disk is full, and which disk it names. | A USB stick or memory card? Check its space in File Explorer (This PC). | Switch on Storage Sense (Settings > System > Storage), so it stays tidy.'

        # ---- E: check lines
        'upd.windows10'       = 'This PC runs Windows 10, which gets no security updates since 14 October 2025'
        'upd.serviceDisabled' = 'The Windows Update service is switched off'
        'upd.serviceOk'       = 'The Windows Update service is available'
        'upd.paused'          = 'Updates are paused until {0}'
        'upd.last'            = 'Last successful update: {0}'
        'upd.lastOld'         = 'Last successful update: {0}, {1} days ago'
        'upd.never'           = 'No successful update found in the history'
        'upd.failed'          = 'Failed: {0} (error {1})'
        'upd.historyUnknown'  = 'The update history could not be read'
        'upd.rebootPending'   = 'Windows is waiting for a restart to finish installing updates'
        'upd.noSpace'         = 'Only {1} GB free on {0}: too little for updates'
        'err.activated'       = 'Windows is activated'
        'err.notActivated'    = 'Windows is not activated'
        'err.clockOk'         = 'The clock is right'
        'err.clockWrong'      = 'The clock is off by {0} minutes'
        'err.clockUnknown'    = 'The clock could not be compared (no internet)'
        'err.crash'           = '{0} crashed or froze {1} time(s) in the past 3 days'
        'err.noCrash'         = 'No program crashed in the past 3 days'
        'sd.noPending'        = 'No updates are waiting for a restart'
        'sd.fastStartup'      = 'Fast startup is on: Shut down does not fully switch Windows off'

        # ---- E: findings, and what to do about each
        'finding.windows10'             = 'This PC still runs Windows 10, which gets no security updates since 14 October 2025.'
        'advice.windows10'              = 'Upgrade to Windows 11 if the PC can (the PC Health Check app says so), or plan a new PC. That is a job for the technician.'
        'finding.updateServiceDisabled' = 'The Windows Update service is switched off, so no updates can install.'
        'advice.updateServiceDisabled'  = 'Housecall can switch it back on below (needs admin, can be undone). Ask the client whether someone switched it off on purpose.'
        'finding.updateSpace'           = 'There is too little space for updates ({0} GB free).'
        'advice.updateSpace'            = 'Choose D4 to free up space, then choose E1 again.'
        'finding.updatesPaused'         = 'Updates are paused until {0}.'
        'advice.updatesPaused'          = 'Housecall can resume them below (needs admin, can be undone), or click Resume updates in Settings > Windows Update.'
        'finding.rebootPending'         = 'Windows is waiting for a restart to finish installing updates.'
        'advice.rebootPending'          = 'Restart the PC: Start > Power > Update and restart. That can take a while once; do not switch it off meanwhile.'
        'finding.updateFailures'        = 'An update failed to install recently (error {0}).'
        'advice.updateFailures'         = 'Housecall can reset Windows Update below (needs admin): it downloads the updates again. Then choose Check for updates in Settings > Windows Update.'
        'finding.updatesStale'          = 'Windows has not installed an update for {0} days.'
        'advice.updatesStale'           = 'Open Settings > Windows Update and click Check for updates. If it gets stuck, Housecall can reset Windows Update below (needs admin).'
        'finding.updatesOk'             = 'Windows Update works and is up to date.'
        'advice.updatesOk'              = 'If an update keeps failing with a message, note the error code (0x...) and choose E1 again after trying once more.'
        'finding.clockWrong'            = 'The PC''s clock is off by {0} minutes. That causes "your connection is not private" and certificate errors on websites.'
        'advice.clockWrong'             = 'Housecall can set the clock right below (needs admin). Also check the time zone: see the steps.'
        'finding.notActivated'          = 'Windows is not activated. That causes the "Activate Windows" message and blocks personalising.'
        'advice.notActivated'           = 'Check under Settings > System > Activation. A PC that came with Windows usually reactivates by itself once online; otherwise a licence is needed.'
        'finding.recentCrash'           = '{0} crashed or froze recently, which may be the message the client saw.'
        'advice.recentCrash'            = 'Update or reinstall that program (the steps for D3 go through it). Housecall can also check Windows'' own files below.'
        'finding.errorsOk'              = 'No known cause found for an error message.'
        'advice.errorsOk'               = 'Take a photo of the message next time it appears, especially any code. Housecall can check Windows'' own files below (needs admin, takes a while).'
        'finding.fastStartup'           = 'Fast startup is on: Shut down does not fully switch Windows off, so problems survive it.'
        'advice.fastStartup'            = 'Housecall can switch fast startup off below (needs admin, can be undone). Restart always fully restarts, with or without it.'
        'finding.shutdownOk'            = 'Nothing on this PC blocks shutting down or restarting.'
        'advice.shutdownOk'             = 'If a program asks to save or will not close, close it first. If the PC hangs on "Shutting down", see the steps.'

        # ---- E: fixes
        'fix.note.redownload'            = '(Windows downloads the updates again)'
        'fix.note.long'                  = '(takes 15 to 30 minutes, keep the PC on)'
        'fix.enableUpdateService'        = 'Switch the Windows Update service back on'
        'fix.enableUpdateService.done'   = 'Switched the Windows Update service back on'
        'fix.resumeUpdates'              = 'Resume updates'
        'fix.resumeUpdates.done'         = 'Resumed updates'
        'fix.resetUpdates'               = 'Reset Windows Update'
        'fix.resetUpdates.done'          = 'Reset Windows Update'
        'fix.syncClock'                  = 'Set the clock right with internet time'
        'fix.syncClock.done'             = 'Set the clock right with internet time'
        'fix.repairWindows'              = 'Check and repair Windows'' own files'
        'fix.repairWindows.done'         = 'Checked and repaired Windows'' own files'
        'fix.disableFastStartup'         = 'Switch fast startup off'
        'fix.disableFastStartup.done'    = 'Switched fast startup off'

        # ---- E: step-by-step guides
        'steps.windows10'             = 'Open the PC Health Check app (or download it from Microsoft) and click Check now under Windows 11. | Compatible? Settings > Update & Security > Windows Update offers the upgrade. Back up the client''s files first. | Not compatible? Discuss a new PC, or Microsoft''s paid Extended Security Updates. | Until then: keep the browser and antivirus up to date, and run F3 now and then.'
        'steps.updateServiceDisabled' = 'Choose the fix above to switch it back on (needs admin), or do it by hand. | Type Services in Start and open it. | Find Windows Update, double-click it, set Startup type to Manual, click Start, then OK. | Open Settings > Windows Update and click Check for updates.'
        'steps.updateSpace'           = 'Choose D4 to free up space with Housecall. | Updates need at least 10 GB free, big feature updates more. | Then open Settings > Windows Update and click Check for updates.'
        'steps.updatesPaused'         = 'Choose the fix above to resume updates (needs admin), or do it by hand. | Open Settings (Windows key + I) > Windows Update. | Click Resume updates, then Check for updates.'
        'steps.rebootPending'         = 'Save open work and close programs. | Click Start > Power > Update and restart. | Wait: the PC may restart more than once. Do not switch it off while it says "Working on updates". | Afterwards, choose E1 again.'
        'steps.updateFailures'        = 'Choose the fix above to reset Windows Update (needs admin). | Restart the PC. | Open Settings > Windows Update and click Check for updates, then Download and install. | Still failing? Search for the error code (0x...) on the Microsoft website, or choose E2 to check Windows'' own files.'
        'steps.updatesStale'          = 'Open Settings (Windows key + I) > Windows Update and click Check for updates. | Stuck at a percentage for over an hour? Choose the fix above to reset Windows Update (needs admin) and restart. | Make sure there is enough space (D4) and a working internet connection (A1).'
        'steps.updatesOk'             = 'Open Settings > Windows Update and look under Update history for failed updates. | Note the error code of a failed one and search for it on the Microsoft website. | Try Check for updates once more.'
        'steps.clockWrong'            = 'Choose the fix above to set the clock right (needs admin). | Open Settings (Windows key + I) > Time & language > Date & time. | Switch on "Set time automatically" and "Set time zone automatically", or choose (UTC+01:00) Amsterdam, Berlin... | Click Sync now. | The clock keeps going wrong after the PC was off? The small battery on the motherboard is empty: a job for the technician.'
        'steps.notActivated'          = 'Open Settings (Windows key + I) > System > Activation. | Click Troubleshoot if it is offered, and sign in with the client''s Microsoft account if asked. | Replaced parts recently? Choose "I changed hardware on this device recently". | Still not activated: the client needs a licence (a product key).'
        'steps.recentCrash'           = 'Ask the client when the message appears and in which program. | Update or reinstall that program (see D3). | Choose the fix above to check Windows'' own files (needs admin, takes a while).'
        'steps.errorsOk'              = 'Next time the message appears: take a photo of it, including any code. | Search for the exact text or code online, or show it to your technician. | Choose the fix above to check and repair Windows'' own files (needs admin, takes 15 to 30 minutes).'
        'steps.fastStartup'           = 'Choose the fix above to switch it off (needs admin), or do it by hand. | Type Control Panel in Start > Power Options > Choose what the power buttons do. | Click "Change settings that are currently unavailable" and untick "Turn on fast startup". Click Save changes.'
        'steps.shutdownOk'            = 'Save work and close all programs first. | Click Start > Power > Shut down (or Restart). | Hangs for more than 10 minutes on "Shutting down"? Hold the power button for 10 seconds. | Keeps happening? Choose E1: waiting updates are the most common cause.'

        # ---- A4: email
        'mail.ask'            = 'Which email address? Only the part after the @ is used, e.g. ziggo.nl'
        'mail.invalid'        = '"{0}" does not look like an email address. Type it like this: name@ziggo.nl'
        'mail.typo'           = '"{0}" looks like a typo: did you mean {1}?'
        'mail.receives'       = '{0} receives email'
        'mail.noMx'           = '{0} cannot receive email'
        'mail.in'             = 'Receiving'
        'mail.out'            = 'Sending'
        'mail.serverOk'       = '{0}: {1} answers, {2} ms'
        'mail.serverDown'     = '{0}: {1} does not answer'
        'mail.unknownProvider' = 'Mail servers of {0} not known to Housecall: not checked'
        'mail.apps'           = 'Mail programs: {0}'
        'mail.noApps'         = 'No mail program installed (webmail only)'
        'mail.retired'        = 'The old Windows Mail app is installed; it stopped working at the end of 2024'
        'finding.mailTypo'       = '"{0}" is probably a typo of {1}. Mail to or from the wrong address goes nowhere.'
        'advice.mailTypo'        = 'Check the address in the mail program''s account settings, and choose A4 again with the right one.'
        'finding.mailNoDomain'   = '{0} cannot receive email: the address is probably misspelled, or no longer exists.'
        'advice.mailNoDomain'    = 'Check the spelling with the client. An old provider address (for example after moving) may have been closed.'
        'finding.mailServerDown' = 'The mail server of {0} does not answer this PC.'
        'advice.mailServerDown'  = 'Check for an outage at the provider on a phone (for example allestoringen.nl). If there is none, security software on this PC may be blocking mail.'
        'finding.mailAppRetired' = 'The old Windows Mail app is still installed. Microsoft switched it off at the end of 2024: mail no longer arrives in it.'
        'advice.mailAppRetired'  = 'Switch the client to the new Outlook (free, in the Microsoft Store) or to webmail. The steps below go through it.'
        'finding.mailOk'         = 'The mail servers of {0} can be reached. The problem is probably the password, a full mailbox, or the mail program''s settings.'
        'advice.mailOk'          = 'Try signing in to webmail first: if that works, the mail program''s settings are the problem. The steps below go through it.'
        'steps.mailTypo'         = 'Open the mail program''s account settings and look at the address. | Correct the part after the @, or remove the account and add it again with the right address. | Choose A4 again with the right address.'
        'steps.mailNoDomain'     = 'Check the spelling of the address with the client, letter by letter. | Did the client change internet provider? An old address such as @hetnet.nl or @home.nl may still work, or may have been closed: check with that provider. | Choose A4 again with the right address.'
        'steps.mailServerDown'   = 'On a phone with Wi-Fi off, check for an outage at the provider (for example allestoringen.nl). | No outage? Pause the antivirus or firewall on this PC for a moment and try sending and receiving. | Works then? Add an exception for the mail program in that security program, and switch the protection back on.'
        'steps.mailAppRetired'   = 'Install the new Outlook: open the Microsoft Store, search for Outlook and click Get. It is free. | Open it and add the client''s email address; Outlook finds the settings itself for most providers. | Or use webmail in the browser, and make a shortcut on the desktop. | Remove the old Mail app (Settings > Apps, "Mail and Calendar", three dots, Uninstall) so the client cannot open it by mistake.'
        'steps.mailOk'           = 'Sign in to webmail in the browser with the client''s address and password. | Does that fail? The password is wrong: reset it through the provider''s website ("forgot password"). | Does webmail work? Remove the account from the mail program and add it again, typing the password afresh. | Mail arrives in webmail but not in the program? Check the spam folder, and whether the mailbox is full (delete old mail with big attachments).'

        # ---- fixes added later
        'fix.note.restartNeeded'     = '(works after a restart of the PC)'
        'fix.note.uninstaller'       = '(opens the program''s own uninstaller)'

        # ---- G: check lines
        'shell.profileOk'          = 'Signed in with the normal user profile'
        'shell.tempProfile'        = 'Windows signed in with a TEMPORARY profile: the client''s own desktop and files are not loaded'
        'shell.explorerOk'         = 'File Explorer (desktop, taskbar, folders) is running and responding'
        'shell.explorerMissing'    = 'File Explorer is not running, so there is no taskbar or desktop'
        'shell.explorerHung'       = 'File Explorer has stopped responding'
        'shell.iconsShown'         = 'Desktop icons are shown ({0} items on the desktop)'
        'shell.iconsHidden'        = 'Desktop icons are switched off, so the desktop looks empty'
        'shell.desktopOneDrive'    = 'The desktop is kept in OneDrive, and OneDrive is running'
        'shell.desktopOneDriveOff' = 'The desktop is kept in OneDrive, but OneDrive is not running'
        'shell.recycleHidden'      = 'The Recycle Bin is hidden from the desktop'
        'shell.taskbarShown'       = 'The taskbar stays visible'
        'shell.taskbarAutoHide'    = 'The taskbar hides itself until the mouse touches the bottom of the screen'
        'shell.searchHidden'       = 'The search box is hidden from the taskbar'
        'shell.tabletMode'         = 'Tablet mode is on: bigger tiles, no desktop icons'

        # ---- G: findings, and what to do about each
        'finding.tempProfile'      = 'Windows could not load the client''s own profile and signed in with an empty, temporary one. The files are almost certainly still there, but this session does not show them, and anything saved now is lost at sign-out.'
        'advice.tempProfile'       = 'Do not let the client save anything now. Restart the PC first; the steps below go further if that does not help.'
        'finding.explorerMissing'  = 'File Explorer is not running. It draws the desktop, the taskbar and the folders, so they are all gone.'
        'advice.explorerMissing'   = 'Housecall can start it again below. It is harmless.'
        'finding.explorerHung'     = 'File Explorer is stuck. That is why the taskbar, the desktop or the folders do not react.'
        'advice.explorerHung'      = 'Housecall can restart it below. Open folder windows close; files are not touched.'
        'finding.iconsHidden'      = 'The desktop icons are switched off. The files are still there, only hidden. This often happens by accident with a right-click on the desktop.'
        'advice.iconsHidden'       = 'Housecall can show them again below (it can be undone).'
        'finding.desktopOneDrive'  = 'The client''s desktop is kept in OneDrive, but OneDrive is not running. That can make desktop files seem missing or out of date.'
        'advice.desktopOneDrive'   = 'Choose G2 to check OneDrive.'
        'finding.tabletMode'       = 'Tablet mode is on. It makes Windows 10 look different: big tiles, and no icons on the desktop.'
        'advice.tabletMode'        = 'Switch it off with the steps below.'
        'finding.taskbarAutoHide'  = 'The taskbar hides itself: it only appears when the mouse touches the bottom of the screen.'
        'advice.taskbarAutoHide'   = 'Housecall can make it stay visible below (it can be undone).'
        'finding.searchHidden'     = 'The search box is hidden from the taskbar, so there is nowhere to type a search.'
        'advice.searchHidden'      = 'Housecall can show it again below (it can be undone).'
        'finding.recycleHidden'    = 'The Recycle Bin is hidden from the desktop. Deleted files are still in it.'
        'advice.recycleHidden'     = 'Housecall can show it again below (it can be undone).'
        'finding.shellOk'          = 'The desktop, the taskbar and File Explorer are set normally.'
        'advice.shellOk'           = 'Still acting strange? Restarting File Explorer below is harmless and often helps.'

        # ---- G: fixes
        'fix.note.explorer'        = '(the taskbar is gone for a few seconds, open folder windows close)'
        'fix.restartExplorer'      = 'Restart File Explorer'
        'fix.restartExplorer.done' = 'Restarted File Explorer'
        'fix.showDesktopIcons'     = 'Show the desktop icons again'
        'fix.showDesktopIcons.done' = 'Showed the desktop icons again'
        'fix.showRecycleBin'       = 'Show the Recycle Bin on the desktop'
        'fix.showRecycleBin.done'  = 'Showed the Recycle Bin on the desktop'
        'fix.showSearch'           = 'Show the search box on the taskbar'
        'fix.showSearch.done'      = 'Showed the search box on the taskbar'
        'fix.taskbarStay'          = 'Keep the taskbar visible'
        'fix.taskbarStay.done'     = 'The taskbar stays visible'

        # ---- G: step-by-step guides
        'steps.tempProfile'        = 'Do not save anything now: it would be lost at sign-out. | Restart the PC (Start > Power > Restart) and sign in again. Often that is enough. | Still a temporary profile? Check that the disk is not full (D4); a full disk is a common cause. | Still not? The profile needs repairing in the registry, with admin rights. Do this only with a backup, or plan it as a separate job. | The client''s files are normally still in C:\Users\<name>: open that folder to reassure the client.'
        'steps.explorerMissing'    = 'Choose the fix above to start it, or do it by hand. | Press Ctrl + Shift + Esc to open Task Manager. | Click Run new task, type explorer and press Enter. | The taskbar and the desktop come back.'
        'steps.explorerHung'       = 'Choose the fix above to restart it, or do it by hand. | Press Ctrl + Shift + Esc to open Task Manager. | Find Windows Explorer in the list, right-click it and choose Restart. | Happens often? Choose D1 or D3 to look for the cause.'
        'steps.iconsHidden'        = 'Choose the fix above (it can be undone), or do it by hand. | Right-click an empty spot on the desktop. | Choose View, then click Show desktop icons so it gets a tick.'
        'steps.desktopOneDrive'    = 'Choose G2 to check OneDrive. | Or start OneDrive by hand: type OneDrive in Start and open it. | Wait until the cloud icon at the bottom right no longer shows arrows.'
        'steps.tabletMode'         = 'Click the speech-bubble icon at the bottom right, next to the clock (the Action Center). | Click the Tablet mode tile so it is no longer blue. | Or: Settings (Windows key + I) > System > Tablet, and choose "Don''t use tablet mode".'
        'steps.taskbarAutoHide'    = 'Choose the fix above (it can be undone), or do it by hand. | Move the mouse to the bottom of the screen so the taskbar appears, right-click it and choose Taskbar settings. | Switch off "Automatically hide the taskbar" (Windows 11: under Taskbar behaviours).'
        'steps.searchHidden'       = 'Choose the fix above (it can be undone), or do it by hand. | Right-click the taskbar and choose Taskbar settings. | Under Search, choose Search box (Windows 10: right-click the taskbar > Search > Show search box).'
        'steps.recycleHidden'      = 'Choose the fix above (it can be undone), or do it by hand. | Open Settings (Windows key + I) > Personalisation > Themes > Desktop icon settings. | Tick Recycle Bin and click OK.'
        'steps.shellOk'            = 'Choose the fix above to restart File Explorer; it is harmless. | Desktop looks empty? Right-click the desktop > View > Show desktop icons. | Files seem gone? Choose G2 to check OneDrive, or search for the file name in File Explorer. | Everything suddenly big? Choose B3.'
        'fix.resetWinsock'           = 'Reset Windows'' network settings'
        'fix.resetWinsock.done'      = 'Reset Windows'' network settings (restart needed)'
        'fix.restartAdapter'         = 'Restart network adapter "{0}"'
        'fix.restartAdapter.done'    = 'Restarted network adapter "{0}"'
        'fix.uninstallProgram'       = 'Uninstall {0}'
        'fix.uninstallProgram.done'  = 'Uninstalled {0}'
        'fix.openNotifySettings'     = 'Open the notification settings in {0}'
        'fix.openNotifySettings.done' = 'Opened the notification settings in {0}'
        'fix.openWebmail'            = 'Open the {0} webmail in the browser'
        'fix.openWebmail.done'       = 'Opened the {0} webmail'
        'fix.restorePoint'           = 'Making a Windows restore point first...'
        'fix.restorePointOk'         = 'Restore point made.'
        'fix.restorePointRecent'     = 'Windows already made a restore point in the past 24 hours.'
        'fix.restorePointNone'       = 'No restore point: System Protection is off on this PC.'

        # ---- relay, unlock, visit memory
        'relay.askCode'      = 'Code from Google Authenticator (Enter = skip)'
        'relay.unlocked'     = 'Unlocked until {0}.'
        'relay.wrongCode'    = 'That code is not right. Type the code the app shows now.'
        'relay.codeUsed'     = 'That code was already used. Wait for the next one (every 30 seconds).'
        'relay.locked'       = 'Too many wrong codes: wait 15 minutes.'
        'relay.notSetUp'     = 'The relay is not set up yet: run tools\setup-ai.ps1 on your own PC.'
        'relay.expired'      = 'The unlock has expired: type a new code.'
        'relay.unreachable'  = 'The relay cannot be reached. Is the Supabase project paused? Restore it in the Supabase dashboard.'
        'relay.aiKey'        = 'The AI key in Supabase is not right: check ANTHROPIC_API_KEY.'
        'relay.aiBusy'       = 'The AI is busy right now: try again in a minute.'
        'relay.aiCredit'     = 'The Anthropic account has no credit: add credit at console.anthropic.com > Billing.'
        'relay.error'        = 'The relay answered with an error ({0}).'
        'menu.history'       = 'Visit history'
        'mem.title'          = 'Visit history of this PC'
        'mem.none'           = 'No earlier visits recorded for this PC.'
        'mem.known'          = 'Known PC{0}: last visit {1}'
        'mem.saveAsk'        = 'Save this visit in your visit history? Code from Google Authenticator (Enter = skip)'
        'mem.labelAsk'       = 'Name or note for this PC, for your records (Enter = {0})'
        'mem.noLabel'        = 'none'
        'mem.saved'          = 'Visit saved in your visit history.'
        'mem.notSaved'       = 'The visit was not saved: {0}'

        # ---- the AI chat
        'ai.describe'        = 'Describe the problem in your own words (Enter = back)'
        'ai.privacy'         = 'Only the problem and the check results go to the AI. No files, passwords or documents.'
        'ai.thinking'        = 'The AI is thinking...'
        'ai.running'         = 'The AI checks: {0}  {1}'
        'ai.answer'          = 'AI:'
        'ai.confidence.low'    = 'Certainty: low (the checks do not show the cause)'
        'ai.confidence.medium' = 'Certainty: medium'
        'ai.confidence.high'   = 'Certainty: high'
        'ai.steps'           = 'Steps:'
        'ai.refused'         = 'The AI did not answer this question. Choose a letter from the menu.'
        'ai.noAnswer'        = 'The AI did not reach an answer. Choose a letter from the menu.'

        # ---- the invoice
        'inv.askCode'     = 'Code from Google Authenticator for the invoice (Enter = no invoice, just the client note)'
        'inv.title'       = 'Invoice'
        'inv.intro'       = 'Enter = the suggestion in brackets, 0 = no invoice (the client note instead)'
        'inv.clientName'  = 'Client name [{0}]'
        'inv.address'     = 'Street and number'
        'inv.postcode'    = 'Postcode and city'
        'inv.email'       = 'Email (optional)'
        'inv.minutes'     = 'Time worked in minutes [{0}]'
        'inv.minutesBad'  = 'Type a number of minutes, e.g. 45.'
        'inv.labour'      = 'Labour: {0} min at {1} per hour'
        'inv.startLine'       = 'Labour {0} min: starting price ({1} min)'
        'inv.extraTime'       = '+ {0} x 15 min extra, {1} each'
        'inv.win.rateStart'   = '{0} for the first {1} min, then {2} per quarter of an hour begun'
        'inv.win.done'        = 'What was done (choose or type)'
        'inv.win.asked'       = 'Asked for help with'
        'inv.win.fixed'       = 'Fixed'
        'inv.win.notFixed'    = 'Not fixed'
        'inv.win.remove'      = 'Remove selected'
        'inv.win.itemFixed'   = 'Fixed: {0}'
        'inv.win.itemOpen'    = 'Not fixed: {0}'
        'work.presets'        = 'Internet and Wi-Fi working again | Printer installed | Printer working again | Email set up | Windows updated | Computer made faster | Startup programs cleaned up | Virus scan done | Unwanted programs removed | Sound working again | Device connected and set up | Password reset | Backup made of photos and files | New computer set up | Explained how to use it | A part has to be ordered | The problem is with the internet provider | The computer is too old to repair'
        'inv.callout'     = 'Charge the call-out fee of {0}? (Y/N) [Y]'
        'inv.calloutLine' = 'Call-out fee'
        'inv.extra'       = 'Extra line, e.g. "Wireless mouse 19,95" (Enter = done)'
        'inv.extraBad'    = 'Type a description and then an amount, e.g. "USB stick 12,50".'
        'inv.noLines'     = 'There is nothing to invoice: the client note is shown instead.'
        'inv.payment'     = 'Payment: {0}'
        'inv.pay.pin'      = 'card'
        'inv.pay.cash'     = 'cash'
        'inv.pay.transfer' = 'bank transfer'
        'inv.pay.tikkie'   = 'payment request'
        'inv.confirm'     = 'Total {0}. Make the invoice? (Y/N)'
        'inv.noSettings'  = 'Your invoice details are not set up yet: run tools\setup-invoice.ps1. The client note is shown instead.'
        'inv.failed'      = 'The invoice could not be made: {0} The client note is shown instead.'
        'inv.skipped'     = 'No invoice: the client note is shown instead.'
        'inv.made'        = 'Invoice {0} made.'
        'inv.win.client'      = 'Client'
        'inv.win.name'        = 'Name'
        'inv.win.work'        = 'Work'
        'inv.win.minutes'     = 'Time worked (minutes)'
        'inv.win.rate'        = 'at {0} per hour'
        'inv.win.callout'     = 'Call-out fee {0}'
        'inv.win.extras'      = 'Extra lines (for example a new mouse)'
        'inv.win.description' = 'Description'
        'inv.win.amount'      = 'Amount'
        'inv.win.payment'     = 'Payment'
        'inv.win.total'       = 'Total: {0}'
        'inv.win.make'        = 'Make invoice'
        'inv.win.none'        = 'No invoice (note)'
        'inv.win.needName'    = 'Fill in the client''s name.'
        'inv.win.needPayment' = 'Choose how the client pays.'
        'inv.win.badLine'     = 'Extra line {0}: type a description and an amount, like 19,95.'
        'inv.win.nothing'     = 'There is nothing to invoice yet: fill in the time or an extra line.'
        'doc.invoice'     = 'INVOICE {0}'
        'doc.date'        = 'Invoice date: {0}'
        'doc.kvk'         = 'KvK {0}'
        'doc.btwNumber'   = 'VAT no. {0}'
        'doc.iban'        = 'IBAN {0}'
        'doc.to'          = 'Invoice to'
        'doc.costs'       = 'Costs'
        'doc.subtotal'    = 'Subtotal excl. VAT'
        'doc.btw'         = 'VAT 21%'
        'doc.total'       = 'Total'
        'doc.paidPin'     = 'Paid by card on {0}.'
        'doc.paidCash'    = 'Paid in cash on {0}.'
        'doc.paidTikkie'  = 'To be paid through the payment request sent on {0}.'
        'doc.transfer'    = 'Please transfer {0} before {1} to {2}, stating invoice number {3}.'
        'doc.kor'         = 'Exempt from VAT under the small business scheme (KOR).'
        'doc.btwUnset'    = 'VAT not set up yet.'
        'doc.thanks'      = 'Thank you for your trust.'
        'doc.windowTitle' = 'Housecall - invoice {0}'
        'doc.invoiceWord' = 'Invoice'
        'doc.numberDate'  = ('{0}  ' + [char]0x00B7 + '  {1}')
        'doc.toCap'       = 'INVOICE TO'
        'doc.subjectCap'  = 'REGARDING'
        'doc.descriptionCap' = 'DESCRIPTION'
        'doc.amountCap'   = 'AMOUNT'
        'doc.workTitle'   = 'Computer help at home'
        'doc.notFixed'    = '{0} (not fixed yet)'
        'doc.totalWord'   = 'Total'
        'doc.pageOf'      = 'Page {0} of {1}'
        'mem.invoice'       = 'invoice {0}'
        'mem.deleteAsk'     = 'Number of a visit to delete (Enter = back)'
        'mem.deleteConfirm' = 'Delete the visit of {0}? (Y/N)'
        'mem.deleted'       = 'Visit deleted.'
        'mem.invoiceKept'   = 'Invoice {0} is kept: invoices must be kept for 7 years.'
    }

    nl = @{
        'tagline'          = 'vindt en verhelpt computerproblemen, altijd met uw akkoord'
        'promise'          = 'Er verandert niets op deze pc zonder uw ja.'

        'status.admin'     = 'beheerder'
        'status.notAdmin'  = 'geen beheerder'
        'status.online'    = 'online'
        'status.offline'   = 'offline'
        'status.dryRun'    = 'PROEFDRAAI: alleen controleren, er wordt niets hersteld'
        'status.clock'     = 'Bezig sinds {0}, {1} min'
        'env.outdated'     = 'Deze Housecall-kopie is verouderd. Zet de nieuwe op de USB-stick: draai tools\make-usb.ps1 op uw eigen pc.'
        'status.clockOver' = 'Bezig sinds {0}, {1} min: het starttarief ({2} min) is op, vraag de klant of u verder mag'

        'menu.question'    = 'Waar gaat het probleem over?'
        'menu.ai'          = 'Iets anders: beschrijf het zelf (AI-chat)'
        'menu.hintHome'    = 'Typ een letter, of ga direct naar een probleem, bijv. A1'
        'menu.back'        = 'Terug'
        'menu.language'    = 'English'
        'menu.quit'        = 'Stoppen'
        'menu.prompt'      = 'Kies'
        'menu.unknown'     = '"{0}" is geen keuze. Probeer een letter zoals A, of een code zoals A1.'

        'area.question'    = '{0}  {1}: wat is het probleem?'
        'area.ai'          = 'Geen van deze: beschrijf het zelf (AI-chat)'
        'area.hint'        = 'Typ een nummer, bijv. 1, of de hele code'

        'problem.notBuilt' = 'De controles voor dit probleem zijn nog niet gebouwd.'
        'problem.willLook' = 'Er wordt gekeken naar:'
        'pressEnter'       = 'Druk op Enter om terug te gaan'

        'ai.title'         = 'Beschrijf het probleem in uw eigen woorden'
        'ai.youTyped'      = 'U typte: {0}'
        'ai.notBuilt'      = 'De AI-chat is nog niet gebouwd. Kies voorlopig een letter uit het menu.'
        'ai.offline'       = 'Deze pc is offline, dus de AI-chat is niet bereikbaar. Het menu werkt zonder internet.'

        'goodbye'          = 'Housecall is gesloten. Er is niets achtergebleven op deze pc.'
        'goodbyeChanged'   = 'Housecall is gesloten. De {0} wijziging(en) die u goedkeurde blijven staan; verder is er niets achtergebleven.'
        'env.notWindows'   = 'Housecall werkt alleen op Windows.'
        'env.oldPowerShell' = 'Housecall heeft PowerShell 5.1 of nieuwer nodig. Deze pc heeft {0}.'

        'area.A'  = 'Internet en wifi'
        'area.B'  = 'Geluid, beeld en videobellen'
        'area.C'  = 'Printer en apparaten'
        'area.D'  = 'Traag of vastlopen'
        'area.E'  = 'Windows en updates'
        'area.F'  = 'Veiligheid en oplichting'
        'area.G'  = 'Bestanden, bureaublad en accounts'

        'looks.A' = 'netwerkadapter, adres van de router, router, DNS, internet, proxy, wifi-signaal'
        'looks.B' = 'standaard geluidsapparaat, dempen en volume, audioservice, toegang tot camera en microfoon, schermschaal'
        'looks.C' = 'afdrukservice, vastgelopen printopdrachten, standaardprinter, USB-apparaten met fouten, Bluetooth'
        'looks.D' = 'vrije schijfruimte, programma''s die geheugen en processor gebruiken, opstartprogramma''s, recente crashes, tijd sinds herstart'
        'looks.E' = 'Windows Update-service, laatste geslaagde update, wachtende herstart'
        'looks.F' = 'programma''s voor overname op afstand zoals AnyDesk, sites die meldingen mogen sturen, Microsoft Defender, onbekende geplande taken'
        'looks.G' = 'tijdelijk profiel, Verkenner, pictogrammen op het bureaublad, taakbalk en zoeken, OneDrive, downloads, welk programma een bestand opent'

        'problem.A1' = 'Helemaal geen internet'
        'problem.A2' = 'Wifi is traag of valt steeds weg'
        'problem.A3' = 'Een website of app laadt niet'
        'problem.A4' = 'E-mail verzenden of ontvangen lukt niet'
        'problem.B1' = 'Geen geluid'
        'problem.B2' = 'Microfoon of camera (videobellen)'
        'problem.B3' = 'Scherm te klein, te donker of verkeerd'
        'problem.C1' = 'De printer print niet'
        'problem.C2' = 'Muis, toetsenbord of USB-stick'
        'problem.C3' = 'Bluetooth'
        'problem.D1' = 'De hele computer is traag'
        'problem.D2' = 'Opstarten duurt heel lang'
        'problem.D3' = 'Een programma loopt vast of crasht'
        'problem.D4' = 'De schijf is vol'
        'problem.E1' = 'Update loopt vast of mislukt'
        'problem.E2' = 'Foutmelding op het scherm'
        'problem.E3' = 'Afsluiten of herstarten lukt niet'
        'problem.F1' = 'Een pop-up zegt dat ik een virus heb'
        'problem.F2' = 'Iemand belde mij en kwam in mijn computer'
        'problem.F3' = 'Volledige veiligheidscontrole'
        'problem.G1' = 'Bureaublad, taakbalk of mappen doen raar'
        'problem.G2' = 'Mijn bestanden zijn weg of staan niet overal'
        'problem.G3' = 'Ik kan een bestand niet vinden, of het opent verkeerd'

        # ---- running a check
        'run.checking' = 'Bezig met controleren... er verandert niets op deze pc.'
        'run.found'    = 'Gevonden:'
        'run.advice'   = 'Wat te doen:'

        # ---- A: check lines
        'net.noAdapter'        = 'Geen netwerkadapter gevonden'
        'net.wifiDisabled'     = 'Wifi-adapter "{0}" staat uit'
        'net.adapterOff'       = 'Netwerkadapter "{0}" staat uit'
        'net.wifiNotConnected' = 'Wifi staat aan, maar is met geen enkel netwerk verbonden'
        'net.cableUnplugged'   = 'Geen netwerkkabel aangesloten ("{0}")'
        'net.adapterUp'        = 'Netwerkadapter "{0}" staat aan'
        'net.wifiConnected'    = 'Verbonden met wifi "{0}", signaal {1}%'
        'net.wifiConnectedNoSignal' = 'Verbonden met wifi'
        'net.cableConnected'   = 'Verbonden via een netwerkkabel'
        'net.weakSignal'       = 'Het wifi-signaal is zwak: {0}%'
        'net.proxy'            = 'Verkeer gaat via een proxy: {0}'
        'net.noAddress'        = 'Geen adres van de router ({0})'
        'net.address'          = 'Adres van de router: {0}'
        'net.addressStatic'    = 'Vast adres, met de hand ingesteld: {0}'
        'net.noGateway'        = 'Geen router (gateway) ingesteld voor deze verbinding'
        'net.gatewayOk'        = 'Router {0} antwoordt in {1} ms'
        'net.gatewayNoPing'    = 'Router {0} negeert testberichten (dat is geen probleem)'
        'net.gatewayDown'      = 'Router {0} antwoordt niet'
        'net.internetDown'     = 'Voorbij de router komt niets op internet'
        'net.internetOk'       = 'Internet bereikbaar, {0} ms'
        'net.dnsDown'          = 'Namen van websites worden niet gevonden (DNS-server {0})'
        'net.dnsOk'            = 'Namen van websites worden gevonden (DNS)'
        'net.webOk'            = 'Testpagina laadt normaal'
        'net.webIntercepted'   = 'Een inlogpagina of een ander programma vangt het webverkeer af'
        'net.webFailed'        = 'De testpagina laadt niet'
        'net.skipped'          = 'Overige controles overgeslagen'
        'net.lossOk'           = 'Routertest: alle {0} berichten kwamen terug, gemiddeld {1} ms'
        'net.loss'             = 'Routertest: {0} van de {1} berichten kwijtgeraakt'
        'net.drops'            = 'Keren dat de wifi wegviel, afgelopen 7 dagen: {0} (slaapstand en afsluiten meegeteld)'
        'net.internetWorks'    = 'Internet werkt op deze pc'
        'net.none'             = 'geen'

        # ---- A: findings, and what to do about each
        'finding.noAdapter'        = 'Windows ziet helemaal geen netwerkadapter. Het stuurprogramma ontbreekt misschien, of de adapter is kapot.'
        'advice.noAdapter'         = 'Open Apparaatbeheer en zoek een netwerkadapter met een waarschuwingsteken. Installeer het stuurprogramma van de site van de fabrikant, via een telefoon (USB-tethering) of een andere pc.'
        'finding.wifiDisabled'     = 'De wifi-adapter staat uit.'
        'advice.wifiDisabled'      = 'Zet wifi aan: Instellingen > Netwerk en internet > Wifi, of de wifitoets op het toetsenbord. Controleer ook of de vliegtuigstand uit staat.'
        'finding.adapterOff'       = 'De netwerkadapter staat uit.'
        'advice.adapterOff'        = 'Zet hem weer aan: Instellingen > Netwerk en internet > Geavanceerde netwerkinstellingen > Inschakelen.'
        'finding.wifiNotConnected' = 'Wifi staat aan, maar de pc is met geen netwerk verbonden.'
        'advice.wifiNotConnected'  = 'Controleer of de vliegtuigstand uit staat. Klik dan rechtsonder op het wifi-icoon en kies het thuisnetwerk. Het wachtwoord staat vaak op een sticker op de router.'
        'finding.cableUnplugged'   = 'Deze pc gebruikt een netwerkkabel, maar de kabel is niet aangesloten.'
        'advice.cableUnplugged'    = 'Druk de kabel aan beide kanten aan tot hij klikt. Probeer een andere poort op de router, of een andere kabel.'
        'finding.noAddress'        = 'De pc is verbonden, maar de router heeft hem geen adres gegeven.'
        'advice.noAddress'         = 'Vernieuw het adres: ipconfig /release en daarna ipconfig /renew. Helpt dat niet, herstart dan de router: 30 seconden stroom eraf, daarna 3 minuten wachten.'
        'finding.noGateway'        = 'Er is geen router ingesteld voor deze verbinding. Meestal een vast adres dat met de hand is ingesteld.'
        'advice.noGateway'         = 'Zet de verbinding terug op automatisch: Instellingen > Netwerk en internet > (de verbinding) > IP-toewijzing > Automatisch (DHCP).'
        'finding.gatewayDown'      = 'De router antwoordt niet.'
        'advice.gatewayDown'       = 'Kijk of de lampjes van de router branden. Herstart hem: 30 seconden stroom eraf, daarna 3 minuten wachten.'
        'finding.internetDown'     = 'De router werkt, maar de router zelf heeft geen internet.'
        'advice.internetDown'      = 'Herstart modem en router. Kijk op een telefoon of er een storing is bij de provider (bijv. allestoringen.nl). Controleer het internetlampje op de router.'
        'finding.dnsDown'          = 'Internet werkt, maar namen van websites worden niet gevonden (DNS).'
        'advice.dnsDown'           = 'Leeg de DNS-cache: ipconfig /flushdns. Zijn de DNS-servers met de hand ingesteld, zet ze dan terug op automatisch.'
        'finding.webIntercepted'   = 'Iets vangt het webverkeer af: een inlogpagina van de wifi (hotel, gastnetwerk) of een programma op deze pc.'
        'advice.webIntercepted'    = 'Open een browser en kijk of er een inlogpagina verschijnt. Is die er niet, kies dan F3 om naar onbekende programma''s te zoeken.'
        'finding.proxy'            = 'Er is een proxy ingesteld. Op een thuis-pc is dat meestal ongewenst, en soms adware.'
        'advice.proxy'             = 'Zet hem uit: Instellingen > Netwerk en internet > Proxy. Kies daarna F3 om naar onbekende programma''s te zoeken.'
        'finding.weakSignal'       = 'Internet werkt, maar het wifi-signaal is hier zwak.'
        'advice.weakSignal'        = 'Ga dichter bij de router zitten, zet de router niet in een kast, of plaats een wifi-versterker of mesh-punt.'
        'finding.allGood'          = 'De internetverbinding werkt op deze pc.'
        'advice.allGood'           = 'Doet een bepaalde website of app het niet, kies dan A3. Is internet traag of valt het weg, kies dan A2.'
        'finding.unstable'         = 'De verbinding met de router is onstabiel: {0}% van de testberichten raakte kwijt.'
        'advice.unstable'          = 'Herstart de router en ga er dichterbij zitten. Een netwerkkabel is stabieler dan wifi.'
        'finding.dropsMany'        = 'De wifi viel de afgelopen 7 dagen {0} keer weg, vaker dan slaapstand en afsluiten verklaren.'
        'advice.dropsMany'         = 'Werk het wifi-stuurprogramma bij, zet energiebesparing voor de wifi-adapter uit in Apparaatbeheer, en herstart de router.'
        'finding.connHealthy'      = 'De verbinding ziet er nu gezond uit. Traagheid komt waarschijnlijk door het abonnement of de provider.'
        'advice.connHealthy'       = 'Doe een snelheidstest (bijv. speedtest.net) en vergelijk die met het abonnement. Probeer het ook op een ander moment van de dag.'

        # ---- A3: one website
        'site.ask'       = 'Welke website? Bijvoorbeeld: marktplaats.nl'
        'site.invalid'   = '"{0}" lijkt geen webadres. Typ het zo: whatsapp.com'
        'site.hosts'     = 'Het hosts-bestand stuurt {0} naar {1}'
        'site.hostsOk'   = 'Geen speciale regel voor {0} in het hosts-bestand'
        'site.dnsOk'     = '{0} gevonden: {1}'
        'site.dnsFail'   = '{0} niet gevonden'
        'site.tcpOk'     = '{0} antwoordt op de beveiligde poort, {1} ms'
        'site.tcpFail'   = '{0} antwoordt niet op de beveiligde poort'
        'site.httpOk'    = '{0} stuurt een pagina (status {1})'
        'site.httpError' = '{0} antwoordt met een fout (status {1})'
        'site.httpNone'  = '{0} stuurt geen pagina'

        'finding.siteHosts'    = 'Het hosts-bestand stuurt deze site naar een ander adres: een oude instelling, of malware.'
        'advice.siteHosts'     = 'Haal de regel voor deze site weg uit C:\Windows\System32\drivers\etc\hosts (beheerder nodig) en kies daarna F3.'
        'finding.siteNotFound' = 'De naam {0} wordt niet gevonden. Misschien een typefout, of de site bestaat niet meer.'
        'advice.siteNotFound'  = 'Controleer de spelling. Probeer het op een telefoon: lukt het daar ook niet, dan ligt het aan de site.'
        'finding.siteBlocked'  = 'De site wordt gevonden, maar antwoordt niet aan deze pc.'
        'advice.siteBlocked'   = 'Probeer het op een telefoon met wifi uit. Werkt het daar wel, dan blokkeert beveiligingssoftware of een firewall op deze pc het misschien.'
        'finding.siteError'    = 'De site antwoordt met een fout ({0}). Het probleem ligt waarschijnlijk bij de site zelf.'
        'advice.siteError'     = 'Probeer het later nog eens. Kijk op een telefoon of het daar ook misgaat.'
        'finding.siteOk'       = 'De site werkt vanaf deze pc. Het probleem zit waarschijnlijk in de browser of de app.'
        'advice.siteOk'        = 'Wis de cache en cookies van deze site in de browser, probeer een andere browser, of zet browserextensies uit. Bij een app: bijwerken of opnieuw installeren.'

        # ---- F: check lines
        'sec.noRemote'         = 'Geen programma''s voor overname op afstand gevonden'
        'sec.installed'        = 'op de pc gezet op {0}'
        'sec.installedUnknown' = 'staat op de pc, datum onbekend'
        'sec.downloaded'       = 'gedownload op {0}'
        'sec.running'          = 'DRAAIT NU'
        'sec.autoStart'        = 'start mee met Windows'
        'sec.lastUsed'         = 'laatst gebruikt op {0}'
        'sec.noTasks'          = 'Geen verdachte geplande taken'
        'sec.task'             = 'Geplande taak "{0}" start: {1}'
        'sec.avUnknown'        = 'De status van de virusbescherming kon niet worden gelezen'
        'sec.avOff'            = 'Er staat geen virusbescherming aan'
        'sec.avOld'            = '{0} staat aan, maar is {1} dagen niet bijgewerkt'
        'sec.avOutdated'       = '{0} staat aan, maar is niet bijgewerkt'
        'sec.avOk'             = '{0} staat aan en is bijgewerkt'
        'sec.threats'          = 'Bedreigingen tegengehouden, afgelopen 30 dagen: {0}'
        'sec.notifyNone'       = 'Geen websites mogen pop-upmeldingen sturen'
        'sec.notifyKnown'      = 'Bekende sites mogen meldingen sturen: {0}'
        'sec.notifySite'       = '{0} mag meldingen sturen ({1}, sinds {2})'
        'sec.notifySiteNoDate' = '{0} mag meldingen sturen ({1})'
        'sec.noProxy'          = 'Geen proxy ingesteld'
        'sec.hostsOk'          = 'Het hosts-bestand is normaal'
        'sec.hostsRedirect'    = 'Het hosts-bestand stuurt {0} naam/namen door: {1}'

        # ---- F: findings, and what to do about each
        'finding.remoteActive'   = '{0} draait op dit moment. Er kan nu iemand met deze pc verbonden zijn.'
        'advice.remoteActive'    = 'Verbreek eerst het internet: wifi uit of kabel eruit. Sluit dan het programma en vraag of de klant het kent. Zo niet: verwijder het na hun ja, bel de bank, en wijzig de wachtwoorden van e-mail en bank vanaf een ander apparaat.'
        'finding.remoteRecent'   = '{0} is kort geleden op deze pc gezet ({1}). Heeft de klant dat niet zelf gedaan, dan past het bij oplichting door een nep-helpdesk.'
        'advice.remoteRecent'    = 'Vraag de klant wie het op de pc heeft gezet. Was het een onbekende: verwijder het na hun ja, bel direct de bank, en wijzig de wachtwoorden van e-mail en bank vanaf een ander apparaat.'
        'finding.remoteOld'      = '{0} staat al langer op deze pc. Waarschijnlijk bewust, maar vraag het na.'
        'advice.remoteOld'       = 'Vraag of de klant of de familie het gebruikt. Gebruikt niemand het, dan sluit verwijderen een deur.'
        'finding.defenderOff'    = 'De virusbescherming staat uit.'
        'advice.defenderOff'     = 'Zet hem aan: Windows-beveiliging > Virus- en bedreigingsbeveiliging. Is een andere virusscanner verlopen, verwijder die dan zodat Microsoft Defender het overneemt.'
        'finding.avOld'          = 'De virusbescherming staat aan, maar is niet bijgewerkt.'
        'advice.avOld'           = 'Windows-beveiliging > Virus- en bedreigingsbeveiliging > Beveiligingsupdates > Controleren op updates. Lukt dat niet, kies dan E1.'
        'finding.threatsFound'   = 'De virusbescherming heeft de afgelopen 30 dagen {0} bedreiging(en) tegengehouden.'
        'advice.threatsFound'    = 'Open Windows-beveiliging > Beveiligingsgeschiedenis om te zien wat het was, en doe een volledige scan.'
        'finding.suspiciousTask' = 'De geplande taak "{0}" start een verborgen of gedownloade opdracht. Dat is typisch voor malware.'
        'advice.suspiciousTask'  = 'Na het ja van de klant kan Housecall hem hieronder uitschakelen (kan weer worden aangezet). Doe daarna een volledige scan in Windows-beveiliging.'
        'finding.unknownTask'    = 'De geplande taak "{0}" start een script op de achtergrond. Gewone programma''s doen dat ook, maar malware ook.'
        'advice.unknownTask'     = 'Vraag of de klant hem kent. Zo niet, dan kan Housecall hem hieronder uitschakelen (kan weer worden aangezet).'
        'finding.notifySites'    = '{0} website(s) mogen pop-upmeldingen tonen. Zo komen nep-virusmeldingen op het scherm.'
        'advice.notifySites'     = 'Blokkeer ze in de browser: Instellingen > Privacy en beveiliging > Site-instellingen > Meldingen. Bel nooit een telefoonnummer uit zo''n melding.'
        'finding.hostsRedirect'  = 'Het hosts-bestand stuurt namen van websites naar andere adressen.'
        'advice.hostsRedirect'   = 'Bekijk C:\Windows\System32\drivers\etc\hosts. Regels die de klant niet kent, mogen weg (beheerder nodig).'
        'finding.cleanPopup'     = 'Niets op deze pc verklaart de pop-up. Het was hoogstwaarschijnlijk een nepwebsite, geen echt virus.'
        'advice.cleanPopup'      = 'Zo''n pagina is onschuldig zodra hij dicht is: sluit de browser (Alt+F4, of Taakbeheer als hij niet sluit). Bel nooit het nummer dat erop staat. Heeft de klant wel gebeld: kies F2.'
        'finding.cleanCall'      = 'Geen programma voor overname op afstand of ander spoor van een indringer gevonden.'
        'advice.cleanCall'       = 'Vroeg de beller om bankgegevens of codes, bel dan toch de bank. Snelle hulp (Quick Assist) zit in Windows en laat na afloop niets achter.'
        'finding.cleanAll'       = 'Geen veiligheidsproblemen gevonden.'
        'advice.cleanAll'        = 'Houd Windows en de browser bijgewerkt. Echte bedrijven bellen nooit over een virus.'

        # ---- fixes and undo
        'fix.heading'      = 'Wat nu?'
        'fix.steps'        = 'Stap voor stap: zelf oplossen'
        'fix.stepOf'       = 'Stap {0} van {1}:'
        'fix.stepNext'     = 'Enter = volgende stap, 0 = stoppen'
        'fix.stepLast'     = 'Enter = klaar'
        'fix.enterBack'    = 'Enter = terug naar het menu'
        'fix.note.undo'    = '(kan worden teruggedraaid)'
        'fix.note.safe'    = '(veilig, verandert verder niets)'
        'fix.note.restart' = '(het programma kan gewoon weer worden gestart)'
        'fix.needsAdmin'   = '(beheerder nodig)'
        'fix.confirm'      = '{0}? (J/N)'
        'fix.dryRun'       = 'PROEFDRAAI: er is niets veranderd.'
        'fix.done'         = 'Gedaan.'
        'fix.failed'       = 'Dat lukte niet: {0}'
        'fix.adminHow'     = 'Hiervoor is beheerder nodig. Sluit dit venster, klik met rechts op de Startknop, kies Terminal (beheerder), en start Housecall opnieuw.'
        'fix.checkingAgain' = 'Opnieuw controleren of het gelukt is...'
        'fix.cancelled'    = 'Er is niets veranderd.'
        'fix.disableTask'  = 'Geplande taak "{0}" uitschakelen'
        'fix.stopRemote'   = '{0} nu afsluiten'
        'fix.proxyOff'     = 'De proxy uitzetten'
        'fix.flushDns'     = 'De DNS-cache legen'
        'fix.renewIp'      = 'De router om een nieuw adres vragen'
        'fix.disableTask.done' = 'Geplande taak "{0}" uitgeschakeld'
        'fix.stopRemote.done'  = '{0} afgesloten'
        'fix.proxyOff.done'    = 'Proxy uitgezet'
        'fix.flushDns.done'    = 'DNS-cache geleegd'
        'fix.renewIp.done'     = 'Nieuw adres van de router gekregen'
        'menu.undo'        = 'Wijzigingen terugdraaien'
        'undo.nothing'     = 'Er is niets om terug te draaien.'
        'undo.confirm'     = '{0} wijziging(en) van deze sessie terugdraaien? (J/N)'
        'undo.done'        = 'Teruggedraaid: {0}'
        'undo.failed'      = 'Kon niet terugdraaien: {0}'
        'sec.taskKnown'    = 'Geplande taak "{0}" hoort bij {1}, een bekend programma'
        'sec.taskDisabled' = 'Geplande taak "{0}" staat uit'

        # ---- step-by-step guides: steps.<finding id>, steps separated by |
        'steps.noAdapter'        = 'Klik met rechts op de Startknop en kies Apparaatbeheer. | Open "Netwerkadapters". Zoek een regel met een geel waarschuwingsteken. Ziet u niets, kies dan Beeld > Verborgen apparaten weergeven. | Noteer merk en model van de pc (vaak op een sticker aan de onderkant). | Download op een telefoon of andere pc het netwerkstuurprogramma van de supportsite van de fabrikant en zet het op een USB-stick. | Installeer het stuurprogramma, herstart de pc, en kies opnieuw A1.'
        'steps.wifiDisabled'     = 'Klik rechtsonder op het netwerk-icoon, naast de klok. | Is de tegel Wi-Fi grijs, klik er dan op zodat hij blauw wordt. | Is de tegel Vliegtuigstand blauw, klik er dan op om hem uit te zetten. | Probeer op een laptop ook de wifitoets op het toetsenbord (vaak Fn plus een toets met een antenne). | Kies opnieuw A1 om te controleren.'
        'steps.adapterOff'       = 'Open Instellingen (Windows-toets + I) en ga naar Netwerk en internet. | Klik op Geavanceerde netwerkinstellingen. | Zoek de adapter met Uitgeschakeld en klik ernaast op Inschakelen. | Kies opnieuw A1 om te controleren.'
        'steps.wifiNotConnected' = 'Klik rechtsonder op het netwerk-icoon, naast de klok. | Controleer of Vliegtuigstand uit staat. | Klik op het pijltje naast de tegel Wi-Fi om de netwerken te zien. | Kies het thuisnetwerk en klik op Verbinding maken. | Typ het wifi-wachtwoord: dat staat vaak op een sticker op de router. | Kies opnieuw A1 om te controleren.'
        'steps.cableUnplugged'   = 'Volg de kabel van de pc naar de router. | Druk de stekker aan beide kanten stevig aan tot hij klikt. Het lampje naast de aansluiting hoort te gaan knipperen. | Geen lampje? Probeer een andere aansluiting op de router. | Nog steeds niets? Probeer een andere kabel. | Kies opnieuw A1 om te controleren.'
        'steps.noAddress'        = 'Kies hierboven de oplossing om de router om een nieuw adres te vragen (beheerder nodig), of ga met de hand verder. | Trek de stekker uit de router, en uit het modem als dat een apart kastje is. | Wacht 30 seconden en steek de stekker er weer in. | Wacht ongeveer 3 minuten tot de lampjes rustig branden. | Kies opnieuw A1 om te controleren.'
        'steps.noGateway'        = 'Open Instellingen (Windows-toets + I) en ga naar Netwerk en internet. | Klik op Wi-Fi of Ethernet, en dan op de verbinding die gebruikt wordt (bij wifi: de eigenschappen). | Klik naast IP-toewijzing op Bewerken. | Kies Automatisch (DHCP) en klik op Opslaan. | Kies opnieuw A1 om te controleren.'
        'steps.gatewayDown'      = 'Kijk naar de router: branden de lampjes? | Trek de stekker uit de router, en uit het modem als dat een apart kastje is. | Wacht 30 seconden en steek de stekker er weer in. | Wacht ongeveer 3 minuten tot de lampjes rustig branden. | Kies opnieuw A1. Blijft de router donker, dan is hij misschien kapot: bel de provider.'
        'steps.internetDown'     = 'Kijk naar de router: het internet- of WAN-lampje is waarschijnlijk rood of uit. | Herstart modem en router: 30 seconden stroom eraf, daarna 3 minuten wachten. | Kijk op een telefoon met wifi uit of er een storing is bij de provider, bijvoorbeeld op allestoringen.nl. | Nog steeds geen internet? Bel de provider: het probleem zit buiten het huis. | Kies opnieuw A1 om te controleren.'
        'steps.dnsDown'          = 'Kies hierboven de oplossing om de DNS-cache te legen, of ga met de hand verder. | Open Instellingen (Windows-toets + I) > Netwerk en internet en klik op de verbinding die gebruikt wordt. | Klik naast Toewijzing van DNS-server op Bewerken. | Kies Automatisch (DHCP) en klik op Opslaan. | Kies opnieuw A1 om te controleren.'
        'steps.webIntercepted'   = 'Open een webbrowser en ga naar een willekeurige website, bijvoorbeeld nu.nl. | Verschijnt er een inlogpagina of "voorwaarden accepteren" (hotel, bibliotheek, gastnetwerk), vul die dan in. | Verschijnt er niets, kies dan F3 om naar een proxy of onbekende programma''s te zoeken. | Kies opnieuw A1 om te controleren.'
        'steps.proxy'            = 'Kies hierboven de oplossing om de proxy uit te zetten (kan worden teruggedraaid), of ga met de hand verder. | Open Instellingen (Windows-toets + I) > Netwerk en internet > Proxy. | Klik bij Handmatige proxy-instelling op Bewerken en zet "Een proxyserver gebruiken" uit. | Zet bij Automatische proxy-instelling "Installatiescript gebruiken" uit. | Kies F3 om het programma te zoeken dat hem heeft ingesteld.'
        'steps.weakSignal'       = 'Loop met de laptop naar de router en kies opnieuw A1. Daar sterk? Dan is de afstand het probleem. | Haal de router uit kasten, van de vloer, en weg van metaal. | Heeft de router twee netwerken (2,4 en 5 GHz), gebruik dan 2,4 GHz in kamers ver weg. | In een groot huis helpt een wifi-versterker of mesh-punt halverwege.'
        'steps.unstable'         = 'Herstart de router: 30 seconden stroom eraf, daarna 3 minuten wachten. | Ga dichter bij de router zitten en kies opnieuw A2. | Zet grote downloads, streamen en videobellen op andere apparaten even stil en test opnieuw. | Nog steeds onstabiel? Gebruik een netwerkkabel, of vraag de provider om een nieuwe router.'
        'steps.dropsMany'        = 'Klik met rechts op de Startknop en kies Apparaatbeheer. | Open Netwerkadapters en dubbelklik op de wifi-adapter. | Haal op het tabblad Energiebeheer het vinkje weg bij "De computer mag dit apparaat uitschakelen om energie te besparen". | Klik op het tabblad Stuurprogramma op Stuurprogramma bijwerken > Automatisch naar stuurprogramma''s zoeken. | Herstart de router en de pc.'
        'steps.connHealthy'      = 'Sluit andere programma''s en browsertabbladen. | Open speedtest.net op deze pc en klik op Go. | Vergelijk de downloadsnelheid met het abonnement (op de rekening of de website van de provider). | Veel lager? Test opnieuw met een netwerkkabel. Nog steeds laag: bel de provider. | Alleen ''s avonds traag? Dan is het druk bij de provider.'
        'steps.siteHosts'        = 'Open Kladblok als administrator: typ Kladblok in Start, klik er met rechts op, kies Als administrator uitvoeren. | Kies Bestand > Openen, zet het bestandstype op Alle bestanden, en plak: C:\Windows\System32\drivers\etc\hosts | Verwijder de regel met de naam van de site en sla op. | Kies F3 om te zoeken wat hem daar heeft neergezet.'
        'steps.siteNotFound'     = 'Controleer samen met de klant de spelling van het adres. | Zoek de naam van de site op in een zoekmachine in plaats van het adres te typen. | Probeer het op een telefoon: lukt het daar ook niet, dan ligt de site eruit of bestaat hij niet meer.'
        'steps.siteBlocked'      = 'Probeer de site op een telefoon met wifi uit. | Werkt het daar wel? Zet de virusscanner of firewall op deze pc even op pauze en probeer het opnieuw. | Helpt dat, voeg de site dan toe als uitzondering in dat beveiligingsprogramma, en zet de beveiliging weer aan.'
        'steps.siteError'        = 'Wacht 15 minuten en probeer het opnieuw. | Kijk op een telefoon of de site daar ook een fout geeft. | Zoek naar een storing van de site, bijvoorbeeld op allestoringen.nl.'
        'steps.siteOk'           = 'Open de site in de browser en druk op Ctrl + F5 om hem helemaal opnieuw te laden. | Nog steeds mis? Probeer het in een andere browser, bijvoorbeeld Edge. | Werkt het daar wel? In de eerste browser: Instellingen > Privacy > Browsegegevens wissen (cookies en cache). | Nog steeds mis? Zet browserextensies een voor een uit. | Bij een app: werk hem bij, of verwijder hem en installeer hem opnieuw.'
        'steps.remoteActive'     = 'Verbreek het internet: zet wifi uit (netwerk-icoon rechtsonder) of trek de netwerkkabel eruit. | Kies hierboven de oplossing om het programma af te sluiten. | Vraag of de klant het programma kent, en wie vroeg om het te installeren. | Was het een onbekende: bel direct de bank, op het nummer op de bankpas. | Wijzig de wachtwoorden van e-mail en bank vanaf een ander apparaat, niet vanaf deze pc. | Kies F3 voor een volledige controle.'
        'steps.remoteRecent'     = 'Vraag de klant wie het programma op de pc heeft gezet, en wanneer ze die persoon voor het laatst spraken. | Was het een onbekende: bel direct de bank, op het nummer op de bankpas. | Verwijder het programma: Instellingen > Apps, zoek het in de lijst, klik op de drie puntjes ernaast en kies Verwijderen. | Wijzig de wachtwoorden van e-mail en bank vanaf een ander apparaat. | Kies opnieuw F2 om te controleren.'
        'steps.remoteOld'        = 'Vraag of de klant of de familie het programma gebruikt. | Gebruikt niemand het: Instellingen > Apps, zoek het in de lijst, klik op de drie puntjes ernaast en kies Verwijderen. | Kies opnieuw F2 om te controleren.'
        'steps.defenderOff'      = 'Typ Windows-beveiliging in Start en open het. | Klik op Virus- en bedreigingsbeveiliging. | Staat er een andere virusscanner die verlopen is? Verwijder die: Instellingen > Apps, zoek hem in de lijst, drie puntjes, Verwijderen. | Klik bij Instellingen voor virus- en bedreigingsbeveiliging op Instellingen beheren en zet Realtime-beveiliging aan. | Kies opnieuw F3 om te controleren.'
        'steps.avOld'            = 'Typ Windows-beveiliging in Start en open het. | Klik op Virus- en bedreigingsbeveiliging. | Klik bij Beveiligingsupdates op Controleren op updates. | Lukt dat niet? Kies E1 om Windows Update te controleren.'
        'steps.threatsFound'     = 'Typ Windows-beveiliging in Start en open het. | Klik op Virus- en bedreigingsbeveiliging > Beveiligingsgeschiedenis. | Bekijk wat er gevonden is, en of er Verwijderd of In quarantaine staat. | Ga terug, klik op Scanopties, kies Volledige scan en klik op Nu scannen. Laat hem afmaken.'
        'steps.suspiciousTask'   = 'Kies hierboven de oplossing om de taak uit te schakelen (kan weer worden aangezet). | Typ Windows-beveiliging in Start en open het. | Klik op Virus- en bedreigingsbeveiliging > Scanopties, kies Microsoft Defender Offline-scan en klik op Nu scannen. De pc start hiervoor opnieuw op. | Kies daarna opnieuw F3.'
        'steps.unknownTask'      = 'Vraag of de klant het programma kent waar de taak "{0}" bij hoort. | Zoek de naam "{0}" online op om te zien van welk programma hij is. | Onbekend en niet nodig? Kies hierboven de oplossing om hem uit te schakelen (kan weer worden aangezet).'
        'steps.notifySites'      = 'Open de browser die naast de site staat. | Chrome, Edge of Brave: Instellingen > Privacy en beveiliging > Site-instellingen > Meldingen. | Klik onder "Toegestaan om meldingen te sturen" op de drie puntjes naast elke onbekende site en kies Blokkeren of Verwijderen. | Zeg tegen de klant: een pop-up met een telefoonnummer is nooit echt. Sluit hem, en bel nooit.'
        'steps.hostsRedirect'    = 'Open Kladblok als administrator: typ Kladblok in Start, klik er met rechts op, kies Als administrator uitvoeren. | Kies Bestand > Openen, zet het bestandstype op Alle bestanden, en plak: C:\Windows\System32\drivers\etc\hosts | Verwijder de regels die de klant niet kent en sla op. | Kies opnieuw F3 om te controleren.'
        'steps.cleanPopup'       = ('Staat de pop-up nog op het scherm? Druk op Ctrl + Shift + Esc om Taakbeheer te openen. | Selecteer de browser en klik op Taak be' + [char]0xEB + 'indigen. | Open de browser opnieuw. Vraagt hij om de tabbladen terug te zetten, zeg dan nee. | Zeg tegen de klant: zulke pagina''s zien er eng uit maar doen niets zodra ze dicht zijn. Bel nooit het nummer.')
        'steps.cleanCall'        = 'Vraag wat de beller deed: keek hij mee op het scherm, of vroeg hij om codes of bankgegevens? | Vroeg hij om bankgegevens of codes: bel de bank op het nummer op de bankpas. | Wijzig het wachtwoord van de e-mail vanaf een ander apparaat. | Zeg tegen de klant: banken en Microsoft bellen nooit over een virus.'

        # ---- the client note
        'note.title'          = 'Housecall, {0}'
        'note.asked'          = 'Waar u hulp bij vroeg'
        'note.found'          = 'Wat er gevonden is'
        'note.done'           = 'Wat er is gedaan'
        'note.nothingChanged' = 'Er is niets veranderd aan deze pc.'
        'note.notFixed'       = 'Nog niet opgelost'
        'note.notFixedItem'   = 'Niet opgelost: {0}'
        'note.contact'        = 'Vragen?'
        'note.footer'         = 'Dit briefje wordt nergens bewaard: het verdwijnt als u het sluit. Druk het af als u het wilt houden.'
        'note.print'          = 'Afdrukken'
        'note.close'          = 'Sluiten'
        'note.windowTitle'    = 'Housecall - briefje'

        # ---- restarting as administrator
        'fix.elevateAsk'      = 'Hiervoor is beheerder nodig. Housecall nu opnieuw starten als beheerder? Windows vraagt om toestemming. (J/N)'
        'fix.elevated'        = 'Housecall gaat verder in het nieuwe beheerdersvenster. Dit venster mag dicht.'
        'fix.elevateFailed'   = 'Windows heeft het beheerdersvenster niet gestart ({0}).'

        # ---- C: check lines
        'dev.spoolerStopped'     = 'De afdrukservice (Afdrukspooler) draait niet'
        'dev.spoolerOk'          = 'De afdrukservice draait'
        'dev.noPrinter'          = 'Geen printer aanwezig, alleen: {0}'
        'dev.printerReady'       = '{0} is klaar voor gebruik'
        'dev.printerReadyDefault' = '{0} is klaar voor gebruik en is de standaardprinter'
        'dev.printerOffline'     = '{0} staat offline'
        'dev.printerUnreachable' = '{0} antwoordt niet op het netwerk ({1})'
        'dev.printerState'       = '{0}: {1}'
        'dev.state.3'            = 'het papier raakt op'
        'dev.state.4'            = 'het papier is op'
        'dev.state.5'            = 'de inkt of toner raakt op'
        'dev.state.6'            = 'de inkt of toner is op'
        'dev.state.7'            = 'er staat een klep of deur open'
        'dev.state.8'            = 'papier vastgelopen'
        'dev.state.10'           = 'heeft onderhoud nodig'
        'dev.state.11'           = 'de uitvoerlade is vol'
        'dev.defaultVirtual'     = '{0} is de standaardprinter, dus documenten gaan daarheen in plaats van op papier'
        'dev.noDefault'          = 'Er is geen standaardprinter ingesteld'
        'dev.jobsStuck'          = '{0} document(en) vastgelopen in de wachtrij, het oudste sinds {1}'
        'dev.jobsOk'             = 'De afdrukwachtrij is leeg'
        'dev.keyboardOk'         = 'Toetsenbord gevonden'
        'dev.noKeyboard'         = 'Geen toetsenbord gevonden'
        'dev.pointerOk'          = 'Muis of touchpad gevonden'
        'dev.noPointer'          = 'Geen muis of touchpad gevonden'
        'dev.usbDrive'           = 'USB-schijf "{0}" is aangesloten als {1}'
        'dev.usbNoLetter'        = 'USB-schijf "{0}" is aangesloten maar heeft geen stationsletter'
        'dev.noDeviceErrors'     = 'Geen apparaten met problemen'
        'dev.deviceProblem'      = '{0}: {1}'
        'dev.code.10'            = 'kon niet starten'
        'dev.code.22'            = 'uitgeschakeld'
        'dev.code.28'            = 'geen stuurprogramma'
        'dev.code.43'            = 'heeft een probleem gemeld'
        'dev.codeOther'          = 'foutcode {0}'
        'dev.btAdapter'          = 'Bluetooth-adapter "{0}" werkt'
        'dev.btNoAdapter'        = 'Geen Bluetooth-adapter gevonden'
        'dev.btServiceOk'        = 'De Bluetooth-service draait'
        'dev.btServiceStopped'   = 'De Bluetooth-service draait niet'
        'dev.btPaired'           = 'Gekoppeld: {0}'
        'dev.btConnected'        = '{0} (verbonden)'
        'dev.btNotConnected'     = '{0} (niet verbonden)'
        'dev.btNonePaired'       = 'Geen apparaten gekoppeld'

        # ---- C: findings, and what to do about each
        'finding.spoolerStopped'     = 'De afdrukservice draait niet, dus er kan niets worden afgedrukt.'
        'advice.spoolerStopped'      = 'Housecall kan hem hieronder starten (beheerder nodig).'
        'finding.noPrinter'          = 'Er is geen printer aanwezig op deze pc.'
        'advice.noPrinter'           = 'Voeg de printer toe: Instellingen > Bluetooth en apparaten > Printers en scanners > Apparaat toevoegen. De stappen hieronder lopen het door.'
        'finding.printerUnreachable' = 'De printer {0} is niet bereikbaar via het netwerk.'
        'advice.printerUnreachable'  = 'Controleer of de printer aan staat en op dezelfde wifi zit als deze pc. De printer herstarten helpt vaak.'
        'finding.printerOffline'     = 'Windows ziet de printer {0} als offline.'
        'advice.printerOffline'      = 'Zet de printer uit en weer aan en controleer de kabel of wifi. Kies daarna opnieuw C1.'
        'finding.printerAttention'   = 'De printer {0} meldt: {1}.'
        'advice.printerAttention'    = 'Los het op bij de printer zelf (papier, inkt, klep, vastgelopen papier) en kies daarna opnieuw C1.'
        'finding.jobsStuck'          = 'Er zitten documenten vast in de afdrukwachtrij, en die houden alles erachter tegen.'
        'advice.jobsStuck'           = 'Housecall kan de wachtrij hieronder legen. De vastgelopen documenten moeten daarna opnieuw worden afgedrukt.'
        'finding.defaultVirtual'     = 'Documenten gaan naar {0} in plaats van naar de printer.'
        'advice.defaultVirtual'      = 'Housecall kan de echte printer hieronder standaard maken (kan worden teruggedraaid).'
        'finding.noDefault'          = 'Er is geen standaardprinter, dus programma''s weten niet waar ze moeten afdrukken.'
        'advice.noDefault'           = 'Housecall kan de printer hieronder standaard maken (kan worden teruggedraaid).'
        'finding.printerReady'       = 'De printer lijkt klaar voor gebruik.'
        'advice.printerReady'        = 'Housecall kan hieronder een testpagina afdrukken. Komt die eruit, dan zit het probleem in het programma: kijk naar welke printer het afdrukt.'
        'finding.deviceDisabled'     = '{0} is uitgeschakeld in Windows.'
        'advice.deviceDisabled'      = 'Housecall kan het hieronder weer inschakelen (beheerder nodig, kan worden teruggedraaid).'
        'finding.deviceNoDriver'     = 'Windows heeft geen stuurprogramma voor {0}.'
        'advice.deviceNoDriver'      = 'Laat Windows het stuurprogramma zoeken, of haal het van de site van de fabrikant. De stappen hieronder lopen het door.'
        'finding.deviceError'        = '{0} heeft een probleem: {1}.'
        'advice.deviceError'         = 'Haal het eruit, wacht 10 seconden, en steek het in een andere USB-poort. Of laat Housecall het hieronder herstarten (beheerder nodig).'
        'finding.usbNoLetter'        = '{0} is aangesloten maar heeft geen stationsletter, dus hij staat niet in Verkenner.'
        'advice.usbNoLetter'         = 'Geef hem een letter in Schijfbeheer. De stappen hieronder lopen het door.'
        'finding.noPointer'          = 'Windows vindt geen muis of touchpad.'
        'advice.noPointer'           = 'Steek de muis in een andere USB-poort. Bij een draadloze muis: nieuwe batterij, en controleer het kleine ontvangertje.'
        'finding.devicesOk'          = 'Alle aangesloten apparaten werken zonder fouten.'
        'advice.devicesOk'           = 'Probeer een andere USB-poort. Doet een apparaat nog steeds niets, probeer het dan op een andere pc om te zien of het apparaat zelf kapot is.'
        'finding.btNoAdapter'        = 'Deze pc heeft geen werkende Bluetooth-adapter.'
        'advice.btNoAdapter'         = 'Veel desktop-pc''s hebben geen Bluetooth. Een kleine USB Bluetooth-adapter lost dat op.'
        'finding.btServiceStopped'   = 'De Bluetooth-service draait niet.'
        'advice.btServiceStopped'    = 'Housecall kan hem hieronder starten (beheerder nodig).'
        'finding.btOk'               = 'Bluetooth werkt op deze pc.'
        'advice.btOk'                = 'Wil een apparaat niet verbinden: verwijder het in Instellingen en koppel het opnieuw. De stappen hieronder lopen het door.'

        # ---- C: fixes
        'fix.note.reprint'          = '(de vastgelopen documenten moeten opnieuw worden afgedrukt)'
        'fix.startSpooler'          = 'De afdrukservice starten'
        'fix.startSpooler.done'     = 'Afdrukservice gestart'
        'fix.restartSpooler'        = 'De wachtrij legen en de afdrukservice herstarten'
        'fix.restartSpooler.done'   = 'Wachtrij geleegd en afdrukservice herstart'
        'fix.clearJobs'             = 'De vastgelopen documenten uit de wachtrij halen'
        'fix.clearJobs.done'        = 'Vastgelopen documenten uit de wachtrij gehaald'
        'fix.setDefault'            = '{0} de standaardprinter maken'
        'fix.setDefault.done'       = '{0} is de standaardprinter gemaakt'
        'fix.printTestPage'         = 'Een testpagina afdrukken op {0}'
        'fix.printTestPage.done'    = 'Testpagina afgedrukt op {0}'
        'fix.enableDevice'          = '{0} weer inschakelen'
        'fix.enableDevice.done'     = '{0} weer ingeschakeld'
        'fix.restartDevice'         = '{0} herstarten'
        'fix.restartDevice.done'    = '{0} herstart'
        'fix.startBtService'        = 'De Bluetooth-service starten'
        'fix.startBtService.done'   = 'Bluetooth-service gestart'

        # ---- C: step-by-step guides
        'steps.spoolerStopped'     = 'Kies hierboven de oplossing om hem te starten (beheerder nodig), of doe het met de hand. | Typ Services in Start en open het. | Zoek Afdrukspooler en dubbelklik erop. | Zet Opstarttype op Automatisch, klik op Starten en daarna op OK. | Kies opnieuw C1 om te controleren.'
        'steps.noPrinter'          = 'Zet de printer aan en sluit hem aan: een USB-kabel, of dezelfde wifi als deze pc. | Open Instellingen (Windows-toets + I) > Bluetooth en apparaten > Printers en scanners. | Klik op Apparaat toevoegen en wacht tot de printer verschijnt, klik dan ernaast op Apparaat toevoegen. | Staat hij er niet bij? Klik op "Handmatig toevoegen", of installeer de software van de site van de printerfabrikant. | Kies opnieuw C1 om te controleren.'
        'steps.printerUnreachable' = 'Controleer of de printer aan staat en geen foutmelding op zijn scherm heeft. | Controleer of hij op dezelfde wifi zit als deze pc (in het menu van de printer, vaak onder Netwerk of Wi-Fi). | Zet de printer uit, wacht 10 seconden, en zet hem weer aan. Wacht tot hij klaar is. | Antwoordt hij nog steeds niet? Herstart dan ook de router. | Kies opnieuw C1 om te controleren.'
        'steps.printerOffline'     = 'Zet de printer uit en weer aan, en controleer de USB-kabel of wifi. | Open Instellingen > Bluetooth en apparaten > Printers en scanners en klik op de printer. | Klik op Afdrukwachtrij openen. Controleer in het menu Printer dat "Printer offline gebruiken" niet is aangevinkt. | Kies opnieuw C1 om te controleren.'
        'steps.printerAttention'   = 'Kijk naar het scherm of de lampjes van de printer: die zeggen wat er mis is. | Doe er papier in, vervang de inkt of toner, sluit alle kleppen, of trek vastgelopen papier er voorzichtig uit. | Zet de printer uit en weer aan. | Kies opnieuw C1 om te controleren.'
        'steps.jobsStuck'          = 'Kies hierboven een oplossing om de wachtrij te legen, of doe het met de hand. | Open Instellingen > Bluetooth en apparaten > Printers en scanners, klik op de printer en dan op Afdrukwachtrij openen. | Klik in het menu Printer op Alle documenten annuleren. | Gaan ze niet weg? Herstart de pc. | Druk het document opnieuw af.'
        'steps.defaultVirtual'     = 'Kies hierboven de oplossing om de echte printer standaard te maken (kan worden teruggedraaid), of doe het met de hand. | Open Instellingen > Bluetooth en apparaten > Printers en scanners. | Zet "Windows mijn standaardprinter laten beheren" uit. | Klik op de echte printer en dan op Als standaard instellen. | Druk opnieuw af.'
        'steps.noDefault'          = 'Kies hierboven de oplossing om een standaardprinter in te stellen (kan worden teruggedraaid), of doe het met de hand. | Open Instellingen > Bluetooth en apparaten > Printers en scanners. | Zet "Windows mijn standaardprinter laten beheren" uit. | Klik op de printer en dan op Als standaard instellen. | Druk opnieuw af.'
        'steps.printerReady'       = 'Kies hierboven de oplossing om een testpagina af te drukken. | Komt hij eruit? Dan werkt de printer: kijk in het programma welke printer er in het venster Afdrukken is gekozen. | Komt er niets uit? Zet de printer uit en weer aan, en kies opnieuw C1. | Nog steeds niets? Verwijder de printer in Instellingen > Printers en scanners en voeg hem opnieuw toe.'
        'steps.deviceDisabled'     = 'Kies hierboven de oplossing om het weer in te schakelen (beheerder nodig), of doe het met de hand. | Klik met rechts op de Startknop en kies Apparaatbeheer. | Zoek het apparaat (het heeft een klein pijltje naar beneden), klik er met rechts op en kies Apparaat inschakelen. | Kies hetzelfde probleem opnieuw om te controleren.'
        'steps.deviceNoDriver'     = 'Klik met rechts op de Startknop en kies Apparaatbeheer. | Klik met rechts op het apparaat met het gele waarschuwingsteken en kies Stuurprogramma bijwerken > Automatisch naar stuurprogramma''s zoeken. | Niet gevonden? Download het stuurprogramma van de site van de fabrikant. | Herstart de pc en kies hetzelfde probleem opnieuw.'
        'steps.deviceError'        = 'Haal het apparaat eruit, wacht 10 seconden, en steek het in een andere USB-poort (bij een desktop: een aan de achterkant). | Of kies hierboven de oplossing om het te herstarten (beheerder nodig). | Nog steeds mis? Klik met rechts op Start > Apparaatbeheer, klik met rechts op het apparaat, kies Apparaat verwijderen en herstart de pc: Windows installeert het opnieuw. | Kies hetzelfde probleem opnieuw om te controleren.'
        'steps.usbNoLetter'        = 'Klik met rechts op de Startknop en kies Schijfbeheer. | Zoek de USB-schijf in de onderste helft (er staat Verwisselbaar bij). | Klik met rechts op de partitie, kies Stationsletter en paden wijzigen > Toevoegen, kies een letter en klik op OK. | Open Verkenner: de schijf staat er nu bij. | Staat er Niet-toegewezen of RAW? Dan is de stick misschien leeg of beschadigd: formatteer hem niet voordat duidelijk is of de bestanden nodig zijn.'
        'steps.noPointer'          = 'Steek de muis in een andere USB-poort. | Draadloze muis: doe er een nieuwe batterij in, en controleer of het kleine ontvangertje erin zit. | Laptop: druk op de touchpadtoets (vaak Fn plus een toets met een touchpad-plaatje). | Gebruik intussen het toetsenbord: Tab en de pijltjestoetsen verplaatsen, Enter klikt.'
        'steps.devicesOk'          = 'Haal het apparaat eruit en steek het in een andere USB-poort. | Herstart de pc met het apparaat aangesloten. | Probeer het apparaat op een andere pc: lukt het daar ook niet, dan is het apparaat zelf kapot. | Kies opnieuw C2.'
        'steps.btNoAdapter'        = 'Kijk of deze pc wel Bluetooth heeft: veel desktop-pc''s niet. | Laptop: controleer of de vliegtuigstand uit staat (netwerk-icoon rechtsonder). | Geen Bluetooth? Een kleine USB Bluetooth-adapter lost het op: steek hem erin en kies opnieuw C3.'
        'steps.btServiceStopped'   = 'Kies hierboven de oplossing om hem te starten (beheerder nodig), of doe het met de hand. | Typ Services in Start en open het. | Zoek Bluetooth-ondersteuningsservice en dubbelklik erop. | Zet Opstarttype op Handmatig, klik op Starten en daarna op OK. | Kies opnieuw C3 om te controleren.'
        'steps.btOk'               = 'Open Instellingen (Windows-toets + I) > Bluetooth en apparaten en controleer of Bluetooth op Aan staat. | Zet het apparaat (koptelefoon, speaker, muis) uit en aan, en zet het in koppelstand: vaak de Bluetooth-knop ingedrukt houden tot een lampje knippert. | Klik in Instellingen op de drie puntjes naast het apparaat en kies Apparaat verwijderen. | Klik op Apparaat toevoegen > Bluetooth en kies het apparaat uit de lijst. | Kies opnieuw C3 om te controleren.'

        # ---- B: check lines
        'snd.serviceStopped' = 'De geluidsservice (Windows Audio) draait niet'
        'snd.serviceOk'      = 'De geluidsservice draait'
        'snd.noOutput'       = 'Geen luidspreker of koptelefoon gevonden'
        'snd.default'        = 'Geluid gaat naar {0}, volume {1}%'
        'snd.muted'          = '{0} staat gedempt'
        'snd.volumeLow'      = 'Het volume van {0} staat op {1}%'
        'snd.defaultScreen'  = '{0} is een beeldscherm of digitale uitgang: zonder speakers daar hoort u niets'
        'snd.others'         = 'Andere uitgangen: {0}'
        'call.mic'           = 'Microfoon: {0}, niveau {1}%'
        'call.noMic'         = 'Geen microfoon gevonden'
        'call.micMuted'      = 'Microfoon {0} staat gedempt'
        'call.micLow'        = 'Microfoon {0} staat heel zacht ({1}%)'
        'call.camera'        = 'Camera: {0}'
        'call.noCamera'      = 'Geen camera gevonden'
        'call.privacyOk'     = 'Apps mogen de {0} gebruiken'
        'call.blocked'       = '{0} mag de {1} niet gebruiken'
        'priv.microphone'    = 'microfoon'
        'priv.webcam'        = 'camera'
        'priv.all'           = 'Geen enkele app op deze pc'
        'priv.apps'          = 'Apps'
        'priv.desktop'       = 'Bureaubladprogramma''s (Zoom, Teams, Skype)'
        'scr.brightness'     = 'Helderheid: {0}%'
        'scr.tooDark'        = 'De helderheid van het scherm staat heel laag ({0}%)'
        'scr.colorFilter'    = 'Er staat een kleurenfilter aan (bijvoorbeeld zwart-wit)'
        'scr.highContrast'   = 'Hoog contrast staat aan'
        'scr.magnifier'      = 'Het Vergrootglas staat open'
        'scr.normal'         = 'Geen kleurenfilter, hoog contrast of Vergrootglas aan'
        'scr.rotated'        = 'Het hoofdscherm staat rechtop (staand)'
        'scr.scale'          = 'Schaal {0}%, tekstgrootte {1}%'

        # ---- B: findings, and what to do about each
        'finding.audioServiceStopped' = 'De geluidsservice draait niet, dus er kan geen geluid klinken.'
        'advice.audioServiceStopped'  = 'Housecall kan hem hieronder herstarten (beheerder nodig).'
        'finding.noOutput'            = 'Windows vindt geen luidspreker of koptelefoon.'
        'advice.noOutput'             = 'Controleer of de speakers zijn aangesloten en aan staan. Een scherm dat voor geluid wordt gebruikt, moet aan staan.'
        'finding.muted'               = 'Het geluid staat gedempt op {0}.'
        'advice.muted'                = 'Housecall kan het hieronder weer aanzetten (kan worden teruggedraaid).'
        'finding.volumeLow'           = 'Het volume van {0} staat bijna uit ({1}%).'
        'advice.volumeLow'            = 'Housecall kan het hieronder harder zetten (kan worden teruggedraaid).'
        'finding.defaultScreen'       = 'Geluid gaat naar {0}, en dat is waarschijnlijk niet waar de klant luistert.'
        'advice.defaultScreen'        = 'Kies hieronder de speakers of koptelefoon. Kan worden teruggedraaid.'
        'finding.soundOk'             = 'Windows stuurt geluid naar {0}, en dat staat aan.'
        'advice.soundOk'              = 'Speel hieronder een testgeluid af. Hoort u niets? Controleer de stroom en de volumeknop van de speaker, of kies hieronder een andere uitgang.'
        'finding.privacyBlocked'      = '{0} mag de {1} niet gebruiken. Daarom kan de ander de klant niet horen of zien.'
        'advice.privacyBlocked'       = 'Housecall kan het hieronder toestaan (kan worden teruggedraaid).'
        'finding.micMuted'            = 'De microfoon {0} staat gedempt.'
        'advice.micMuted'             = 'Housecall kan het dempen hieronder opheffen (kan worden teruggedraaid).'
        'finding.noMic'               = 'Windows vindt geen microfoon.'
        'advice.noMic'                = 'Sluit de headset of webcam met de microfoon aan, of controleer de kabel.'
        'finding.micLow'              = 'De microfoon {0} staat heel zacht.'
        'advice.micLow'               = 'Housecall kan hem hieronder harder zetten (kan worden teruggedraaid).'
        'finding.noCamera'            = 'Windows vindt geen camera.'
        'advice.noCamera'             = 'Sluit de webcam aan. Kijk op een laptop of er een klein schuifje voor de lens zit, of een cameratoets.'
        'finding.callsOk'             = 'De microfoon en camera werken, en apps mogen ze gebruiken.'
        'advice.callsOk'              = 'Kijk in de belapp zelf welke microfoon en camera er gekozen zijn (vaak onder Instellingen > Audio en video).'
        'finding.tooDark'             = 'Het scherm staat heel donker ({0}%).'
        'advice.tooDark'              = 'Housecall kan het hieronder lichter maken (kan worden teruggedraaid).'
        'finding.colorFilter'         = 'Er staat een kleurenfilter aan, waardoor het scherm zwart-wit of vreemd gekleurd is. Vaak per ongeluk aangezet met Windows-toets + Ctrl + C.'
        'advice.colorFilter'          = 'Druk op Windows-toets + Ctrl + C, of zet het uit in Instellingen. De stappen hieronder lopen het door.'
        'finding.highContrast'        = 'Hoog contrast staat aan: een zwarte achtergrond en felle kleuren. Vaak per ongeluk aangezet.'
        'advice.highContrast'         = 'Druk op linker Alt + linker Shift + Print Screen, of zet het uit in Instellingen. De stappen hieronder lopen het door.'
        'finding.magnifier'           = 'Het Vergrootglas staat open: het maakt alles groot en volgt de muis.'
        'advice.magnifier'            = 'Housecall kan het hieronder sluiten. Windows-toets + Esc sluit het ook.'
        'finding.rotated'             = 'Het hoofdscherm staat op zijn kant.'
        'advice.rotated'              = 'Draai het terug met de stappen hieronder. Staat het scherm echt rechtop, dan is dit in orde.'
        'finding.screenOk'            = 'Er staat niets aan dat het uiterlijk van het scherm verandert.'
        'advice.screenOk'             = 'Om alles groter te maken voor de klant: zie de stappen hieronder.'

        # ---- B: fixes
        'fix.restartAudio'            = 'De geluidsservice herstarten'
        'fix.restartAudio.done'       = 'Geluidsservice herstart'
        'fix.setDefaultAudio'         = 'Geluid afspelen via {0}'
        'fix.setDefaultAudio.done'    = 'Geluid gaat nu via {0}'
        'fix.unmute'                  = '{0} niet meer dempen'
        'fix.unmute.done'             = '{0} niet meer gedempt'
        'fix.setVolume'               = 'Het volume van {0} hoger zetten'
        'fix.setVolume.done'          = 'Volume van {0} hoger gezet'
        'fix.testSound'               = 'Een testgeluid afspelen'
        'fix.testSound.done'          = 'Testgeluid afgespeeld'
        'fix.allowAccess'             = 'Toestaan: {0}'
        'fix.allowAccess.done'        = 'Toegestaan: {0}'
        'fix.allowAccessMachine'      = 'Toestaan voor de hele pc: {0}'
        'fix.allowAccessMachine.done' = 'Toegestaan voor de hele pc: {0}'
        'fix.setBrightness'           = 'Het scherm lichter maken (80%)'
        'fix.setBrightness.done'      = 'Scherm lichter gemaakt'
        'fix.closeMagnifier'          = 'Het Vergrootglas sluiten'
        'fix.closeMagnifier.done'     = 'Vergrootglas gesloten'

        # ---- B: step-by-step guides
        'steps.audioServiceStopped' = 'Kies hierboven de oplossing om hem te herstarten (beheerder nodig), of doe het met de hand. | Typ Services in Start en open het. | Zoek Windows Audio, klik er met rechts op en kies Opnieuw starten (of Starten). | Kies opnieuw B1 om te controleren.'
        'steps.noOutput'            = 'Controleer of de speakers of koptelefoon zijn aangesloten (bij een desktop de groene aansluiting) en aan staan. | Gebruikt u het geluid van een scherm of tv? Zet die aan en controleer het volume daarvan. | Bluetooth-koptelefoon: kies C3 om de verbinding te controleren. | Herstart de pc en kies opnieuw B1.'
        'steps.muted'               = 'Kies hierboven de oplossing om het dempen op te heffen, of doe het met de hand. | Klik rechtsonder op het luidspreker-icoon, naast de klok. | Klik op het luidsprekersymbool naast de volumeschuif, zodat er geen kruisje meer staat. | Speel iets af om te controleren.'
        'steps.volumeLow'           = 'Kies hierboven de oplossing om het harder te zetten, of doe het met de hand. | Klik rechtsonder op het luidspreker-icoon, naast de klok. | Sleep de volumeschuif naar ongeveer de helft. | Controleer ook de volumeknop op de speakers zelf.'
        'steps.defaultScreen'       = 'Kies hierboven de juiste uitgang (kan worden teruggedraaid), of doe het met de hand. | Klik rechtsonder op het luidspreker-icoon, en dan op het pijltje naast de volumeschuif. | Kies de speakers of koptelefoon uit de lijst. | Speel iets af om te controleren.'
        'steps.soundOk'             = 'Kies hierboven "Een testgeluid afspelen" en luister. | Hoort u niets? Controleer de stroom, de kabel en de volumeknop van de speakers. | Probeer hierboven een andere uitgang, bijvoorbeeld de koptelefoon. | Ontbreekt het geluid maar in een programma (een browsertabblad, een video)? Controleer het volume in dat programma, en klik met rechts op het luidspreker-icoon > Volumemixer.'
        'steps.privacyBlocked'      = 'Kies hierboven de oplossing om het toe te staan (kan worden teruggedraaid), of doe het met de hand. | Open Instellingen (Windows-toets + I) > Privacy en beveiliging > Microfoon (of Camera). | Zet "Toegang tot microfoon", "Apps toegang geven tot uw microfoon" en "Bureaublad-apps toegang geven tot uw microfoon" aan (bij de camera: dezelfde drie). | Zet in de lijst daaronder de belapp aan (WhatsApp, Teams, ...). | Sluit de belapp, open hem opnieuw, en probeer te bellen.'
        'steps.micMuted'            = 'Kies hierboven de oplossing om het dempen op te heffen, of doe het met de hand. | Open Instellingen (Windows-toets + I) > Systeem > Geluid. | Klik onder Invoer op de microfoon en controleer dat hij niet gedempt is. Zet het volume op ongeveer 80. | Kijk ook of er een dempknop op de headset of de kabel zit.'
        'steps.noMic'               = 'Sluit de headset of webcam met de microfoon aan. Headset met twee stekkers: de roze is de microfoon. | Open Instellingen > Systeem > Geluid en kijk onder Invoer. | Nog steeds niets? Kies C2 om naar apparaten met problemen te zoeken.'
        'steps.micLow'              = 'Kies hierboven de oplossing om hem harder te zetten, of doe het met de hand. | Open Instellingen (Windows-toets + I) > Systeem > Geluid. | Klik onder Invoer op de microfoon en zet het volume op ongeveer 80. | Test het: de balk bij "Uw microfoon testen" beweegt als de klant praat.'
        'steps.noCamera'            = 'Sluit de webcam aan, als de pc er een gebruikt. | Laptop: kijk of er een klein schuifje voor de lens zit, of een toets met een camera-plaatje. | Kies C2 om naar apparaten met problemen te zoeken. | Herstart de pc en kies opnieuw B2.'
        'steps.callsOk'             = 'Open de belapp (WhatsApp, Teams, Zoom). | Kies in de instellingen, vaak onder Audio en video, de juiste microfoon, speaker en camera. | Doe een testgesprek, bijvoorbeeld met een familielid. | Alleen tijdens bellen stil? Sluit andere programma''s die de camera of microfoon misschien gebruiken.'
        'steps.tooDark'             = 'Kies hierboven de oplossing om het lichter te maken (kan worden teruggedraaid), of doe het met de hand. | Klik rechtsonder op het netwerk- of luidspreker-icoon: onderaan dat paneel staat de helderheidsschuif. | Sleep hem naar rechts. | Laptop: de toetsen met een zonnetje (vaak met Fn) veranderen ook de helderheid.'
        'steps.colorFilter'         = 'Druk tegelijk op de Windows-toets + Ctrl + C. | Nog steeds grijs? Open Instellingen (Windows-toets + I) > Toegankelijkheid > Kleurfilters. | Zet Kleurfilters uit. | Zet ook de "Sneltoets voor kleurfilters" uit, zodat het niet meer per ongeluk kan gebeuren.'
        'steps.highContrast'        = 'Druk tegelijk op linker Alt + linker Shift + Print Screen, en bevestig met Ja als dat gevraagd wordt. | Of open Instellingen (Windows-toets + I) > Toegankelijkheid > Contrastthema''s. | Kies Geen en klik op Toepassen.'
        'steps.magnifier'           = 'Kies hierboven de oplossing om het te sluiten, of druk op de Windows-toets + Esc. | Zodat het niet terugkomt: Instellingen > Toegankelijkheid > Vergrootglas, en zet de sneltoets en "starten voor aanmelden" uit.'
        'steps.rotated'             = 'Druk op Ctrl + Alt + pijltje omhoog (werkt op sommige pc''s). | Of open Instellingen (Windows-toets + I) > Systeem > Beeldscherm. | Klik bovenaan op het juiste scherm en kies bij Beeldschermstand: Liggend. | Klik op Wijzigingen behouden.'
        'steps.screenOk'            = 'Tekst groter maken: Instellingen (Windows-toets + I) > Toegankelijkheid > Tekstgrootte. Sleep de schuif en klik op Toepassen. | Alles groter maken: Instellingen > Systeem > Beeldscherm > Schaal, kies 125% of 150%. | Controleer de resolutie bij Beeldschermresolutie: die met (Aanbevolen) is het scherpst. | Is de muisaanwijzer slecht te zien? Instellingen > Toegankelijkheid > Muisaanwijzer en aanraken: maak hem groter of feller van kleur.'

        # ---- D: check lines
        'perf.diskOk'      = 'Schijf {0} {1} GB vrij ({2}%)'
        'perf.diskLow'     = 'Schijf {0} raakt vol: {1} GB vrij ({2}%)'
        'perf.diskFull'    = 'Schijf {0} is vol: {1} GB vrij ({2}%)'
        'perf.hdd'         = 'Windows staat op {0}, een ouderwetse harde schijf (HDD), en die is traag'
        'perf.memory'      = 'Geheugen in gebruik: {0}% van {1} GB'
        'perf.memoryFull'  = 'Het geheugen is bijna vol: {0}% van {1} GB in gebruik'
        'perf.lowRam'      = 'Maar {0} GB geheugen: weinig voor Windows 11'
        'perf.cpu'         = 'Processor: {0}% bezig'
        'perf.cpuBusy'     = 'De processor is {0}% bezig, vooral met {1}'
        'perf.uptime'      = 'Laatst herstart: {0} dag(en) geleden'
        'perf.uptimeLong'  = 'Al {0} dagen niet herstart'
        'perf.startup'     = '{0} programma''s starten met Windows'
        'perf.startupMany' = '{0} programma''s starten met Windows: {1}'
        'perf.crashApp'    = '{0} is deze week {1} keer vastgelopen of gecrasht'
        'perf.noCrashes'   = 'Deze week is geen programma vastgelopen of gecrasht'
        'perf.blueScreens' = 'Blauwe schermen, afgelopen 30 dagen: {0}'
        'perf.shutdowns'   = 'Onverwacht uitgevallen, afgelopen 30 dagen: {0} keer'
        'perf.sizes'       = 'Tijdelijke bestanden {0} GB, Prullenbak {1} GB, Downloads {2} GB'

        # ---- D: findings, and what to do about each
        'finding.diskFull'    = 'Schijf {0} is vol ({1} GB vrij). Een volle schijf maakt Windows traag en houdt updates tegen.'
        'advice.diskFull'     = 'Kies D4: daar kan Housecall ruimte vrijmaken.'
        'finding.diskLow'     = 'Schijf {0} raakt vol ({1} GB vrij).'
        'advice.diskLow'      = 'Kies D4: daar kan Housecall ruimte vrijmaken.'
        'finding.spaceFull'   = 'Schijf {0} is vol ({1} GB vrij).'
        'advice.spaceFull'    = 'Housecall kan hieronder tijdelijke bestanden verwijderen en de Prullenbak legen. De stappen laten zien waar de grote bestanden staan.'
        'finding.spaceLow'    = 'Schijf {0} raakt vol ({1} GB vrij).'
        'advice.spaceLow'     = 'Housecall kan hieronder tijdelijke bestanden verwijderen en de Prullenbak legen. De stappen laten zien waar de grote bestanden staan.'
        'finding.memoryFull'  = 'Het geheugen is bijna vol ({0}%). Windows moet dan de veel tragere schijf gebruiken.'
        'advice.memoryFull'   = 'Sluit programma''s en browsertabbladen die niet nodig zijn. Gebruikt een programma het meeste, dan kan Housecall het hieronder sluiten.'
        'finding.cpuBusy'     = 'De processor is erg druk ({0}%), vooral met {1}.'
        'advice.cpuBusy'      = 'Als Housecall het hieronder aanbiedt, kan het dat programma sluiten (niet-opgeslagen werk gaat verloren). Iets onbekends? Kies F3.'
        'finding.longUptime'  = 'De pc is al {0} dagen niet herstart. Windows wordt trager hoe langer het draait.'
        'advice.longUptime'   = 'Herstart de pc: Start > Aan/uit > Opnieuw opstarten (niet Afsluiten). De stappen hieronder leggen uit waarom.'
        'finding.hddSystem'   = 'Windows staat op een ouderwetse harde schijf (HDD). Dat is de meest voorkomende reden dat een oudere pc traag is.'
        'advice.hddSystem'    = 'Vervangen door een SSD maakt de pc vele malen sneller. Dat is een klus voor de monteur.'
        'finding.lowRam'      = 'De pc heeft maar {0} GB geheugen, weinig voor Windows 11.'
        'advice.lowRam'       = 'Houd weinig programma''s tegelijk open. Geheugen bijplaatsen, als de pc dat toelaat, is een klus voor de monteur.'
        'finding.manyStartup' = '{0} programma''s starten met Windows, en dat vertraagt het opstarten en het werken.'
        'advice.manyStartup'  = 'Housecall kan hieronder de overbodige laten stoppen (kan worden teruggedraaid).'
        'finding.slowOk'      = 'Niets op deze pc verklaart nu de traagheid.'
        'advice.slowOk'       = 'Alleen traag in de browser? Te veel tabbladen of extensies. Traag op een bepaald moment? Kies D1 opnieuw op dat moment.'
        'finding.startOk'     = 'Het opstarten ziet er normaal uit: weinig opstartprogramma''s en een snelle schijf.'
        'advice.startOk'      = 'Installeert Windows updates tijdens het opstarten, dan duurt dat een keer wat langer. Kies E1 om te controleren.'
        'finding.crashes'     = '{0} is deze week {1} keer vastgelopen of gecrasht.'
        'advice.crashes'      = 'Werk dat programma bij of installeer het opnieuw. De stappen hieronder lopen het door.'
        'finding.someCrashes' = '{0} is deze week een of twee keer vastgelopen of gecrasht.'
        'advice.someCrashes'  = 'Af en toe is normaal. Blijft het gebeuren, werk het dan bij of installeer het opnieuw.'
        'finding.blueScreens' = 'Windows is de afgelopen 30 dagen {0} keer gestopt met een blauw scherm.'
        'advice.blueScreens'  = 'Meestal een stuurprogramma of hardware die kapotgaat. Werk Windows (E1) en de stuurprogramma''s bij. Blijft het gebeuren, dan is het een klus voor de monteur.'
        'finding.shutdowns'   = 'De pc is de afgelopen 30 dagen {0} keer onverwacht uitgevallen.'
        'advice.shutdowns'    = 'Een stroomstoring, een stekker eruit, de aan/uit-knop ingedrukt houden, of oververhitting. Bij een laptop de accu controleren; bij een desktop de stroomkabel en stof in de ventilatoren.'
        'finding.crashOk'     = 'Deze week geen crashes, vastlopers of blauwe schermen.'
        'advice.crashOk'      = 'Loopt een programma af en toe vast, werk het dan bij. Zeg tegen de klant: sla vaak op.'
        'finding.diskOk'      = 'Schijf {0} heeft genoeg ruimte ({1} GB vrij).'
        'advice.diskOk'       = 'Niets op te ruimen. Zegt een programma dat de schijf vol is, dan kan het een andere schijf of een USB-stick bedoelen.'

        # ---- D: fixes
        'fix.note.temp'              = '(alleen tijdelijke bestanden, niets persoonlijks)'
        'fix.note.noundo'            = '(kan niet worden teruggedraaid: bekijk eerst de inhoud)'
        'fix.note.unsaved'           = '(niet-opgeslagen werk daarin gaat verloren)'
        'fix.disableStartup'         = '{0} niet meer met Windows laten starten'
        'fix.disableStartup.done'    = '{0} start niet meer met Windows'
        'fix.disableStartupMachine'  = '{0} niet meer met Windows laten starten, voor alle gebruikers'
        'fix.disableStartupMachine.done' = '{0} start niet meer met Windows, voor alle gebruikers'
        'fix.closeProcess'           = '{0} afsluiten'
        'fix.closeProcess.done'      = '{0} afgesloten'
        'fix.emptyTemp'              = 'Tijdelijke bestanden verwijderen ({0} GB)'
        'fix.emptyTemp.done'         = 'Tijdelijke bestanden verwijderd'
        'fix.emptyRecycleBin'        = 'De Prullenbak legen ({0} GB)'
        'fix.emptyRecycleBin.done'   = 'Prullenbak geleegd'

        # ---- D: step-by-step guides
        'steps.diskFull'    = 'Kies D4 om met Housecall ruimte vrij te maken. | Of open Instellingen (Windows-toets + I) > Systeem > Opslag en klik op Aanbevelingen voor opschonen. | Zet op dezelfde pagina Opslaginzicht aan, zodat Windows zelf opruimt. | Zet grote foto''s en video''s op een USB-schijf of in de cloud, na overleg met de klant.'
        'steps.diskLow'     = 'Kies D4 om met Housecall ruimte vrij te maken. | Open Instellingen (Windows-toets + I) > Systeem > Opslag en zet Opslaginzicht aan, zodat Windows zelf opruimt.'
        'steps.spaceFull'   = ('Kies hierboven de oplossingen: eerst de tijdelijke bestanden, de Prullenbak pas na het bekijken van de inhoud met de klant. | Open Instellingen (Windows-toets + I) > Systeem > Opslag en klik op Aanbevelingen voor opschonen. | Kijk onder "Meer categorie' + [char]0xEB + 'n weergeven" wat de meeste ruimte inneemt (Apps, Documenten, Afbeeldingen, Video''s). | Verwijder programma''s die de klant niet meer gebruikt: Instellingen > Apps, zoek het in de lijst, drie puntjes, Verwijderen. | Zet Opslaginzicht aan, zodat Windows zelf opruimt.')
        'steps.spaceLow'    = 'Kies hierboven de oplossingen: eerst de tijdelijke bestanden, de Prullenbak pas na het bekijken van de inhoud met de klant. | Open Instellingen (Windows-toets + I) > Systeem > Opslag en klik op Aanbevelingen voor opschonen. | Zet Opslaginzicht aan, zodat Windows zelf opruimt.'
        'steps.memoryFull'  = ('Druk op Ctrl + Shift + Esc om Taakbeheer te openen. | Klik op het tabblad Processen op de kolom Geheugen om daarop te sorteren. | Sluit programma''s die niet nodig zijn: selecteer ze en klik op Taak be' + [char]0xEB + 'indigen. Sla eerst open werk op. | Browser met veel tabbladen? Sluit de tabbladen die niet nodig zijn. | Nog steeds vol? Herstart de pc.')
        'steps.cpuBusy'     = ('Druk op Ctrl + Shift + Esc om Taakbeheer te openen. | Klik op het tabblad Processen op de kolom CPU om daarop te sorteren. | Kent de klant het drukste programma? Sla het werk op, selecteer het en klik op Taak be' + [char]0xEB + 'indigen. | Onbekende naam? Zoek hem online op, en kies F3.')
        'steps.longUptime'  = 'Sla open werk op en sluit programma''s. | Klik op Start > Aan/uit > Opnieuw opstarten. Opnieuw opstarten begint echt opnieuw; Afsluiten (met snel opstarten) niet. | Kies na het herstarten opnieuw D1.'
        'steps.hddSystem'   = 'Leg de klant uit: de schijf is het traagste onderdeel van deze pc. | Bied aan hem te vervangen door een SSD (SATA-SSD bij oudere pc''s, NVMe als de pc een M.2-sleuf heeft), met Windows erop overgezet. | Tot die tijd: houd de opstartlijst kort (D2) en de schijf opgeruimd (D4).'
        'steps.lowRam'      = 'Houd weinig programma''s en browsertabbladen tegelijk open. | Kijk of de pc een vrije geheugensleuf heeft of uitgebreid kan worden (merk en model op de sticker aan de onderkant). | Kan het: geheugen bijplaatsen is een klus voor de monteur.'
        'steps.manyStartup' = 'Kies hierboven de oplossingen om programma''s niet meer met Windows te laten starten (ze werken nog gewoon als u ze opent). | Of druk op Ctrl + Shift + Esc > Opstart-apps, selecteer een programma en klik op Uitschakelen. | Laat de virusscanner, het geluid, de touchpad en OneDrive aan staan. | Herstart de pc en kijk of hij sneller opstart.'
        'steps.slowOk'      = 'Vraag wanneer het traag is: bij het opstarten (kies D2), in de browser, of in een programma? | Browser: sluit tabbladen en verwijder extensies die de klant niet gebruikt. | Kies D1 opnieuw op het moment dat het traag is. | Kies ook F3: ongewenste programma''s kunnen een pc vertragen.'
        'steps.startOk'     = 'Herstart de pc en meet de tijd van de aan-knop tot een bruikbaar bureaublad. | Langer dan 2 minuten? Kies E1: Windows is misschien bezig met updates. | Elke keer traag? Kies D1 terwijl hij opstart.'
        'steps.crashes'     = 'Werk het programma bij: vaak onder Help > Controleren op updates, of via de Microsoft Store > Bibliotheek > Updates ophalen. | Crasht het nog? Instellingen > Apps, zoek het in de lijst, drie puntjes, Geavanceerde opties (als dat er staat) > Herstellen. | Anders: verwijder het, herstart de pc en installeer het opnieuw van de site van de maker. | Kies over een paar dagen opnieuw D3.'
        'steps.someCrashes' = 'Werk het programma bij, vaak onder Help > Controleren op updates. | Zeg tegen de klant: sla vaak op. | Blijft het gebeuren, kies dan opnieuw D3.'
        'steps.blueScreens' = 'Kies E1 en installeer alle Windows-updates, ook de optionele stuurprogramma-updates. | Noteer de volgende keer de foutcode op het blauwe scherm (bijvoorbeeld MEMORY_MANAGEMENT): die wijst naar de oorzaak. | Kort geleden een apparaat of programma toegevoegd? Verwijder het en kijk of het stopt. | Blijft het gebeuren: een klus voor de monteur (geheugentest, schijfcontrole).'
        'steps.shutdowns'   = 'Vraag of de stroom uitviel, of iemand de aan/uit-knop ingedrukt hield of de stekker eruit trok. | Laptop: valt hij uit bij een bepaald accuniveau? Dan is de accu versleten. | Desktop: controleer de stroomkabel, en laat het stof uit de ventilatoren halen (oververhitting). | Blijft het gebeuren: een klus voor de monteur.'
        'steps.crashOk'     = 'Vraag welk programma vastloopt, en wanneer. | Werk dat programma bij. | Kies D3 opnieuw direct nadat het gebeurt.'
        'steps.diskOk'      = 'Vraag welk programma zegt dat de schijf vol is, en welke schijf het noemt. | Een USB-stick of geheugenkaart? Kijk in Verkenner (Deze pc) hoeveel ruimte die heeft. | Zet Opslaginzicht aan (Instellingen > Systeem > Opslag), zodat het opgeruimd blijft.'

        # ---- E: check lines
        'upd.windows10'       = 'Deze pc draait Windows 10, dat sinds 14 oktober 2025 geen beveiligingsupdates meer krijgt'
        'upd.serviceDisabled' = 'De Windows Update-service is uitgeschakeld'
        'upd.serviceOk'       = 'De Windows Update-service is beschikbaar'
        'upd.paused'          = 'Updates zijn gepauzeerd tot {0}'
        'upd.last'            = 'Laatste geslaagde update: {0}'
        'upd.lastOld'         = 'Laatste geslaagde update: {0}, {1} dagen geleden'
        'upd.never'           = 'Geen geslaagde update gevonden in de geschiedenis'
        'upd.failed'          = 'Mislukt: {0} (fout {1})'
        'upd.historyUnknown'  = 'De updategeschiedenis kon niet worden gelezen'
        'upd.rebootPending'   = 'Windows wacht op een herstart om updates af te maken'
        'upd.noSpace'         = 'Maar {1} GB vrij op {0}: te weinig voor updates'
        'err.activated'       = 'Windows is geactiveerd'
        'err.notActivated'    = 'Windows is niet geactiveerd'
        'err.clockOk'         = 'De klok staat goed'
        'err.clockWrong'      = 'De klok loopt {0} minuten verkeerd'
        'err.clockUnknown'    = 'De klok kon niet worden vergeleken (geen internet)'
        'err.crash'           = '{0} is de afgelopen 3 dagen {1} keer vastgelopen of gecrasht'
        'err.noCrash'         = 'De afgelopen 3 dagen is geen programma gecrasht'
        'sd.noPending'        = 'Er wachten geen updates op een herstart'
        'sd.fastStartup'      = 'Snel opstarten staat aan: Afsluiten zet Windows niet helemaal uit'

        # ---- E: findings, and what to do about each
        'finding.windows10'             = 'Deze pc draait nog Windows 10, dat sinds 14 oktober 2025 geen beveiligingsupdates meer krijgt.'
        'advice.windows10'              = 'Upgrade naar Windows 11 als de pc dat kan (de app PC-statuscontrole zegt het), of plan een nieuwe pc. Dat is een klus voor de monteur.'
        'finding.updateServiceDisabled' = ('De Windows Update-service is uitgeschakeld, dus er kunnen geen updates worden ge' + [char]0xEF + 'nstalleerd.')
        'advice.updateServiceDisabled'  = 'Housecall kan hem hieronder weer inschakelen (beheerder nodig, kan worden teruggedraaid). Vraag of iemand hem bewust heeft uitgezet.'
        'finding.updateSpace'           = 'Er is te weinig ruimte voor updates ({0} GB vrij).'
        'advice.updateSpace'            = 'Kies D4 om ruimte vrij te maken, en kies daarna opnieuw E1.'
        'finding.updatesPaused'         = 'Updates zijn gepauzeerd tot {0}.'
        'advice.updatesPaused'          = 'Housecall kan ze hieronder hervatten (beheerder nodig, kan worden teruggedraaid), of klik op Updates hervatten in Instellingen > Windows Update.'
        'finding.rebootPending'         = 'Windows wacht op een herstart om updates af te maken.'
        'advice.rebootPending'          = 'Herstart de pc: Start > Aan/uit > Bijwerken en opnieuw opstarten. Dat kan een keer even duren; zet hem intussen niet uit.'
        'finding.updateFailures'        = 'Een update is onlangs mislukt (fout {0}).'
        'advice.updateFailures'         = 'Housecall kan Windows Update hieronder opnieuw instellen (beheerder nodig): de updates worden dan opnieuw gedownload. Klik daarna op Naar updates zoeken in Instellingen > Windows Update.'
        'finding.updatesStale'          = ('Windows heeft al {0} dagen geen update ge' + [char]0xEF + 'nstalleerd.')
        'advice.updatesStale'           = 'Open Instellingen > Windows Update en klik op Naar updates zoeken. Loopt het vast, dan kan Housecall Windows Update hieronder opnieuw instellen (beheerder nodig).'
        'finding.updatesOk'             = 'Windows Update werkt en is bijgewerkt.'
        'advice.updatesOk'              = 'Mislukt een update steeds met een melding, noteer dan de foutcode (0x...) en kies opnieuw E1 na nog een poging.'
        'finding.clockWrong'            = ('De klok van de pc loopt {0} minuten verkeerd. Dat geeft "uw verbinding is niet priv' + [char]0xE9 + '"-achtige fouten en certificaatfouten op websites.')
        'advice.clockWrong'             = 'Housecall kan de klok hieronder gelijkzetten (beheerder nodig). Controleer ook de tijdzone: zie de stappen.'
        'finding.notActivated'          = 'Windows is niet geactiveerd. Daardoor staat er "Windows activeren" in beeld en kan de klant weinig instellen.'
        'advice.notActivated'           = 'Kijk onder Instellingen > Systeem > Activering. Een pc die met Windows geleverd is, activeert meestal vanzelf zodra hij online is; anders is een licentie nodig.'
        'finding.recentCrash'           = '{0} is onlangs vastgelopen of gecrasht; dat is misschien de melding die de klant zag.'
        'advice.recentCrash'            = 'Werk dat programma bij of installeer het opnieuw (de stappen bij D3 lopen het door). Housecall kan hieronder ook de eigen bestanden van Windows controleren.'
        'finding.errorsOk'              = 'Geen bekende oorzaak gevonden voor een foutmelding.'
        'advice.errorsOk'               = 'Maak de volgende keer een foto van de melding, vooral van een code. Housecall kan hieronder de eigen bestanden van Windows controleren (beheerder nodig, duurt even).'
        'finding.fastStartup'           = 'Snel opstarten staat aan: Afsluiten zet Windows niet helemaal uit, dus problemen blijven.'
        'advice.fastStartup'            = 'Housecall kan snel opstarten hieronder uitzetten (beheerder nodig, kan worden teruggedraaid). Opnieuw opstarten start altijd helemaal opnieuw, met of zonder.'
        'finding.shutdownOk'            = 'Niets op deze pc houdt afsluiten of herstarten tegen.'
        'advice.shutdownOk'             = 'Vraagt een programma om op te slaan of sluit het niet, sluit het dan eerst. Blijft de pc hangen op "Afsluiten", zie dan de stappen.'

        # ---- E: fixes
        'fix.note.redownload'            = '(Windows downloadt de updates opnieuw)'
        'fix.note.long'                  = '(duurt 15 tot 30 minuten, laat de pc aan)'
        'fix.enableUpdateService'        = 'De Windows Update-service weer inschakelen'
        'fix.enableUpdateService.done'   = 'Windows Update-service weer ingeschakeld'
        'fix.resumeUpdates'              = 'Updates hervatten'
        'fix.resumeUpdates.done'         = 'Updates hervat'
        'fix.resetUpdates'               = 'Windows Update opnieuw instellen'
        'fix.resetUpdates.done'          = 'Windows Update opnieuw ingesteld'
        'fix.syncClock'                  = 'De klok gelijkzetten met de internettijd'
        'fix.syncClock.done'             = 'Klok gelijkgezet met de internettijd'
        'fix.repairWindows'              = 'De eigen bestanden van Windows controleren en herstellen'
        'fix.repairWindows.done'         = 'Eigen bestanden van Windows gecontroleerd en hersteld'
        'fix.disableFastStartup'         = 'Snel opstarten uitzetten'
        'fix.disableFastStartup.done'    = 'Snel opstarten uitgezet'

        # ---- E: step-by-step guides
        'steps.windows10'             = 'Open de app PC-statuscontrole (of download hem bij Microsoft) en klik bij Windows 11 op Nu controleren. | Geschikt? Instellingen > Bijwerken en beveiliging > Windows Update biedt de upgrade aan. Maak eerst een back-up van de bestanden van de klant. | Niet geschikt? Bespreek een nieuwe pc, of de betaalde Extended Security Updates van Microsoft. | Tot die tijd: houd de browser en virusscanner bijgewerkt, en kies af en toe F3.'
        'steps.updateServiceDisabled' = 'Kies hierboven de oplossing om hem weer in te schakelen (beheerder nodig), of doe het met de hand. | Typ Services in Start en open het. | Zoek Windows Update, dubbelklik erop, zet Opstarttype op Handmatig, klik op Starten en daarna op OK. | Open Instellingen > Windows Update en klik op Naar updates zoeken.'
        'steps.updateSpace'           = 'Kies D4 om met Housecall ruimte vrij te maken. | Updates hebben minstens 10 GB vrij nodig, grote functie-updates meer. | Open daarna Instellingen > Windows Update en klik op Naar updates zoeken.'
        'steps.updatesPaused'         = 'Kies hierboven de oplossing om updates te hervatten (beheerder nodig), of doe het met de hand. | Open Instellingen (Windows-toets + I) > Windows Update. | Klik op Updates hervatten, en dan op Naar updates zoeken.'
        'steps.rebootPending'         = 'Sla open werk op en sluit programma''s. | Klik op Start > Aan/uit > Bijwerken en opnieuw opstarten. | Wacht: de pc kan meer dan een keer herstarten. Zet hem niet uit zolang er "Bezig met updates" staat. | Kies daarna opnieuw E1.'
        'steps.updateFailures'        = 'Kies hierboven de oplossing om Windows Update opnieuw in te stellen (beheerder nodig). | Herstart de pc. | Open Instellingen > Windows Update en klik op Naar updates zoeken, en dan op Downloaden en installeren. | Mislukt het nog? Zoek de foutcode (0x...) op bij Microsoft, of kies E2 om de eigen bestanden van Windows te controleren.'
        'steps.updatesStale'          = 'Open Instellingen (Windows-toets + I) > Windows Update en klik op Naar updates zoeken. | Blijft hij langer dan een uur op een percentage hangen? Kies hierboven de oplossing om Windows Update opnieuw in te stellen (beheerder nodig) en herstart. | Zorg voor genoeg ruimte (D4) en een werkende internetverbinding (A1).'
        'steps.updatesOk'             = 'Open Instellingen > Windows Update en kijk onder Updategeschiedenis naar mislukte updates. | Noteer de foutcode van een mislukte update en zoek die op bij Microsoft. | Probeer Naar updates zoeken nog een keer.'
        'steps.clockWrong'            = 'Kies hierboven de oplossing om de klok gelijk te zetten (beheerder nodig). | Open Instellingen (Windows-toets + I) > Tijd en taal > Datum en tijd. | Zet "Tijd automatisch instellen" en "Tijdzone automatisch instellen" aan, of kies (UTC+01:00) Amsterdam, Berlijn... | Klik op Nu synchroniseren. | Loopt de klok steeds verkeerd nadat de pc uit stond? Dan is het batterijtje op het moederbord leeg: een klus voor de monteur.'
        'steps.notActivated'          = 'Open Instellingen (Windows-toets + I) > Systeem > Activering. | Klik op Probleemoplosser als die er staat, en meld u aan met het Microsoft-account van de klant als dat gevraagd wordt. | Onlangs onderdelen vervangen? Kies "Ik heb onlangs de hardware op dit apparaat gewijzigd". | Nog steeds niet geactiveerd: de klant heeft een licentie (productcode) nodig.'
        'steps.recentCrash'           = 'Vraag de klant wanneer de melding verschijnt en in welk programma. | Werk dat programma bij of installeer het opnieuw (zie D3). | Kies hierboven de oplossing om de eigen bestanden van Windows te controleren (beheerder nodig, duurt even).'
        'steps.errorsOk'              = 'De volgende keer dat de melding verschijnt: maak er een foto van, met een eventuele code. | Zoek de precieze tekst of code online op, of laat hem aan uw monteur zien. | Kies hierboven de oplossing om de eigen bestanden van Windows te controleren en te herstellen (beheerder nodig, duurt 15 tot 30 minuten).'
        'steps.fastStartup'           = 'Kies hierboven de oplossing om het uit te zetten (beheerder nodig), of doe het met de hand. | Typ Configuratiescherm in Start > Energiebeheer > Het gedrag van de aan/uit-knoppen bepalen. | Klik op "Instellingen wijzigen die momenteel niet beschikbaar zijn" en haal het vinkje weg bij "Snel opstarten inschakelen". Klik op Wijzigingen opslaan.'
        'steps.shutdownOk'            = 'Sla eerst het werk op en sluit alle programma''s. | Klik op Start > Aan/uit > Afsluiten (of Opnieuw opstarten). | Blijft hij langer dan 10 minuten op "Afsluiten" hangen? Houd de aan/uit-knop 10 seconden ingedrukt. | Gebeurt het vaker? Kies E1: wachtende updates zijn de meest voorkomende oorzaak.'

        # ---- A4: email
        'mail.ask'            = 'Welk e-mailadres? Alleen het deel na de @ wordt gebruikt, bijv. ziggo.nl'
        'mail.invalid'        = '"{0}" lijkt geen e-mailadres. Typ het zo: naam@ziggo.nl'
        'mail.typo'           = '"{0}" lijkt een typefout: bedoelt u {1}?'
        'mail.receives'       = '{0} ontvangt e-mail'
        'mail.noMx'           = '{0} kan geen e-mail ontvangen'
        'mail.in'             = 'Ontvangen'
        'mail.out'            = 'Versturen'
        'mail.serverOk'       = '{0}: {1} antwoordt, {2} ms'
        'mail.serverDown'     = '{0}: {1} antwoordt niet'
        'mail.unknownProvider' = 'Mailservers van {0} zijn Housecall niet bekend: niet gecontroleerd'
        'mail.apps'           = 'Mailprogramma''s: {0}'
        'mail.noApps'         = 'Geen mailprogramma aanwezig (alleen webmail)'
        'mail.retired'        = 'De oude Windows Mail-app staat erop; die werkt sinds eind 2024 niet meer'
        'finding.mailTypo'       = '"{0}" is waarschijnlijk een typefout van {1}. Mail van of naar het verkeerde adres komt nergens aan.'
        'advice.mailTypo'        = 'Controleer het adres in de accountinstellingen van het mailprogramma, en kies opnieuw A4 met het juiste adres.'
        'finding.mailNoDomain'   = '{0} kan geen e-mail ontvangen: het adres is waarschijnlijk verkeerd gespeld, of bestaat niet meer.'
        'advice.mailNoDomain'    = 'Controleer de spelling met de klant. Een oud provideradres (bijvoorbeeld na een verhuizing) kan zijn opgeheven.'
        'finding.mailServerDown' = 'De mailserver van {0} antwoordt niet aan deze pc.'
        'advice.mailServerDown'  = 'Kijk op een telefoon of er een storing is bij de provider (bijvoorbeeld allestoringen.nl). Is die er niet, dan blokkeert beveiligingssoftware op deze pc misschien de mail.'
        'finding.mailAppRetired' = 'De oude Windows Mail-app staat nog op de pc. Microsoft heeft die eind 2024 uitgezet: er komt geen mail meer in binnen.'
        'advice.mailAppRetired'  = 'Zet de klant over op de nieuwe Outlook (gratis, in de Microsoft Store) of op webmail. De stappen hieronder lopen het door.'
        'finding.mailOk'         = 'De mailservers van {0} zijn bereikbaar. Het probleem is waarschijnlijk het wachtwoord, een volle mailbox, of de instellingen van het mailprogramma.'
        'advice.mailOk'          = 'Probeer eerst in te loggen op webmail: lukt dat, dan zitten de instellingen van het mailprogramma fout. De stappen hieronder lopen het door.'
        'steps.mailTypo'         = 'Open de accountinstellingen van het mailprogramma en kijk naar het adres. | Verbeter het deel na de @, of verwijder het account en voeg het opnieuw toe met het juiste adres. | Kies opnieuw A4 met het juiste adres.'
        'steps.mailNoDomain'     = 'Controleer samen met de klant de spelling van het adres, letter voor letter. | Van internetprovider gewisseld? Een oud adres zoals @hetnet.nl of @home.nl kan nog werken, of kan zijn opgeheven: vraag het na bij die provider. | Kies opnieuw A4 met het juiste adres.'
        'steps.mailServerDown'   = 'Kijk op een telefoon met wifi uit of er een storing is bij de provider (bijvoorbeeld allestoringen.nl). | Geen storing? Zet de virusscanner of firewall op deze pc even op pauze en probeer te versturen en te ontvangen. | Werkt het dan? Voeg in dat beveiligingsprogramma een uitzondering toe voor het mailprogramma, en zet de beveiliging weer aan.'
        'steps.mailAppRetired'   = 'Installeer de nieuwe Outlook: open de Microsoft Store, zoek Outlook en klik op Downloaden. Hij is gratis. | Open hem en voeg het e-mailadres van de klant toe; bij de meeste providers vindt Outlook de instellingen zelf. | Of gebruik webmail in de browser, en zet een snelkoppeling op het bureaublad. | Verwijder de oude Mail-app (Instellingen > Apps, "E-mail en agenda", drie puntjes, Verwijderen) zodat de klant hem niet per ongeluk opent.'
        'steps.mailOk'           = 'Log in de browser in op webmail met het adres en wachtwoord van de klant. | Lukt dat niet? Dan klopt het wachtwoord niet: stel het opnieuw in via de website van de provider ("wachtwoord vergeten"). | Werkt webmail wel? Verwijder het account uit het mailprogramma en voeg het opnieuw toe, en typ het wachtwoord opnieuw. | Komt mail wel in webmail maar niet in het programma? Kijk in de map Ongewenste e-mail, en of de mailbox vol is (verwijder oude mail met grote bijlagen).'

        # ---- fixes added later
        'fix.note.restartNeeded'     = '(werkt na een herstart van de pc)'
        'fix.note.uninstaller'       = '(opent het eigen verwijderprogramma)'

        # ---- G: controleregels
        'shell.profileOk'          = 'Aangemeld met het normale gebruikersprofiel'
        'shell.tempProfile'        = 'Windows heeft aangemeld met een TIJDELIJK profiel: het eigen bureaublad en de bestanden van de klant zijn niet geladen'
        'shell.explorerOk'         = 'Verkenner (bureaublad, taakbalk, mappen) draait en reageert'
        'shell.explorerMissing'    = 'Verkenner draait niet, dus er is geen taakbalk en geen bureaublad'
        'shell.explorerHung'       = 'Verkenner reageert niet meer'
        'shell.iconsShown'         = 'Pictogrammen op het bureaublad worden getoond ({0} items op het bureaublad)'
        'shell.iconsHidden'        = 'De pictogrammen op het bureaublad staan uit, dus het bureaublad lijkt leeg'
        'shell.desktopOneDrive'    = 'Het bureaublad staat in OneDrive, en OneDrive draait'
        'shell.desktopOneDriveOff' = 'Het bureaublad staat in OneDrive, maar OneDrive draait niet'
        'shell.recycleHidden'      = 'De Prullenbak is verborgen op het bureaublad'
        'shell.taskbarShown'       = 'De taakbalk blijft zichtbaar'
        'shell.taskbarAutoHide'    = 'De taakbalk verbergt zichzelf tot de muis de onderkant van het scherm raakt'
        'shell.searchHidden'       = 'Het zoekvak is verborgen op de taakbalk'
        'shell.tabletMode'         = 'De tabletmodus staat aan: grote tegels, geen pictogrammen op het bureaublad'

        # ---- G: bevindingen, en wat eraan te doen
        'finding.tempProfile'      = 'Windows kon het eigen profiel van de klant niet laden en heeft aangemeld met een leeg, tijdelijk profiel. De bestanden zijn vrijwel zeker nog aanwezig, maar deze sessie laat ze niet zien, en wat nu wordt opgeslagen gaat verloren bij het afmelden.'
        'advice.tempProfile'       = 'Laat de klant nu niets opslaan. Start eerst de pc opnieuw op; de stappen hieronder gaan verder als dat niet helpt.'
        'finding.explorerMissing'  = 'Verkenner draait niet. Die tekent het bureaublad, de taakbalk en de mappen, dus die zijn allemaal weg.'
        'advice.explorerMissing'   = 'Housecall kan hem hieronder weer starten. Dat is onschuldig.'
        'finding.explorerHung'     = 'Verkenner is vastgelopen. Daarom reageren de taakbalk, het bureaublad of de mappen niet.'
        'advice.explorerHung'      = 'Housecall kan hem hieronder herstarten. Open mapvensters gaan dicht; bestanden blijven onaangeroerd.'
        'finding.iconsHidden'      = 'De pictogrammen op het bureaublad staan uit. De bestanden zijn er nog, ze zijn alleen verborgen. Dit gebeurt vaak per ongeluk met een rechtermuisklik op het bureaublad.'
        'advice.iconsHidden'       = 'Housecall kan ze hieronder weer tonen (kan worden teruggedraaid).'
        'finding.desktopOneDrive'  = 'Het bureaublad van de klant staat in OneDrive, maar OneDrive draait niet. Daardoor kunnen bestanden op het bureaublad lijken te ontbreken of verouderd zijn.'
        'advice.desktopOneDrive'   = 'Kies G2 om OneDrive te controleren.'
        'finding.tabletMode'       = 'De tabletmodus staat aan. Die laat Windows 10 er anders uitzien: grote tegels en geen pictogrammen op het bureaublad.'
        'advice.tabletMode'        = 'Zet hem uit met de stappen hieronder.'
        'finding.taskbarAutoHide'  = 'De taakbalk verbergt zichzelf: hij verschijnt pas als de muis de onderkant van het scherm raakt.'
        'advice.taskbarAutoHide'   = 'Housecall kan hem hieronder zichtbaar laten blijven (kan worden teruggedraaid).'
        'finding.searchHidden'     = 'Het zoekvak is verborgen op de taakbalk, dus er is geen plek om een zoekopdracht te typen.'
        'advice.searchHidden'      = 'Housecall kan het hieronder weer tonen (kan worden teruggedraaid).'
        'finding.recycleHidden'    = 'De Prullenbak is verborgen op het bureaublad. Verwijderde bestanden zitten er nog in.'
        'advice.recycleHidden'     = 'Housecall kan hem hieronder weer tonen (kan worden teruggedraaid).'
        'finding.shellOk'          = 'Het bureaublad, de taakbalk en Verkenner staan normaal ingesteld.'
        'advice.shellOk'           = 'Doet het toch raar? Verkenner hieronder herstarten is onschuldig en helpt vaak.'

        # ---- G: oplossingen
        'fix.note.explorer'        = '(de taakbalk is een paar seconden weg, open mapvensters gaan dicht)'
        'fix.restartExplorer'      = 'Verkenner herstarten'
        'fix.restartExplorer.done' = 'Verkenner herstart'
        'fix.showDesktopIcons'     = 'De pictogrammen op het bureaublad weer tonen'
        'fix.showDesktopIcons.done' = 'Pictogrammen op het bureaublad weer getoond'
        'fix.showRecycleBin'       = 'De Prullenbak op het bureaublad tonen'
        'fix.showRecycleBin.done'  = 'Prullenbak op het bureaublad getoond'
        'fix.showSearch'           = 'Het zoekvak op de taakbalk tonen'
        'fix.showSearch.done'      = 'Zoekvak op de taakbalk getoond'
        'fix.taskbarStay'          = 'De taakbalk zichtbaar laten blijven'
        'fix.taskbarStay.done'     = 'De taakbalk blijft zichtbaar'

        # ---- G: stap-voor-stap
        'steps.tempProfile'        = 'Sla nu niets op: dat gaat verloren bij het afmelden. | Start de pc opnieuw op (Start > Aan/uit > Opnieuw opstarten) en meld opnieuw aan. Vaak is dat genoeg. | Nog steeds een tijdelijk profiel? Controleer of de schijf niet vol is (D4); een volle schijf is een veelvoorkomende oorzaak. | Nog steeds? Dan moet het profiel in het register worden hersteld, met beheerdersrechten. Doe dit alleen met een back-up, of plan het als aparte klus. | De bestanden van de klant staan normaal nog in C:\Users\<naam>: open die map om de klant gerust te stellen.'
        'steps.explorerMissing'    = 'Kies hierboven de oplossing om hem te starten, of doe het met de hand. | Druk op Ctrl + Shift + Esc om Taakbeheer te openen. | Klik op Nieuwe taak uitvoeren, typ explorer en druk op Enter. | De taakbalk en het bureaublad komen terug.'
        'steps.explorerHung'       = 'Kies hierboven de oplossing om hem te herstarten, of doe het met de hand. | Druk op Ctrl + Shift + Esc om Taakbeheer te openen. | Zoek Windows Verkenner in de lijst, klik er met rechts op en kies Opnieuw opstarten. | Gebeurt het vaak? Kies D1 of D3 om de oorzaak te zoeken.'
        'steps.iconsHidden'        = 'Kies hierboven de oplossing (kan worden teruggedraaid), of doe het met de hand. | Klik met rechts op een lege plek op het bureaublad. | Kies Beeld en klik op Bureaubladpictogrammen weergeven, zodat er een vinkje voor staat.'
        'steps.desktopOneDrive'    = 'Kies G2 om OneDrive te controleren. | Of start OneDrive met de hand: typ OneDrive in Start en open het. | Wacht tot het wolkje rechtsonder geen pijltjes meer laat zien.'
        'steps.tabletMode'         = 'Klik op het tekstballon-pictogram rechtsonder, naast de klok (het Actiecentrum). | Klik op de tegel Tabletmodus, zodat die niet meer blauw is. | Of: Instellingen (Windows-toets + I) > Systeem > Tablet, en kies "Tabletmodus niet gebruiken".'
        'steps.taskbarAutoHide'    = 'Kies hierboven de oplossing (kan worden teruggedraaid), of doe het met de hand. | Beweeg de muis naar de onderkant van het scherm zodat de taakbalk verschijnt, klik er met rechts op en kies Taakbalkinstellingen. | Zet "De taakbalk automatisch verbergen" uit (Windows 11: onder Taakbalkgedrag).'
        'steps.searchHidden'       = 'Kies hierboven de oplossing (kan worden teruggedraaid), of doe het met de hand. | Klik met rechts op de taakbalk en kies Taakbalkinstellingen. | Kies onder Zoeken voor Zoekvak (Windows 10: rechtermuisklik op de taakbalk > Zoeken > Zoekvak weergeven).'
        'steps.recycleHidden'      = 'Kies hierboven de oplossing (kan worden teruggedraaid), of doe het met de hand. | Open Instellingen (Windows-toets + I) > Persoonlijke instellingen > Thema''s > Instellingen voor bureaubladpictogrammen. | Vink Prullenbak aan en klik op OK.'
        'steps.shellOk'            = 'Kies hierboven de oplossing om Verkenner te herstarten; dat is onschuldig. | Lijkt het bureaublad leeg? Rechtermuisklik op het bureaublad > Beeld > Bureaubladpictogrammen weergeven. | Lijken bestanden weg? Kies G2 om OneDrive te controleren, of zoek de bestandsnaam op in Verkenner. | Alles ineens groot? Kies B3.'
        'fix.resetWinsock'           = 'De netwerkinstellingen van Windows herstellen'
        'fix.resetWinsock.done'      = 'Netwerkinstellingen van Windows hersteld (herstart nodig)'
        'fix.restartAdapter'         = 'Netwerkadapter "{0}" herstarten'
        'fix.restartAdapter.done'    = 'Netwerkadapter "{0}" herstart'
        'fix.uninstallProgram'       = '{0} verwijderen'
        'fix.uninstallProgram.done'  = '{0} verwijderd'
        'fix.openNotifySettings'     = 'De meldingsinstellingen openen in {0}'
        'fix.openNotifySettings.done' = 'Meldingsinstellingen geopend in {0}'
        'fix.openWebmail'            = 'De webmail van {0} openen in de browser'
        'fix.openWebmail.done'       = 'Webmail van {0} geopend'
        'fix.restorePoint'           = 'Eerst een Windows-herstelpunt maken...'
        'fix.restorePointOk'         = 'Herstelpunt gemaakt.'
        'fix.restorePointRecent'     = 'Windows heeft de afgelopen 24 uur al een herstelpunt gemaakt.'
        'fix.restorePointNone'       = 'Geen herstelpunt: Systeembeveiliging staat uit op deze pc.'

        # ---- relay, unlock, visit memory
        'relay.askCode'      = 'Code uit Google Authenticator (Enter = overslaan)'
        'relay.unlocked'     = 'Ontgrendeld tot {0}.'
        'relay.wrongCode'    = 'Die code klopt niet. Typ de code die de app nu laat zien.'
        'relay.codeUsed'     = 'Die code is al gebruikt. Wacht op de volgende (elke 30 seconden).'
        'relay.locked'       = 'Te veel verkeerde codes: wacht 15 minuten.'
        'relay.notSetUp'     = 'De relay is nog niet ingesteld: start tools\setup-ai.ps1 op uw eigen pc.'
        'relay.expired'      = 'De ontgrendeling is verlopen: typ een nieuwe code.'
        'relay.unreachable'  = 'De relay is niet bereikbaar. Staat het Supabase-project op pauze? Herstel het in het Supabase-dashboard.'
        'relay.aiKey'        = 'De AI-sleutel in Supabase klopt niet: controleer ANTHROPIC_API_KEY.'
        'relay.aiBusy'       = 'De AI is nu druk: probeer het over een minuut opnieuw.'
        'relay.aiCredit'     = 'Het Anthropic-account heeft geen tegoed: voeg tegoed toe via console.anthropic.com > Billing.'
        'relay.error'        = 'De relay gaf een fout ({0}).'
        'menu.history'       = 'Bezoekgeschiedenis'
        'mem.title'          = 'Bezoekgeschiedenis van deze pc'
        'mem.none'           = 'Geen eerdere bezoeken vastgelegd voor deze pc.'
        'mem.known'          = 'Bekende pc{0}: laatste bezoek {1}'
        'mem.saveAsk'        = 'Dit bezoek opslaan in uw bezoekgeschiedenis? Code uit Google Authenticator (Enter = overslaan)'
        'mem.labelAsk'       = 'Naam of kenmerk voor deze pc, voor uw administratie (Enter = {0})'
        'mem.noLabel'        = 'geen'
        'mem.saved'          = 'Bezoek opgeslagen in uw bezoekgeschiedenis.'
        'mem.notSaved'       = 'Het bezoek is niet opgeslagen: {0}'

        # ---- the AI chat
        'ai.describe'        = 'Beschrijf het probleem in uw eigen woorden (Enter = terug)'
        'ai.privacy'         = 'Alleen het probleem en de uitkomst van de controles gaan naar de AI. Geen bestanden, wachtwoorden of documenten.'
        'ai.thinking'        = 'De AI denkt na...'
        'ai.running'         = 'De AI controleert: {0}  {1}'
        'ai.answer'          = 'AI:'
        'ai.confidence.low'    = 'Zekerheid: laag (de controles laten de oorzaak niet zien)'
        'ai.confidence.medium' = 'Zekerheid: middel'
        'ai.confidence.high'   = 'Zekerheid: hoog'
        'ai.steps'           = 'Stappen:'
        'ai.refused'         = 'De AI heeft deze vraag niet beantwoord. Kies een letter uit het menu.'
        'ai.noAnswer'        = 'De AI kwam niet tot een antwoord. Kies een letter uit het menu.'

        # ---- the invoice
        'inv.askCode'     = 'Code uit Google Authenticator voor de factuur (Enter = geen factuur, alleen het briefje)'
        'inv.title'       = 'Factuur'
        'inv.intro'       = 'Enter = de suggestie tussen haakjes, 0 = geen factuur (dan het briefje)'
        'inv.clientName'  = 'Naam van de klant [{0}]'
        'inv.address'     = 'Straat en huisnummer'
        'inv.postcode'    = 'Postcode en plaats'
        'inv.email'       = 'E-mail (niet verplicht)'
        'inv.minutes'     = 'Gewerkte tijd in minuten [{0}]'
        'inv.minutesBad'  = 'Typ een aantal minuten, bijv. 45.'
        'inv.labour'      = 'Arbeid: {0} min, {1} per uur'
        'inv.startLine'       = 'Arbeid {0} min: starttarief (tot {1} min)'
        'inv.extraTime'       = '+ {0} x 15 min extra, {1} per kwartier'
        'inv.win.rateStart'   = '{0} voor de eerste {1} min, daarna {2} per begonnen kwartier'
        'inv.win.done'        = 'Wat er is gedaan (kies of typ zelf)'
        'inv.win.asked'       = 'Hulpvraag'
        'inv.win.fixed'       = 'Opgelost'
        'inv.win.notFixed'    = 'Niet opgelost'
        'inv.win.remove'      = 'Geselecteerde verwijderen'
        'inv.win.itemFixed'   = 'Opgelost: {0}'
        'inv.win.itemOpen'    = 'Niet opgelost: {0}'
        'work.presets'        = ('Internet en wifi weer werkend gemaakt | Printer ge' + [char]0xEF + 'nstalleerd | Printer weer werkend gemaakt | E-mail ingesteld | Windows bijgewerkt | Computer sneller gemaakt | Opstartprogramma''s opgeruimd | Virusscan gedaan | Ongewenste programma''s verwijderd | Geluid weer werkend gemaakt | Apparaat aangesloten en ingesteld | Wachtwoord hersteld | Back-up gemaakt van foto''s en bestanden | Nieuwe computer ingesteld | Uitleg gegeven over het gebruik | Onderdeel moet besteld worden | Probleem ligt bij de internetprovider | Computer is te oud om te repareren')
        'inv.callout'     = 'Voorrijkosten van {0} rekenen? (J/N) [J]'
        'inv.calloutLine' = 'Voorrijkosten'
        'inv.extra'       = 'Extra regel, bijv. "Draadloze muis 19,95" (Enter = klaar)'
        'inv.extraBad'    = 'Typ een omschrijving en dan een bedrag, bijv. "USB-stick 12,50".'
        'inv.noLines'     = 'Er is niets te factureren: het briefje wordt getoond.'
        'inv.payment'     = 'Betaling: {0}'
        'inv.pay.pin'      = 'pin'
        'inv.pay.cash'     = 'contant'
        'inv.pay.transfer' = 'overmaken'
        'inv.pay.tikkie'   = 'betaalverzoek'
        'inv.confirm'     = 'Totaal {0}. Factuur maken? (J/N)'
        'inv.noSettings'  = 'Uw factuurgegevens zijn nog niet ingesteld: start tools\setup-invoice.ps1. Het briefje wordt getoond.'
        'inv.failed'      = 'De factuur kon niet worden gemaakt: {0} Het briefje wordt getoond.'
        'inv.skipped'     = 'Geen factuur: het briefje wordt getoond.'
        'inv.made'        = 'Factuur {0} gemaakt.'
        'inv.win.client'      = 'Klant'
        'inv.win.name'        = 'Naam'
        'inv.win.work'        = 'Werk'
        'inv.win.minutes'     = 'Gewerkte tijd (minuten)'
        'inv.win.rate'        = 'tegen {0} per uur'
        'inv.win.callout'     = 'Voorrijkosten {0}'
        'inv.win.extras'      = 'Extra regels (bijvoorbeeld een nieuwe muis)'
        'inv.win.description' = 'Omschrijving'
        'inv.win.amount'      = 'Bedrag'
        'inv.win.payment'     = 'Betaling'
        'inv.win.total'       = 'Totaal: {0}'
        'inv.win.make'        = 'Factuur maken'
        'inv.win.none'        = 'Geen factuur (briefje)'
        'inv.win.needName'    = 'Vul de naam van de klant in.'
        'inv.win.needPayment' = 'Kies hoe de klant betaalt.'
        'inv.win.badLine'     = 'Extra regel {0}: typ een omschrijving en een bedrag, zoals 19,95.'
        'inv.win.nothing'     = 'Er is nog niets te factureren: vul de tijd of een extra regel in.'
        'doc.invoice'     = 'FACTUUR {0}'
        'doc.date'        = 'Factuurdatum: {0}'
        'doc.kvk'         = 'KvK {0}'
        'doc.btwNumber'   = 'Btw-id {0}'
        'doc.iban'        = 'IBAN {0}'
        'doc.to'          = 'Factuur aan'
        'doc.costs'       = 'Kosten'
        'doc.subtotal'    = 'Subtotaal excl. btw'
        'doc.btw'         = 'Btw 21%'
        'doc.total'       = 'Totaal'
        'doc.paidPin'     = 'Betaald met pin op {0}.'
        'doc.paidCash'    = 'Contant betaald op {0}.'
        'doc.paidTikkie'  = 'Te betalen via het betaalverzoek van {0}.'
        'doc.transfer'    = 'Graag {0} overmaken voor {1} naar {2}, onder vermelding van factuurnummer {3}.'
        'doc.kor'         = 'Vrijgesteld van btw op grond van de kleineondernemersregeling (KOR).'
        'doc.btwUnset'    = 'Btw nog niet ingesteld.'
        'doc.thanks'      = 'Bedankt voor uw vertrouwen.'
        'doc.windowTitle' = 'Housecall - factuur {0}'
        'doc.invoiceWord' = 'Factuur'
        'doc.numberDate'  = ('{0}  ' + [char]0x00B7 + '  {1}')
        'doc.toCap'       = 'FACTUUR AAN'
        'doc.subjectCap'  = 'BETREFT'
        'doc.descriptionCap' = 'OMSCHRIJVING'
        'doc.amountCap'   = 'BEDRAG'
        'doc.workTitle'   = 'Computerhulp aan huis'
        'doc.notFixed'    = '{0} (nog niet opgelost)'
        'doc.totalWord'   = 'Totaal'
        'doc.pageOf'      = 'Pagina {0} van {1}'
        'mem.invoice'       = 'factuur {0}'
        'mem.deleteAsk'     = 'Nummer van een bezoek om te verwijderen (Enter = terug)'
        'mem.deleteConfirm' = 'Het bezoek van {0} verwijderen? (J/N)'
        'mem.deleted'       = 'Bezoek verwijderd.'
        'mem.invoiceKept'   = 'Factuur {0} blijft bewaard: facturen moeten 7 jaar bewaard worden.'
    }
}

$script:Lang = 'en'

# T 'key' returns the sentence in the current language; extra arguments fill
# its {0}, {1}... placeholders. A key missing from Dutch falls back to English,
# and a key missing from both shows as [key] so it is spotted, not hidden.
function T {
    # Deliberately not [Parameter(Mandatory)]: that makes it an advanced
    # function, and advanced functions refuse the extra $args used below.
    param([string]$Key)
    $text = $script:Strings[$script:Lang][$Key]
    if ($null -eq $text) { $text = $script:Strings['en'][$Key] }
    if ($null -eq $text) { return "[$Key]" }
    if ($args.Count -gt 0) { return ($text -f $args) }
    $text
}

# Dutch when Windows is set to Dutch, English for everything else.
function Get-HcDefaultLanguage {
    try {
        if ((Get-UICulture).Name -like 'nl*') { return 'nl' }
    } catch { }
    'en'
}

# ==================================================== src\ui.ps1 ==
<#
    Console output: the four line styles (same as Reveille's setup.ps1), menu
    options, and the banner.
#>

function Write-Step  { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  $m" -ForegroundColor Yellow }
function Write-Dim   { param([string]$m) Write-Host "  $m" -ForegroundColor DarkGray }

# One menu line: the key in yellow, then the label.  [A] Internet & Wi-Fi
function Write-Option {
    param([string]$Key, [string]$Label)
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Yellow
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Label
}

# Several short options on one line, for the footer: [0] Back  [L] English  [Q] Quit
function Write-OptionRow {
    param([object[]]$Options)
    Write-Host '  ' -NoNewline
    foreach ($o in $Options) {
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Write-Host $o[0] -NoNewline -ForegroundColor Yellow
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host ($o[1] + '    ') -NoNewline -ForegroundColor Gray
    }
    Write-Host ''
}

# Clearing between screens keeps the menu readable at the client's desk. A
# scripted run (the tests) keeps everything, so the output can be read back.
function Clear-HcScreen {
    if ($null -eq $script:HcInputQueue) {
        try { Clear-Host } catch { }
    }
}

# Every read goes through here, so tests can feed answers from a queue. When
# the queue runs dry, or there is no console to read from, the answer is Q:
# a scripted run ends instead of hanging.
$script:HcInputQueue = $null

function Read-HcLine {
    param([string]$Prompt)
    if ($null -ne $script:HcInputQueue) {
        if ($script:HcInputQueue.Count -eq 0) { return 'Q' }
        $line = [string]$script:HcInputQueue.Dequeue()
        Write-Host "  $Prompt> $line" -ForegroundColor DarkGray
        return $line
    }
    try {
        $line = Read-Host "  $Prompt"
    } catch {
        # Nobody at a console (a non-interactive run): remember it, so the
        # note is printed instead of waiting for a click that never comes.
        $script:NoConsole = $true
        return 'Q'
    }
    # $null is the end of the input (it was redirected from a file or NUL):
    # nobody will type anything more, so stop instead of asking forever.
    if ($null -eq $line) { $script:NoConsole = $true; return 'Q' }
    $line
}

<#
    The banner.

    Drawn from a bitmap the way Reveille draws its own, so this file stays
    plain ASCII: the block and rule characters are built from [char] codes and
    render correctly however the script is fetched.
#>

$script:Glyphs = @{
    'H' = @('#...#', '#...#', '#####', '#...#', '#...#')
    'O' = @('.###.', '#...#', '#...#', '#...#', '.###.')
    'U' = @('#...#', '#...#', '#...#', '#...#', '.###.')
    'S' = @('.####', '#....', '.###.', '....#', '####.')
    'E' = @('#####', '#....', '####.', '#....', '#####')
    'C' = @('.####', '#....', '#....', '#....', '.####')
    'A' = @('.###.', '#...#', '#####', '#...#', '#...#')
    'L' = @('#....', '#....', '#....', '#....', '#####')
}

function Write-Banner {
    param([pscustomobject]$Environment)

    $block = [string][char]0x2588      # full block
    $rule = [string][char]0x2500       # horizontal rule
    $word = 'HOUSECALL'

    # Warm yellow at the top falling to orange: a porch light. HOUSE and CALL
    # share the gradient; the H keeps the bright end so it reads as the mark.
    $gradient = @('Yellow', 'Yellow', 'DarkYellow', 'DarkYellow', 'DarkRed')

    Write-Host ''
    for ($row = 0; $row -lt 5; $row++) {
        Write-Host '  ' -NoNewline
        for ($i = 0; $i -lt $word.Length; $i++) {
            $line = $script:Glyphs[[string]$word[$i]][$row]
            $text = ($line -replace '#', $block) -replace '\.', ' '
            $colour = if ($i -eq 0) { 'White' } else { $gradient[$row] }
            Write-Host "$text " -ForegroundColor $colour -NoNewline
        }
        Write-Host ''
    }

    Write-Host ''
    Write-Host ('  ' + ($rule * 53)) -ForegroundColor DarkGray
    Write-Host ('   ' + (T 'tagline')) -ForegroundColor Gray
    if ($Environment) { Write-HcStatus $Environment }
    Write-Host ('  ' + ($rule * 53)) -ForegroundColor DarkGray
    Write-Dim (T 'promise')
    Write-Host ''
}

# One line under the banner: what this PC is and what Housecall may do on it.
#   Windows 11 Home  .  PowerShell 5.1  .  not admin  .  online
function Write-HcStatus {
    param([pscustomobject]$Environment)
    $dot = '  ' + [char]0x00B7 + '  '
    $parts = @(
        $Environment.Os
        ('PowerShell ' + $Environment.PSVersion.Major + '.' + $Environment.PSVersion.Minor)
        $(if ($Environment.IsAdmin) { T 'status.admin' } else { T 'status.notAdmin' })
        $(if ($Environment.Online) { T 'status.online' } else { T 'status.offline' })
    )
    Write-Host ('   ' + ($parts -join $dot)) -ForegroundColor DarkGray
    # How long this visit has been going; yellow once the starting price is used up.
    $clock = Get-HcClockLine
    Write-Host ('   ' + $clock.Text) -ForegroundColor $(if ($clock.Over) { 'Yellow' } else { 'DarkGray' })
    if ($script:DryRun) {
        Write-Host ('   ' + (T 'status.dryRun')) -ForegroundColor Magenta
    }
}

# ==================================================== src\environment.ps1 ==
<#
    What Housecall needs to know about the PC before it shows the menu.
    Everything here is read-only and quick: the whole thing should finish in
    well under two seconds, even offline.
#>

function Test-HcAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Milliseconds to open a TCP connection, or -1 when it does not get through
# within the timeout (unreachable, refused, firewall).
function Get-HcTcpMs {
    param([string]$Address, [int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $attempt = $client.BeginConnect($Address, $Port, $null, $null)
        if ($attempt.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) {
            return [int][math]::Max(1, $clock.ElapsedMilliseconds)
        }
    } catch {
    } finally {
        $client.Close()
    }
    -1
}

# Milliseconds for one ping, or -1 for no reply.
function Get-HcPingMs {
    param([string]$Address, [int]$TimeoutMs = 1000)
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $ping.Send($Address, $TimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return [int][math]::Max(1, $reply.RoundtripTime)
        }
    } catch {
    } finally {
        $ping.Dispose()
    }
    -1
}

# Milliseconds to reach the internet, or -1. Uses IP addresses, not names, so
# a broken DNS still counts as online -- telling those apart is A1's job.
function Get-HcInternetMs {
    foreach ($target in @(@('1.1.1.1', 443), @('8.8.8.8', 53))) {
        $ms = Get-HcTcpMs $target[0] $target[1]
        if ($ms -ge 0) { return $ms }
    }
    -1
}

function Test-HcOnline { (Get-HcInternetMs) -ge 0 }

<#
    Online is measured at the start, but a visit often fixes the internet
    (A1). Before anything that needs the relay, and after a fix, an offline
    PC is measured again, so the invoice and history still work once the
    internet is back. Costs up to 3 seconds, and only while offline.
#>
<#
    A copy on a USB stick does not update itself. When it runs from a file
    and the PC is online, it compares its build with version.txt on GitHub
    and returns a warning when they differ; $null when all is well, or when
    it cannot tell (offline, no answer, the dev version).
#>
function Get-HcOutdatedWarning {
    param([pscustomobject]$Environment)
    if (-not $script:HcFromFile -or "$script:HcBuild" -notmatch '^[0-9a-f]{12}$' -or -not $Environment.Online) { return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $latest = "$((Invoke-WebRequest -Uri 'https://github.com/Shamilimanuel/Housecall/raw/main/version.txt' -UseBasicParsing -TimeoutSec 5).Content)".Trim()
    } catch { return $null }
    if ($latest -notmatch '^[0-9a-f]{12}$' -or $latest -eq $script:HcBuild) { return $null }
    T 'env.outdated'
}

function Update-HcOnline {
    param([pscustomobject]$Environment)
    if (-not $Environment.Online) { $Environment.Online = Test-HcOnline }
}

# "Windows 11 Home" rather than "Microsoft Windows 11 Home".
function Get-HcOsName {
    try {
        $caption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
        return ($caption -replace '^Microsoft\s+', '').Trim()
    } catch {
        return 'Windows'
    }
}

function Get-HcEnvironment {
    [pscustomobject]@{
        IsWindows = ($env:OS -eq 'Windows_NT')
        PSVersion = $PSVersionTable.PSVersion
        Os        = Get-HcOsName
        IsAdmin   = Test-HcAdmin
        Online    = Test-HcOnline
    }
}

# ==================================================== src\menu.ps1 ==
<#
    The menu: letter = area, number = problem. A opens an area, A1 jumps
    straight to a problem, and inside an area a bare 1 means the same as A1.

    Reserved keys, never to be used as an area letter:
        ?  AI chat    0  back    L  language    H  visit history
        U  undo this session's fixes    Q  quit
#>

$script:Areas = [ordered]@{
    A = @('A1', 'A2', 'A3', 'A4')
    B = @('B1', 'B2', 'B3')
    C = @('C1', 'C2', 'C3')
    D = @('D1', 'D2', 'D3', 'D4')
    E = @('E1', 'E2', 'E3')
    F = @('F1', 'F2', 'F3')
    G = @('G1', 'G2', 'G3')
}

<#
    Turn what was typed into one decision. Pure: no output, no state, so the
    tests can cover every kind of input.

    Kind is one of: empty, area, problem, ai, back, language, history, undo, quit,
    freetext (a sentence, which the AI chat will take), unknown.
#>
function Resolve-HcChoice {
    param(
        [AllowEmptyString()][string]$Text,
        # The letter of the area on screen, or '' on the home menu.
        [string]$CurrentArea = ''
    )

    $raw = if ($null -eq $Text) { '' } else { $Text.Trim() }
    $key = $raw.ToUpperInvariant()
    $result = { param($kind, $value) [pscustomobject]@{ Kind = $kind; Value = $value } }

    if ($key -eq '') { return & $result 'empty' $null }
    if ($key -eq '?') { return & $result 'ai' $null }
    if ($key -eq '0') { return & $result 'back' $null }
    if ($key -eq 'L') { return & $result 'language' $null }
    if ($key -eq 'Q') { return & $result 'quit' $null }
    if ($key -eq 'U') { return & $result 'undo' $null }
    if ($key -eq 'H') { return & $result 'history' $null }

    if ($script:Areas.Contains($key)) { return & $result 'area' $key }

    if ($key -match '^([A-Z])(\d)$' -and $script:Areas.Contains($Matches[1])) {
        if ($script:Areas[$Matches[1]] -contains $key) { return & $result 'problem' $key }
        return & $result 'unknown' $raw
    }

    if ($key -match '^\d$' -and $CurrentArea) {
        $code = $CurrentArea + $key
        if ($script:Areas[$CurrentArea] -contains $code) { return & $result 'problem' $code }
        return & $result 'unknown' $raw
    }

    # Three words or more reads as someone describing the problem.
    if (($raw -split '\s+').Count -ge 3) { return & $result 'freetext' $raw }

    & $result 'unknown' $raw
}

# ------------------------------------------------------------------ screens --

function Show-HcHome {
    param([pscustomobject]$Environment, [string]$Message)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'menu.question')) -ForegroundColor Yellow
    Write-Host ''
    foreach ($letter in $script:Areas.Keys) {
        Write-Option $letter (T "area.$letter")
    }
    Write-Host ''
    if (-not $script:NoAI) { Write-Option '?' (T 'menu.ai'); Write-Host '' }
    Write-OptionRow (Get-HcFooter)
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'menu.hintHome') }
}

function Show-HcArea {
    param([pscustomobject]$Environment, [string]$Letter, [string]$Message)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'area.question' $Letter (T "area.$Letter"))) -ForegroundColor Yellow
    Write-Host ''
    foreach ($code in $script:Areas[$Letter]) {
        Write-Option $code (T "problem.$code")
    }
    Write-Host ''
    if (-not $script:NoAI) { Write-Option '?' (T 'area.ai'); Write-Host '' }
    Write-OptionRow (@(, @('0', (T 'menu.back'))) + (Get-HcFooter))
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'area.hint') }
}

# The footer keys shared by every menu screen. U only shows once something
# was changed in this session.
function Get-HcFooter {
    $row = @(@('L', (T 'menu.language')), @('H', (T 'menu.history')))
    if ($script:HcChanges.Count -gt 0) { $row += , @('U', (T 'menu.undo')) }
    $row + (, @('Q', (T 'menu.quit')))
}

<#
    Runs the handler registered for $Code (see src\checks\), or says which
    checks will run once it is built.

    The handler returns a scriptblock that checks the PC and returns a
    report. After the report come the fixes it offers; once one is applied,
    the same check runs again, so the screen shows whether it worked.
#>
function Invoke-HcProblem {
    param([pscustomobject]$Environment, [string]$Code)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + $Code + '  ' + (T "problem.$Code")) -ForegroundColor Yellow
    Write-Host ''
    $handler = $script:ProblemHandlers[$Code]
    if (-not $handler) {
        Write-Warn2 (T 'problem.notBuilt')
        Write-Dim (T 'problem.willLook')
        Write-Dim ('  ' + (T ('looks.' + $Code.Substring(0, 1))))
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }

    $script:HcCurrentCode = $Code
    $check = & $handler
    if (-not $check) { return }      # e.g. A3 when no site was typed
    Write-Dim (T 'run.checking')
    Write-Host ''
    $report = & $check
    Write-HcReport $report
    Save-HcVisit $Code $report
    Invoke-HcReportLoop $Code $check $report
}

<#
    What follows a report: Wat nu?, a fix, the check again as proof, until
    Enter. $OnlyFixes (from the AI chat) limits the offered fixes to the
    ones the AI chose, in its order; they still come from the check itself.
#>
function Invoke-HcReportLoop {
    param([string]$Code, [scriptblock]$Check, [pscustomobject]$Report, [string[]]$OnlyFixes)
    if ($PSBoundParameters.ContainsKey('OnlyFixes')) { Select-HcActions $Report $OnlyFixes }
    while (@($Report.Actions).Count -gt 0 -or @(Get-HcSteps $Report).Count -gt 0) {
        $result = Invoke-HcActionMenu $Report
        if ($result -eq 'back') { return }
        if ($result -eq 'changed') {
            Write-Host ''
            Write-Dim (T 'fix.checkingAgain')
            Write-Host ''
            $Report = & $Check
            Write-HcReport $Report
            Save-HcVisit $Code $Report
            if ($PSBoundParameters.ContainsKey('OnlyFixes')) { Select-HcActions $Report $OnlyFixes }
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

# Keeps only the offered fixes whose id is in $FixIds, in that order.
function Select-HcActions {
    param([pscustomobject]$Report, [string[]]$FixIds)
    $kept = New-Object System.Collections.ArrayList
    foreach ($id in @($FixIds)) {
        foreach ($a in @($Report.Actions | Where-Object { $_.FixId -eq $id })) {
            if (-not $kept.Contains($a)) { [void]$kept.Add($a) }
        }
    }
    $Report.Actions = $kept
}

# ---------------------------------------------------------------- main loop --

function Start-Housecall {
    param(
        [switch]$DryRun,
        [string]$Lang,
        # A problem code to open straight away, e.g. after restarting as admin.
        [string]$Start,
        # Leave the AI chat out of the menu.
        [switch]$NoAI,
        # For tests: answers to feed in instead of reading the keyboard.
        [string[]]$Answers
    )

    $script:DryRun = [bool]$DryRun
    $script:NoAI = [bool]$NoAI
    $script:RestorePointDone = $false
    $script:HcChanges.Clear()
    $script:HcVisit.Clear()
    $script:HcWork.Clear()
    $script:HcAsked = ''
    $script:HandedOff = $false
    $script:HcToken = $null
    $script:HcKnownLabel = $null
    $script:HcQuitSkipped = $false
    $script:HcStartedAt = Get-Date
    $script:Lang = if ($script:Strings.ContainsKey("$Lang".ToLowerInvariant())) { "$Lang".ToLowerInvariant() } else { Get-HcDefaultLanguage }
    $script:HcInputQueue = $null
    if ($PSBoundParameters.ContainsKey('Answers')) {
        $script:HcInputQueue = New-Object System.Collections.Queue
        foreach ($a in $Answers) { $script:HcInputQueue.Enqueue($a) }
    }

    $environment = Get-HcEnvironment
    if (-not $environment.IsWindows) { Write-Warn2 (T 'env.notWindows'); return }
    if ($environment.PSVersion.Major -lt 5) {
        Write-Warn2 (T 'env.oldPowerShell' $environment.PSVersion.ToString())
        return
    }
    $script:IsAdmin = [bool]$environment.IsAdmin

    $area = ''          # '' = home menu, otherwise the letter on screen
    $message = $null    # one-off warning shown under the menu
    if (-not $Start) { $message = Get-HcOutdatedWarning $environment }

    $first = Resolve-HcChoice $Start
    if ($first.Kind -eq 'problem') {
        $area = $first.Value.Substring(0, 1)
        Invoke-HcProblem $environment $first.Value
    }

    while (-not $script:HandedOff) {
        if ($area) { Show-HcArea $environment $area $message } else { Show-HcHome $environment $message }
        $message = $null

        $choice = Resolve-HcChoice (Read-HcLine (T 'menu.prompt')) -CurrentArea $area
        if ($script:NoAI -and $choice.Kind -in @('ai', 'freetext')) {
            $choice = [pscustomobject]@{ Kind = 'unknown'; Value = $(if ($choice.Value) { $choice.Value } else { '?' }) }
        }
        if ($choice.Kind -in @('ai', 'freetext', 'history', 'quit')) { Update-HcOnline $environment }
        switch ($choice.Kind) {
            'area'     { $area = $choice.Value }
            'problem'  {
                $area = $choice.Value.Substring(0, 1)
                $before = $script:HcChanges.Count
                Invoke-HcProblem $environment $choice.Value
                if ($script:HcChanges.Count -ne $before) { Update-HcOnline $environment }
            }
            'ai'       { Invoke-HcAi $environment }
            'freetext' { Invoke-HcAi $environment $choice.Value }
            'back'     { $area = '' }
            'language' { $script:Lang = if ($script:Lang -eq 'nl') { 'en' } else { 'nl' } }
            'undo'     { $message = Invoke-HcUndo }
            'history'  { Show-HcHistory $environment }
            'unknown'  { $message = T 'menu.unknown' $choice.Value }
            'quit'     {
                # The invoice (or, without one, the plain note), and the visit saved with it.
                $invoice = Invoke-HcInvoice $environment
                Save-HcVisitRecord $environment $invoice
                if ($invoice) { Show-HcInvoice $invoice } else { Show-HcNote }
                Write-Host ''
                if ($script:HcChanges.Count -gt 0) { Write-Ok (T 'goodbyeChanged' $script:HcChanges.Count) } else { Write-Ok (T 'goodbye') }
                Write-Host ''
                return
            }
        }
    }
}

# ==================================================== src\checks\common.ps1 ==
<#
    The shape every check shares, for all areas A to F.

    A problem is handled in three steps, kept apart on purpose:

      1. Get-...Facts   reads the PC. Read-only, and the only step that
                        touches Windows, so tests replace it with fake facts.
      2. Test-...       turns facts into a report. Pure: no output, no
                        reading the PC, so every scenario can be tested.
      3. Write-HcReport prints the report.

    A report is a list of result lines plus one finding: the id of the most
    important thing found (finding.<id> and advice.<id> in strings.ps1).
    It can also offer actions: fixes from srcixes.ps1 that the verdict
    thinks will help, which the person can pick after reading the report.

    A handler returns a scriptblock that reads the PC and returns the
    report. Invoke-HcProblem runs it once, and again after every fix, as
    proof that the fix worked.
#>

# Problem code -> the function that handles it. Each area's file registers
# its own; a code with no handler shows the "not built yet" screen.
$script:ProblemHandlers = @{}

# One line of a report. Status is ok, problem, warn or skipped; Text is
# already in the current language.
function New-HcResult {
    param([string]$Status, [string]$Text)
    [pscustomobject]@{ Status = $Status; Text = $Text }
}

function New-HcReport {
    [pscustomobject]@{
        Results     = New-Object System.Collections.ArrayList
        FindingId   = $null
        FindingArgs = @()
        Actions     = New-Object System.Collections.ArrayList
    }
}

# Offers a fix. $FixId names an entry in $script:Fixes (srcixes.ps1);
# $Target is what it acts on, for example a task's name and folder.
function Add-HcAction {
    param([pscustomobject]$Report, [string]$FixId, [hashtable]$Target = @{})
    [void]$Report.Actions.Add([pscustomobject]@{ FixId = $FixId; Target = $Target })
}

# Adds a line to the report. Written as a function so the Test- functions
# stay readable: Add-HcLine $r ok (T 'net.dnsOk')
function Add-HcLine {
    param([pscustomobject]$Report, [string]$Status, [string]$Text)
    [void]$Report.Results.Add((New-HcResult $Status $Text))
}

# Sets the finding, unless one is already set: the first real problem in the
# chain is the cause, and whatever follows from it is not.
function Set-HcFinding {
    param([pscustomobject]$Report, [string]$Id, [object[]]$Arguments = @())
    if ($null -eq $Report.FindingId) {
        $Report.FindingId = $Id
        $Report.FindingArgs = $Arguments
    }
}

$script:ResultStyle = @{
    ok      = @('[ OK ]', 'Green')
    problem = @('[ !! ]', 'Red')
    warn    = @('[ !  ]', 'Yellow')
    skipped = @('[ -- ]', 'DarkGray')
}

function Write-HcReport {
    # -LinesOnly: the result lines without the finding, for the AI chat,
    # which gives its own answer.
    param([pscustomobject]$Report, [switch]$LinesOnly)
    foreach ($line in $Report.Results) {
        $style = $script:ResultStyle[$line.Status]
        Write-Host ('  ' + $style[0] + ' ') -NoNewline -ForegroundColor $style[1]
        $colour = if ($line.Status -eq 'skipped') { 'DarkGray' } else { 'Gray' }
        Write-Host $line.Text -ForegroundColor $colour
    }
    if ($Report.FindingId -and -not $LinesOnly) {
        $findingArgs = @('finding.' + $Report.FindingId) + @($Report.FindingArgs)
        Write-Host ''
        Write-HcLabelled (T 'run.found') (T @findingArgs) 'Yellow'
        Write-Host ''
        Write-HcLabelled (T 'run.advice') (T ('advice.' + $Report.FindingId)) 'Cyan'
    }
}

# "Found: text" with the text word-wrapped under itself, so a long sentence
# does not run back to the left edge of the window.
function Write-HcLabelled {
    param([string]$Label, [string]$Text, [string]$LabelColour)
    $width = 100
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 40) { $width = [math]::Min($w - 2, 100) }
    } catch { }

    $indent = ' ' * (2 + $Label.Length + 1)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($word in ($Text -split ' ')) {
        if ($current -and ($indent.Length + $current.Length + 1 + $word.Length) -gt $width) {
            $lines.Add($current)
            $current = $word
        } elseif ($current) {
            $current += ' ' + $word
        } else {
            $current = $word
        }
    }
    if ($current) { $lines.Add($current) }

    Write-Host ('  ' + $Label + ' ') -NoNewline -ForegroundColor $LabelColour
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 0) { Write-Host $lines[$i] } else { Write-Host ($indent + $lines[$i]) }
    }
}

# ==================================================== src\checks\network.ps1 ==
<#
    Area A: Internet & Wi-Fi.

      A1  no internet at all          Test-HcInternet
      A2  Wi-Fi slow or drops         Test-HcInternet, then Test-HcConnectionQuality
      A3  one website will not load   Test-HcInternet, then Test-HcSite
      A4  email                       not built yet

    The chain in Test-HcInternet follows the path a packet takes: adapter,
    connection, address, router, internet, names (DNS), the web. The first
    link that fails is the finding; the links after it are skipped, because
    they cannot work without it.

    Everything is read with objects (Get-NetAdapter, Get-NetIPConfiguration),
    never by reading the text of ipconfig, because Windows translates that
    text. The one exception is netsh for the Wi-Fi name and signal, where
    only the untranslated parts are matched: "SSID" and a number with "%".
#>

$script:WeakSignal = 40      # % and below counts as weak
$script:TestHost = 'www.msftconnecttest.com'   # what Windows itself uses to test the internet

# ------------------------------------------------------------------- facts --

function Get-HcWifiInfo {
    $info = [pscustomobject]@{ Ssid = $null; Signal = $null }
    try {
        $text = & netsh.exe wlan show interfaces 2>$null
        foreach ($line in $text) {
            if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { $info.Ssid = $Matches[1] }
            elseif ($line -match ':\s*(\d{1,3})\s*%\s*$') { $info.Signal = [int]$Matches[1] }
        }
    } catch { }
    $info
}

# The proxy Windows programs are told to use, or $null. Adware likes setting
# one, including an automatic-configuration script (AutoConfigURL).
function Get-HcProxy {
    try {
        $s = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($s.ProxyEnable -eq 1 -and $s.ProxyServer) { return [string]$s.ProxyServer }
        if ($s.AutoConfigURL) { return [string]$s.AutoConfigURL }
    } catch { }
    $null
}

function Test-HcDns {
    param([string]$Name = $script:TestHost)
    try {
        $answer = Resolve-DnsName -Name $Name -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
        return @($answer | Where-Object { $_.IPAddress }).Count -gt 0
    } catch {
        return $false
    }
}

# 'ok', 'intercepted' (something else answered: a login page, a proxy) or
# 'failed'. Plain http on purpose: a Wi-Fi login page can only catch that.
function Get-HcWebTest {
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $page = Invoke-WebRequest -Uri "http://$script:TestHost/connecttest.txt" -UseBasicParsing `
            -TimeoutSec 6 -MaximumRedirection 0 -ErrorAction Stop
        if ($page.Content -match 'Microsoft Connect Test') { return 'ok' }
        return 'intercepted'
    } catch {
        # A redirect (to a login page) also lands here, as an error.
        $response = $_.Exception.Response
        if ($null -ne $response) { return 'intercepted' }
        return 'failed'
    } finally {
        $ProgressPreference = $saved
    }
}

<#
    Reads everything A1 needs, in the order of the chain, and stops reading
    once a link is missing: there is no point waiting for a router that has
    no address to answer. Fields left $null were not checked.
#>
function Get-HcNetworkFacts {
    $f = [pscustomobject]@{
        Adapters = @(); Active = $null; Ssid = $null; Signal = $null
        IPv4 = $null; Dhcp = $null; Gateway = $null; DnsServers = @()
        Proxy = $null; GatewayMs = $null; InternetMs = $null; DnsOk = $null; Web = $null
    }

    $f.Adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -notmatch 'Bluetooth' } |
        ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Status  = [string]$_.Status
                IsWifi  = ([string]$_.PhysicalMediaType -match '802\.11') -or ($_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN')
                IfIndex = $_.ifIndex
            }
        })
    $f.Proxy = Get-HcProxy

    $up = @($f.Adapters | Where-Object { $_.Status -eq 'Up' })
    if ($up.Count -eq 0) { return $f }

    # The adapter in use is the one with a router; otherwise the first one up.
    $chosen = $null
    foreach ($a in $up) {
        $config = Get-NetIPConfiguration -InterfaceIndex $a.IfIndex -ErrorAction SilentlyContinue
        if ($null -eq $chosen -or ($config.IPv4DefaultGateway -and -not $chosen.Config.IPv4DefaultGateway)) {
            $chosen = [pscustomobject]@{ Adapter = $a; Config = $config }
        }
    }
    $f.Active = $chosen.Adapter
    $config = $chosen.Config
    if ($config) {
        $f.IPv4 = @($config.IPv4Address | ForEach-Object { $_.IPAddress }) | Select-Object -First 1
        $f.Gateway = @($config.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Select-Object -First 1
        $f.DnsServers = @($config.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
    }
    $ipInterface = Get-NetIPInterface -InterfaceIndex $f.Active.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipInterface) { $f.Dhcp = ([string]$ipInterface.Dhcp -eq 'Enabled') }

    if ($f.Active.IsWifi) {
        $wifi = Get-HcWifiInfo
        $f.Ssid = $wifi.Ssid
        $f.Signal = $wifi.Signal
    }

    if (-not $f.IPv4 -or $f.IPv4 -like '169.254.*' -or -not $f.Gateway) { return $f }

    $f.GatewayMs = Get-HcPingMs $f.Gateway
    if ($f.GatewayMs -lt 0) { $f.GatewayMs = Get-HcPingMs $f.Gateway }   # one retry
    $f.InternetMs = Get-HcInternetMs
    if ($f.InternetMs -lt 0) { return $f }

    $f.DnsOk = Test-HcDns
    if ($f.DnsOk) { $f.Web = Get-HcWebTest }
    $f
}

# ------------------------------------------------------------------ verdict --

# A1. Walks the chain; see the top of this file.
function Test-HcInternet {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $f = $Facts

    # Adapter
    if (@($f.Adapters).Count -eq 0) {
        Add-HcLine $r problem (T 'net.noAdapter')
        Set-HcFinding $r 'noAdapter'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    if ($null -eq $f.Active) {
        $wifi = @($f.Adapters | Where-Object { $_.IsWifi }) | Select-Object -First 1
        $cable = @($f.Adapters | Where-Object { -not $_.IsWifi }) | Select-Object -First 1
        if ($wifi -and $wifi.Status -eq 'Disabled') {
            Add-HcLine $r problem (T 'net.wifiDisabled' $wifi.Name)
            Set-HcFinding $r 'wifiDisabled'
        } elseif ($wifi) {
            Add-HcLine $r problem (T 'net.wifiNotConnected')
            Set-HcFinding $r 'wifiNotConnected'
        } elseif ($cable.Status -eq 'Disabled') {
            Add-HcLine $r problem (T 'net.adapterOff' $cable.Name)
            Set-HcFinding $r 'adapterOff'
        } else {
            Add-HcLine $r problem (T 'net.cableUnplugged' $cable.Name)
            Set-HcFinding $r 'cableUnplugged'
        }
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.adapterUp' $f.Active.Name)

    # Connection
    $weak = $false
    if ($f.Active.IsWifi) {
        if ($f.Ssid -and $null -ne $f.Signal) {
            Add-HcLine $r ok (T 'net.wifiConnected' $f.Ssid $f.Signal)
            if ($f.Signal -le $script:WeakSignal) {
                Add-HcLine $r warn (T 'net.weakSignal' $f.Signal)
                $weak = $true
            }
        } else {
            Add-HcLine $r ok (T 'net.wifiConnectedNoSignal')
        }
    } else {
        Add-HcLine $r ok (T 'net.cableConnected')
    }
    if ($f.Proxy) { Add-HcLine $r warn (T 'net.proxy' $f.Proxy) }

    # Address
    if (-not $f.IPv4 -or $f.IPv4 -like '169.254.*') {
        $shown = if ($f.IPv4) { $f.IPv4 } else { T 'net.none' }
        Add-HcLine $r problem (T 'net.noAddress' $shown)
        Set-HcFinding $r 'noAddress'
        Add-HcAction $r 'renewIp'
        Add-HcAction $r 'restartAdapter' @{ Label = $f.Active.Name; Name = $f.Active.Name }
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    if ($f.Dhcp -eq $false) {
        Add-HcLine $r warn (T 'net.addressStatic' $f.IPv4)
    } else {
        Add-HcLine $r ok (T 'net.address' $f.IPv4)
    }

    # Router
    if (-not $f.Gateway) {
        Add-HcLine $r problem (T 'net.noGateway')
        Set-HcFinding $r 'noGateway'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    $internetOk = ($null -ne $f.InternetMs -and $f.InternetMs -ge 0)
    if ($f.GatewayMs -ge 0) {
        Add-HcLine $r ok (T 'net.gatewayOk' $f.Gateway $f.GatewayMs)
    } elseif ($internetOk) {
        # Some routers ignore pings. The internet getting through proves it works.
        Add-HcLine $r ok (T 'net.gatewayNoPing' $f.Gateway)
    } else {
        Add-HcLine $r problem (T 'net.gatewayDown' $f.Gateway)
        Set-HcFinding $r 'gatewayDown'
        Add-HcAction $r 'restartAdapter' @{ Label = $f.Active.Name; Name = $f.Active.Name }
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }

    # Internet
    if (-not $internetOk) {
        Add-HcLine $r problem (T 'net.internetDown')
        Set-HcFinding $r 'internetDown'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.internetOk' $f.InternetMs)

    # Names
    if ($f.DnsOk -eq $false) {
        $servers = if (@($f.DnsServers).Count) { @($f.DnsServers) -join ', ' } else { T 'net.none' }
        Add-HcLine $r problem (T 'net.dnsDown' $servers)
        Set-HcFinding $r 'dnsDown'
        Add-HcAction $r 'flushDns'
        Add-HcAction $r 'resetWinsock'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.dnsOk')

    # The web
    switch ($f.Web) {
        'ok'          { Add-HcLine $r ok (T 'net.webOk') }
        'intercepted' { Add-HcLine $r problem (T 'net.webIntercepted'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }) }
        'failed'      { Add-HcLine $r problem (T 'net.webFailed'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }); Add-HcAction $r 'resetWinsock' }
    }

    # Nothing broken: the smaller things, then all good.
    if ($f.Proxy) { Set-HcFinding $r 'proxy'; Add-HcAction $r 'proxyOff' }
    if ($weak) { Set-HcFinding $r 'weakSignal' }
    Set-HcFinding $r 'allGood'
    $r
}

# The findings after which the internet itself works, so A2 and A3 can go on.
$script:InternetWorks = @('allGood', 'weakSignal', 'proxy')

function Get-HcConnectionQuality {
    param([string]$Gateway, [int]$Count = 10)
    $times = @()
    $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        $ms = Get-HcPingMs $Gateway 1000
        if ($ms -ge 0) { $times += $ms } else { $lost++ }
    }
    $average = if ($times.Count) { [int]($times | Measure-Object -Average).Average } else { -1 }
    [pscustomobject]@{ Sent = $Count; Lost = $lost; AverageMs = $average }
}

# Wi-Fi disconnects in the past 7 days (WLAN-AutoConfig event 8003), or $null
# when there is no Wi-Fi log to read. Sleep and shutdown count too, which is
# why the bar for calling it a problem is high.
function Get-HcWifiDrops {
    try {
        $filter = @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8003; StartTime = (Get-Date).AddDays(-7) }
        return @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop).Count
    } catch {
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { return 0 }
        return $null
    }
}

# A2. Only goes further than A1 when the internet works at all.
function Test-HcConnectionQuality {
    param([pscustomobject]$Facts, [pscustomobject]$Quality, $Drops)
    $r = Test-HcInternet $Facts
    if ($script:InternetWorks -notcontains $r.FindingId) { return $r }

    $base = $r.FindingId
    $r.FindingId = $null
    $lossPct = 0
    if ($Quality) {
        if ($Quality.Lost -eq 0) {
            Add-HcLine $r ok (T 'net.lossOk' $Quality.Sent $Quality.AverageMs)
        } else {
            $lossPct = [int](100 * $Quality.Lost / $Quality.Sent)
            $status = if ($lossPct -ge 10) { 'problem' } else { 'warn' }
            Add-HcLine $r $status (T 'net.loss' $Quality.Lost $Quality.Sent)
        }
    }
    if ($Facts.Active.IsWifi -and $null -ne $Drops) {
        $status = if ($Drops -ge 50) { 'problem' } else { 'ok' }
        Add-HcLine $r $status (T 'net.drops' $Drops)
    }

    if ($base -eq 'weakSignal') { Set-HcFinding $r 'weakSignal' }
    if ($lossPct -ge 10) { Set-HcFinding $r 'unstable' @($lossPct) }
    if ($Facts.Active.IsWifi -and $Drops -ge 50) { Set-HcFinding $r 'dropsMany' @($Drops) }
    if ($base -eq 'proxy') { Set-HcFinding $r 'proxy' }
    Set-HcFinding $r 'connHealthy'
    $r
}

# ------------------------------------------------------------- one website --

# "https://www.Marktplaats.nl/abc" -> "www.marktplaats.nl"; $null when it is
# not a web address at all.
function ConvertTo-HcHostName {
    param([string]$Text)
    $h = "$Text".Trim().ToLowerInvariant()
    $h = $h -replace '^[a-z][a-z0-9+.-]*://', ''
    $h = $h -replace '[/?#].*$', ''
    $h = $h -replace ':\d+$', ''
    if ($h -match '^([a-z0-9-]+\.)+[a-z]{2,}$') { return $h }
    $null
}

# A line in the hosts file that sends this site (or its www. twin) somewhere,
# as the address it is sent to, or $null.
function Get-HcHostsEntry {
    param([string]$HostName, [string]$Path = (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'))
    $names = @($HostName, ($HostName -replace '^www\.', ''), ('www.' + ($HostName -replace '^www\.', '')))
    try {
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $clean = ($line -replace '#.*$', '').Trim()
            if (-not $clean) { continue }
            $parts = $clean -split '\s+'
            if ($parts.Count -lt 2) { continue }
            foreach ($name in $parts[1..($parts.Count - 1)]) {
                if ($names -contains $name.ToLowerInvariant()) { return $parts[0] }
            }
        }
    } catch { }
    $null
}

function Get-HcSiteFacts {
    param([string]$HostName)
    $s = [pscustomobject]@{ Host = $HostName; HostsEntry = $null; Address = $null; TcpMs = $null; HttpStatus = $null }
    $s.HostsEntry = Get-HcHostsEntry $HostName

    try {
        $s.Address = @([System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.IPAddressToString }) |
            Select-Object -First 1
    } catch { }
    if (-not $s.Address) { return $s }

    $s.TcpMs = Get-HcTcpMs $s.Address 443 3000
    if ($s.TcpMs -lt 0) { return $s }

    # Older Windows 10 builds still offer TLS 1.0 first; most sites refuse it.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $page = Invoke-WebRequest -Uri "https://$HostName/" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $s.HttpStatus = [int]$page.StatusCode
    } catch {
        $response = $_.Exception.Response
        $s.HttpStatus = if ($null -ne $response) { [int]$response.StatusCode } else { 0 }
    } finally {
        $ProgressPreference = $saved
    }
    $s
}

# A3, after A1 said the internet works. 4xx still means the site is alive
# (403 is often just bot protection); only 5xx and silence count against it.
function Test-HcSite {
    param([pscustomobject]$Site)
    $r = New-HcReport
    $h = $Site.Host
    Add-HcLine $r ok (T 'net.internetWorks')

    if ($Site.HostsEntry) {
        Add-HcLine $r problem (T 'site.hosts' $h $Site.HostsEntry)
        Set-HcFinding $r 'siteHosts'
    } else {
        Add-HcLine $r ok (T 'site.hostsOk' $h)
    }

    if (-not $Site.Address) {
        Add-HcLine $r problem (T 'site.dnsFail' $h)
        Set-HcFinding $r 'siteNotFound' @($h)
        return $r
    }
    Add-HcLine $r ok (T 'site.dnsOk' $h $Site.Address)

    if ($Site.TcpMs -lt 0) {
        Add-HcLine $r problem (T 'site.tcpFail' $h)
        Set-HcFinding $r 'siteBlocked'
        return $r
    }
    Add-HcLine $r ok (T 'site.tcpOk' $h $Site.TcpMs)

    if ($Site.HttpStatus -ge 500) {
        Add-HcLine $r problem (T 'site.httpError' $h $Site.HttpStatus)
        Set-HcFinding $r 'siteError' @($Site.HttpStatus)
    } elseif ($Site.HttpStatus -ge 200) {
        Add-HcLine $r ok (T 'site.httpOk' $h $Site.HttpStatus)
    } else {
        Add-HcLine $r problem (T 'site.httpNone' $h)
        Set-HcFinding $r 'siteBlocked'
    }
    Set-HcFinding $r 'siteOk'
    $r
}

# ---------------------------------------------------------------- handlers --

# Each handler returns the check as a scriptblock (see src\checks\common.ps1).
function Invoke-HcA1 { { Test-HcInternet (Get-HcNetworkFacts) } }

function Invoke-HcA2 {
    {
        $facts = Get-HcNetworkFacts
        $quality = $null
        $drops = $null
        if ($facts.GatewayMs -ge 0) { $quality = Get-HcConnectionQuality $facts.Gateway }
        if ($facts.Active.IsWifi) { $drops = Get-HcWifiDrops }
        Test-HcConnectionQuality $facts $quality $drops
    }
}

function Invoke-HcA3 {
    $hostName = $null
    while (-not $hostName) {
        $typed = Read-HcLine (T 'site.ask')
        if (-not "$typed".Trim() -or "$typed".Trim().ToUpperInvariant() -eq 'Q') { return }
        $hostName = ConvertTo-HcHostName $typed
        if (-not $hostName) { Write-Warn2 (T 'site.invalid' $typed) }
    }
    Write-Host ''
    New-HcSiteCheck $hostName
}

function Invoke-HcSiteCheck {
    param([string]$HostName)
    $base = Test-HcInternet (Get-HcNetworkFacts)
    # The internet itself is down: that is the answer, not the site.
    if ($script:InternetWorks -notcontains $base.FindingId) { return $base }
    Test-HcSite (Get-HcSiteFacts $HostName)
}

# The A3 check for one site, as a scriptblock that names it. Built from text
# rather than a closure: a closure cannot see Housecall's functions when it
# runs through [scriptblock]::Create, and a shared variable would be
# overwritten when the AI runs several checks. The name is checked first,
# so only letters, digits, dots and dashes ever reach the text.
function New-HcSiteCheck {
    param([string]$HostName)
    if ($HostName -notmatch '^[a-z0-9.-]+$') { return $null }
    [scriptblock]::Create("Invoke-HcSiteCheck '$HostName'")
}

$script:ProblemHandlers['A1'] = 'Invoke-HcA1'
$script:ProblemHandlers['A2'] = 'Invoke-HcA2'
$script:ProblemHandlers['A3'] = 'Invoke-HcA3'

# ==================================================== src\checks\email.ps1 ==
<#
    A4: email will not send or arrive.

    Asks for the email address, but uses only the part after the @: that
    domain decides the mail servers. Then: does the domain receive mail at
    all, do its receiving (IMAP) and sending (SMTP) servers answer from this
    PC, and which mail program is installed -- including the old Windows
    Mail app, which Microsoft switched off at the end of 2024 and which many
    older clients still try to use.

    What cannot be checked from outside: the password, and whether the
    mailbox is full. The finding says so, and the steps go through them.
#>

# The providers clients in the Netherlands use most, with their servers.
# Webmail only where the address is certain.
$script:MailProviders = @(
    @{ Name = 'Ziggo';     Domains = 'ziggo.nl', 'home.nl', 'casema.nl', 'chello.nl', 'upcmail.nl', 'quicknet.nl'
       Imap = 'imap.ziggo.nl'; Smtp = 'smtp.ziggo.nl'; SmtpPort = 587; Web = $null }
    @{ Name = 'KPN';       Domains = 'kpnmail.nl', 'kpnplanet.nl', 'planet.nl', 'hetnet.nl', 'xs4all.nl', 'telfort.nl', 'telfortglasvezel.nl'
       Imap = 'imap.kpnmail.nl'; Smtp = 'smtp.kpnmail.nl'; SmtpPort = 587; Web = $null }
    @{ Name = 'Outlook.com'; Domains = 'outlook.com', 'outlook.nl', 'hotmail.com', 'hotmail.nl', 'live.com', 'live.nl', 'msn.com'
       Imap = 'outlook.office365.com'; Smtp = 'smtp-mail.outlook.com'; SmtpPort = 587; Web = 'https://outlook.live.com/mail/' }
    @{ Name = 'Gmail';     Domains = 'gmail.com', 'googlemail.com'
       Imap = 'imap.gmail.com'; Smtp = 'smtp.gmail.com'; SmtpPort = 587; Web = 'https://mail.google.com/' }
    @{ Name = 'iCloud';    Domains = 'icloud.com', 'me.com', 'mac.com'
       Imap = 'imap.mail.me.com'; Smtp = 'smtp.mail.me.com'; SmtpPort = 587; Web = 'https://www.icloud.com/mail' }
    @{ Name = 'Yahoo';     Domains = 'yahoo.com', 'yahoo.nl', 'ymail.com'
       Imap = 'imap.mail.yahoo.com'; Smtp = 'smtp.mail.yahoo.com'; SmtpPort = 465; Web = 'https://mail.yahoo.com/' }
)

# "naam@Ziggo.nl " -> "ziggo.nl"; also accepts just the domain.
function ConvertTo-HcMailDomain {
    param([string]$Text)
    $d = ("$Text".Trim().ToLowerInvariant() -split '@')[-1].Trim()
    if ($d -match '^([a-z0-9-]+\.)+[a-z]{2,}$') { return $d }
    $null
}

# How many letters must change to turn one word into the other (Levenshtein),
# kept to two rows so no two-dimensional array is needed.
function Get-HcEditDistance {
    param([string]$A, [string]$B)
    $previous = @(0..$B.Length)
    for ($i = 1; $i -le $A.Length; $i++) {
        $current = @($i) + @(0) * $B.Length
        for ($j = 1; $j -le $B.Length; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $delete = $previous[$j] + 1
            $insert = $current[$j - 1] + 1
            $replace = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($delete, $insert), $replace)
        }
        $previous = $current
    }
    $previous[$B.Length]
}

# A known provider domain one or two letters away: "zigo.nl" -> "ziggo.nl".
function Get-HcMailTypo {
    param([string]$Domain)
    foreach ($p in $script:MailProviders) {
        if ($p.Domains -contains $Domain) { return $null }
    }
    foreach ($p in $script:MailProviders) {
        foreach ($known in $p.Domains) {
            $limit = if ($known.Length -ge 8) { 2 } else { 1 }
            if ((Get-HcEditDistance $Domain $known) -le $limit) { return $known }
        }
    }
    $null
}

function Get-HcMailApps {
    $apps = @()
    $appPath = { param($exe) [bool](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue) }
    if (& $appPath 'OUTLOOK.EXE') { $apps += 'Outlook' }
    if (Get-AppxPackage -Name Microsoft.OutlookForWindows -ErrorAction SilentlyContinue) { $apps += 'Outlook (new)' }
    if (& $appPath 'thunderbird.exe') { $apps += 'Thunderbird' }
    [pscustomobject]@{
        Apps          = $apps
        RetiredMail   = [bool](Get-AppxPackage -Name microsoft.windowscommunicationsapps -ErrorAction SilentlyContinue)
    }
}

function Get-HcMailFacts {
    param([string]$Domain)
    $provider = $script:MailProviders | Where-Object { $_.Domains -contains $Domain } | Select-Object -First 1
    $mx = @()
    try { $mx = @(Resolve-DnsName $Domain -Type MX -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.NameExchange } | ForEach-Object { $_.NameExchange }) } catch { }
    $f = [pscustomobject]@{
        Domain = $Domain; Provider = $null; Web = $null; Typo = (Get-HcMailTypo $Domain)
        ReceivesMail = ($mx.Count -gt 0); ImapHost = $null; ImapMs = $null; SmtpHost = $null; SmtpMs = $null
        Apps = Get-HcMailApps
    }
    if ($provider) {
        $f.Provider = $provider.Name
        $f.Web = $provider.Web
        $f.ImapHost = $provider.Imap
        $f.SmtpHost = $provider.Smtp
        $f.ImapMs = Get-HcTcpMs $provider.Imap 993 3000
        $f.SmtpMs = Get-HcTcpMs $provider.Smtp $provider.SmtpPort 3000
    }
    $f
}

function Test-HcMail {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $d = $Facts.Domain
    Add-HcLine $r ok (T 'net.internetWorks')

    if ($Facts.Typo) {
        Add-HcLine $r warn (T 'mail.typo' $d $Facts.Typo)
        $found['mailTypo'] = @($d, $Facts.Typo)
    }
    if ($Facts.ReceivesMail) {
        Add-HcLine $r ok (T 'mail.receives' $d)
    } else {
        Add-HcLine $r problem (T 'mail.noMx' $d)
        $found['mailNoDomain'] = @($d)
    }

    if ($Facts.Provider) {
        foreach ($s in @(@('in', $Facts.ImapHost, $Facts.ImapMs), @('out', $Facts.SmtpHost, $Facts.SmtpMs))) {
            $what = T "mail.$($s[0])"
            if ($s[2] -ge 0) { Add-HcLine $r ok (T 'mail.serverOk' $what $s[1] $s[2]) }
            else {
                Add-HcLine $r problem (T 'mail.serverDown' $what $s[1])
                if (-not $found['mailServerDown']) { $found['mailServerDown'] = @($Facts.Provider) }
            }
        }
    } elseif ($Facts.ReceivesMail -and -not $Facts.Typo) {
        Add-HcLine $r skipped (T 'mail.unknownProvider' $d)
    }

    $apps = @($Facts.Apps.Apps)
    if ($apps.Count) { Add-HcLine $r ok (T 'mail.apps' ($apps -join ', ')) } else { Add-HcLine $r ok (T 'mail.noApps') }
    if ($Facts.Apps.RetiredMail) {
        Add-HcLine $r warn (T 'mail.retired')
        $found['mailAppRetired'] = @()
    }
    if ($Facts.Web) { Add-HcAction $r 'openWebmail' @{ Label = $Facts.Provider; Url = $Facts.Web } }

    Select-HcFinding $r $found @('mailTypo', 'mailNoDomain', 'mailServerDown', 'mailAppRetired') 'mailOk'
    if ($r.FindingId -eq 'mailOk') { $r.FindingArgs = @($(if ($Facts.Provider) { $Facts.Provider } else { $d })) }
    $r
}

function Invoke-HcA4 {
    $domain = $null
    while (-not $domain) {
        $typed = Read-HcLine (T 'mail.ask')
        if (-not "$typed".Trim() -or "$typed".Trim().ToUpperInvariant() -eq 'Q') { return }
        $domain = ConvertTo-HcMailDomain $typed
        if (-not $domain) { Write-Warn2 (T 'mail.invalid' $typed) }
    }
    Write-Host ''
    New-HcMailCheck $domain
}

function Invoke-HcMailCheck {
    param([string]$Domain)
    $base = Test-HcInternet (Get-HcNetworkFacts)
    if ($script:InternetWorks -notcontains $base.FindingId) { return $base }
    Test-HcMail (Get-HcMailFacts $Domain)
}

# The A4 check for one domain; built from text for the same reasons as New-HcSiteCheck.
function New-HcMailCheck {
    param([string]$Domain)
    if ($Domain -notmatch '^[a-z0-9.-]+$') { return $null }
    [scriptblock]::Create("Invoke-HcMailCheck '$Domain'")
}

$script:ProblemHandlers['A4'] = 'Invoke-HcA4'

# ==================================================== src\checks\security.ps1 ==
<#
    Area F: Safety & scams.

      F1  a pop-up says I have a virus         notifications, antivirus, proxy, hosts file
      F2  someone called and got into my PC    remote-access programs, scheduled tasks, antivirus, notifications
      F3  full security check                  all of the above

    The scam this is built around: a caller (or a fake virus pop-up with a
    phone number) talks the client into installing AnyDesk, TeamViewer or
    similar, then takes over the PC and the bank account. So F2 looks for
    remote-access programs installed, downloaded, running or merely used
    before, and dates each one: "installed two days ago" is what matters.

    Everything is read-only and works without admin. Nothing is ever removed
    here -- plenty of families use these tools on purpose. Housecall reports
    and asks; removal (Phase 2) always needs the client's yes.
#>

$script:RecentDays = 30

# Remote-access programs. Pattern matches the installed name and service
# names; Processes are process names without .exe; Traces are folders a tool
# leaves behind even after it is removed or was only run once.
$script:RemoteToolList = @(
    @{ Name = 'AnyDesk';               Pattern = 'AnyDesk';                      Processes = @('AnyDesk');                          Traces = @('%APPDATA%\AnyDesk', '%ProgramData%\AnyDesk') }
    @{ Name = 'TeamViewer';            Pattern = 'TeamViewer';                   Processes = @('TeamViewer', 'TeamViewer_Service', 'tv_w32', 'tv_x64'); Traces = @('%APPDATA%\TeamViewer') }
    @{ Name = 'UltraViewer';           Pattern = 'UltraViewer';                  Processes = @('UltraViewer_Desktop', 'UltraViewer_Service'); Traces = @() }
    @{ Name = 'RustDesk';              Pattern = 'RustDesk';                     Processes = @('rustdesk');                         Traces = @('%APPDATA%\RustDesk') }
    @{ Name = 'HopToDesk';             Pattern = 'HopToDesk';                    Processes = @('HopToDesk');                        Traces = @('%APPDATA%\HopToDesk') }
    @{ Name = 'Supremo';               Pattern = '^Supremo';                     Processes = @('Supremo', 'SupremoService', 'SupremoHelper'); Traces = @() }
    @{ Name = 'ScreenConnect';         Pattern = 'ScreenConnect';                Processes = @('ScreenConnect.ClientService', 'ScreenConnect.WindowsClient'); Traces = @() }
    @{ Name = 'LogMeIn / GoTo';        Pattern = 'LogMeIn(?! Hamachi)|GoTo Resolve|GoToAssist'; Processes = @('LogMeIn', 'LMIGuardianSvc', 'GoToAssist'); Traces = @() }
    @{ Name = 'Splashtop';             Pattern = 'Splashtop';                    Processes = @('SRService', 'SRManager', 'strwinclt');  Traces = @() }
    @{ Name = 'AeroAdmin';             Pattern = 'AeroAdmin';                    Processes = @('AeroAdmin');                        Traces = @() }
    @{ Name = 'Ammyy Admin';           Pattern = 'Ammyy';                        Processes = @('AA_v3', 'Ammyy');                   Traces = @() }
    @{ Name = 'RemotePC';              Pattern = 'RemotePC';                     Processes = @('RemotePCService', 'RemotePCDesktop'); Traces = @() }
    @{ Name = 'Zoho Assist';           Pattern = 'Zoho Assist';                  Processes = @('ZA_Connect', 'ZohoURS');            Traces = @() }
    @{ Name = 'Chrome Remote Desktop'; Pattern = 'Chrome Remote Desktop';        Processes = @('remoting_host');                    Traces = @() }
    @{ Name = 'DWService';             Pattern = 'DWAgent|DWService';            Processes = @('dwagent', 'dwagsvc');               Traces = @() }
    @{ Name = 'VNC';                   Pattern = 'VNC';                          Processes = @('winvnc', 'tvnserver', 'vncserver'); Traces = @() }
    @{ Name = 'Getscreen.me';          Pattern = 'Getscreen';                    Processes = @('getscreen');                        Traces = @() }
    @{ Name = 'ISL Light';             Pattern = 'ISL Light|ISL AlwaysOn';       Processes = @('ISLLight', 'ISLAlwaysOnMonitor');   Traces = @() }
    @{ Name = 'Remote Utilities';      Pattern = 'Remote Utilities';             Processes = @('rutserv', 'rfusclient');            Traces = @() }
    @{ Name = 'Atera';                 Pattern = 'AteraAgent|Atera Networks';    Processes = @('AteraAgent');                       Traces = @() }
    # Built into Windows: nothing to find installed, but running means a session is on.
    @{ Name = 'Quick Assist';          Pattern = $null;                          Processes = @('QuickAssist');                      Traces = @() }
)

# Scheduled tasks of tools Shamil installs himself. They start a hidden
# script from AppData, like malware does, so they are recognised by name AND
# by the script they run -- a look-alike name alone does not pass.
$script:KnownTasks = @(
    @{ Owner = 'Reveille'; Name = '^(Reveille|PCRemote)'; Command = '\\(Reveille|PCRemote)\\start-agent-hidden\.vbs' }
    @{ Owner = 'Courier';  Name = '^Courier';             Command = '\\Courier\\start-agent-hidden\.vbs' }
)

# Browsers built on Chrome keep site permissions in a Preferences file per
# profile. Firefox keeps them in a database this cannot read yet.
$script:BrowserRoots = @(
    @{ Name = 'Chrome';   Path = '%LOCALAPPDATA%\Google\Chrome\User Data' }
    @{ Name = 'Edge';     Path = '%LOCALAPPDATA%\Microsoft\Edge\User Data' }
    @{ Name = 'Brave';    Path = '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data' }
    @{ Name = 'Opera';    Path = '%APPDATA%\Opera Software\Opera Stable' }
    @{ Name = 'Opera GX'; Path = '%APPDATA%\Opera Software\Opera GX Stable' }
)

# How to open each browser at its notification settings (fix openNotifySettings).
# chrome.exe, msedge.exe and brave.exe are found through Windows' App Paths.
$script:BrowserExe = @{
    'Chrome'   = 'chrome.exe'
    'Edge'     = 'msedge.exe'
    'Brave'    = 'brave.exe'
    'Opera'    = [Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Programs\Opera\launcher.exe')
    'Opera GX' = [Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\Programs\Opera GX\launcher.exe')
}
$script:BrowserScheme = @{ 'Chrome' = 'chrome'; 'Edge' = 'edge'; 'Brave' = 'brave'; 'Opera' = 'opera'; 'Opera GX' = 'opera' }

# Sites that people really do allow to send notifications. They are listed
# as fine; everything else is flagged, because that is where fake virus
# warnings come from. Matched on the host name, subdomains included.
$script:KnownNotificationSites = @(
    'mail.google.com', 'calendar.google.com', 'meet.google.com', 'chat.google.com', 'youtube.com'
    'web.whatsapp.com', 'web.telegram.org', 'messenger.com', 'facebook.com', 'instagram.com'
    'outlook.live.com', 'outlook.office.com', 'outlook.office365.com', 'teams.microsoft.com', 'teams.live.com'
    'discord.com', 'x.com', 'linkedin.com', 'marktplaats.nl', 'nu.nl', 'nos.nl'
    'localhost', '127.0.0.1'
)

function Test-HcKnownSite {
    param([string]$Site)
    $h = ($Site -replace '^[a-z]+://', '' -replace '[:/].*$', '').ToLowerInvariant()
    foreach ($known in $script:KnownNotificationSites) {
        if ($h -eq $known -or $h.EndsWith('.' + $known)) { return $true }
    }
    $false
}

# Which finding wins when several are found: the most urgent first.
$script:SecurityPriority = @(
    'remoteActive', 'remoteRecent', 'defenderOff', 'suspiciousTask', 'notifySites',
    'proxy', 'hostsRedirect', 'avOld', 'threatsFound', 'remoteOld', 'unknownTask'
)

# ------------------------------------------------------------------- facts --

function ConvertFrom-HcInstallDate {
    param([string]$Text)
    $d = [datetime]::MinValue
    if ($Text -and [datetime]::TryParseExact($Text.Trim(), 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return $d }
    $null
}

function Get-HcDownloadFolders {
    $folders = @()
    try { $folders += (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path } catch { }
    $folders += Join-Path $env:USERPROFILE 'Downloads'
    $folders += [Environment]::GetFolderPath('Desktop')
    @($folders | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
}

function Get-HcRemoteTools {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installed = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.StartMode -eq 'Auto' } | ForEach-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" })
    $runKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    $runValues = @(foreach ($k in $runKeys) {
        $item = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($item) { $item.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "$($_.Name) $($_.Value)" } }
    })
    $downloads = @(foreach ($folder in Get-HcDownloadFolders) {
        Get-ChildItem -LiteralPath $folder -File -Filter *.exe -ErrorAction SilentlyContinue
    })

    foreach ($tool in $script:RemoteToolList) {
        $found = [pscustomobject]@{
            Name = $tool.Name; Installed = $false; InstallDate = $null; Running = $false
            AutoStart = $false; Downloaded = $null; LastUsed = $null; Processes = $tool.Processes
            Uninstall = $null
        }
        $p = $tool.Pattern
        if ($p) {
            $entry = $installed | Where-Object { $_.DisplayName -match $p } | Select-Object -First 1
            if ($entry) {
                $found.Installed = $true
                $found.InstallDate = ConvertFrom-HcInstallDate $entry.InstallDate
                $found.Uninstall = [string]$entry.UninstallString
            }
            $found.AutoStart = [bool](@($services + $runValues) -match $p)
            $file = $downloads | Where-Object { $_.Name -match $p } | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($file) { $found.Downloaded = $file.CreationTime }
        }
        $found.Running = [bool]($processes | Where-Object { $tool.Processes -contains $_ })
        foreach ($trace in $tool.Traces) {
            $folder = [Environment]::ExpandEnvironmentVariables($trace)
            if (Test-Path -LiteralPath $folder) {
                $when = (Get-Item -LiteralPath $folder).LastWriteTime
                if ($null -eq $found.LastUsed -or $when -gt $found.LastUsed) { $found.LastUsed = $when }
            }
        }
        if ($found.Installed -or $found.Running -or $found.AutoStart -or $found.Downloaded -or $found.LastUsed) { $found }
    }
}

# Sites allowed to send notifications, from every Chrome-family profile.
# Preferences can be large, so this uses the .NET JSON reader with the size
# limit lifted instead of ConvertFrom-Json, which fails on big files in 5.1.
function Get-HcNotificationSites {
    try { Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop } catch { return @() }
    $json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json.MaxJsonLength = [int]::MaxValue

    foreach ($browser in $script:BrowserRoots) {
        $root = [Environment]::ExpandEnvironmentVariables($browser.Path)
        if (-not (Test-Path -LiteralPath $root)) { continue }
        # Opera keeps Preferences in the root; the others in one folder per profile.
        $files = @(Get-Item -LiteralPath (Join-Path $root 'Preferences') -ErrorAction SilentlyContinue) +
                 @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'Preferences') -ErrorAction SilentlyContinue })
        foreach ($file in $files) {
            try {
                $prefs = $json.DeserializeObject([IO.File]::ReadAllText($file.FullName))
                $sites = $prefs['profile']['content_settings']['exceptions']['notifications']
            } catch { continue }
            if ($null -eq $sites) { continue }
            foreach ($key in $sites.Keys) {
                if ($sites[$key]['setting'] -ne 1) { continue }
                $since = $null
                try {
                    # Microseconds since 1601, the same epoch as a Windows file time.
                    $since = [DateTime]::FromFileTimeUtc([int64]$sites[$key]['last_modified'] * 10).ToLocalTime()
                } catch { }
                [pscustomobject]@{ Browser = $browser.Name; Site = ($key -split ',')[0] -replace ':443$', ''; Since = $since }
            }
        }
    }
}

# The antivirus Windows Security reports, and for Defender its update age and
# recent detections. productState's middle byte is 0x10 or 0x11 when on; the
# last byte is 0x00 when up to date.
function Get-HcAntivirus {
    $av = [pscustomobject]@{ Known = $false; Name = $null; Enabled = $false; Outdated = $false; DaysOld = $null; Threats = $null }
    try {
        $products = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
        $av.Known = $true
        foreach ($p in $products) {
            $hex = '{0:X6}' -f [int]$p.productState
            if ($hex.Substring(2, 2) -in @('10', '11')) {
                $av.Enabled = $true
                $av.Name = $p.displayName
                $av.Outdated = ($hex.Substring(4, 2) -ne '00')
                break
            }
        }
        if (-not $av.Name -and $products.Count) { $av.Name = $products[0].displayName }
    } catch { }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($av.Name -match 'Defender' -or -not $av.Known) {
            $av.Known = $true
            if (-not $av.Name) { $av.Name = 'Microsoft Defender' }
            $av.Enabled = [bool]($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled)
            if ($mp.AntivirusSignatureLastUpdated) {
                $av.DaysOld = [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
                $av.Outdated = ($av.DaysOld -gt 7)
            }
        }
        $av.Threats = @(Get-MpThreatDetection -ErrorAction Stop |
            Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-$script:RecentDays) }).Count
    } catch { }
    $av
}

<#
    Scheduled tasks outside Windows' own folder whose command looks like
    malware. Two levels:
      strong  a script host with an encoded, hidden or downloading command,
              or a program run from Temp, Public or Downloads
      weak    a script host running a script file from the user's folders --
              legitimate tools do this too, so it is only "check this"
#>
$script:ScriptHosts = 'powershell|pwsh|mshta|wscript|cscript|cmd|rundll32|regsvr32'

function Get-HcTaskLevel {
    param([string]$Execute, [string]$Arguments)
    $exe = [IO.Path]::GetFileNameWithoutExtension(($Execute -replace '"', ''))
    $isHost = $exe -match "^($script:ScriptHosts)$"
    if ($isHost -and $Arguments -match '-e(nc|ncodedcommand)?\s|FromBase64|https?://|-w(indowstyle)?\s+hid|DownloadString|Invoke-WebRequest|iwr |\biex\b') { return 'strong' }
    if ($Execute -match '\\(Temp|Users\\Public|Downloads)\\') { return 'strong' }
    if ($isHost -and $Arguments -match '\\(AppData|ProgramData|Users)\\') { return 'weak' }
    $null
}

function Get-HcKnownTaskOwner {
    param([string]$Name, [string]$Command)
    foreach ($k in $script:KnownTasks) {
        if ($Name -match $k.Name -and $Command -match $k.Command) { return $k.Owner }
    }
    $null
}

function Get-HcSuspiciousTasks {
    foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($action in @($task.Actions | Where-Object { $_.Execute })) {
            $level = Get-HcTaskLevel $action.Execute $action.Arguments
            if ($level) {
                $full = ("$($action.Execute) $($action.Arguments)").Trim()
                $command = if ($full.Length -gt 70) { $full.Substring(0, 67) + '...' } else { $full }
                [pscustomobject]@{
                    Name = $task.TaskName; Path = $task.TaskPath; Command = $command; Level = $level
                    Disabled = ([string]$task.State -eq 'Disabled'); Owner = Get-HcKnownTaskOwner $task.TaskName $full
                }
                break
            }
        }
    }
}

# Hosts-file lines that send a name somewhere, other than the usual localhost.
function Get-HcHostsRedirects {
    param([string]$Path = (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'))
    try {
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $clean = ($line -replace '#.*$', '').Trim()
            if (-not $clean) { continue }
            $parts = $clean -split '\s+'
            if ($parts.Count -lt 2) { continue }
            foreach ($name in $parts[1..($parts.Count - 1)]) {
                if ($name -notmatch '^(localhost|localhost\.localdomain|broadcasthost)$') { "$name -> $($parts[0])" }
            }
        }
    } catch { }
}

# Reads only the parts asked for: F1 does not need to wait for the task list.
function Get-HcSecurityFacts {
    param([string[]]$Parts)
    $f = [pscustomobject]@{
        Now = Get-Date; RemoteTools = $null; Tasks = $null; Antivirus = $null
        Notifications = $null; Proxy = $null; Hosts = $null
    }
    if ($Parts -contains 'remote')        { $f.RemoteTools = @(Get-HcRemoteTools) }
    if ($Parts -contains 'tasks')         { $f.Tasks = @(Get-HcSuspiciousTasks) }
    if ($Parts -contains 'antivirus')     { $f.Antivirus = Get-HcAntivirus }
    if ($Parts -contains 'notifications') { $f.Notifications = @(Get-HcNotificationSites) }
    if ($Parts -contains 'proxy')         { $f.Proxy = Get-HcProxy }
    if ($Parts -contains 'hosts')         { $f.Hosts = @(Get-HcHostsRedirects) }
    $f
}

# ------------------------------------------------------------------ verdict --

function Format-HcDate {
    param([datetime]$Date)
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    $Date.ToString('d MMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))
}

<#
    One verdict for F1, F2 and F3: $Parts says which sections to show, in
    that order. Every section adds its lines and names what it found; the
    finding is then the most urgent one by $script:SecurityPriority, or
    $CleanId when nothing was found.
#>
function Test-HcSecurity {
    param([pscustomobject]$Facts, [string[]]$Parts, [string]$CleanId)
    $r = New-HcReport
    $found = @{}
    $recent = $Facts.Now.AddDays(-$script:RecentDays)

    foreach ($part in $Parts) {
        switch ($part) {
            'remote' {
                $tools = @($Facts.RemoteTools)
                if ($tools.Count -eq 0) { Add-HcLine $r ok (T 'sec.noRemote'); break }
                foreach ($t in $tools) {
                    $bits = @()
                    if ($t.Installed) {
                        $bits += $(if ($t.InstallDate) { T 'sec.installed' (Format-HcDate $t.InstallDate) } else { T 'sec.installedUnknown' })
                    }
                    if ($t.Downloaded) { $bits += T 'sec.downloaded' (Format-HcDate $t.Downloaded) }
                    if ($t.Running) { $bits += T 'sec.running' }
                    if ($t.AutoStart) { $bits += T 'sec.autoStart' }
                    if ($t.LastUsed -and -not $t.Running) { $bits += T 'sec.lastUsed' (Format-HcDate $t.LastUsed) }

                    $newest = @($t.InstallDate, $t.Downloaded, $t.LastUsed) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
                    $isRecent = ($newest -and $newest -gt $recent)
                    $status = if ($t.Running -or $isRecent) { 'problem' } else { 'warn' }
                    Add-HcLine $r $status ('{0}: {1}' -f $t.Name, ($bits -join ', '))

                    if ($t.Running) { Add-HcAction $r 'stopRemote' @{ Label = $t.Name; Processes = $t.Processes } }
                    if ($t.Uninstall) { Add-HcAction $r 'uninstallProgram' @{ Label = $t.Name; Command = $t.Uninstall } }
                    if ($t.Running -and -not $found['remoteActive']) { $found['remoteActive'] = @($t.Name) }
                    elseif ($isRecent -and -not $found['remoteRecent']) { $found['remoteRecent'] = @($t.Name, (Format-HcDate $newest)) }
                    elseif (-not $found['remoteOld']) { $found['remoteOld'] = @($t.Name) }
                }
            }
            'tasks' {
                $tasks = @($Facts.Tasks)
                if ($tasks.Count -eq 0) { Add-HcLine $r ok (T 'sec.noTasks'); break }
                foreach ($t in $tasks) {
                    if ($t.Owner) { Add-HcLine $r ok (T 'sec.taskKnown' $t.Name $t.Owner); continue }
                    if ($t.Disabled) { Add-HcLine $r ok (T 'sec.taskDisabled' $t.Name); continue }
                    $status = if ($t.Level -eq 'strong') { 'problem' } else { 'warn' }
                    Add-HcLine $r $status (T 'sec.task' $t.Name $t.Command)
                    Add-HcAction $r 'disableTask' @{ Label = $t.Name; Name = $t.Name; Path = $t.Path }
                    $id = if ($t.Level -eq 'strong') { 'suspiciousTask' } else { 'unknownTask' }
                    if (-not $found[$id]) { $found[$id] = @($t.Name) }
                }
            }
            'antivirus' {
                $av = $Facts.Antivirus
                if ($null -eq $av -or -not $av.Known) { Add-HcLine $r skipped (T 'sec.avUnknown'); break }
                if (-not $av.Enabled) {
                    Add-HcLine $r problem (T 'sec.avOff')
                    $found['defenderOff'] = @()
                } elseif ($av.Outdated) {
                    $text = if ($av.DaysOld) { T 'sec.avOld' $av.Name $av.DaysOld } else { T 'sec.avOutdated' $av.Name }
                    Add-HcLine $r warn $text
                    $found['avOld'] = @()
                } else {
                    Add-HcLine $r ok (T 'sec.avOk' $av.Name)
                }
                if ($av.Threats -gt 0) {
                    Add-HcLine $r warn (T 'sec.threats' $av.Threats)
                    $found['threatsFound'] = @($av.Threats)
                }
            }
            'notifications' {
                $sites = @($Facts.Notifications)
                $known = @($sites | Where-Object { Test-HcKnownSite $_.Site })
                $unknown = @($sites | Where-Object { -not (Test-HcKnownSite $_.Site) })
                if ($known.Count) {
                    $names = @($known | ForEach-Object { $_.Site -replace '^[a-z]+://', '' } | Sort-Object -Unique) -join ', '
                    Add-HcLine $r ok (T 'sec.notifyKnown' $names)
                }
                if ($unknown.Count -eq 0) {
                    if (-not $known.Count) { Add-HcLine $r ok (T 'sec.notifyNone') }
                    break
                }
                foreach ($s in $unknown) {
                    $text = if ($s.Since) { T 'sec.notifySite' $s.Site $s.Browser (Format-HcDate $s.Since) } else { T 'sec.notifySiteNoDate' $s.Site $s.Browser }
                    Add-HcLine $r warn $text
                }
                foreach ($b in @($unknown | ForEach-Object { $_.Browser } | Sort-Object -Unique)) {
                    if ($script:BrowserExe.ContainsKey($b)) { Add-HcAction $r 'openNotifySettings' @{ Label = $b; Browser = $b } }
                }
                $found['notifySites'] = @($unknown.Count)
            }
            'proxy' {
                if ($Facts.Proxy) {
                    Add-HcLine $r warn (T 'net.proxy' $Facts.Proxy)
                    Add-HcAction $r 'proxyOff'
                    $found['proxy'] = @()
                } else {
                    Add-HcLine $r ok (T 'sec.noProxy')
                }
            }
            'hosts' {
                $lines = @($Facts.Hosts)
                if ($lines.Count -eq 0) { Add-HcLine $r ok (T 'sec.hostsOk'); break }
                $shown = ($lines | Select-Object -First 3) -join ', '
                if ($lines.Count -gt 3) { $shown += ', ...' }
                Add-HcLine $r warn (T 'sec.hostsRedirect' $lines.Count $shown)
                $found['hostsRedirect'] = @()
            }
        }
    }

    foreach ($id in $script:SecurityPriority) {
        if ($found.ContainsKey($id)) { Set-HcFinding $r $id $found[$id]; break }
    }
    Set-HcFinding $r $CleanId
    $r
}

# ---------------------------------------------------------------- handlers --

$script:SecurityChecks = @{
    F1 = @{ Parts = @('notifications', 'antivirus', 'proxy', 'hosts');                  Clean = 'cleanPopup' }
    F2 = @{ Parts = @('remote', 'tasks', 'antivirus', 'notifications');                 Clean = 'cleanCall' }
    F3 = @{ Parts = @('remote', 'tasks', 'antivirus', 'notifications', 'proxy', 'hosts'); Clean = 'cleanAll' }
}

function Invoke-HcSecurityRun {
    param([string]$Code)
    $plan = $script:SecurityChecks[$Code]
    Test-HcSecurity (Get-HcSecurityFacts $plan.Parts) $plan.Parts $plan.Clean
}

# Built from text, naming its own code; see New-HcSiteCheck.
function Invoke-HcSecurityCheck {
    param([string]$Code)
    if ($Code -notmatch '^F\d$') { return $null }
    [scriptblock]::Create("Invoke-HcSecurityRun '$Code'")
}

function Invoke-HcF1 { Invoke-HcSecurityCheck 'F1' }
function Invoke-HcF2 { Invoke-HcSecurityCheck 'F2' }
function Invoke-HcF3 { Invoke-HcSecurityCheck 'F3' }

$script:ProblemHandlers['F1'] = 'Invoke-HcF1'
$script:ProblemHandlers['F2'] = 'Invoke-HcF2'
$script:ProblemHandlers['F3'] = 'Invoke-HcF3'

# ==================================================== src\checks\devices.ps1 ==
<#
    Area C: Printer & devices.

      C1  printer will not print        print service, printers, default printer, queue
      C2  mouse, keyboard or USB stick  devices with errors, keyboard and mouse, USB drives
      C3  Bluetooth                     adapter, Bluetooth service, paired devices

    Same shape as A and F: Get-...Facts reads the PC, Test-... decides, and
    the fixes it offers live in src\fixes.ps1. Everything here reads
    through CIM and PnP objects, which Windows does not translate.
#>

# Printers that only exist on the PC: PDF, XPS, OneNote, fax. Documents
# sent there never reach paper -- a common "my printer does nothing".
$script:VirtualPrinter = 'Print to PDF|XPS|OneNote|Fax|Send To'
$script:VirtualPort = '^(PORTPROMPT:|nul:|SHRFAX:|XPSPort:|FILE:)'

# How old a waiting print job must be before it counts as stuck.
$script:StuckMinutes = 10

# DetectedErrorState values Windows reports for a printer, and whether each
# stops printing (problem) or is only a warning.
$script:PrinterStates = @{ 3 = 'warn'; 4 = 'problem'; 5 = 'warn'; 6 = 'problem'; 7 = 'problem'; 8 = 'problem'; 10 = 'problem'; 11 = 'problem' }

# ------------------------------------------------------------------- facts --

function Get-HcPrinterFacts {
    $f = [pscustomobject]@{ Now = Get-Date; SpoolerRunning = $false; SpoolerDisabled = $false; Printers = @(); Jobs = @() }
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($spooler) {
        $f.SpoolerRunning = ($spooler.Status -eq 'Running')
        $f.SpoolerDisabled = ([string]$spooler.StartType -eq 'Disabled')
    }
    if (-not $f.SpoolerRunning) { return $f }

    $ports = @{}
    Get-CimInstance Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue | ForEach-Object { $ports[$_.Name] = $_.HostAddress }

    $f.Printers = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object {
        $virtual = ($_.Name -match $script:VirtualPrinter) -or ([string]$_.DriverName -match $script:VirtualPrinter) -or ([string]$_.PortName -match $script:VirtualPort)
        $hostAddress = $ports[[string]$_.PortName]
        $reachable = $null
        if ($hostAddress -and -not $virtual) {
            $reachable = (Get-HcPingMs $hostAddress) -ge 0
            if (-not $reachable) { $reachable = (Get-HcPingMs $hostAddress) -ge 0 }
        }
        [pscustomobject]@{
            Name = $_.Name; Default = [bool]$_.Default; Virtual = $virtual
            Offline = ([bool]$_.WorkOffline -or $_.PrinterStatus -eq 7 -or $_.DetectedErrorState -eq 9)
            State = [int]$_.DetectedErrorState; HostAddress = $hostAddress; Reachable = $reachable
        }
    })
    $f.Jobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ Printer = ($_.Name -split ',')[0]; Document = $_.Document; Submitted = $_.TimeSubmitted; Status = [string]$_.JobStatus }
    })
    $f
}

# Devices Windows reports a problem for, from Device Manager's own list.
function Get-HcProblemDevices {
    param([string]$Class)
    $all = if ($Class) { Get-PnpDevice -Class $Class -PresentOnly -ErrorAction SilentlyContinue } else { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue }
    @($all | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
        [pscustomobject]@{ Name = $_.FriendlyName; Class = $_.Class; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId }
    })
}

function Get-HcUsbDrives {
    foreach ($disk in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -eq 'USB' })) {
        $letters = @(Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue |
            ForEach-Object { Get-CimAssociatedInstance -InputObject $_ -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue } |
            ForEach-Object { $_.DeviceID })
        [pscustomobject]@{ Name = ($disk.Model -replace '\s+USB Device$', ''); Letters = $letters }
    }
}

function Get-HcInputFacts {
    [pscustomobject]@{
        Problems  = @(Get-HcProblemDevices)
        Keyboards = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue).Count
        Pointers  = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue).Count
        UsbDrives = @(Get-HcUsbDrives)
    }
}

<#
    Bluetooth devices in Device Manager come in three kinds, told apart by
    their instance id: the adapter (USB\ or PCI\), paired devices
    (BTHENUM\DEV_ or BTHLE\DEV_) and Windows' own helpers (everything else).
    A paired device is "present" while it is connected.
#>
function Get-HcBluetoothFacts {
    $devices = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
    $service = Get-Service -Name bthserv -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Adapters = @($devices | Where-Object { $_.InstanceId -match '^(USB|PCI|ACPI)\\' -and $_.Present } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId }
        })
        ServiceRunning = ($service -and $service.Status -eq 'Running')
        Paired = @($devices | Where-Object { $_.InstanceId -match '^BTH(ENUM|LE)\\DEV_' } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Connected = [bool]$_.Present }
        } | Sort-Object Name -Unique)
    }
}

# ------------------------------------------------------------------ verdict --

# "switched off", "no driver installed", ... for a Device Manager error code.
function Get-HcDeviceReason {
    param([int]$Code)
    if ($script:Strings['en'].ContainsKey("dev.code.$Code")) { return (T "dev.code.$Code") }
    T 'dev.codeOther' $Code
}

# Lines, a finding and a fix for one device with a problem. Shared by C2 and C3.
function Add-HcDeviceProblem {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Device)
    Add-HcLine $Report problem (T 'dev.deviceProblem' $Device.Name (Get-HcDeviceReason $Device.Code))
    $target = @{ Label = $Device.Name; InstanceId = $Device.InstanceId }
    switch ($Device.Code) {
        22      { Add-HcAction $Report 'enableDevice' $target; if (-not $Found['deviceDisabled']) { $Found['deviceDisabled'] = @($Device.Name) } }
        28      { if (-not $Found['deviceNoDriver']) { $Found['deviceNoDriver'] = @($Device.Name) } }
        default { Add-HcAction $Report 'restartDevice' $target; if (-not $Found['deviceError']) { $Found['deviceError'] = @($Device.Name, (Get-HcDeviceReason $Device.Code)) } }
    }
}

function Select-HcFinding {
    param([pscustomobject]$Report, [hashtable]$Found, [string[]]$Priority, [string]$Clean)
    foreach ($id in $Priority) {
        if ($Found.ContainsKey($id)) { Set-HcFinding $Report $id $Found[$id]; break }
    }
    Set-HcFinding $Report $Clean
}

# C1.
function Test-HcPrinter {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.SpoolerRunning) {
        Add-HcLine $r problem (T 'dev.spoolerStopped')
        Add-HcAction $r 'startSpooler'
        Set-HcFinding $r 'spoolerStopped'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'dev.spoolerOk')

    $real = @($Facts.Printers | Where-Object { -not $_.Virtual })
    if ($real.Count -eq 0) {
        $virtualNames = @($Facts.Printers | ForEach-Object { $_.Name })
        $shown = if ($virtualNames.Count) { $virtualNames -join ', ' } else { T 'net.none' }
        Add-HcLine $r problem (T 'dev.noPrinter' $shown)
        Set-HcFinding $r 'noPrinter'
        return $r
    }

    foreach ($p in $real) {
        if ($p.Reachable -eq $false) {
            Add-HcLine $r problem (T 'dev.printerUnreachable' $p.Name $p.HostAddress)
            if (-not $found['printerUnreachable']) { $found['printerUnreachable'] = @($p.Name) }
        } elseif ($p.Offline) {
            Add-HcLine $r problem (T 'dev.printerOffline' $p.Name)
            if (-not $found['printerOffline']) { $found['printerOffline'] = @($p.Name) }
        } elseif ($script:PrinterStates.ContainsKey($p.State)) {
            $what = T "dev.state.$($p.State)"
            Add-HcLine $r $script:PrinterStates[$p.State] (T 'dev.printerState' $p.Name $what)
            if ($script:PrinterStates[$p.State] -eq 'problem' -and -not $found['printerAttention']) { $found['printerAttention'] = @($p.Name, $what) }
        } elseif ($p.Default) {
            Add-HcLine $r ok (T 'dev.printerReadyDefault' $p.Name)
        } else {
            Add-HcLine $r ok (T 'dev.printerReady' $p.Name)
        }
    }

    # The default printer: a real one, or documents never reach paper.
    $default = @($Facts.Printers | Where-Object { $_.Default }) | Select-Object -First 1
    $best = @($real | Where-Object { -not $_.Offline -and $_.Reachable -ne $false }) + $real | Select-Object -First 1
    if ($null -eq $default) {
        Add-HcLine $r problem (T 'dev.noDefault')
        Add-HcAction $r 'setDefault' @{ Label = $best.Name; Name = $best.Name }
        $found['noDefault'] = @()
    } elseif ($default.Virtual) {
        Add-HcLine $r problem (T 'dev.defaultVirtual' $default.Name)
        Add-HcAction $r 'setDefault' @{ Label = $best.Name; Name = $best.Name; Previous = $default.Name }
        $found['defaultVirtual'] = @($default.Name)
    }

    # The queue: documents waiting longer than a few minutes block the rest.
    $stuck = @($Facts.Jobs | Where-Object { $_.Status -match 'Error|Fout' -or ($_.Submitted -and $_.Submitted -lt $Facts.Now.AddMinutes(-$script:StuckMinutes)) })
    if ($stuck.Count) {
        $oldest = ($stuck | Sort-Object Submitted | Select-Object -First 1).Submitted
        $when = if ($oldest) { $oldest.ToString('HH:mm') } else { '?' }
        Add-HcLine $r problem (T 'dev.jobsStuck' $stuck.Count $when)
        Add-HcAction $r 'clearJobs'
        Add-HcAction $r 'restartSpooler'
        $found['jobsStuck'] = @()
    } else {
        Add-HcLine $r ok (T 'dev.jobsOk')
    }

    Select-HcFinding $r $found @('printerUnreachable', 'printerOffline', 'printerAttention', 'jobsStuck', 'defaultVirtual', 'noDefault') 'printerReady'
    if ($r.FindingId -eq 'printerReady') {
        $target = if ($default -and -not $default.Virtual) { $default } else { $best }
        Add-HcAction $r 'printTestPage' @{ Label = $target.Name; Name = $target.Name }
    }
    $r
}

# C2.
function Test-HcInputDevices {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Keyboards -gt 0) { Add-HcLine $r ok (T 'dev.keyboardOk') } else { Add-HcLine $r warn (T 'dev.noKeyboard') }
    if ($Facts.Pointers -gt 0) {
        Add-HcLine $r ok (T 'dev.pointerOk')
    } else {
        Add-HcLine $r problem (T 'dev.noPointer')
        $found['noPointer'] = @()
    }
    foreach ($d in @($Facts.UsbDrives)) {
        if (@($d.Letters).Count) {
            Add-HcLine $r ok (T 'dev.usbDrive' $d.Name (@($d.Letters) -join ', '))
        } else {
            Add-HcLine $r problem (T 'dev.usbNoLetter' $d.Name)
            if (-not $found['usbNoLetter']) { $found['usbNoLetter'] = @($d.Name) }
        }
    }
    $problems = @($Facts.Problems)
    if ($problems.Count -eq 0) {
        Add-HcLine $r ok (T 'dev.noDeviceErrors')
    } else {
        foreach ($d in $problems) { Add-HcDeviceProblem $r $found $d }
    }
    Select-HcFinding $r $found @('noPointer', 'deviceDisabled', 'deviceError', 'deviceNoDriver', 'usbNoLetter') 'devicesOk'
    $r
}

# C3.
function Test-HcBluetooth {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    $adapters = @($Facts.Adapters)
    if ($adapters.Count -eq 0) {
        Add-HcLine $r problem (T 'dev.btNoAdapter')
        Set-HcFinding $r 'btNoAdapter'
        return $r
    }
    foreach ($a in $adapters) {
        if ($a.Code -eq 0) { Add-HcLine $r ok (T 'dev.btAdapter' $a.Name) } else { Add-HcDeviceProblem $r $found $a }
    }
    if ($Facts.ServiceRunning) {
        Add-HcLine $r ok (T 'dev.btServiceOk')
    } else {
        Add-HcLine $r problem (T 'dev.btServiceStopped')
        Add-HcAction $r 'startBtService'
        $found['btServiceStopped'] = @()
    }
    $paired = @($Facts.Paired)
    if ($paired.Count) {
        $names = @($paired | ForEach-Object { if ($_.Connected) { T 'dev.btConnected' $_.Name } else { T 'dev.btNotConnected' $_.Name } }) -join ', '
        Add-HcLine $r ok (T 'dev.btPaired' $names)
    } else {
        Add-HcLine $r ok (T 'dev.btNonePaired')
    }
    Select-HcFinding $r $found @('deviceDisabled', 'btServiceStopped', 'deviceError', 'deviceNoDriver') 'btOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcC1 { { Test-HcPrinter (Get-HcPrinterFacts) } }
function Invoke-HcC2 { { Test-HcInputDevices (Get-HcInputFacts) } }
function Invoke-HcC3 { { Test-HcBluetooth (Get-HcBluetoothFacts) } }

$script:ProblemHandlers['C1'] = 'Invoke-HcC1'
$script:ProblemHandlers['C2'] = 'Invoke-HcC2'
$script:ProblemHandlers['C3'] = 'Invoke-HcC3'

# ==================================================== src\checks\audio-interop.ps1 ==
<#
    Windows' audio system (Core Audio), reached from PowerShell through a
    little C#: the sound outputs and microphones that are in use, which one
    is the default, mute and volume, and switching the default.

    Compiled on first use only (about a second), so areas other than B never
    pay for it. SetDefault uses IPolicyConfig: undocumented, but it is what
    the sound settings themselves use, and it has been stable since Windows 7.

    Plain ASCII like everything else; the names come from Windows at run time.
    The C# sits in a double-quoted here-string on purpose: a line starting
    with '@ would end the $HcSource here-string that carries all of
    Housecall. So the C# must never contain a dollar sign or a backtick.
#>

$script:HcAudioSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Housecall
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PropertyKey { public Guid Fmtid; public int Pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant
    {
        [FieldOffset(0)] public short Vt;
        [FieldOffset(8)] public IntPtr Pointer;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PropertyKey key);
        int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float level, ref Guid context);
        int SetMasterVolumeLevelScalar(float level, ref Guid context);
        int GetMasterVolumeLevel(out float level);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(int channel, float level, ref Guid context);
        int SetChannelVolumeLevelScalar(int channel, float level, ref Guid context);
        int GetChannelVolumeLevel(int channel, out float level);
        int GetChannelVolumeLevelScalar(int channel, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig
    {
        int GetMixFormat(string id, IntPtr format);
        int GetDeviceFormat(string id, int def, IntPtr format);
        int ResetDeviceFormat(string id);
        int SetDeviceFormat(string id, IntPtr endpointFormat, IntPtr mixFormat);
        int GetProcessingPeriod(string id, int def, IntPtr defaultPeriod, IntPtr minimumPeriod);
        int SetProcessingPeriod(string id, IntPtr period);
        int GetShareMode(string id, IntPtr mode);
        int SetShareMode(string id, IntPtr mode);
        int GetPropertyValue(string id, int store, IntPtr key, IntPtr value);
        int SetPropertyValue(string id, int store, IntPtr key, IntPtr value);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
        int SetEndpointVisibility(string id, int visible);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorClass { }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClass { }

    public class AudioDevice
    {
        public string Id;
        public string Name;
        public bool IsDefault;
        public bool Muted;
        public int Volume;
    }

    public static class Audio
    {
        static readonly Guid VolumeIid = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        static readonly PropertyKey FriendlyName = new PropertyKey { Fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), Pid = 14 };

        static IMMDeviceEnumerator Enumerator() { return (IMMDeviceEnumerator)new MMDeviceEnumeratorClass(); }

        static IAudioEndpointVolume VolumeOf(IMMDevice device)
        {
            Guid iid = VolumeIid;
            object o;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out o));
            return (IAudioEndpointVolume)o;
        }

        static IMMDevice Find(string id)
        {
            foreach (int flow in new[] { 0, 1 })
            {
                IMMDeviceCollection all;
                Marshal.ThrowExceptionForHR(Enumerator().EnumAudioEndpoints(flow, 1, out all));
                int count; all.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IMMDevice d; all.Item(i, out d);
                    string did; d.GetId(out did);
                    if (did == id) return d;
                }
            }
            throw new ArgumentException("No active audio device with id " + id);
        }

        // flow 0 = outputs (speakers), 1 = inputs (microphones). Active devices only.
        public static AudioDevice[] List(int flow)
        {
            var result = new List<AudioDevice>();
            IMMDeviceEnumerator e = Enumerator();
            string defaultId = null;
            IMMDevice def;
            if (e.GetDefaultAudioEndpoint(flow, 0, out def) == 0 && def != null) def.GetId(out defaultId);

            IMMDeviceCollection all;
            Marshal.ThrowExceptionForHR(e.EnumAudioEndpoints(flow, 1, out all));
            int count; all.GetCount(out count);
            for (int i = 0; i < count; i++)
            {
                IMMDevice d; all.Item(i, out d);
                var a = new AudioDevice();
                d.GetId(out a.Id);
                a.IsDefault = (a.Id == defaultId);
                IPropertyStore store;
                if (d.OpenPropertyStore(0, out store) == 0)
                {
                    PropertyKey key = FriendlyName;
                    PropVariant v;
                    if (store.GetValue(ref key, out v) == 0 && v.Vt == 31) a.Name = Marshal.PtrToStringUni(v.Pointer);
                }
                try
                {
                    IAudioEndpointVolume vol = VolumeOf(d);
                    float level; vol.GetMasterVolumeLevelScalar(out level);
                    bool mute; vol.GetMute(out mute);
                    a.Volume = (int)Math.Round(level * 100);
                    a.Muted = mute;
                }
                catch (Exception) { a.Volume = -1; }
                result.Add(a);
            }
            return result.ToArray();
        }

        // All three roles (console, multimedia, communications), like the sound settings do.
        public static void SetDefault(string id)
        {
            var policy = (IPolicyConfig)new PolicyConfigClass();
            for (int role = 0; role < 3; role++) Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, role));
        }

        public static void SetMute(string id, bool mute)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(VolumeOf(Find(id)).SetMute(mute, ref context));
        }

        public static void SetVolume(string id, int percent)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(VolumeOf(Find(id)).SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, percent)) / 100f, ref context));
        }
    }
}
"@

function Initialize-HcAudio {
    if (-not ('Housecall.Audio' -as [type])) {
        Add-Type -TypeDefinition $script:HcAudioSource -Language CSharp -ErrorAction Stop
    }
}

# Active outputs (flow 0) or microphones (flow 1), or $null when Windows'
# audio system cannot be reached at all (for example the service is down).
function Get-HcAudioDevices {
    param([int]$Flow)
    try {
        Initialize-HcAudio
        return @([Housecall.Audio]::List($Flow) | ForEach-Object {
            [pscustomobject]@{ Id = $_.Id; Name = $_.Name; IsDefault = $_.IsDefault; Muted = $_.Muted; Volume = $_.Volume }
        })
    } catch {
        return $null
    }
}

# ==================================================== src\checks\sound.ps1 ==
<#
    Area B: Sound, screen & video calls.

      B1  no sound                      sound service, sound hardware, outputs, mute, volume
      B2  microphone or camera          microphones, cameras, Windows privacy switches
      B3  screen too small, dark, wrong colour filter, high contrast, magnifier,
                                        brightness, orientation, scale

    Sound is read through Core Audio (src\checks\audio-interop.ps1); the
    privacy switches straight from the registry, where Settings keeps them.
#>

# Outputs that are a screen or a digital socket: fine when the screen has
# speakers and is on, silent otherwise -- the classic "sound went to the TV".
$script:ScreenOutput = '(AMD|NVIDIA|Intel).*(High Definition Audio|Display Audio)|HDMI|DisplayPort|Digital Output|S/PDIF|SPDIF'

# Where Settings keeps "may apps use the microphone / camera".
$script:ConsentStore = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'

# Video-call apps from the Store, by the start of their key under ConsentStore.
# Desktop programs (Zoom, Teams classic, Skype desktop) share one switch: NonPackaged.
$script:CallApps = [ordered]@{
    '5319275A.WhatsAppDesktop' = 'WhatsApp'
    'MSTeams'                  = 'Microsoft Teams'
    'MicrosoftTeams'           = 'Microsoft Teams'
    'Microsoft.SkypeApp'       = 'Skype'
    'Microsoft.WindowsCamera'  = 'Camera'
    'FACEBOOK.317180B0BB486'   = 'Messenger'
    'Zoom'                     = 'Zoom'
}

# ------------------------------------------------------------------- facts --

function Get-HcSoundFacts {
    $running = { param($n) $s = Get-Service -Name $n -ErrorAction SilentlyContinue; $s -and $s.Status -eq 'Running' }
    [pscustomobject]@{
        ServiceRunning = (& $running 'Audiosrv') -and (& $running 'AudioEndpointBuilder')
        Problems       = @(Get-HcProblemDevices 'MEDIA')
        Outputs        = Get-HcAudioDevices 0
    }
}

# One privacy switch: the whole PC (HKLM), apps (HKCU), desktop programs
# (NonPackaged), or one app. Only switches set to Deny matter.
function Get-HcPrivacyBlocks {
    param([string]$Capability)
    $blocks = @()
    $value = { param($path) (Get-ItemProperty $path -ErrorAction SilentlyContinue).Value }
    $user = "HKCU:\$script:ConsentStore\$Capability"
    if ((& $value "HKLM:\$script:ConsentStore\$Capability") -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'all'; Name = $null; Key = "HKLM:\$script:ConsentStore\$Capability"; Machine = $true }
    }
    if ((& $value $user) -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'apps'; Name = $null; Key = $user; Machine = $false }
    }
    if ((& $value "$user\NonPackaged") -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'desktop'; Name = $null; Key = "$user\NonPackaged"; Machine = $false }
    }
    foreach ($key in @(Get-ChildItem $user -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' })) {
        foreach ($prefix in $script:CallApps.Keys) {
            if ($key.PSChildName.StartsWith($prefix) -and (& $value $key.PSPath) -eq 'Deny') {
                $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'app'; Name = $script:CallApps[$prefix]; Key = "$user\$($key.PSChildName)"; Machine = $false }
            }
        }
    }
    $blocks
}

function Get-HcCallFacts {
    $cameras = @(Get-PnpDevice -Class Camera, Image -PresentOnly -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Microphones = Get-HcAudioDevices 1
        Cameras     = @($cameras | Where-Object { $_.ConfigManagerErrorCode -eq 0 } | ForEach-Object { $_.FriendlyName })
        Problems    = @($cameras | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Class = $_.Class; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId } })
        Blocks      = @(Get-HcPrivacyBlocks 'microphone') + @(Get-HcPrivacyBlocks 'webcam')
    }
}

function Get-HcScreenFacts {
    $brightness = $null
    try { $brightness = [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1).CurrentBrightness } catch { }
    $portrait = $false
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $portrait = $b.Height -gt $b.Width
    } catch { }
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
    $text = (Get-ItemProperty 'HKCU:\Software\Microsoft\Accessibility' -ErrorAction SilentlyContinue).TextScaleFactor
    $contrast = (Get-ItemProperty 'HKCU:\Control Panel\Accessibility\HighContrast' -ErrorAction SilentlyContinue).Flags
    [pscustomobject]@{
        Brightness   = $brightness
        ColorFilter  = ((Get-ItemProperty 'HKCU:\Software\Microsoft\ColorFiltering' -ErrorAction SilentlyContinue).Active -eq 1)
        HighContrast = ($contrast -and ([int]$contrast -band 1))
        Magnifier    = [bool](Get-Process -Name Magnify -ErrorAction SilentlyContinue)
        Portrait     = $portrait
        Scale        = $(if ($dpi) { [int]([int]$dpi * 100 / 96) } else { 100 })
        TextSize     = $(if ($text) { [int]$text } else { 100 })
    }
}

# ------------------------------------------------------------------ verdict --

# B1.
function Test-HcSound {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.ServiceRunning -or $null -eq $Facts.Outputs) {
        Add-HcLine $r problem (T 'snd.serviceStopped')
        Add-HcAction $r 'restartAudio'
        Set-HcFinding $r 'audioServiceStopped'
        return $r
    }
    Add-HcLine $r ok (T 'snd.serviceOk')
    foreach ($d in @($Facts.Problems)) { Add-HcDeviceProblem $r $found $d }

    $outputs = @($Facts.Outputs)
    if ($outputs.Count -eq 0) {
        Add-HcLine $r problem (T 'snd.noOutput')
        Select-HcFinding $r $found @('deviceDisabled', 'deviceError', 'deviceNoDriver') 'noOutput'
        return $r
    }

    $default = @($outputs | Where-Object { $_.IsDefault }) | Select-Object -First 1
    if (-not $default) { $default = $outputs[0] }
    Add-HcLine $r ok (T 'snd.default' $default.Name $default.Volume)
    if ($default.Muted) {
        Add-HcLine $r problem (T 'snd.muted' $default.Name)
        Add-HcAction $r 'unmute' @{ Label = $default.Name; Id = $default.Id }
        $found['muted'] = @($default.Name)
    }
    if ($default.Volume -ge 0 -and $default.Volume -le 5) {
        Add-HcLine $r problem (T 'snd.volumeLow' $default.Name $default.Volume)
        Add-HcAction $r 'setVolume' @{ Label = $default.Name; Id = $default.Id; Percent = 50; Previous = $default.Volume }
        $found['volumeLow'] = @($default.Name, $default.Volume)
    }
    $others = @($outputs | Where-Object { $_.Id -ne $default.Id })
    $speakers = @($others | Where-Object { $_.Name -notmatch $script:ScreenOutput })
    if ($default.Name -match $script:ScreenOutput -and $speakers.Count) {
        Add-HcLine $r warn (T 'snd.defaultScreen' $default.Name)
        $found['defaultScreen'] = @($default.Name)
    }
    if ($others.Count) { Add-HcLine $r ok (T 'snd.others' (@($others | ForEach-Object { $_.Name }) -join ', ')) }

    # Speakers and headphones first, then screens; the test sound last.
    foreach ($o in @($speakers) + @($others | Where-Object { $_.Name -match $script:ScreenOutput }) | Select-Object -First 5) {
        Add-HcAction $r 'setDefaultAudio' @{ Label = $o.Name; Id = $o.Id; PreviousId = $default.Id }
    }
    Add-HcAction $r 'testSound'

    Select-HcFinding $r $found @('deviceDisabled', 'deviceError', 'deviceNoDriver', 'muted', 'volumeLow', 'defaultScreen') 'soundOk'
    if ($r.FindingId -eq 'soundOk') { $r.FindingArgs = @($default.Name) }
    $r
}

# "WhatsApp", "Apps", ... for a privacy block, in the current language.
function Get-HcBlockWho {
    param([pscustomobject]$Block)
    if ($Block.Who -eq 'app') { return $Block.Name }
    T ('priv.' + $Block.Who)
}

# B2.
function Test-HcCalls {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    $mics = $Facts.Microphones
    if ($null -eq $mics -or @($mics).Count -eq 0) {
        Add-HcLine $r problem (T 'call.noMic')
        $found['noMic'] = @()
    } else {
        $mic = @(@($mics) | Where-Object { $_.IsDefault }) | Select-Object -First 1
        if (-not $mic) { $mic = @($mics)[0] }
        Add-HcLine $r ok (T 'call.mic' $mic.Name $mic.Volume)
        if ($mic.Muted) {
            Add-HcLine $r problem (T 'call.micMuted' $mic.Name)
            Add-HcAction $r 'unmute' @{ Label = $mic.Name; Id = $mic.Id }
            $found['micMuted'] = @($mic.Name)
        } elseif ($mic.Volume -ge 0 -and $mic.Volume -lt 10) {
            Add-HcLine $r problem (T 'call.micLow' $mic.Name $mic.Volume)
            Add-HcAction $r 'setVolume' @{ Label = $mic.Name; Id = $mic.Id; Percent = 80; Previous = $mic.Volume }
            $found['micLow'] = @($mic.Name)
        }
    }

    foreach ($c in @($Facts.Cameras)) { Add-HcLine $r ok (T 'call.camera' $c) }
    foreach ($d in @($Facts.Problems)) { Add-HcDeviceProblem $r $found $d }
    if (@($Facts.Cameras).Count -eq 0 -and @($Facts.Problems).Count -eq 0) {
        Add-HcLine $r warn (T 'call.noCamera')
        $found['noCamera'] = @()
    }

    foreach ($capability in @('microphone', 'webcam')) {
        $blocks = @($Facts.Blocks | Where-Object { $_.Capability -eq $capability })
        $what = T "priv.$capability"
        if ($blocks.Count -eq 0) { Add-HcLine $r ok (T 'call.privacyOk' $what); continue }
        foreach ($b in $blocks) {
            $who = Get-HcBlockWho $b
            Add-HcLine $r problem (T 'call.blocked' $who $what)
            $fix = if ($b.Machine) { 'allowAccessMachine' } else { 'allowAccess' }
            Add-HcAction $r $fix @{ Label = "$who, $what"; Key = $b.Key }
            if (-not $found['privacyBlocked']) { $found['privacyBlocked'] = @($who, $what) }
        }
    }

    Select-HcFinding $r $found @('privacyBlocked', 'micMuted', 'noMic', 'deviceDisabled', 'deviceError', 'deviceNoDriver', 'micLow', 'noCamera') 'callsOk'
    $r
}

# B3.
function Test-HcScreen {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($null -ne $Facts.Brightness) {
        if ($Facts.Brightness -lt 30) {
            Add-HcLine $r problem (T 'scr.tooDark' $Facts.Brightness)
            Add-HcAction $r 'setBrightness' @{ Label = ''; Percent = 80; Previous = $Facts.Brightness }
            $found['tooDark'] = @($Facts.Brightness)
        } else {
            Add-HcLine $r ok (T 'scr.brightness' $Facts.Brightness)
        }
    }
    if ($Facts.ColorFilter) { Add-HcLine $r problem (T 'scr.colorFilter'); $found['colorFilter'] = @() }
    if ($Facts.HighContrast) { Add-HcLine $r problem (T 'scr.highContrast'); $found['highContrast'] = @() }
    if ($Facts.Magnifier) {
        Add-HcLine $r problem (T 'scr.magnifier')
        Add-HcAction $r 'closeMagnifier'
        $found['magnifier'] = @()
    }
    if (-not ($Facts.ColorFilter -or $Facts.HighContrast -or $Facts.Magnifier)) { Add-HcLine $r ok (T 'scr.normal') }
    if ($Facts.Portrait) { Add-HcLine $r warn (T 'scr.rotated'); $found['rotated'] = @() }
    Add-HcLine $r ok (T 'scr.scale' $Facts.Scale $Facts.TextSize)

    Select-HcFinding $r $found @('tooDark', 'colorFilter', 'highContrast', 'magnifier', 'rotated') 'screenOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcB1 { { Test-HcSound (Get-HcSoundFacts) } }
function Invoke-HcB2 { { Test-HcCalls (Get-HcCallFacts) } }
function Invoke-HcB3 { { Test-HcScreen (Get-HcScreenFacts) } }

$script:ProblemHandlers['B1'] = 'Invoke-HcB1'
$script:ProblemHandlers['B2'] = 'Invoke-HcB2'
$script:ProblemHandlers['B3'] = 'Invoke-HcB3'

# ==================================================== src\checks\performance.ps1 ==
<#
    Area D: Slow or freezing.

      D1  the whole computer is slow    disk space, memory, CPU now, time since restart,
                                        system disk type, RAM size, startup programs
      D2  takes ages to start           startup programs, system disk type, disk space
      D3  a program freezes or crashes  crashes and hangs this week, blue screens,
                                        unexpected shutdowns, memory
      D4  the disk is full              free space, Temp, Recycle Bin, Downloads

    CPU comes from Win32_PerfFormattedData classes, not Get-Counter, whose
    counter names Windows translates. Startup programs are switched on and
    off the way Task Manager does it: a StartupApproved value, first byte
    02 = on, 03 = off, so it can be undone.
#>

$script:DiskFullPercent  = 5      # free % of the system disk at or below: full
$script:DiskLowPercent   = 15     # ... at or below: getting full
$script:MemoryFullPercent = 90
$script:CpuBusyPercent   = 80
$script:UptimeDays       = 7
$script:ManyStartup      = 8

# Programs that start with Windows and should keep doing so: security,
# sound and touchpad drivers, OneDrive (photo backup).
$script:KeepAtStartup = 'SecurityHealth|Defender|Realtek|RtkAud|Nahimic|Waves|Dolby|Synaptics|ELAN|igfx|Intel|AMD|NVIDIA|Bluetooth|OneDrive|Housecall|Reveille|Courier'

# Windows' own background processes: their crashes are Windows' business,
# and "update or reinstall it" would be nonsense advice.
$script:WindowsHelpers = '^(dllhost|svchost|backgroundTaskHost|RuntimeBroker|taskhostw|WerFault|SearchProtocolHost|SearchHost|SearchIndexer|conhost|sihost|ctfmon|smartscreen)$'

# Processes never offered for closing.
$script:SystemProcess = '^(System|Idle|svchost|csrss|wininit|services|lsass|smss|dwm|explorer|MsMpEng|Registry|Memory Compression|audiodg|winlogon|fontdrvhost|Secure System|powershell|conhost)$'

# ------------------------------------------------------------------- facts --

function Get-HcSystemDisk {
    $drive = $env:SystemDrive
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    $media = $null
    try {
        $media = [string](Get-Partition -DriveLetter $drive.TrimEnd(':') -ErrorAction Stop | Get-Disk -ErrorAction Stop | Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1).MediaType
    } catch { }
    [pscustomobject]@{
        Drive  = $drive
        FreeGB = [math]::Round($d.FreeSpace / 1GB, 1)
        SizeGB = [math]::Round($d.Size / 1GB, 1)
        FreePercent = if ($d.Size) { [int](100 * $d.FreeSpace / $d.Size) } else { 100 }
        Media  = $media     # SSD, HDD or Unspecified
    }
}

<#
    Startup programs from the Run keys and Startup folders, each with the
    StartupApproved value Task Manager uses to switch it on or off.
#>
function Get-HcStartupItems {
    $approvedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Hive = 'HKCU'; Kind = 'Run';           Key = 'Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLM'; Kind = 'Run';           Key = 'Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLM'; Kind = 'Run32';         Key = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKCU'; Kind = 'StartupFolder'; Folder = [Environment]::GetFolderPath('Startup') }
        @{ Hive = 'HKLM'; Kind = 'StartupFolder'; Folder = [Environment]::GetFolderPath('CommonStartup') }
    )
    foreach ($s in $sources) {
        $names = @()
        if ($s.Key) {
            $item = Get-Item "$($s.Hive):\$($s.Key)" -ErrorAction SilentlyContinue
            if ($item) { $names = @($item.Property) }
        } elseif ($s.Folder -and (Test-Path -LiteralPath $s.Folder)) {
            $names = @(Get-ChildItem -LiteralPath $s.Folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { $_.Name })
        }
        $approved = "$($s.Hive):\$approvedRoot\$($s.Kind)"
        $values = Get-ItemProperty $approved -ErrorAction SilentlyContinue
        foreach ($n in $names) {
            $bytes = if ($values) { $values.$n } else { $null }
            [pscustomobject]@{
                Name     = ($n -replace '\.lnk$', '')
                Value    = $n
                Machine  = ($s.Hive -eq 'HKLM')
                Approved = $approved
                Enabled  = -not ($bytes -and $bytes.Count -gt 0 -and ($bytes[0] -band 1))
            }
        }
    }
}

function Get-HcBusyProcesses {
    $cores = [Math]::Max(1, [Environment]::ProcessorCount)
    @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('_Total', 'Idle') } |
        Sort-Object PercentProcessorTime -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{
                Name = ($_.Name -replace '#\d+$', '')
                Cpu  = [int]($_.PercentProcessorTime / $cores)
                MemoryMB = [int]($_.WorkingSetPrivate / 1MB)
            }
        })
}

function Get-HcPerformanceFacts {
    param([switch]$Crashes, [switch]$Sizes)
    $os = Get-CimInstance Win32_OperatingSystem
    $f = [pscustomobject]@{
        Disk        = Get-HcSystemDisk
        RamGB       = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        MemoryUsed  = [int](100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
        Cpu         = [int](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorTime
        Busy        = @(Get-HcBusyProcesses)
        UptimeDays  = [int]((Get-Date) - $os.LastBootUpTime).TotalDays
        Startup     = @(Get-HcStartupItems)
        CrashApps   = @()
        Shutdowns   = 0
        BlueScreens = 0
        Sizes       = $null
    }
    if ($Crashes) {
        $since = (Get-Date).AddDays(-7)
        try {
            $f.CrashApps = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -ErrorAction Stop |
                Group-Object { ([string]$_.Properties[0].Value) -replace '\.exe$', '' } | Where-Object { $_.Name -notmatch $script:WindowsHelpers } |
                Sort-Object Count -Descending | Select-Object -First 5 |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } })
        } catch { }
        $month = (Get-Date).AddDays(-30)
        try { $f.Shutdowns = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $month } -ErrorAction Stop).Count } catch { }
        try { $f.BlueScreens = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $month } -ErrorAction Stop).Count } catch { }
    }
    if ($Sizes) {
        $size = { param($path) if ($path -and (Test-Path -LiteralPath $path)) { [math]::Round(((Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 1) } else { 0 } }
        $binGB = 0
        try {
            $bytes = 0
            foreach ($i in (New-Object -ComObject Shell.Application).Namespace(10).Items()) { $bytes += $i.Size }
            $binGB = [math]::Round($bytes / 1GB, 1)
        } catch { }
        $downloads = $null
        try { $downloads = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path } catch { }
        $f.Sizes = [pscustomobject]@{ TempGB = & $size $env:TEMP; BinGB = $binGB; DownloadsGB = & $size $downloads }
    }
    $f
}

# ------------------------------------------------------------------ verdict --

# Lines for the startup programs, and a switch-off offer for each one that
# may go. Returns how many are on.
function Add-HcStartupLines {
    param([pscustomobject]$Report, [object[]]$Items)
    $on = @($Items | Where-Object { $_.Enabled })
    $names = @($on | ForEach-Object { $_.Name }) -join ', '
    if ($on.Count -gt $script:ManyStartup) {
        Add-HcLine $Report warn (T 'perf.startupMany' $on.Count $names)
    } else {
        Add-HcLine $Report ok (T 'perf.startup' $on.Count)
    }
    foreach ($i in @($on | Where-Object { $_.Name -notmatch $script:KeepAtStartup }) | Select-Object -First 6) {
        $fix = if ($i.Machine) { 'disableStartupMachine' } else { 'disableStartup' }
        Add-HcAction $Report $fix @{ Label = $i.Name; Approved = $i.Approved; Value = $i.Value }
    }
    $on.Count
}

function Add-HcDiskLine {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Disk)
    if ($Disk.FreePercent -le $script:DiskFullPercent) {
        Add-HcLine $Report problem (T 'perf.diskFull' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
        $Found['diskFull'] = @($Disk.Drive, $Disk.FreeGB)
    } elseif ($Disk.FreePercent -le $script:DiskLowPercent) {
        Add-HcLine $Report warn (T 'perf.diskLow' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
        $Found['diskLow'] = @($Disk.Drive, $Disk.FreeGB)
    } else {
        Add-HcLine $Report ok (T 'perf.diskOk' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
    }
    if ($Disk.Media -eq 'HDD') {
        Add-HcLine $Report warn (T 'perf.hdd' $Disk.Drive)
        $Found['hddSystem'] = @()
    }
}

function Add-HcMemoryLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    if ($Facts.MemoryUsed -ge $script:MemoryFullPercent) {
        Add-HcLine $Report problem (T 'perf.memoryFull' $Facts.MemoryUsed $Facts.RamGB)
        $Found['memoryFull'] = @($Facts.MemoryUsed)
    } else {
        Add-HcLine $Report ok (T 'perf.memory' $Facts.MemoryUsed $Facts.RamGB)
    }
    if ($Facts.RamGB -le 4.1) {
        Add-HcLine $Report warn (T 'perf.lowRam' $Facts.RamGB)
        $Found['lowRam'] = @($Facts.RamGB)
    }
}

# D1.
function Test-HcSlow {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    Add-HcDiskLine $r $found $Facts.Disk
    Add-HcMemoryLines $r $found $Facts

    $top = @($Facts.Busy) | Select-Object -First 1
    if ($Facts.Cpu -ge $script:CpuBusyPercent) {
        $who = if ($top) { $top.Name } else { '?' }
        Add-HcLine $r problem (T 'perf.cpuBusy' $Facts.Cpu $who)
        $found['cpuBusy'] = @($Facts.Cpu, $who)
    } else {
        Add-HcLine $r ok (T 'perf.cpu' $Facts.Cpu)
    }
    # A program hogging the processor or memory may be closed (unsaved work goes).
    $hog = @($Facts.Busy | Where-Object { $_.Name -notmatch $script:SystemProcess -and ($_.Cpu -ge 50 -or ($Facts.MemoryUsed -ge $script:MemoryFullPercent -and $_.MemoryMB -ge 1500)) }) | Select-Object -First 1
    if ($hog) { Add-HcAction $r 'closeProcess' @{ Label = $hog.Name; Name = $hog.Name } }

    if ($Facts.UptimeDays -ge $script:UptimeDays) {
        Add-HcLine $r warn (T 'perf.uptimeLong' $Facts.UptimeDays)
        $found['longUptime'] = @($Facts.UptimeDays)
    } else {
        Add-HcLine $r ok (T 'perf.uptime' $Facts.UptimeDays)
    }
    if ((Add-HcStartupLines $r $Facts.Startup) -gt $script:ManyStartup) { $found['manyStartup'] = @(@($Facts.Startup | Where-Object { $_.Enabled }).Count) }

    Select-HcFinding $r $found @('diskFull', 'memoryFull', 'cpuBusy', 'longUptime', 'hddSystem', 'lowRam', 'manyStartup', 'diskLow') 'slowOk'
    $r
}

# D2.
function Test-HcSlowStart {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if ((Add-HcStartupLines $r $Facts.Startup) -gt $script:ManyStartup) { $found['manyStartup'] = @(@($Facts.Startup | Where-Object { $_.Enabled }).Count) }
    Add-HcDiskLine $r $found $Facts.Disk
    Add-HcMemoryLines $r $found $Facts
    Select-HcFinding $r $found @('diskFull', 'hddSystem', 'manyStartup', 'lowRam', 'diskLow') 'startOk'
    $r
}

# D3.
function Test-HcCrashes {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $apps = @($Facts.CrashApps)
    if ($apps.Count) {
        foreach ($a in $apps) { Add-HcLine $r $(if ($a.Count -ge 3) { 'problem' } else { 'warn' }) (T 'perf.crashApp' $a.Name $a.Count) }
        $worst = $apps[0]
        if ($worst.Count -ge 3) { $found['crashes'] = @($worst.Name, $worst.Count) } else { $found['someCrashes'] = @($worst.Name) }
    } else {
        Add-HcLine $r ok (T 'perf.noCrashes')
    }
    if ($Facts.BlueScreens -gt 0) {
        Add-HcLine $r problem (T 'perf.blueScreens' $Facts.BlueScreens)
        $found['blueScreens'] = @($Facts.BlueScreens)
    }
    if ($Facts.Shutdowns -gt 0) {
        Add-HcLine $r warn (T 'perf.shutdowns' $Facts.Shutdowns)
        $found['shutdowns'] = @($Facts.Shutdowns)
    }
    Add-HcMemoryLines $r $found $Facts
    Add-HcDiskLine $r $found $Facts.Disk
    Select-HcFinding $r $found @('blueScreens', 'crashes', 'memoryFull', 'diskFull', 'shutdowns', 'someCrashes', 'lowRam') 'crashOk'
    $r
}

# D4.
function Test-HcDiskSpace {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    Add-HcDiskLine $r $found $Facts.Disk
    $s = $Facts.Sizes
    if ($s) {
        Add-HcLine $r ok (T 'perf.sizes' $s.TempGB $s.BinGB $s.DownloadsGB)
        if ($s.TempGB -ge 0.5) { Add-HcAction $r 'emptyTemp' @{ Label = $s.TempGB } }
        if ($s.BinGB -ge 0.1) { Add-HcAction $r 'emptyRecycleBin' @{ Label = $s.BinGB } }
    }
    # D4 is where the space gets freed, so its findings point below, not to D4.
    Select-HcFinding $r $found @('diskFull', 'diskLow') 'diskOk'
    switch ($r.FindingId) {
        'diskFull' { $r.FindingId = 'spaceFull' }
        'diskLow'  { $r.FindingId = 'spaceLow' }
        'diskOk'   { $r.FindingArgs = @($Facts.Disk.Drive, $Facts.Disk.FreeGB) }
    }
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcD1 { { Test-HcSlow (Get-HcPerformanceFacts) } }
function Invoke-HcD2 { { Test-HcSlowStart (Get-HcPerformanceFacts) } }
function Invoke-HcD3 { { Test-HcCrashes (Get-HcPerformanceFacts -Crashes) } }
function Invoke-HcD4 { { Test-HcDiskSpace (Get-HcPerformanceFacts -Sizes) } }

$script:ProblemHandlers['D1'] = 'Invoke-HcD1'
$script:ProblemHandlers['D2'] = 'Invoke-HcD2'
$script:ProblemHandlers['D3'] = 'Invoke-HcD3'
$script:ProblemHandlers['D4'] = 'Invoke-HcD4'

# ==================================================== src\checks\updates.ps1 ==
<#
    Area E: Windows & updates.

      E1  update stuck or failing      update service, last real update, failures,
                                       paused, restart pending, disk space, Windows 10
      E2  error message on the screen  activation, the clock, restart pending, recent crashes
      E3  will not shut down / restart restart pending (updates), fast startup, time since restart

    The update history comes from Windows Update's own COM object; titles
    are translated by Windows, so nothing here matches on them except the
    two KB numbers of Defender's daily definitions, which are left out: they
    install every day and would hide a Windows Update that is stuck.
#>

$script:DefenderKbs = 'KB2267602|KB4052623'
$script:StaleDays = 45
$script:UpdateSpaceGB = 10
$script:ClockToleranceSec = 300

# ------------------------------------------------------------------- facts --

function Test-HcRebootPending {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Get-HcUpdateHistory {
    $h = [pscustomobject]@{ LastSuccess = $null; Failures = @(); Known = $false }
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        $entries = @($searcher.QueryHistory(0, [Math]::Min($count, 100)) | Where-Object { $_.Operation -eq 1 -and $_.Title -notmatch $script:DefenderKbs })
        $h.Known = $true
        $h.LastSuccess = ($entries | Where-Object { $_.ResultCode -eq 2 } | Sort-Object Date -Descending | Select-Object -First 1).Date
        if ($h.LastSuccess) { $h.LastSuccess = $h.LastSuccess.ToLocalTime() }
        $since = (Get-Date).AddDays(-30)
        $h.Failures = @($entries | Where-Object { $_.ResultCode -in @(4, 5) -and $_.Date -gt $since } |
            Group-Object Title | ForEach-Object { $_.Group[0] } | Sort-Object Date -Descending | Select-Object -First 3 |
            ForEach-Object { [pscustomobject]@{ Title = ($_.Title -replace '\s+\(.*$', ''); Code = ('0x{0:X8}' -f $_.HResult) } })
    } catch { }
    $h
}

function Get-HcUpdateFacts {
    $pause = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime
    $pausedUntil = $null
    if ($pause) { try { $pausedUntil = [datetime]::Parse($pause, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime() } catch { } }
    $service = Get-Service wuauserv -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Now             = Get-Date
        ServiceDisabled = ($service -and [string]$service.StartType -eq 'Disabled')
        History         = Get-HcUpdateHistory
        RebootPending   = Test-HcRebootPending
        PausedUntil     = $pausedUntil
        Windows10       = ([Environment]::OSVersion.Version.Build -lt 22000)
        Disk            = Get-HcSystemDisk
    }
}

# Seconds this PC's clock is off from internet time (the Date header of the
# page Windows itself uses to test the internet), or $null when offline.
function Get-HcClockOffset {
    try {
        $r = Invoke-WebRequest -Uri "http://$script:TestHost/connecttest.txt" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $server = [datetime]::Parse($r.Headers['Date'], [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        return [int]([datetime]::UtcNow - $server).TotalSeconds
    } catch {
        return $null
    }
}

function Get-HcErrorFacts {
    $activated = $null
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop | Select-Object -First 1
        if ($lic) { $activated = ($lic.LicenseStatus -eq 1) }
    } catch { }
    $crashes = @()
    try {
        $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = (Get-Date).AddDays(-3) } -ErrorAction Stop |
            Group-Object { ([string]$_.Properties[0].Value) -replace '\.exe$', '' } | Where-Object { $_.Name -notmatch $script:WindowsHelpers } |
            Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } })
    } catch { }
    [pscustomobject]@{
        Activated     = $activated
        ClockOffset   = Get-HcClockOffset
        RebootPending = Test-HcRebootPending
        Crashes       = $crashes
    }
}

function Get-HcShutdownFacts {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        RebootPending = Test-HcRebootPending
        FastStartup   = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1)
        UptimeDays    = [int]((Get-Date) - $os.LastBootUpTime).TotalDays
    }
}

# ------------------------------------------------------------------ verdict --

# E1.
function Test-HcUpdates {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Windows10) {
        Add-HcLine $r problem (T 'upd.windows10')
        $found['windows10'] = @()
    }
    if ($Facts.ServiceDisabled) {
        Add-HcLine $r problem (T 'upd.serviceDisabled')
        Add-HcAction $r 'enableUpdateService'
        $found['updateServiceDisabled'] = @()
    } else {
        Add-HcLine $r ok (T 'upd.serviceOk')
    }
    if ($Facts.PausedUntil -and $Facts.PausedUntil -gt $Facts.Now) {
        Add-HcLine $r warn (T 'upd.paused' (Format-HcDate $Facts.PausedUntil))
        Add-HcAction $r 'resumeUpdates'
        $found['updatesPaused'] = @(Format-HcDate $Facts.PausedUntil)
    }

    $h = $Facts.History
    if ($h.Known) {
        if ($h.LastSuccess) {
            $days = [int]($Facts.Now - $h.LastSuccess).TotalDays
            if ($days -gt $script:StaleDays) {
                Add-HcLine $r problem (T 'upd.lastOld' (Format-HcDate $h.LastSuccess) $days)
                $found['updatesStale'] = @($days)
            } else {
                Add-HcLine $r ok (T 'upd.last' (Format-HcDate $h.LastSuccess))
            }
        } else {
            Add-HcLine $r problem (T 'upd.never')
            $found['updatesStale'] = @('?')
        }
        foreach ($f in @($h.Failures)) { Add-HcLine $r problem (T 'upd.failed' $f.Title $f.Code) }
        if (@($h.Failures).Count) { $found['updateFailures'] = @(@($h.Failures)[0].Code) }
    } else {
        Add-HcLine $r skipped (T 'upd.historyUnknown')
    }
    if ($found['updateFailures'] -or $found['updatesStale']) { Add-HcAction $r 'resetUpdates' }

    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    }
    if ($Facts.Disk.FreeGB -lt $script:UpdateSpaceGB) {
        Add-HcLine $r problem (T 'upd.noSpace' $Facts.Disk.Drive $Facts.Disk.FreeGB)
        $found['updateSpace'] = @($Facts.Disk.FreeGB)
    }

    Select-HcFinding $r $found @('updateServiceDisabled', 'windows10', 'updateSpace', 'updatesPaused', 'rebootPending', 'updateFailures', 'updatesStale') 'updatesOk'
    $r
}

# E2.
function Test-HcErrors {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Activated -eq $false) {
        Add-HcLine $r problem (T 'err.notActivated')
        $found['notActivated'] = @()
    } elseif ($Facts.Activated) {
        Add-HcLine $r ok (T 'err.activated')
    }
    if ($null -eq $Facts.ClockOffset) {
        Add-HcLine $r skipped (T 'err.clockUnknown')
    } elseif ([Math]::Abs($Facts.ClockOffset) -gt $script:ClockToleranceSec) {
        Add-HcLine $r problem (T 'err.clockWrong' ([int]([Math]::Abs($Facts.ClockOffset) / 60)))
        Add-HcAction $r 'syncClock'
        $found['clockWrong'] = @([int]([Math]::Abs($Facts.ClockOffset) / 60))
    } else {
        Add-HcLine $r ok (T 'err.clockOk')
    }
    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    }
    $crashes = @($Facts.Crashes)
    if ($crashes.Count) {
        foreach ($c in $crashes) { Add-HcLine $r warn (T 'err.crash' $c.Name $c.Count) }
        $found['recentCrash'] = @($crashes[0].Name)
    } else {
        Add-HcLine $r ok (T 'err.noCrash')
    }
    Add-HcAction $r 'repairWindows'
    Select-HcFinding $r $found @('clockWrong', 'notActivated', 'rebootPending', 'recentCrash') 'errorsOk'
    $r
}

# E3.
function Test-HcShutdown {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    } else {
        Add-HcLine $r ok (T 'sd.noPending')
    }
    if ($Facts.FastStartup) {
        Add-HcLine $r warn (T 'sd.fastStartup')
        Add-HcAction $r 'disableFastStartup'
        $found['fastStartup'] = @()
    }
    if ($Facts.UptimeDays -ge $script:UptimeDays) {
        Add-HcLine $r warn (T 'perf.uptimeLong' $Facts.UptimeDays)
        $found['longUptime'] = @($Facts.UptimeDays)
    } else {
        Add-HcLine $r ok (T 'perf.uptime' $Facts.UptimeDays)
    }
    Select-HcFinding $r $found @('rebootPending', 'fastStartup', 'longUptime') 'shutdownOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcE1 { { Test-HcUpdates (Get-HcUpdateFacts) } }
function Invoke-HcE2 { { Test-HcErrors (Get-HcErrorFacts) } }
function Invoke-HcE3 { { Test-HcShutdown (Get-HcShutdownFacts) } }

$script:ProblemHandlers['E1'] = 'Invoke-HcE1'
$script:ProblemHandlers['E2'] = 'Invoke-HcE2'
$script:ProblemHandlers['E3'] = 'Invoke-HcE3'

# ==================================================== src\checks\desktop.ps1 ==
<#
    Area G: files, desktop & accounts.

      G1  the desktop, taskbar or folders act strange
                                  temporary profile, File Explorer running and
                                  responding, desktop icons and Recycle Bin
                                  shown, Desktop moved into OneDrive, taskbar
                                  auto-hide, search box, tablet mode (Windows 10)
      G2  files gone or not everywhere      (not built yet)
      G3  a file cannot be found or opens wrong  (not built yet)

    What an older client says on the phone: "my desktop is empty", "the bar at
    the bottom is gone", "my folders won't open", "everything suddenly looks
    different". One check looks at all of it, because the client cannot tell
    these apart. Everything here reads the current user's own settings; only
    the fixes in src\fixes.ps1 change them, and each can be undone.
#>

$script:ExplorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$script:RecycleBinId = '{645FF040-5081-101B-9F08-00AA002F954E}'
# Where Windows really keeps "Show desktop icons": the desktop's own view
# settings. Bit 0x1000 of FFlags means no icons. HideIcons under Advanced is
# only a copy, which Explorer overwrites from FFlags when it starts (found
# on Shamil's PC, 27 Sep: setting HideIcons alone came back within seconds).
$script:DesktopBagKey = 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
$script:NoIconsFlag = 0x1000

# ------------------------------------------------------------------- facts --

# A temporary profile: Windows could not load the user's own profile and
# signed in with an empty one, so the desktop and files seem gone.
function Test-HcTempProfile {
    if ("$env:USERPROFILE" -match '\\TEMP(\.[^\\]*)?$') { return $true }
    try {
        $mine = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { $_.LocalPath -eq $env:USERPROFILE } | Select-Object -First 1
        if ($mine -and ([int]$mine.Status -band 1)) { return $true }
    } catch { }
    $false
}

function Get-HcShellFacts {
    $advanced = Get-ItemProperty "$script:ExplorerKey\Advanced" -ErrorAction SilentlyContinue
    $flags = (Get-ItemProperty $script:DesktopBagKey -ErrorAction SilentlyContinue).FFlags
    $icons = Get-ItemProperty "$script:ExplorerKey\HideDesktopIcons\NewStartPanel" -ErrorAction SilentlyContinue
    $taskbar = (Get-ItemProperty "$script:ExplorerKey\StuckRects3" -ErrorAction SilentlyContinue).Settings
    $search = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -ErrorAction SilentlyContinue).SearchboxTaskbarMode
    $tablet = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell' -ErrorAction SilentlyContinue).TabletMode
    # The shell's explorer has a window (the taskbar); a folder window's
    # explorer may not. Frozen = a windowed explorer that stopped responding.
    $explorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    $desktop = [Environment]::GetFolderPath('Desktop')
    $items = 0
    foreach ($folder in @($desktop, [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        if ($folder -and (Test-Path -LiteralPath $folder)) {
            $items += @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count
        }
    }
    [pscustomobject]@{
        TempProfile      = Test-HcTempProfile
        ExplorerRunning  = ($explorer.Count -gt 0)
        ExplorerHung     = [bool]@($explorer | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and -not $_.Responding }).Count
        IconsHidden      = (Test-HcIconsHidden $advanced.HideIcons $flags)
        RecycleBinHidden = ($icons -and $icons.$script:RecycleBinId -eq 1)
        DesktopItems     = $items
        DesktopInOneDrive = ("$desktop" -match '\\OneDrive[^\\]*\\')
        OneDriveRunning  = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        TaskbarAutoHide  = (Test-HcTaskbarAutoHide $taskbar)
        SearchHidden     = ($null -ne $search -and [int]$search -eq 0)
        TabletMode       = ($tablet -eq 1)
        Windows10        = ([Environment]::OSVersion.Version.Build -lt 22000)
    }
}

# The desktop's view flags decide; HideIcons only counts when they are missing.
function Test-HcIconsHidden {
    param($HideIcons, $Flags)
    if ($null -ne $Flags) { return [bool]((ConvertTo-HcUInt32 $Flags) -band $script:NoIconsFlag) }
    ($HideIcons -eq 1)
}

# Registry DWORDs come back as signed Int32; the flag maths needs them unsigned.
function ConvertTo-HcUInt32 {
    param($Value)
    [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0)
}

function ConvertTo-HcInt32 {
    param([uint32]$Value)
    [BitConverter]::ToInt32([BitConverter]::GetBytes($Value), 0)
}

# The taskbar's settings are a binary blob; byte 8 is 3 when it hides itself
# and 2 when it stays. Pure, so the tests can check both ways.
function Test-HcTaskbarAutoHide {
    param([byte[]]$Settings)
    [bool]($Settings -and $Settings.Count -gt 8 -and ($Settings[8] -band 1))
}

function ConvertTo-HcTaskbarSetting {
    param([byte[]]$Settings, [bool]$AutoHide)
    $copy = [byte[]]$Settings.Clone()
    if ($AutoHide) { $copy[8] = [byte]($copy[8] -bor 1) } else { $copy[8] = [byte]($copy[8] -band 0xFE) }
    , $copy
}

# ------------------------------------------------------------------ verdict --

# G1.
function Test-HcShell {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.TempProfile) {
        Add-HcLine $r problem (T 'shell.tempProfile')
        $found['tempProfile'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.profileOk')
    }

    if (-not $Facts.ExplorerRunning) {
        Add-HcLine $r problem (T 'shell.explorerMissing')
        $found['explorerMissing'] = @()
    } elseif ($Facts.ExplorerHung) {
        Add-HcLine $r problem (T 'shell.explorerHung')
        $found['explorerHung'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.explorerOk')
    }
    # Restarting Explorer is first when it is the cause.
    $explorerCause = $found.ContainsKey('explorerMissing') -or $found.ContainsKey('explorerHung')
    if ($explorerCause) { Add-HcAction $r 'restartExplorer' }

    if ($Facts.IconsHidden) {
        Add-HcLine $r problem (T 'shell.iconsHidden')
        Add-HcAction $r 'showDesktopIcons'
        $found['iconsHidden'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.iconsShown' $Facts.DesktopItems)
    }
    if ($Facts.DesktopInOneDrive) {
        if ($Facts.OneDriveRunning) {
            Add-HcLine $r ok (T 'shell.desktopOneDrive')
        } else {
            Add-HcLine $r warn (T 'shell.desktopOneDriveOff')
            $found['desktopOneDrive'] = @()
        }
    }
    if ($Facts.RecycleBinHidden) {
        Add-HcLine $r warn (T 'shell.recycleHidden')
        Add-HcAction $r 'showRecycleBin'
        $found['recycleHidden'] = @()
    }

    if ($Facts.TaskbarAutoHide) {
        Add-HcLine $r warn (T 'shell.taskbarAutoHide')
        Add-HcAction $r 'taskbarStay'
        $found['taskbarAutoHide'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.taskbarShown')
    }
    if ($Facts.SearchHidden) {
        Add-HcLine $r warn (T 'shell.searchHidden')
        Add-HcAction $r 'showSearch'
        $found['searchHidden'] = @()
    }
    if ($Facts.Windows10 -and $Facts.TabletMode) {
        Add-HcLine $r warn (T 'shell.tabletMode')
        $found['tabletMode'] = @()
    }

    # Nothing wrong in the settings, yet the client says it acts strange:
    # restarting Explorer is still the harmless first thing to try.
    if (-not $explorerCause) { Add-HcAction $r 'restartExplorer' }

    Select-HcFinding $r $found @('tempProfile', 'explorerMissing', 'explorerHung', 'iconsHidden', 'desktopOneDrive', 'tabletMode', 'taskbarAutoHide', 'searchHidden', 'recycleHidden') 'shellOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcG1 { { Test-HcShell (Get-HcShellFacts) } }

$script:ProblemHandlers['G1'] = 'Invoke-HcG1'

# ==================================================== src\fixes.ps1 ==
<#
    Fixes: the only code in Housecall that changes the PC.

    Every fix is on this list; nothing else, and never the AI, may change
    anything. A report offers fixes (Add-HcAction), the person picks one and
    confirms it, and only then does Apply run. Each fix says:

      Label    fix.<id> in strings.ps1, filled from the target, and
               fix.<id>.done for the note and undo ("Disabled task X")
      Note     undo = can be undone, safe = harmless and needs no undo,
               restart = closes a program, which can simply be started again,
               reprint = removes stuck print jobs, which need printing again,
               temp = only temporary files, noundo = cannot be undone,
               unsaved = closes a program, and its unsaved work,
               redownload = Windows downloads again, long = takes a while,
               restartNeeded = works after a restart, uninstaller = opens the
               program's own uninstaller
      Admin    needs an administrator PowerShell
      Apply    does it; throws when it fails
      Undo     puts it back ($null when there is nothing to put back)

    Fixes never delete. A scheduled task is disabled, not removed; a program
    is closed, not uninstalled (uninstalling needs its own uninstaller).

    Every applied fix goes on $script:HcChanges, so U can undo the session.
#>

$script:HcChanges = New-Object System.Collections.ArrayList

$script:Fixes = @{
    disableTask = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null }
        Undo  = { param($t) Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null }
    }
    stopRemote = @{
        Note = 'restart'; Admin = $false
        Apply = { param($t) Get-Process -Name $t.Processes -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }
    proxyOff = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            $now = Get-ItemProperty $key
            $t.Saved = @{ ProxyEnable = $now.ProxyEnable; AutoConfigURL = $now.AutoConfigURL }
            Set-ItemProperty $key -Name ProxyEnable -Value 0 -ErrorAction Stop
            if ($now.AutoConfigURL) { Remove-ItemProperty $key -Name AutoConfigURL -ErrorAction Stop }
        }
        Undo = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            if ($null -ne $t.Saved.ProxyEnable) { Set-ItemProperty $key -Name ProxyEnable -Value $t.Saved.ProxyEnable -ErrorAction Stop }
            if ($t.Saved.AutoConfigURL) { Set-ItemProperty $key -Name AutoConfigURL -Value $t.Saved.AutoConfigURL -ErrorAction Stop }
        }
    }
    flushDns = @{
        Note = 'safe'; Admin = $false
        Apply = { param($t) & ipconfig.exe /flushdns | Out-Null; if ($LASTEXITCODE -ne 0) { throw "ipconfig /flushdns: $LASTEXITCODE" } }
        Undo  = $null
    }
    renewIp = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            & ipconfig.exe /release | Out-Null
            & ipconfig.exe /renew | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ipconfig /renew: $LASTEXITCODE" }
        }
        Undo = $null
    }

    # Clears Windows' network settings back to how they were installed.
    # Only takes effect after a restart; the note on the fix says so.
    resetWinsock = @{
        Note = 'restartNeeded'; Admin = $true
        Apply = {
            param($t)
            & netsh.exe winsock reset | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "netsh winsock reset: $LASTEXITCODE" }
            & netsh.exe int ip reset | Out-Null
        }
        Undo = $null
    }
    restartAdapter = @{
        Note = 'safe'; Admin = $true
        Apply = { param($t) Restart-NetAdapter -Name $t.Name -Confirm:$false -ErrorAction Stop }
        Undo  = $null
    }

    # ---- F: remote tools and notification sites
    # Runs the program's own uninstaller (it may ask for permission itself).
    uninstallProgram = @{
        Note = 'uninstaller'; Admin = $false
        Apply = {
            param($t)
            $command = [string]$t.Command
            if ($command -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $arguments = $Matches[2] }
            elseif ($command -match '^\s*(\S+\.exe)\s*(.*)$') { $exe = $Matches[1]; $arguments = $Matches[2] }
            else { throw "Unknown uninstall command: $command" }
            if ($arguments) { Start-Process -FilePath $exe -ArgumentList $arguments -Wait -ErrorAction Stop }
            else { Start-Process -FilePath $exe -Wait -ErrorAction Stop }
        }
        Undo = $null
    }
    # Opens the browser straight at its notification settings, where a site
    # is blocked in two clicks. Housecall does not edit the browser's own
    # settings file: a browser that is open overwrites it, and a damaged one
    # can reset the client's whole profile.
    openNotifySettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = {
            param($t)
            $exe = $script:BrowserExe[$t.Browser]
            $scheme = $script:BrowserScheme[$t.Browser]
            Start-Process -FilePath $exe -ArgumentList "$($scheme)://settings/content/notifications" -ErrorAction Stop
        }
        Undo = $null
    }

    # Opens the provider's webmail in the browser: a check more than a change.
    openWebmail = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process $t.Url }
        Undo  = $null
    }

    # ---- C: printer and devices
    startSpooler = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service Spooler).StartType -eq 'Disabled') { Set-Service Spooler -StartupType Automatic -ErrorAction Stop }
            Start-Service Spooler -ErrorAction Stop
        }
        Undo = $null
    }
    # Stuck documents are gone afterwards; the note on this fix says so.
    restartSpooler = @{
        Note = 'reprint'; Admin = $true
        Apply = {
            param($t)
            Stop-Service Spooler -Force -ErrorAction Stop
            Get-ChildItem (Join-Path $env:SystemRoot 'System32\spool\PRINTERS') -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Start-Service Spooler -ErrorAction Stop
        }
        Undo = $null
    }
    # Without admin, Windows lets people cancel their own documents.
    clearJobs = @{
        Note = 'reprint'; Admin = $false
        Apply = { param($t) Get-CimInstance Win32_PrintJob | Remove-CimInstance -ErrorAction Stop }
        Undo  = $null
    }
    # Also stops "let Windows manage my default printer", which would
    # otherwise switch it back to whatever was used last.
    setDefault = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
            $t.SavedMode = (Get-ItemProperty $key -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode
            Set-ItemProperty $key -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -ErrorAction Stop
            $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Name -replace "'", "''"))
            $result = Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop
            if ($result.ReturnValue -ne 0) { throw "SetDefaultPrinter: $($result.ReturnValue)" }
        }
        Undo = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
            if ($t.Previous) {
                $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Previous -replace "'", "''"))
                if ($printer) { [void](Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop) }
            }
            if ($null -eq $t.SavedMode) { Remove-ItemProperty $key -Name LegacyDefaultPrinterMode -ErrorAction SilentlyContinue }
            else { Set-ItemProperty $key -Name LegacyDefaultPrinterMode -Value $t.SavedMode -Type DWord }
        }
    }
    printTestPage = @{
        Note = 'safe'; Admin = $false
        Apply = {
            param($t)
            $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Name -replace "'", "''"))
            $result = Invoke-CimMethod -InputObject $printer -MethodName PrintTestPage -ErrorAction Stop
            if ($result.ReturnValue -ne 0) { throw "PrintTestPage: $($result.ReturnValue)" }
        }
        Undo = $null
    }
    enableDevice = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) Enable-PnpDevice -InstanceId $t.InstanceId -Confirm:$false -ErrorAction Stop }
        Undo  = { param($t) Disable-PnpDevice -InstanceId $t.InstanceId -Confirm:$false -ErrorAction Stop }
    }
    restartDevice = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            & pnputil.exe /restart-device $t.InstanceId | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "pnputil /restart-device: $LASTEXITCODE" }
        }
        Undo = $null
    }
    # ---- B: sound, video calls, screen
    # Restarting the endpoint builder restarts Windows Audio with it.
    restartAudio = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            foreach ($name in 'AudioEndpointBuilder', 'Audiosrv') {
                if ([string](Get-Service $name).StartType -eq 'Disabled') { Set-Service $name -StartupType Automatic -ErrorAction Stop }
            }
            Restart-Service AudioEndpointBuilder -Force -ErrorAction Stop
            Start-Service Audiosrv -ErrorAction Stop
        }
        Undo = $null
    }
    setDefaultAudio = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetDefault($t.Id) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetDefault($t.PreviousId) }
    }
    unmute = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetMute($t.Id, $false) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetMute($t.Id, $true) }
    }
    setVolume = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetVolume($t.Id, $t.Percent) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetVolume($t.Id, $t.Previous) }
    }
    # A check more than a change: it is not listed on the note.
    testSound = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = {
            param($t)
            $wav = Join-Path $env:WINDIR 'Media\Windows Notify System Generic.wav'
            if (-not (Test-Path $wav)) { $wav = Join-Path $env:WINDIR 'Media\chimes.wav' }
            (New-Object Media.SoundPlayer $wav).PlaySync()
        }
        Undo = $null
    }
    allowAccess = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) $t.Saved = (Get-ItemProperty $t.Key).Value; Set-ItemProperty $t.Key -Name Value -Value 'Allow' -ErrorAction Stop }
        Undo  = { param($t) Set-ItemProperty $t.Key -Name Value -Value $t.Saved -ErrorAction Stop }
    }
    allowAccessMachine = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) $t.Saved = (Get-ItemProperty $t.Key).Value; Set-ItemProperty $t.Key -Name Value -Value 'Allow' -ErrorAction Stop }
        Undo  = { param($t) Set-ItemProperty $t.Key -Name Value -Value $t.Saved -ErrorAction Stop }
    }
    setBrightness = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop | Select-Object -First 1
            [void](Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$t.Percent } -ErrorAction Stop)
        }
        Undo = {
            param($t)
            $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop | Select-Object -First 1
            [void](Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$t.Previous } -ErrorAction Stop)
        }
    }
    closeMagnifier = @{
        Note = 'restart'; Admin = $false
        Apply = { param($t) Get-Process -Name Magnify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }

    # ---- D: slow or freezing
    # The same switch Task Manager's Startup tab flips: first byte 03 = off.
    disableStartup = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            if (-not (Test-Path $t.Approved)) { New-Item $t.Approved -Force | Out-Null }
            $t.Saved = (Get-ItemProperty $t.Approved -ErrorAction SilentlyContinue).($t.Value)
            Set-ItemProperty $t.Approved -Name $t.Value -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary -ErrorAction Stop
        }
        Undo = {
            param($t)
            if ($null -eq $t.Saved) { Remove-ItemProperty $t.Approved -Name $t.Value -ErrorAction Stop }
            else { Set-ItemProperty $t.Approved -Name $t.Value -Value ([byte[]]$t.Saved) -Type Binary -ErrorAction Stop }
        }
    }
    disableStartupMachine = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) & $script:Fixes.disableStartup.Apply $t }
        Undo  = { param($t) & $script:Fixes.disableStartup.Undo $t }
    }
    closeProcess = @{
        Note = 'unsaved'; Admin = $false
        Apply = { param($t) Get-Process -Name $t.Name -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }
    # Only files untouched for a day: whatever is in use right now stays.
    emptyTemp = @{
        Note = 'temp'; Admin = $false
        Apply = {
            param($t)
            $cutoff = (Get-Date).AddDays(-1)
            Get-ChildItem -LiteralPath $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Undo = $null
    }
    emptyRecycleBin = @{
        Note = 'noundo'; Admin = $false
        Apply = { param($t) Clear-RecycleBin -Force -ErrorAction Stop }
        Undo  = $null
    }

    # ---- E: Windows and updates
    enableUpdateService = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $t.Saved = [string](Get-Service wuauserv).StartType
            Set-Service wuauserv -StartupType Manual -ErrorAction Stop
            Start-Service wuauserv -ErrorAction Stop
        }
        Undo = { param($t) Stop-Service wuauserv -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType $t.Saved -ErrorAction Stop }
    }
    # The same values the "Resume updates" button in Settings clears.
    resumeUpdates = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
            $names = 'PauseUpdatesExpiryTime', 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime'
            $now = Get-ItemProperty $key -ErrorAction Stop
            $t.Saved = @{}
            foreach ($n in $names) {
                if ($null -ne $now.$n) { $t.Saved[$n] = $now.$n; Remove-ItemProperty $key -Name $n -ErrorAction Stop }
            }
        }
        Undo = {
            param($t)
            foreach ($n in $t.Saved.Keys) { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name $n -Value $t.Saved[$n] -ErrorAction Stop }
        }
    }
    # The classic cure for stuck updates: a fresh download folder. The old
    # one is renamed, not deleted, so nothing is lost if it matters.
    resetUpdates = @{
        Note = 'redownload'; Admin = $true
        Apply = {
            param($t)
            $services = 'wuauserv', 'bits', 'cryptsvc'
            foreach ($s in $services) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
            $folder = Join-Path $env:SystemRoot 'SoftwareDistribution'
            if (Test-Path $folder) { Rename-Item $folder ('SoftwareDistribution.old-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -ErrorAction Stop }
            foreach ($s in $services) { Start-Service $s -ErrorAction SilentlyContinue }
        }
        Undo = $null
    }
    syncClock = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service w32time).StartType -eq 'Disabled') { Set-Service w32time -StartupType Manual -ErrorAction Stop }
            Start-Service w32time -ErrorAction SilentlyContinue
            & w32tm.exe /resync /force | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "w32tm /resync: $LASTEXITCODE" }
        }
        Undo = $null
    }
    # DISM repairs Windows' own store of system files (from Windows Update),
    # then SFC repairs the files in use from that store. Their progress shows
    # in the window while they run.
    repairWindows = @{
        Note = 'long'; Admin = $true
        Apply = {
            param($t)
            & dism.exe /Online /Cleanup-Image /RestoreHealth
            & sfc.exe /scannow
        }
        Undo = $null
    }
    disableFastStartup = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
            $t.Saved = (Get-ItemProperty $key).HiberbootEnabled
            Set-ItemProperty $key -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
        }
        Undo = { param($t) Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value $t.Saved -Type DWord -ErrorAction Stop }
    }

    startBtService = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service bthserv).StartType -eq 'Disabled') { Set-Service bthserv -StartupType Manual -ErrorAction Stop }
            Start-Service bthserv -ErrorAction Stop
        }
        Undo = $null
    }

    # ---- G: desktop, taskbar and folders
    # Explorer draws the desktop, the taskbar and the folder windows.
    # Restarting it is harmless: the taskbar is gone for a few seconds, open
    # folder windows close, and files are untouched.
    restartExplorer = @{
        Note = 'explorer'; Admin = $false
        Apply = { param($t) Restart-HcExplorer }
        Undo  = $null
    }
    # The settings below only take effect once Explorer restarts, so each
    # one restarts it, and so does its undo.
    # Both the desktop's view flags (the real setting) and HideIcons (the copy).
    showDesktopIcons = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $t.SavedHide = (Get-ItemProperty "$script:ExplorerKey\Advanced" -ErrorAction SilentlyContinue).HideIcons
            $t.SavedFlags = (Get-ItemProperty $script:DesktopBagKey -ErrorAction SilentlyContinue).FFlags
            New-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            if ($null -ne $t.SavedFlags) {
                $shown = (ConvertTo-HcUInt32 $t.SavedFlags) -band (-bnot [uint32]$script:NoIconsFlag)
                New-ItemProperty $script:DesktopBagKey -Name FFlags -Value (ConvertTo-HcInt32 $shown) -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            }
            Restart-HcExplorer
        }
        Undo = {
            param($t)
            if ($null -eq $t.SavedHide) { Remove-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -ErrorAction SilentlyContinue }
            else { New-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -Value $t.SavedHide -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
            if ($null -ne $t.SavedFlags) { New-ItemProperty $script:DesktopBagKey -Name FFlags -Value $t.SavedFlags -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
            Restart-HcExplorer
        }
    }
    showRecycleBin = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcShellValue $t "$script:ExplorerKey\HideDesktopIcons\NewStartPanel" $script:RecycleBinId 0 }
        Undo  = { param($t) Undo-HcShellValue $t }
    }
    showSearch = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcShellValue $t 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 2 }
        Undo  = { param($t) Undo-HcShellValue $t }
    }
    taskbarStay = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = "$script:ExplorerKey\StuckRects3"
            $t.Saved = [byte[]](Get-ItemProperty $key -ErrorAction Stop).Settings
            Set-ItemProperty $key -Name Settings -Value (ConvertTo-HcTaskbarSetting $t.Saved $false) -Type Binary -ErrorAction Stop
            Restart-HcExplorer
        }
        Undo = {
            param($t)
            Set-ItemProperty "$script:ExplorerKey\StuckRects3" -Name Settings -Value ([byte[]]$t.Saved) -Type Binary -ErrorAction Stop
            Restart-HcExplorer
        }
    }
}

# Stops Explorer and waits for Windows to start it again (it does so by
# itself); starts it when it does not come back within five seconds.
function Restart-HcExplorer {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process explorer.exe
}

# One DWORD in the user's Explorer settings, remembered for undo, then
# Explorer restarted so it shows.
function Set-HcShellValue {
    param([hashtable]$Target, [string]$Key, [string]$Name, [int]$Value)
    $Target.Key = $Key
    $Target.Name = $Name
    $Target.Saved = (Get-ItemProperty $Key -ErrorAction SilentlyContinue).$Name
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    New-ItemProperty $Key -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Restart-HcExplorer
}

function Undo-HcShellValue {
    param([hashtable]$Target)
    if ($null -eq $Target.Saved) { Remove-ItemProperty $Target.Key -Name $Target.Name -ErrorAction Stop }
    else { New-ItemProperty $Target.Key -Name $Target.Name -Value $Target.Saved -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
    Restart-HcExplorer
}

# "Disable scheduled task "X" (can be undone)" -- the label with its note.
function Get-HcFixLabel {
    param([pscustomobject]$Action)
    $fix = $script:Fixes[$Action.FixId]
    $label = T ('fix.' + $Action.FixId) $Action.Target.Label
    $note = T ('fix.note.' + $fix.Note)
    if ($fix.Admin -and -not $script:IsAdmin) { $note += ' ' + (T 'fix.needsAdmin') }
    "$label $note"
}

# The step-by-step guide for a report's finding: steps.<id> in strings.ps1,
# steps separated by " | ", filled from the finding's arguments. Empty when
# the finding has no guide (for example "all good").
function Get-HcSteps {
    param([pscustomobject]$Report)
    if (-not $Report.FindingId) { return @() }
    $key = 'steps.' + $Report.FindingId
    if ($null -eq $script:Strings['en'][$key]) { return @() }
    $all = @($key) + @($Report.FindingArgs)
    @((T @all) -split '\s*\|\s*' | Where-Object { $_ })
}

# One step at a time, so it can be done together with the client: Enter
# shows the next step, 0 stops.
function Show-HcSteps {
    param([string[]]$Steps)
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        Write-Host ''
        Write-HcLabelled (T 'fix.stepOf' ($i + 1) $Steps.Count) $Steps[$i] 'Cyan'
        $last = ($i -eq $Steps.Count - 1)
        $answer = "$(Read-HcLine (T $(if ($last) { 'fix.stepLast' } else { 'fix.stepNext' })))".Trim()
        if ($answer -in @('0', 'Q', 'q')) { break }
    }
}

function Test-HcYes {
    param([string]$Answer)
    "$Answer".Trim() -match '^(y|yes|j|ja)$'
}

<#
    Shows the offered fixes under a report and runs the one picked. Returns
    'changed' when something was changed (the caller checks again), 'back'
    when Enter was pressed, and 'none' when it was cancelled or failed (the
    list is shown again).
#>
function Invoke-HcActionMenu {
    param([pscustomobject]$Report)
    $actions = @($Report.Actions)
    $steps = @(Get-HcSteps $Report)
    if ($actions.Count -eq 0 -and $steps.Count -eq 0) { return 'back' }

    Write-Host ''
    Write-Host ('  ' + (T 'fix.heading')) -ForegroundColor Yellow
    for ($i = 0; $i -lt $actions.Count; $i++) {
        Write-Option ([string]($i + 1)) (Get-HcFixLabel $actions[$i])
    }
    if ($steps.Count) { Write-Option 'S' (T 'fix.steps') }
    Write-Dim (T 'fix.enterBack')

    $pick = "$(Read-HcLine (T 'menu.prompt'))".Trim()
    if ($steps.Count -and $pick -match '^[sS]$') {
        Show-HcSteps $steps
        return 'none'
    }
    $n = 0
    if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $actions.Count) { return 'back' }
    $action = $actions[$n - 1]
    $fix = $script:Fixes[$action.FixId]
    $label = T ('fix.' + $action.FixId) $action.Target.Label

    if ($fix.Admin -and -not $script:IsAdmin -and -not $script:DryRun) {
        if (-not $script:HcSource) {
            Write-Warn2 (T 'fix.adminHow')
            return 'none'
        }
        if (-not (Test-HcYes (Read-HcLine (T 'fix.elevateAsk')))) {
            Write-Dim (T 'fix.cancelled')
            return 'none'
        }
        if (Start-HcElevated $script:HcCurrentCode) {
            $script:HandedOff = $true
            Write-Ok (T 'fix.elevated')
            return 'back'
        }
        return 'none'
    }
    if (-not (Test-HcYes (Read-HcLine (T 'fix.confirm' $label)))) {
        Write-Dim (T 'fix.cancelled')
        return 'none'
    }
    if ($script:DryRun) {
        Write-Host ('  ' + (T 'fix.dryRun')) -ForegroundColor Magenta
        return 'none'
    }

    if ($fix.Admin) { New-HcRestorePoint }
    try {
        & $fix.Apply $action.Target
    } catch {
        Write-Warn2 (T 'fix.failed' $_.Exception.Message)
        return 'none'
    }
    if (-not $fix.NoLog) {
        $done = T ('fix.' + $action.FixId + '.done') $action.Target.Label
        [void]$script:HcChanges.Add([pscustomobject]@{ FixId = $action.FixId; Target = $action.Target; Label = $done })
    }
    Write-Ok (T 'fix.done')
    'changed'
}

<#
    Restarts Housecall as administrator, at the same problem, when a fix
    needs it. Housecall's own code ($script:HcSource) goes into a temporary
    file; the new window reads it, deletes it straight away and runs it. So
    it works after `irm | iex` (no file on disk) and without internet --
    which matters, since renewing the IP is a fix for having no internet.
    The small start-up command travels -EncodedCommand, so no path or quote
    in it can break.
#>
function Start-HcElevated {
    param([string]$Code)
    if (-not $script:HcSource) { return $false }
    $file = Join-Path $env:TEMP ('housecall-' + [guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($file, $script:HcSource, (New-Object Text.ASCIIEncoding))

    $options = "-Start '$Code' -Lang '$script:Lang'"
    if ($script:DryRun) { $options += ' -DryRun' }
    if ($script:NoAI) { $options += ' -NoAI' }
    $quoted = $file.Replace("'", "''")
    $boot = "`$f = '$quoted'; `$s = [IO.File]::ReadAllText(`$f); Remove-Item -LiteralPath `$f -Force; " +
            "`$ErrorActionPreference = 'Stop'; . ([scriptblock]::Create(`$s)); `$script:HcSource = `$s; Start-Housecall $options"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
    try {
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    } catch {
        # Most often: the person said No to Windows' permission question.
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Write-Warn2 (T 'fix.elevateFailed' $_.Exception.Message)
        return $false
    }
    $true
}

<#
    A Windows restore point before the first admin fix of a session: the
    safety net under Housecall's own undo. Windows allows one per 24 hours
    and only when System Protection is on; both cases are reported and
    Housecall carries on, because the fix itself still asks and undoes.
#>
$script:RestorePointDone = $false

function New-HcRestorePoint {
    if ($script:RestorePointDone -or -not $script:IsAdmin) { return }
    $script:RestorePointDone = $true
    Write-Dim (T 'fix.restorePoint')
    $warnings = $null
    try {
        Checkpoint-Computer -Description ('Housecall ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings
        if ($warnings) { Write-Dim (T 'fix.restorePointRecent') } else { Write-Ok (T 'fix.restorePointOk') }
    } catch {
        Write-Warn2 (T 'fix.restorePointNone')
    }
}

# U on the menu: undo this session's changes, newest first.
function Invoke-HcUndo {
    $undoable = @($script:HcChanges | Where-Object { $script:Fixes[$_.FixId].Undo })
    if ($undoable.Count -eq 0) { return (T 'undo.nothing') }
    if (-not (Test-HcYes (Read-HcLine (T 'undo.confirm' $undoable.Count)))) { return (T 'fix.cancelled') }

    $messages = @()
    for ($i = $undoable.Count - 1; $i -ge 0; $i--) {
        $change = $undoable[$i]
        try {
            & $script:Fixes[$change.FixId].Undo $change.Target
            $script:HcChanges.Remove($change)
            $messages += T 'undo.done' $change.Label
        } catch {
            $messages += T 'undo.failed' $change.Label
        }
    }
    $messages -join ' / '
}

# ==================================================== src\note.ps1 ==
<#
    The client note: what they asked for help with, what was found, what was
    done, and how to reach you. It opens by itself when Housecall is closed
    (Q), in the client's language, in its own window with large text.

    Nothing is written to disk. Closing the window is the end of it; the
    Print button is how a client keeps a copy (Microsoft Print to PDF makes
    a PDF, for email).
#>

# Your contact details for the bottom of the note, one line each. Left
# empty, the "Questions?" part is simply not shown. This file is public on
# GitHub, so only details that may be public go here: decided 26 Sep, the
# email yes, the phone number no.
$script:Contact = @(
    'Shamil: shamilimanuel@outlook.com'
)

# The problems opened in this session, each with its latest finding (the
# one after any fixes). Filled by Invoke-HcProblem.
$script:HcVisit = New-Object System.Collections.ArrayList

# What the client asked for help with, typed by Shamil in the invoice
# window. Empty: every problem opened this visit is listed instead.
$script:HcAsked = ''

# What Shamil did by hand, from the invoice window: Text, and Done ($true
# for fixed, $false for not fixed).
$script:HcWork = New-Object System.Collections.ArrayList

# The ready-made options for that list; any other text can be typed.
function Get-HcWorkPresets {
    @((T 'work.presets') -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Adds one item; $false when it is empty or already on the list.
function Add-HcWorkItem {
    param([string]$Text, [bool]$Done)
    $t = ("$Text" -replace '\s+', ' ').Trim()
    if (-not $t) { return $false }
    if ($t.Length -gt 150) { $t = $t.Substring(0, 150) }
    if (@($script:HcWork | Where-Object { $_.Text -eq $t }).Count) { return $false }
    [void]$script:HcWork.Add([pscustomobject]@{ Text = $t; Done = $Done })
    $true
}

# Everything done this visit for the history and the invoice: Housecall's
# fixes, then the hand-made list, with "Not fixed:" in front where needed.
function Get-HcVisitChanges {
    $all = @($script:HcChanges | ForEach-Object { $_.Label })
    $all += @($script:HcWork | ForEach-Object { if ($_.Done) { $_.Text } else { T 'note.notFixedItem' $_.Text } })
    @($all | Select-Object -First 30)
}

function Save-HcVisit {
    param([string]$Code, [pscustomobject]$Report)
    $entry = $script:HcVisit | Where-Object { $_.Code -eq $Code } | Select-Object -First 1
    if (-not $entry) {
        $entry = [pscustomobject]@{ Code = $Code; FindingId = $null; FindingArgs = @() }
        [void]$script:HcVisit.Add($entry)
    }
    $entry.FindingId = $Report.FindingId
    $entry.FindingArgs = @($Report.FindingArgs)
}

<#
    The note as a list of blocks, each with a Style (title, heading, text,
    small) and its Text. Pure, so it can be tested; the window and the
    printout both draw from it. Empty when no problem was opened.
#>
function Get-HcNoteBlocks {
    param([datetime]$Date = (Get-Date))
    if (@($script:HcVisit).Count -eq 0) { return @() }
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }

    & $block 'title' (T 'note.title' $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture)))
    foreach ($b in @(Get-HcVisitBlocks)) { $b }

    if ($script:Contact) {
        & $block 'heading' (T 'note.contact')
        foreach ($line in @($script:Contact)) { & $block 'text' $line }
    }
    & $block 'small' (T 'note.footer')
}

# What the client asked, what was found and what was done: the middle of
# both the note and the invoice.
function Get-HcVisitBlocks {
    $visits = @($script:HcVisit)
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    & $block 'heading' (T 'note.asked')
    if ("$script:HcAsked".Trim()) {
        & $block 'text' "$script:HcAsked".Trim()
    } else {
        foreach ($v in $visits) { & $block 'text' (T "problem.$($v.Code)") }
    }

    $found = @($visits | Where-Object { $_.FindingId })
    if ($found.Count) {
        & $block 'heading' (T 'note.found')
        foreach ($v in $found) {
            $all = @('finding.' + $v.FindingId) + @($v.FindingArgs)
            & $block 'text' (T @all)
        }
    }

    & $block 'heading' (T 'note.done')
    $changes = @($script:HcChanges)
    $fixed = @($script:HcWork | Where-Object { $_.Done })
    $open = @($script:HcWork | Where-Object { -not $_.Done })
    if ($changes.Count -eq 0 -and $fixed.Count -eq 0) {
        & $block 'text' (T 'note.nothingChanged')
    } else {
        foreach ($c in $changes) { & $block 'text' $c.Label }
        foreach ($w in $fixed) { & $block 'text' $w.Text }
    }
    if ($open.Count) {
        & $block 'heading' (T 'note.notFixed')
        foreach ($w in $open) { & $block 'text' $w.Text }
    }
}

function Show-HcNote {
    $blocks = @(Get-HcNoteBlocks)
    if ($blocks.Count -eq 0) { return }
    Show-HcDocument $blocks (T 'note.windowTitle')
}

# The note or the invoice: in its own window, or printed to the console when
# there is no one to look at a window.
function Show-HcDocument {
    param([object[]]$Blocks, [string]$Title)
    # A scripted run (the tests) prints the document instead of opening a window.
    if ($null -ne $script:HcInputQueue) {
        Write-Host ''
        foreach ($b in $Blocks) { Write-Host ('  [note] ' + $b.Text) }
        return
    }
    try {
        if ($script:NoConsole) { throw 'nobody to close a window' }
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        Show-HcNoteWindow $Blocks $Title
    } catch {
        # No desktop to show a window on: show the document in the console.
        Write-Host ''
        foreach ($b in $Blocks) { Write-Host ('  ' + $b.Text) }
    }
}

function Show-HcNoteWindow {
    param([object[]]$Blocks, [string]$Title)
    [Windows.Forms.Application]::EnableVisualStyles()
    $family = 'Segoe UI'
    $script:HcNoteFonts = @{
        title   = New-Object Drawing.Font($family, 20, [Drawing.FontStyle]::Bold)
        heading = New-Object Drawing.Font($family, 14, [Drawing.FontStyle]::Bold)
        text    = New-Object Drawing.Font($family, 13)
        # The payment line under the total: normal text, with space above it.
        payment = New-Object Drawing.Font($family, 13)
        small   = New-Object Drawing.Font($family, 10, [Drawing.FontStyle]::Italic)
        # Money rows: a fixed-width font keeps the amounts in one column.
        row     = New-Object Drawing.Font('Consolas', 11)
        rowBold = New-Object Drawing.Font('Consolas', 11, [Drawing.FontStyle]::Bold)
    }
    $script:HcNoteBlocks = $Blocks

    $form = New-Object Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object Drawing.Size(680, 760)
    $form.MinimumSize = New-Object Drawing.Size(480, 400)
    $form.BackColor = [Drawing.Color]::White
    $form.TopMost = $true          # in front of the console, once
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })

    $box = New-Object Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = [Drawing.Color]::White
    $box.DetectUrls = $false
    $box.Cursor = [Windows.Forms.Cursors]::Default
    foreach ($b in $Blocks) {
        $box.SelectionStart = $box.TextLength
        $box.SelectionFont = $script:HcNoteFonts[$b.Style]
        $box.SelectionColor = if ($b.Style -eq 'small') { [Drawing.Color]::DimGray } else { [Drawing.Color]::Black }
        $gap = if ($b.Style -in @('heading', 'small', 'payment')) { "`n" } else { '' }
        $box.AppendText($gap + $b.Text + "`n")
    }

    $inner = New-Object Windows.Forms.Panel
    $inner.Dock = 'Fill'
    $inner.Padding = New-Object Windows.Forms.Padding(32, 24, 32, 8)
    $inner.Controls.Add($box)

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.Height = 72
    $buttons.Padding = New-Object Windows.Forms.Padding(24, 12, 24, 12)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)

    $close = New-Object Windows.Forms.Button
    $close.Text = T 'note.close'
    $close.Size = New-Object Drawing.Size(150, 44)
    $close.Font = New-Object Drawing.Font($family, 12)
    $close.BackColor = [Drawing.Color]::White; $close.ForeColor = [Drawing.Color]::Black
    $close.Add_Click({ $this.FindForm().Close() })
    $form.CancelButton = $close

    $print = New-Object Windows.Forms.Button
    $print.Text = T 'note.print'
    $print.Size = New-Object Drawing.Size(150, 44)
    $print.Font = New-Object Drawing.Font($family, 12)
    $print.BackColor = [Drawing.Color]::White; $print.ForeColor = [Drawing.Color]::Black
    $print.Add_Click({ Invoke-HcNotePrint })

    $buttons.Controls.Add($close)
    $buttons.Controls.Add($print)
    $form.Controls.Add($inner)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $close     # no blinking text cursor in the note
    [void]$form.ShowDialog()
    $form.Dispose()
}

# Prints the note's blocks, continuing on a new page when one is full.
function Invoke-HcNotePrint {
    $doc = New-Object Drawing.Printing.PrintDocument
    $doc.DocumentName = 'Housecall'
    $script:HcNotePrintAt = 0
    $doc.Add_PrintPage({
        param($sender, $e)
        $area = $e.MarginBounds
        $y = [single]$area.Top
        while ($script:HcNotePrintAt -lt $script:HcNoteBlocks.Count) {
            $b = $script:HcNoteBlocks[$script:HcNotePrintAt]
            $font = $script:HcNoteFonts[$b.Style]
            if ($b.Style -in @('heading', 'small', 'payment')) { $y += $font.GetHeight($e.Graphics) * 0.6 }
            $size = $e.Graphics.MeasureString($b.Text, $font, $area.Width)
            if ($y + $size.Height -gt $area.Bottom -and $y -gt $area.Top) { $e.HasMorePages = $true; return }
            $rect = New-Object Drawing.RectangleF([single]$area.Left, $y, [single]$area.Width, $size.Height)
            $e.Graphics.DrawString($b.Text, $font, [Drawing.Brushes]::Black, $rect)
            $y += $size.Height + 4
            $script:HcNotePrintAt++
        }
        $e.HasMorePages = $false
    })
    $dialog = New-Object Windows.Forms.PrintDialog
    $dialog.Document = $doc
    $dialog.UseEXDialog = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        try { $doc.Print() } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Housecall') }
    }
    $doc.Dispose()
}

# ==================================================== src\relay.ps1 ==
<#
    The relay (a Supabase Edge Function, relay\housecall\index.ts) and what
    goes through it: unlocking with a Google Authenticator code, and visit
    memory. The AI chat (src\ai.ps1) uses the same unlock.

    One code unlocks the relay until Housecall closes (at most 4 hours,
    which the relay enforces). The token lives only in this PowerShell
    session and is never written to disk.

    Visit memory: each PC gets a scrambled id (SHA-256 of its BIOS serial
    and machine UUID), never a name. The relay keeps the visits in Shamil's
    Supabase; nothing is kept on the client's PC.
#>

$script:RelayUrl = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'
$script:HcToken = $null
$script:HcTokenExpires = [datetime]::MinValue
$script:HcKnownLabel = $null

# One POST to the relay. Returns Ok, Status, Data (the parsed JSON) and
# Error (the relay's error code, or 'unreachable').
function Invoke-HcRelay {
    param([hashtable]$Body)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $json = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $r = Invoke-WebRequest -Uri $script:RelayUrl -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' `
            -UseBasicParsing -TimeoutSec 150 -ErrorAction Stop
        $reader = New-Object IO.StreamReader($r.RawContentStream, [Text.Encoding]::UTF8)
        return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Data = ($reader.ReadToEnd() | ConvertFrom-Json); Error = $null }
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { return [pscustomobject]@{ Ok = $false; Status = 0; Data = $null; Error = 'unreachable' } }
        $status = [int]$response.StatusCode
        $code = 'unreachable'
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
            $parsed = $reader.ReadToEnd() | ConvertFrom-Json
            if ($parsed.error) { $code = [string]$parsed.error }
        } catch { }
        return [pscustomobject]@{ Ok = $false; Status = $status; Data = $null; Error = $code }
    } finally {
        $ProgressPreference = $saved
    }
}

# A relay error in plain words.
function Get-HcRelayMessage {
    param([string]$Code)
    switch ($Code) {
        'wrong_code'  { T 'relay.wrongCode' }
        'code_used'   { T 'relay.codeUsed' }
        'locked'      { T 'relay.locked' }
        'not_set_up'  { T 'relay.notSetUp' }
        'locked_out'  { T 'relay.expired' }
        'unreachable' { T 'relay.unreachable' }
        'ai_key'      { T 'relay.aiKey' }
        'ai_busy'     { T 'relay.aiBusy' }
        'ai_credit'   { T 'relay.aiCredit' }
        'no_settings' { T 'inv.noSettings' }
        default       { T 'relay.error' $Code }
    }
}

function Test-HcUnlocked {
    $script:HcToken -and $script:HcTokenExpires -gt (Get-Date).AddMinutes(1)
}

<#
    Asks for the Authenticator code, unless this session is already
    unlocked. Enter (or anything that is not a code) skips. Returns $true
    once unlocked. The first unlock also shows what is known about this PC.
#>
function Unlock-HcRelay {
    param([string]$PromptKey = 'relay.askCode')
    if (Test-HcUnlocked) { return $true }
    if ($script:HcToken) { Write-Dim (T 'relay.expired') }
    for ($try = 0; $try -lt 3; $try++) {
        $code = ("$(Read-HcLine (T $PromptKey))" -replace '\s', '')
        if ($code -notmatch '^\d{6}$') { return $false }
        $r = Invoke-HcRelay @{ action = 'unlock'; code = $code }
        if ($r.Ok) {
            $script:HcToken = $r.Data.token
            $script:HcTokenExpires = [datetime]::Parse($r.Data.expires, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
            Write-Ok (T 'relay.unlocked' $script:HcTokenExpires.ToString('HH:mm'))
            Show-HcKnownPc
            return $true
        }
        Write-Warn2 (Get-HcRelayMessage $r.Error)
        if ($r.Error -notin @('wrong_code', 'code_used')) { return $false }
    }
    $false
}

# ------------------------------------------------------------ visit memory --

# A scrambled, stable id for this PC. The BIOS serial and machine UUID
# survive a Windows reinstall; when both are placeholders (cheap boards say
# "To be filled by O.E.M."), Windows' own MachineGuid is added.
function Get-HcPcId {
    $serial = ''
    $uuid = ''
    try { $serial = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
    try { $uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
    $parts = "housecall|$($serial.Trim())|$($uuid.Trim())"
    if ($serial -match '^\s*$|O\.?E\.?M|Default|System Serial|^0+$' -and $uuid -match '^[F0-]*$') {
        try { $parts += '|' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction Stop).MachineGuid } catch { }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($parts)) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

# The visits of this PC as Ok, Visits and Error. Not a bare list: an empty
# list returned from a PowerShell function arrives as $null, which looked
# exactly like a failed request (found by Shamil on his first try, 26 Sep).
function Get-HcVisits {
    if (-not (Test-HcUnlocked)) { return [pscustomobject]@{ Ok = $false; Visits = @(); Error = 'locked_out' } }
    $r = Invoke-HcRelay @{ action = 'visit_get'; token = $script:HcToken; pc = (Get-HcPcId) }
    if (-not $r.Ok) { return [pscustomobject]@{ Ok = $false; Visits = @(); Error = $r.Error } }
    [pscustomobject]@{ Ok = $true; Visits = @($r.Data.visits | Where-Object { $_ }); Error = $null }
}

# "3 sep. 2026: C1, D2" -- what a stored visit was about.
function Format-HcVisitLine {
    param($Visit)
    $when = Format-HcDate ([datetime]::Parse([string]$Visit.visited_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime())
    $codes = @($Visit.problems | ForEach-Object { $_.code }) -join ', '
    if (-not $codes) { $codes = '-' }
    "$when ($codes)"
}

# One line after unlocking: "Known PC (mevr. de Vries): last visit 3 sep. 2026 (C1)".
function Show-HcKnownPc {
    $result = Get-HcVisits
    $visits = @($result.Visits)
    if (-not $result.Ok -or $visits.Count -eq 0) { return }
    $last = $visits[0]
    $label = @($visits | Where-Object { $_.label } | Select-Object -First 1).label
    $script:HcKnownLabel = $label
    $shown = if ($label) { " ($label)" } else { '' }
    Write-Step (T 'mem.known' $shown (Format-HcVisitLine $last))
}

# H on the menu: the visit history of this PC, with a number to delete one.
# Deleting a visit never deletes its invoice: invoices are kept 7 years.
function Show-HcHistory {
    param([pscustomobject]$Environment)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'mem.title')) -ForegroundColor Yellow
    Write-Host ''
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
    } elseif (Unlock-HcRelay) {
        while ($true) {
            $result = Get-HcVisits
            $visits = @($result.Visits)
            if (-not $result.Ok) { Write-Warn2 (Get-HcRelayMessage $result.Error); break }
            if ($visits.Count -eq 0) { Write-Dim (T 'mem.none'); break }
            Write-Host ''
            for ($i = 0; $i -lt $visits.Count; $i++) {
                $v = $visits[$i]
                $label = if ($v.label) { "  [$($v.label)]" } else { '' }
                $invoiceNo = if ($v.invoice_number) { '  ' + (T 'mem.invoice' $v.invoice_number) } else { '' }
                Write-Option ([string]($i + 1)) ((Format-HcVisitLine $v) + $label + $invoiceNo)
                foreach ($p in @($v.problems)) { Write-Dim ('     ' + $p.code + '  ' + (T "problem.$($p.code)")) }
                foreach ($c in @($v.changes)) { Write-Dim ('     + ' + $c) }
            }
            Write-Host ''
            $pick = "$(Read-HcLine (T 'mem.deleteAsk'))".Trim()
            $n = 0
            if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $visits.Count) { return }
            $chosen = $visits[$n - 1]
            if (-not (Test-HcYes (Read-HcLine (T 'mem.deleteConfirm' (Format-HcVisitLine $chosen))))) {
                Write-Dim (T 'fix.cancelled')
                continue
            }
            $r = Invoke-HcRelay @{ action = 'visit_delete'; token = $script:HcToken; pc = (Get-HcPcId); id = [long]$chosen.id }
            if (-not $r.Ok) { Write-Warn2 (Get-HcRelayMessage $r.Error); continue }
            Write-Ok (T 'mem.deleted')
            if ($chosen.invoice_number) { Write-Dim (T 'mem.invoiceKept' $chosen.invoice_number) }
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

<#
    At the end of a visit (Q): offers to save it. Asks for the code when
    the session is not unlocked yet, and for an optional name or note, so
    Shamil can find it again for the invoice. Skipped in a dry run, offline,
    or when no problem was opened.
#>
function Save-HcVisitRecord {
    param([pscustomobject]$Environment, $Invoice)
    if ($script:HcVisit.Count -eq 0 -or $script:DryRun -or -not $Environment.Online -or $script:HcQuitSkipped) { return }
    Write-Host ''
    if (-not (Unlock-HcRelay 'mem.saveAsk')) { return }
    if ($Invoice) {
        # The invoice already names the client: no need to ask again.
        $label = [string]$Invoice.client_name
    } else {
        $current = if ($script:HcKnownLabel) { $script:HcKnownLabel } else { T 'mem.noLabel' }
        $typed = "$(Read-HcLine (T 'mem.labelAsk' $current))".Trim()
        $label = if ($typed -and $typed -ne 'Q') { $typed } else { $script:HcKnownLabel }
    }
    if ($label -and $label.Length -gt 80) { $label = $label.Substring(0, 80) }

    $r = Invoke-HcRelay @{
        action   = 'visit_save'
        token    = $script:HcToken
        pc       = (Get-HcPcId)
        label    = $label
        lang     = $script:Lang
        os       = $Environment.Os
        problems = @($script:HcVisit | Where-Object { $_.FindingId } | ForEach-Object { @{ code = $_.Code; finding = $_.FindingId } })
        changes  = @(Get-HcVisitChanges)
        invoice_number = $(if ($Invoice) { [string]$Invoice.number } else { $null })
    }
    if ($r.Ok) { Write-Ok (T 'mem.saved') } else { Write-Warn2 (T 'mem.notSaved' (Get-HcRelayMessage $r.Error)) }
}

# ==================================================== src\invoice.ps1 ==
<#
    The invoice: at the end of a visit (Q), a short form, then a proper
    invoice instead of the plain client note.

    Shamil's business details, hourly rate, call-out fee and BTW setting
    live in his Supabase (tools\setup-invoice.ps1 fills them in), never in
    this public script. The relay gives out the consecutive invoice number,
    works out the totals and BTW, and keeps the invoice (7 years: fiscale
    bewaarplicht) apart from the visit history.

    Without an unlock, without settings, or with 0 in the form, the client
    still gets the plain note, so a visit never ends without a document.
#>

$script:HcStartedAt = Get-Date
# The minutes the starting price covers, for the clock under the banner. The
# real value comes with the settings at Q; until then the usual 30.
$script:HcStartMinutes = 30

# "Working since 14:05, 35 min"; Over once the starting price's minutes are used up.
function Get-HcClockLine {
    param([datetime]$Now = (Get-Date))
    $minutes = [int][Math]::Floor([Math]::Max(0, ($Now - $script:HcStartedAt).TotalMinutes))
    $since = $script:HcStartedAt.ToString('HH:mm')
    $over = $script:HcStartMinutes -gt 0 -and $minutes -ge $script:HcStartMinutes
    $text = if ($over) { T 'status.clockOver' $since $minutes $script:HcStartMinutes } else { T 'status.clock' $since $minutes }
    [pscustomobject]@{ Text = $text; Over = $over }
}

# 30,00 as "EUR 30,00" with the euro sign, in Dutch notation. The sign is
# built from its char code, since source files stay plain ASCII.
function Format-HcMoney {
    param([decimal]$Amount)
    $nl = [Globalization.CultureInfo]::GetCultureInfo('nl-NL')
    [string][char]0x20AC + ' ' + $Amount.ToString('N2', $nl)
}

# "19,95", "19.95", "EUR 19,95" -> 19.95; $null when it is not an amount.
function ConvertTo-HcAmount {
    param([string]$Text)
    $t = ("$Text" -replace [string][char]0x20AC, '' -replace '(?i)eur', '').Trim()
    if ($t -notmatch '^\d{1,6}([.,]\d{1,2})?$') { return $null }
    [decimal]::Parse(($t -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
}

# "Draadloze muis 19,95" -> description and amount; $null when there is no amount at the end.
function ConvertTo-HcExtraLine {
    param([string]$Text)
    $t = ("$Text" -replace [string][char]0x20AC, ' ').Trim()
    if ($t -notmatch '^(.+?)\s+(?:EUR\s*)?(\d{1,6}(?:[.,]\d{1,2})?)$') { return $null }
    $amount = ConvertTo-HcAmount $Matches[2]
    if ($null -eq $amount) { return $null }
    [pscustomobject]@{ Description = $Matches[1].Trim(); Amount = $amount }
}

# Minutes since Housecall started, rounded up to a quarter of an hour.
function Get-HcSuggestedMinutes {
    param([datetime]$Now = (Get-Date))
    $minutes = [Math]::Ceiling(($Now - $script:HcStartedAt).TotalMinutes / 15) * 15
    [int][Math]::Max(15, $minutes)
}

<#
    The labour lines for the time worked. With a starting price (settings
    start_fee and start_minutes) the first minutes cost that fixed amount
    and only the time after them goes by the hour; without one, all of it
    goes by the hour. 0 minutes gives no labour: a job at a fixed price is
    then an extra line.
#>
function Get-HcLabourLines {
    param([int]$Minutes, $Settings)
    if ($Minutes -le 0) { return }
    $rate = [decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 })
    $start = [decimal]$(if ($Settings.start_fee) { $Settings.start_fee } else { 0 })
    $included = [int]$(if ($Settings.start_minutes) { $Settings.start_minutes } else { 0 })
    if ($start -gt 0 -and $included -gt 0) {
        # The first line names the whole time worked, so the client sees how long it took.
        [pscustomobject]@{ Description = (T 'inv.startLine' $Minutes $included); Amount = $start }
        # After the starting price: per quarter of an hour, every one begun,
        # so the amounts stay round (50 min = 2 quarters extra, not 20 min).
        $extra = $Minutes - $included
        if ($extra -gt 0 -and $rate -gt 0) {
            $quarters = [int][Math]::Ceiling($extra / 15)
            $perQuarter = [Math]::Round($rate / 4, 2)
            [pscustomobject]@{ Description = (T 'inv.extraTime' $quarters (Format-HcMoney $perQuarter)); Amount = $quarters * $perQuarter }
        }
        return
    }
    if ($rate -gt 0) {
        [pscustomobject]@{ Description = (T 'inv.labour' $Minutes (Format-HcMoney $rate)); Amount = [Math]::Round($rate * $Minutes / 60, 2) }
    }
}

# The price next to the minutes in the window.
function Get-HcRateText {
    param($Settings)
    $rate = Format-HcMoney ([decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 }))
    # The relay sends amounts as text ("0.00"), so compare them as numbers.
    $start = [decimal]$(if ($Settings.start_fee) { $Settings.start_fee } else { 0 })
    if ($start -gt 0 -and [int]$Settings.start_minutes -gt 0) {
        $perQuarter = Format-HcMoney ([Math]::Round([decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 }) / 4, 2))
        return (T 'inv.win.rateStart' (Format-HcMoney $start) $Settings.start_minutes $perQuarter)
    }
    T 'inv.win.rate' $rate
}

function Get-HcSettings {
    $r = Invoke-HcRelay @{ action = 'settings_get'; token = $script:HcToken }
    if (-not $r.Ok) { return [pscustomobject]@{ Ok = $false; Settings = $null; Error = $r.Error } }
    [pscustomobject]@{ Ok = $true; Settings = $r.Data.settings; Error = $null }
}

# Asks a question with a suggestion; Enter takes the suggestion, 0 cancels.
function Read-HcField {
    param([string]$Prompt, [string]$Default = '')
    $answer = "$(Read-HcLine $Prompt)".Trim()
    if ($answer -eq '0') { return $null }
    if (-not $answer) { return $Default }
    $answer
}

<#
    The form. Returns the client, the lines and the payment, or $null when
    Shamil cancels (0) -- then the plain note is shown instead.
#>
function Read-HcInvoiceForm {
    param($Settings)
    Write-Host ''
    Write-Host ('  ' + (T 'inv.title')) -ForegroundColor Yellow
    Write-Dim (T 'inv.intro')
    Write-Host ''

    $suggestName = if ($script:HcKnownLabel) { $script:HcKnownLabel } else { '' }
    $name = Read-HcField (T 'inv.clientName' $suggestName) $suggestName
    if ($null -eq $name) { return $null }
    while (-not $name) {
        $name = Read-HcField (T 'inv.clientName' '') ''
        if ($null -eq $name) { return $null }
    }
    $address = Read-HcField (T 'inv.address'); if ($null -eq $address) { return $null }
    $postcode = Read-HcField (T 'inv.postcode'); if ($null -eq $postcode) { return $null }
    $email = Read-HcField (T 'inv.email'); if ($null -eq $email) { return $null }

    $lines = New-Object System.Collections.ArrayList
    $suggested = Get-HcSuggestedMinutes
    $minutes = $null
    while ($null -eq $minutes) {
        $typed = Read-HcField (T 'inv.minutes' $suggested) "$suggested"
        if ($null -eq $typed) { return $null }
        if ($typed -match '^\d{1,4}$') { $minutes = [int]$typed } else { Write-Warn2 (T 'inv.minutesBad') }
    }
    foreach ($l in @(Get-HcLabourLines $minutes $Settings)) { [void]$lines.Add($l) }

    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($fee -gt 0) {
        $yes = Read-HcField (T 'inv.callout' (Format-HcMoney $fee)) 'j'
        if ($null -eq $yes) { return $null }
        if (Test-HcYes $yes) { [void]$lines.Add([pscustomobject]@{ Description = (T 'inv.calloutLine'); Amount = $fee }) }
    }

    while ($true) {
        $typed = "$(Read-HcLine (T 'inv.extra'))".Trim()
        if (-not $typed -or $typed -eq 'Q') { break }
        $extra = ConvertTo-HcExtraLine $typed
        if ($extra) { [void]$lines.Add($extra) } else { Write-Warn2 (T 'inv.extraBad') }
    }
    if ($lines.Count -eq 0) {
        Write-Warn2 (T 'inv.noLines')
        return $null
    }

    # Bank transfer only once an IBAN is set: the invoice has to say where to.
    $methods = [ordered]@{ '1' = 'pin'; '2' = 'cash' }
    if ($Settings.iban) { $methods['3'] = 'transfer' }
    # 'tikkie' stands for any payment request: Tikkie, or the bank's own (ASN betaalverzoek).
    $methods['4'] = 'tikkie'
    $choices = @($methods.Keys | ForEach-Object { "[$_] " + (T ('inv.pay.' + $methods[$_])) }) -join '  '
    $payment = $null
    while (-not $payment) {
        $typed = "$(Read-HcLine (T 'inv.payment' $choices))".Trim()
        if ($typed -in @('0', 'Q')) { return $null }
        if ($methods.Contains($typed)) { $payment = $methods[$typed] }
    }

    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    if (-not (Test-HcYes (Read-HcLine (T 'inv.confirm' (Format-HcMoney $total))))) { return $null }

    [pscustomobject]@{
        Client  = @{ name = $name; address = $address; postcode_city = $postcode; email = $email }
        Lines   = @($lines)
        Payment = $payment
    }
}

<#
    The invoice form as a window (Shamil's request: click, fix, then make
    it). Its fields go through ConvertTo-HcInvoiceForm, which checks them
    and builds the same result as the console form, so it can be tested
    without a window. Without a desktop, the console form is used.
#>
function ConvertTo-HcInvoiceForm {
    param([hashtable]$Values, $Settings)
    $name = "$($Values.Name)".Trim()
    if (-not $name) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.needName') } }

    $lines = New-Object System.Collections.ArrayList
    foreach ($l in @(Get-HcLabourLines ([int]$Values.Minutes) $Settings)) { [void]$lines.Add($l) }
    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($Values.Callout -and $fee -gt 0) {
        [void]$lines.Add([pscustomobject]@{ Description = (T 'inv.calloutLine'); Amount = $fee })
    }
    $row = 0
    foreach ($extra in @($Values.Extras)) {
        $row++
        $description = "$($extra.Description)".Trim()
        $amountText = "$($extra.Amount)".Trim()
        if (-not $description -and -not $amountText) { continue }
        $amount = ConvertTo-HcAmount $amountText
        if (-not $description -or $null -eq $amount) {
            return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.badLine' $row) }
        }
        [void]$lines.Add([pscustomobject]@{ Description = $description; Amount = $amount })
    }
    if ($lines.Count -eq 0) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.nothing') } }
    if ($Values.Payment -notin @('pin', 'cash', 'transfer', 'tikkie')) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.needPayment') } }

    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    [pscustomobject]@{
        Error = $null
        Total = $total
        Form  = [pscustomobject]@{
            Client  = @{ name = $name; address = "$($Values.Address)".Trim(); postcode_city = "$($Values.Postcode)".Trim(); email = "$($Values.Email)".Trim() }
            Lines   = @($lines)
            Payment = $Values.Payment
        }
    }
}

# The window. Returns the form result, or $null for "no invoice".
function Show-HcInvoiceWindow {
    param($Settings)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $font = New-Object Drawing.Font('Segoe UI', 11)
    $bold = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Housecall - ' + (T 'inv.title')
    $form.StartPosition = 'CenterScreen'
    # Tall enough for everything, but never taller than the screen: the
    # fields scroll on a small laptop.
    $height = [Math]::Min(960, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 20)
    $form.Size = New-Object Drawing.Size(640, $height)
    $form.MinimumSize = New-Object Drawing.Size(560, 480)
    $form.Font = $font
    # Every colour set explicitly: Windows themes with custom system colours
    # (Shamil's PC has one) otherwise give white text on white, or dark fields.
    $form.BackColor = [Drawing.Color]::White
    $form.ForeColor = [Drawing.Color]::Black
    $form.TopMost = $true
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })
    $paint = { param($c) $c.BackColor = [Drawing.Color]::White; $c.ForeColor = [Drawing.Color]::Black }

    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object Windows.Forms.Padding(20, 16, 20, 8)
    $layout.ColumnCount = 2
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 190)))
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
    $layout.AutoScroll = $true

    $heading = { param($text)
        $l = New-Object Windows.Forms.Label
        $l.Text = $text; $l.Font = $bold; $l.AutoSize = $true; $l.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 4)
        $layout.Controls.Add($l); $layout.SetColumnSpan($l, 2) }
    $field = { param($label, $value)
        $l = New-Object Windows.Forms.Label
        $l.Text = $label; $l.AutoSize = $true; $l.Anchor = 'Left'; $l.Margin = New-Object Windows.Forms.Padding(0, 6, 8, 0)
        $t = New-Object Windows.Forms.TextBox
        $t.Text = $value; $t.Dock = 'Fill'; $t.BorderStyle = 'FixedSingle'; & $paint $t
        $layout.Controls.Add($l); $layout.Controls.Add($t); $t }

    & $heading (T 'inv.win.client')
    $name = & $field (T 'inv.win.name') "$script:HcKnownLabel"
    $address = & $field (T 'inv.address') ''
    $postcode = & $field (T 'inv.postcode') ''
    $email = & $field (T 'inv.email') ''
    # The client's question in Shamil's words; the problems checked this
    # visit are offered, since he may have checked more than was asked.
    $l = New-Object Windows.Forms.Label
    $l.Text = T 'inv.win.asked'; $l.AutoSize = $true; $l.Anchor = 'Left'; $l.Margin = New-Object Windows.Forms.Padding(0, 6, 8, 0)
    $asked = New-Object Windows.Forms.ComboBox
    $asked.DropDownStyle = 'DropDown'; $asked.Dock = 'Fill'; $asked.FlatStyle = 'Flat'; $asked.MaxLength = 150; & $paint $asked
    foreach ($v in @($script:HcVisit)) { [void]$asked.Items.Add((T "problem.$($v.Code)")) }
    $asked.Text = "$script:HcAsked"
    $layout.Controls.Add($l); $layout.Controls.Add($asked)

    & $heading (T 'inv.win.work')
    $l = New-Object Windows.Forms.Label
    $l.Text = T 'inv.win.minutes'; $l.AutoSize = $true; $l.Anchor = 'Left'
    $minutesRow = New-Object Windows.Forms.FlowLayoutPanel
    $minutesRow.AutoSize = $true; $minutesRow.Dock = 'Fill'; $minutesRow.WrapContents = $false
    $minutes = New-Object Windows.Forms.NumericUpDown
    $minutes.Minimum = 0; $minutes.Maximum = 1440; $minutes.Increment = 15; $minutes.Width = 90; $minutes.BorderStyle = 'FixedSingle'; & $paint $minutes
    $minutes.Value = Get-HcSuggestedMinutes
    $rateLabel = New-Object Windows.Forms.Label
    $rateLabel.AutoSize = $true; $rateLabel.Margin = New-Object Windows.Forms.Padding(8, 6, 0, 0)
    $rateLabel.MaximumSize = New-Object Drawing.Size(290, 0)
    # A non-breaking space after the euro sign: the label wraps, but never
    # between the sign and its amount.
    $rateLabel.Text = (Get-HcRateText $Settings) -replace ([string][char]0x20AC + ' '), ([string][char]0x20AC + [char]0xA0)
    $minutesRow.Controls.Add($minutes); $minutesRow.Controls.Add($rateLabel)
    $layout.Controls.Add($l); $layout.Controls.Add($minutesRow)

    $callout = New-Object Windows.Forms.CheckBox
    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($fee -gt 0) {
        $callout.Text = T 'inv.win.callout' (Format-HcMoney $fee); $callout.AutoSize = $true; $callout.Checked = $true
        $layout.Controls.Add((New-Object Windows.Forms.Label)); $layout.Controls.Add($callout)
    }

    # What was done and what not: pick an option or type one, then Fixed or
    # Not fixed. It goes on the note or invoice, next to Housecall's own fixes.
    & $heading (T 'inv.win.done')
    $workRow = New-Object Windows.Forms.FlowLayoutPanel
    $workRow.AutoSize = $true; $workRow.Dock = 'Fill'; $workRow.WrapContents = $false
    $workPick = New-Object Windows.Forms.ComboBox
    $workPick.DropDownStyle = 'DropDown'; $workPick.Width = 300; $workPick.FlatStyle = 'Flat'; & $paint $workPick
    $workPick.MaxDropDownItems = 12
    foreach ($p in @(Get-HcWorkPresets)) { [void]$workPick.Items.Add($p) }
    $workPick.AutoCompleteMode = 'SuggestAppend'; $workPick.AutoCompleteSource = 'ListItems'
    $addFixed = New-Object Windows.Forms.Button
    $addFixed.Text = T 'inv.win.fixed'; $addFixed.AutoSize = $true; & $paint $addFixed
    $addOpen = New-Object Windows.Forms.Button
    $addOpen.Text = T 'inv.win.notFixed'; $addOpen.AutoSize = $true; & $paint $addOpen
    $workRow.Controls.Add($workPick); $workRow.Controls.Add($addFixed); $workRow.Controls.Add($addOpen)
    $layout.Controls.Add($workRow); $layout.SetColumnSpan($workRow, 2)
    $workList = New-Object Windows.Forms.ListBox
    $workList.Height = 96; $workList.Dock = 'Fill'; $workList.BorderStyle = 'FixedSingle'; & $paint $workList
    $layout.Controls.Add($workList); $layout.SetColumnSpan($workList, 2)
    $removeWork = New-Object Windows.Forms.Button
    $removeWork.Text = T 'inv.win.remove'; $removeWork.AutoSize = $true; $removeWork.Anchor = 'Left'; & $paint $removeWork
    $layout.Controls.Add($removeWork); $layout.SetColumnSpan($removeWork, 2)

    $showWork = {
        $workList.Items.Clear()
        foreach ($w in $script:HcWork) {
            $key = if ($w.Done) { 'inv.win.itemFixed' } else { 'inv.win.itemOpen' }
            [void]$workList.Items.Add((T $key $w.Text))
        }
    }
    $addWork = { param([bool]$done)
        if (Add-HcWorkItem $workPick.Text $done) { $workPick.Text = ''; & $showWork }
        $workPick.Focus() | Out-Null
    }
    $addFixed.Add_Click({ & $addWork $true })
    $addOpen.Add_Click({ & $addWork $false })
    # Enter in the box counts as Fixed, the most common answer.
    $workPick.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $addWork $true } })
    $removeWork.Add_Click({
        $i = $workList.SelectedIndex
        if ($i -ge 0) { $script:HcWork.RemoveAt($i); & $showWork }
    })
    & $showWork

    & $heading (T 'inv.win.extras')
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Height = 130; $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $true; $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = [Drawing.Color]::White
    $grid.GridColor = [Drawing.Color]::Gainsboro
    $grid.EnableHeadersVisualStyles = $false
    $grid.DefaultCellStyle.BackColor = [Drawing.Color]::White
    $grid.DefaultCellStyle.ForeColor = [Drawing.Color]::Black
    $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(204, 228, 247)
    $grid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::Black
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::Black
    [void]$grid.Columns.Add('description', (T 'inv.win.description'))
    [void]$grid.Columns.Add('amount', (T 'inv.win.amount'))
    $grid.Columns[0].FillWeight = 75; $grid.Columns[1].FillWeight = 25
    $layout.Controls.Add($grid); $layout.SetColumnSpan($grid, 2)

    & $heading (T 'inv.win.payment')
    $pay = New-Object Windows.Forms.FlowLayoutPanel
    $pay.AutoSize = $true; $pay.Dock = 'Fill'
    $radios = [ordered]@{}
    $methods = @('pin', 'cash')
    if ($Settings.iban) { $methods += 'transfer' }
    $methods += 'tikkie'
    foreach ($m in $methods) {
        $r = New-Object Windows.Forms.RadioButton
        $r.Text = T ('inv.pay.' + $m); $r.AutoSize = $true; $r.Tag = $m
        $pay.Controls.Add($r); $radios[$m] = $r
    }
    $layout.Controls.Add($pay); $layout.SetColumnSpan($pay, 2)

    $total = New-Object Windows.Forms.Label
    $total.Font = $bold; $total.AutoSize = $true; $total.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 0)
    $layout.Controls.Add($total); $layout.SetColumnSpan($total, 2)
    $problem = New-Object Windows.Forms.Label
    $problem.ForeColor = [Drawing.Color]::Firebrick; $problem.AutoSize = $true; $problem.MaximumSize = New-Object Drawing.Size(540, 0)
    $layout.Controls.Add($problem); $layout.SetColumnSpan($problem, 2)

    # Reads every field into the values ConvertTo-HcInvoiceForm checks.
    $read = {
        $extras = @(foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }
            [pscustomobject]@{ Description = $row.Cells[0].Value; Amount = $row.Cells[1].Value }
        })
        $chosen = @($radios.Values | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }) | Select-Object -First 1
        ConvertTo-HcInvoiceForm @{
            Name = $name.Text; Address = $address.Text; Postcode = $postcode.Text; Email = $email.Text
            Minutes = [int]$minutes.Value; Callout = $callout.Checked; Extras = $extras; Payment = $chosen
        } $Settings
    }
    $script:HcInvoiceResult = $null

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.FlowDirection = 'RightToLeft'; $buttons.Height = 64
    $buttons.Padding = New-Object Windows.Forms.Padding(16, 10, 16, 10)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $make = New-Object Windows.Forms.Button
    $make.Text = T 'inv.win.make'; $make.AutoSize = $true; $make.Height = 40; $make.Font = $bold; & $paint $make
    $none = New-Object Windows.Forms.Button
    $none.Text = T 'inv.win.none'; $none.AutoSize = $true; $none.Height = 40; & $paint $none
    $make.Add_Click({
        $grid.EndEdit() | Out-Null
        $check = & $read
        if ($check.Error) { $problem.Text = $check.Error; return }
        $script:HcInvoiceResult = $check.Form
        $script:HcAsked = $asked.Text.Trim()
        $this.FindForm().Close()
    })
    $none.Add_Click({ $script:HcInvoiceResult = $null; $script:HcAsked = $asked.Text.Trim(); $this.FindForm().Close() })
    $buttons.Controls.Add($make); $buttons.Controls.Add($none)

    # Live total: labour + call-out + valid extra lines, whatever the payment.
    $update = {
        $sum = [decimal]0
        foreach ($l in @(Get-HcLabourLines ([int]$minutes.Value) $Settings)) { $sum += [decimal]$l.Amount }
        if ($callout.Checked) { $sum += $fee }
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }
            $a = ConvertTo-HcAmount "$($row.Cells[1].Value)"
            if ($null -ne $a) { $sum += $a }
        }
        $total.Text = T 'inv.win.total' (Format-HcMoney $sum)
        $problem.Text = ''
    }
    $minutes.Add_ValueChanged($update)
    $callout.Add_CheckedChanged($update)
    $grid.Add_CellValueChanged($update)
    $grid.Add_RowsRemoved($update)
    & $update

    $form.Controls.Add($layout)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $name
    [void]$form.ShowDialog()
    $form.Dispose()
    $script:HcInvoiceResult
}

<#
    The whole invoice step at Q. Returns the invoice from the relay (with its
    number, totals and the seller's details), or $null for the plain note.
#>
function Invoke-HcInvoice {
    param([pscustomobject]$Environment)
    if ($script:HcVisit.Count -eq 0 -or $script:DryRun -or -not $Environment.Online) { return $null }
    Write-Host ''
    if (-not (Unlock-HcRelay 'inv.askCode')) {
        # Enter at the code: no invoice, and no second question to save the visit.
        $script:HcQuitSkipped = $true
        return $null
    }
    $s = Get-HcSettings
    if (-not $s.Ok) { Write-Warn2 (T 'inv.failed' (Get-HcRelayMessage $s.Error)); return $null }
    if (-not $s.Settings -or -not $s.Settings.business_name) { Write-Warn2 (T 'inv.noSettings'); return $null }
    $script:HcStartMinutes = if ([decimal]$(if ($s.Settings.start_fee) { $s.Settings.start_fee } else { 0 }) -gt 0) { [int]$s.Settings.start_minutes } else { 0 }

    # The window when there is a desktop; the console form in tests and without one.
    $form = $null
    $useWindow = ($null -eq $script:HcInputQueue) -and -not $script:NoConsole
    if ($useWindow) {
        try { $form = Show-HcInvoiceWindow $s.Settings } catch { $useWindow = $false }
    }
    if (-not $useWindow) { $form = Read-HcInvoiceForm $s.Settings }
    if (-not $form) { Write-Dim (T 'inv.skipped'); return $null }

    $r = Invoke-HcRelay @{
        action   = 'invoice_create'
        token    = $script:HcToken
        pc       = (Get-HcPcId)
        lang     = $script:Lang
        client   = $form.Client
        lines    = @($form.Lines | ForEach-Object { @{ description = $_.Description; amount = [double]$_.Amount } })
        payment  = $form.Payment
        problems = @($script:HcVisit | Where-Object { $_.FindingId } | ForEach-Object { @{ code = $_.Code; finding = $_.FindingId } })
        changes  = @(Get-HcVisitChanges)
    }
    if (-not $r.Ok) { Write-Warn2 (T 'inv.failed' (Get-HcRelayMessage $r.Error)); return $null }
    Write-Ok (T 'inv.made' $r.Data.invoice.number)
    $r.Data.invoice
}

# ----------------------------------------------------------------- document --

function Format-HcLongDate {
    param([datetime]$Date)
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))
}

# A money row: description on the left, amount on the right, in a fixed-width
# font so the amounts line up on screen and on paper.
function New-HcMoneyRow {
    param([string]$Description, [decimal]$Amount, [string]$Style = 'row')
    $width = 44
    $d = if ($Description.Length -gt $width) { $Description.Substring(0, $width - 3) + '...' } else { $Description }
    [pscustomobject]@{ Style = $Style; Text = $d.PadRight($width) + (Format-HcMoney $Amount).PadLeft(14) }
}

<#
    The invoice as blocks for the same window and printout as the note:
    seller, number and date, client, what was wrong and done, the money,
    and how to pay.
#>
function Get-HcInvoiceBlocks {
    param($Invoice)
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    $s = $Invoice.seller
    $issued = [datetime]::Parse([string]$Invoice.issued_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()

    & $block 'title' (T 'doc.invoice' $Invoice.number)
    & $block 'small' (T 'doc.date' (Format-HcLongDate $issued))

    $seller = @($s.business_name, $s.owner_name, $s.address, $s.postcode_city) | Where-Object { $_ }
    & $block 'text' ($seller -join "`n")
    $ids = @()
    if ($s.kvk) { $ids += T 'doc.kvk' $s.kvk }
    if ($s.btw_number) { $ids += T 'doc.btwNumber' $s.btw_number }
    if ($s.iban) { $ids += T 'doc.iban' $s.iban }
    $contact = @($s.email, $s.phone) | Where-Object { $_ }
    if ($ids.Count) { & $block 'small' ($ids -join '   ') }
    if ($contact.Count) { & $block 'small' ($contact -join '   ') }

    & $block 'heading' (T 'doc.to')
    $client = @($Invoice.client_name, $Invoice.client_address, $Invoice.client_postcode_city, $Invoice.client_email) | Where-Object { $_ }
    & $block 'text' ($client -join "`n")

    $subject = Get-HcInvoiceSubject
    if ($subject) {
        & $block 'heading' (T 'doc.subjectCap')
        & $block 'text' $subject
    }

    & $block 'heading' (T 'doc.costs')
    $work = @(Get-HcInvoiceWork)
    if ($work.Count) {
        & $block 'text' (T 'doc.workTitle')
        foreach ($w in $work) { & $block 'text' ('  - ' + $w.Text) }
    }
    foreach ($l in @($Invoice.lines)) { New-HcMoneyRow $l.description ([decimal]$l.amount) }
    & $block 'row' ('-' * 58)
    if ($Invoice.btw_mode -eq '21') {
        New-HcMoneyRow (T 'doc.subtotal') ([decimal]$Invoice.subtotal)
        New-HcMoneyRow (T 'doc.btw') ([decimal]$Invoice.btw_amount)
    }
    New-HcMoneyRow (T 'doc.total') ([decimal]$Invoice.total) 'rowBold'

    $paidOn = Format-HcLongDate $issued
    switch ($Invoice.payment) {
        'pin'      { & $block 'payment' (T 'doc.paidPin' $paidOn) }
        'cash'     { & $block 'payment' (T 'doc.paidCash' $paidOn) }
        'tikkie'   { & $block 'payment' (T 'doc.paidTikkie' $paidOn) }
        'transfer' {
            $due = Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture))
            & $block 'payment' (T 'doc.transfer' (Format-HcMoney ([decimal]$Invoice.total)) $due $s.iban $Invoice.number)
        }
    }
    # No BTW line until BTW is set: Shamil is not a registered business yet.
    if ($Invoice.btw_mode -eq 'kor') { & $block 'small' (T 'doc.kor') }
    & $block 'small' (T 'doc.thanks')
}

# The drawn A4 page in a window; the text version in tests and without a desktop.
function Show-HcInvoice {
    param($Invoice)
    if ($null -eq $script:HcInputQueue -and -not $script:NoConsole) {
        try { Show-HcInvoicePages $Invoice; return } catch { }
    }
    Show-HcDocument @(Get-HcInvoiceBlocks $Invoice) (T 'doc.windowTitle' $Invoice.number)
}

# ==================================================== src\invoice-page.ps1 ==
<#
    The invoice as a drawn A4 page (layout "B", Shamil's choice): seller and
    number on top, the client next to what it was about, then one table
    with the work done and the costs, the total and how it was paid.

    Get-HcInvoiceLayout measures everything once and returns the pages as
    drawing steps; Write-HcInvoicePage draws a page from them. The window
    and the printer use the same steps, so paper looks like the screen.
    Units are pixels of an A4 page at 96 dpi (794 x 1123).
#>

$script:HcPage = @{ Width = 794; Height = 1123; Left = 64; Right = 730; Top = 60; Bottom = 1040 }

function Get-HcInvoiceStyle {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $world = [Drawing.GraphicsUnit]::World
    $f = { param($size, $style = 'Regular') New-Object Drawing.Font('Segoe UI', [single]$size, [Drawing.FontStyle]$style, $world) }
    @{
        Fonts  = @{
            title = & $f 30 'Bold'; body = & $f 14; bodyBold = & $f 14 'Bold'; small = & $f 12.5
            cap = & $f 11 'Bold'; total = & $f 17 'Bold'; item = & $f 13.5
        }
        Colors = @{
            ink   = [Drawing.Color]::FromArgb(27, 31, 36)
            muted = [Drawing.Color]::FromArgb(107, 116, 128)
            rule  = [Drawing.Color]::FromArgb(215, 221, 227)
            ok    = [Drawing.Color]::FromArgb(46, 125, 79)
            open  = [Drawing.Color]::FromArgb(164, 84, 27)
        }
    }
}

# What the visit was about: the question typed in the invoice window, or
# else the problems that were checked.
function Get-HcInvoiceSubject {
    if ("$script:HcAsked".Trim()) { return "$script:HcAsked".Trim() }
    (@($script:HcVisit) | ForEach-Object { T "problem.$($_.Code)" }) -join ', '
}

# The work under "Computerhulp aan huis": Housecall's own fixes and the
# hand-made list, each with Done.
function Get-HcInvoiceWork {
    foreach ($c in @($script:HcChanges)) { [pscustomobject]@{ Text = $c.Label; Done = $true } }
    foreach ($w in @($script:HcWork)) {
        if ($w.Done) { [pscustomobject]@{ Text = $w.Text; Done = $true } }
        else { [pscustomobject]@{ Text = (T 'doc.notFixed' $w.Text); Done = $false } }
    }
}

function Get-HcInvoiceLayout {
    param($Invoice)
    $style = Get-HcInvoiceStyle
    $F = $style.Fonts
    $P = $script:HcPage
    $bmp = New-Object Drawing.Bitmap(1, 1)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.PageUnit = [Drawing.GraphicsUnit]::Pixel
    $measure = { param($text, $font, $width) $g.MeasureString([string]$text, $F[$font], [int]$width).Height }

    $pages = New-Object System.Collections.ArrayList
    $page = New-Object System.Collections.ArrayList
    [void]$pages.Add($page)
    $y = [single]$P.Top
    $text = { param($t, $font, $x, $yy, $w, $color = 'ink', $align = 'left')
        [void]$page.Add([pscustomobject]@{ Kind = 'text'; Text = [string]$t; Font = $font; X = [single]$x; Y = [single]$yy; W = [single]$w; Color = $color; Align = $align }) }
    $line = { param($yy, $color = 'rule', $width = 1)
        [void]$page.Add([pscustomobject]@{ Kind = 'line'; Y = [single]$yy; X = [single]$P.Left; X2 = [single]$P.Right; Color = $color; Width = [single]$width }) }
    # A new page when the next piece does not fit.
    $room = { param($h)
        if ($y + $h -gt $P.Bottom) {
            $next = New-Object System.Collections.ArrayList
            [void]$pages.Add($next)
            Set-Variable -Name page -Value $next -Scope 1
            Set-Variable -Name y -Value ([single]$P.Top) -Scope 1
        } }

    $s = $Invoice.seller
    $issued = [datetime]::Parse([string]$Invoice.issued_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
    $full = $P.Right - $P.Left
    $half = ($full - 32) / 2
    $amountW = 120
    $descW = $full - $amountW - 16

    # Top: "Factuur", number and date on the left; the seller on the right.
    # GDI+ pads text by a sixth of its size; at 30 px that shows, so pull it back in line.
    & $text (T 'doc.invoiceWord') 'title' ($P.Left - 4) $y $half
    $leftY = $y + (& $measure 'F' 'title' $half)
    & $text ((T 'doc.numberDate' $Invoice.number (Format-HcLongDate $issued))) 'small' $P.Left $leftY $half 'muted'
    $leftY += (& $measure 'x' 'small' $half)
    $rightY = $y + 6
    $sellerX = $P.Left + $half + 32
    & $text $s.business_name 'bodyBold' $sellerX $rightY $half 'ink' 'right'
    $rightY += (& $measure 'x' 'bodyBold' $half)
    $ids = @()
    if ($s.kvk) { $ids += T 'doc.kvk' $s.kvk }
    if ($s.btw_number) { $ids += T 'doc.btwNumber' $s.btw_number }
    if ($s.iban) { $ids += T 'doc.iban' $s.iban }
    foreach ($l in @(@($s.owner_name, $s.address, $s.postcode_city, $s.email, $s.phone) + $ids | Where-Object { $_ })) {
        & $text $l 'small' $sellerX $rightY $half 'muted' 'right'
        $rightY += (& $measure $l 'small' $half)
    }
    $y = [Math]::Max($leftY, $rightY) + 34

    # The client, next to what it was about.
    & $text (T 'doc.toCap') 'cap' $P.Left $y $half 'muted'
    & $text (T 'doc.subjectCap') 'cap' $sellerX $y $half 'muted'
    $y += 18
    $clientY = $y
    foreach ($l in @($Invoice.client_name, $Invoice.client_address, $Invoice.client_postcode_city, $Invoice.client_email) | Where-Object { $_ }) {
        & $text $l 'body' $P.Left $clientY $half
        $clientY += (& $measure $l 'body' $half)
    }
    $subject = Get-HcInvoiceSubject
    $subjectY = $y
    if ($subject) {
        & $text $subject 'body' $sellerX $y $half
        $subjectY += (& $measure $subject 'body' $half)
    }
    $y = [Math]::Max($clientY, $subjectY) + 34

    # The table.
    & $text (T 'doc.descriptionCap') 'cap' $P.Left $y $descW 'muted'
    & $text (T 'doc.amountCap') 'cap' ($P.Right - $amountW) $y $amountW 'muted' 'right'
    $y += 20
    & $line $y 'ink' 1.5
    $y += 8

    $work = @(Get-HcInvoiceWork)
    if ($work.Count) {
        & $room 30
        & $text (T 'doc.workTitle') 'bodyBold' $P.Left $y $descW
        $y += (& $measure 'x' 'bodyBold' $descW) + 2
        foreach ($w in $work) {
            $h = & $measure $w.Text 'item' ($descW - 24)
            & $room $h
            [void]$page.Add([pscustomobject]@{ Kind = $(if ($w.Done) { 'check' } else { 'dash' }); X = [single]($P.Left + 4); Y = [single]($y + 5); Color = $(if ($w.Done) { 'ok' } else { 'open' }) })
            & $text $w.Text 'item' ($P.Left + 24) $y ($descW - 24) $(if ($w.Done) { 'ink' } else { 'muted' })
            $y += $h + 1
        }
        $y += 6
        & $line $y
        $y += 8
    }
    foreach ($l in @($Invoice.lines)) {
        $h = & $measure $l.description 'body' $descW
        & $room ($h + 10)
        & $text $l.description 'body' $P.Left $y $descW
        & $text (Format-HcMoney ([decimal]$l.amount)) 'body' ($P.Right - $amountW) $y $amountW 'ink' 'right'
        $y += $h + 6
        & $line $y
        $y += 8
    }
    if ($Invoice.btw_mode -eq '21') {
        foreach ($pair in @(@((T 'doc.subtotal'), $Invoice.subtotal), @((T 'doc.btw'), $Invoice.btw_amount))) {
            & $room 26
            & $text $pair[0] 'small' $P.Left $y $descW 'muted'
            & $text (Format-HcMoney ([decimal]$pair[1])) 'small' ($P.Right - $amountW) $y $amountW 'muted' 'right'
            $y += 22
        }
    }
    & $room 44
    $y += 2
    & $line $y 'ink' 2
    $y += 8
    & $text (T 'doc.totalWord') 'total' $P.Left $y $descW
    & $text (Format-HcMoney ([decimal]$Invoice.total)) 'total' ($P.Right - $amountW - 40) $y ($amountW + 40) 'ink' 'right'
    $y += (& $measure 'x' 'total' $descW) + 26

    # How it was paid, and the BTW note.
    $paidOn = Format-HcLongDate $issued
    $pay = switch ($Invoice.payment) {
        'pin'      { T 'doc.paidPin' $paidOn }
        'cash'     { T 'doc.paidCash' $paidOn }
        'tikkie'   { T 'doc.paidTikkie' $paidOn }
        'transfer' {
            $due = Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture))
            T 'doc.transfer' (Format-HcMoney ([decimal]$Invoice.total)) $due $s.iban $Invoice.number
        }
    }
    foreach ($para in @($pay, $(if ($Invoice.btw_mode -eq 'kor') { T 'doc.kor' })) | Where-Object { $_ }) {
        $font = if ($para -eq $pay) { 'body' } else { 'small' }
        $h = & $measure $para $font $full
        & $room $h
        & $text $para $font $P.Left $y $full $(if ($font -eq 'small') { 'muted' } else { 'ink' })
        $y += $h + 10
    }

    # The foot of every page.
    $n = $pages.Count
    for ($i = 0; $i -lt $n; $i++) {
        $page = $pages[$i]
        & $line ($P.Bottom + 22)
        & $text (T 'doc.thanks') 'small' $P.Left ($P.Bottom + 30) $half 'muted'
        & $text (T 'doc.pageOf' ($i + 1) $n) 'small' $sellerX ($P.Bottom + 30) $half 'muted' 'right'
    }
    $g.Dispose(); $bmp.Dispose()
    # One array of steps per page (a plain list, so @() gives the pages).
    foreach ($pg in $pages) { , $pg.ToArray() }
}

function Write-HcInvoicePage {
    param([Drawing.Graphics]$Graphics, [object[]]$Steps)
    $style = Get-HcInvoiceStyle
    $Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    foreach ($s in $Steps) {
        $color = $style.Colors[$s.Color]
        switch ($s.Kind) {
            'text' {
                $format = New-Object Drawing.StringFormat
                if ($s.Align -eq 'right') { $format.Alignment = [Drawing.StringAlignment]::Far }
                $brush = New-Object Drawing.SolidBrush($color)
                $rect = New-Object Drawing.RectangleF($s.X, $s.Y, $s.W, [single]400)
                $Graphics.DrawString($s.Text, $style.Fonts[$s.Font], $brush, $rect, $format)
                $brush.Dispose(); $format.Dispose()
            }
            'line' {
                $pen = New-Object Drawing.Pen($color, $s.Width)
                $Graphics.DrawLine($pen, $s.X, $s.Y, $s.X2, $s.Y)
                $pen.Dispose()
            }
            # Drawn, not typed: GDI+ does not fall back to a font that has a tick.
            'check' {
                $pen = New-Object Drawing.Pen($color, [single]2)
                $Graphics.DrawLines($pen, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(($s.X), ($s.Y + 5))),
                    (New-Object Drawing.PointF(($s.X + 4), ($s.Y + 9))),
                    (New-Object Drawing.PointF(($s.X + 11), ($s.Y + 1)))))
                $pen.Dispose()
            }
            'dash' {
                $pen = New-Object Drawing.Pen($color, [single]2)
                $Graphics.DrawLine($pen, $s.X, ($s.Y + 5), ($s.X + 10), ($s.Y + 5))
                $pen.Dispose()
            }
        }
    }
}

# A page as a picture, for the window.
function New-HcInvoiceBitmap {
    param([object[]]$Steps)
    $bmp = New-Object Drawing.Bitmap($script:HcPage.Width, $script:HcPage.Height)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.PageUnit = [Drawing.GraphicsUnit]::Pixel
    $g.Clear([Drawing.Color]::White)
    Write-HcInvoicePage $g $Steps
    $g.Dispose()
    $bmp
}

# The window: the pages under each other on a grey ground, Print and Close.
function Show-HcInvoicePages {
    param($Invoice)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:HcInvoicePages = @(Get-HcInvoiceLayout $Invoice)
    $family = 'Segoe UI'

    $form = New-Object Windows.Forms.Form
    $form.Text = T 'doc.windowTitle' $Invoice.number
    $form.StartPosition = 'CenterScreen'
    $height = [Math]::Min(1000, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 20)
    $form.Size = New-Object Drawing.Size(880, $height)
    $form.MinimumSize = New-Object Drawing.Size(500, 400)
    $form.BackColor = [Drawing.Color]::FromArgb(233, 237, 241)
    $form.TopMost = $true
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })

    $scroll = New-Object Windows.Forms.FlowLayoutPanel
    $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true; $scroll.FlowDirection = 'TopDown'; $scroll.WrapContents = $false
    $scroll.Padding = New-Object Windows.Forms.Padding(28, 20, 20, 20)
    $scroll.BackColor = $form.BackColor
    foreach ($steps in $script:HcInvoicePages) {
        $pic = New-Object Windows.Forms.PictureBox
        $pic.Image = New-HcInvoiceBitmap $steps
        $pic.SizeMode = 'AutoSize'
        $pic.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 20)
        $scroll.Controls.Add($pic)
    }

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.FlowDirection = 'RightToLeft'; $buttons.Height = 72
    $buttons.Padding = New-Object Windows.Forms.Padding(24, 12, 24, 12)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $close = New-Object Windows.Forms.Button
    $close.Text = T 'note.close'; $close.Size = New-Object Drawing.Size(150, 44); $close.Font = New-Object Drawing.Font($family, 12)
    $close.BackColor = [Drawing.Color]::White; $close.ForeColor = [Drawing.Color]::Black
    $close.Add_Click({ $this.FindForm().Close() })
    $form.CancelButton = $close
    $print = New-Object Windows.Forms.Button
    $print.Text = T 'note.print'; $print.Size = New-Object Drawing.Size(150, 44); $print.Font = New-Object Drawing.Font($family, 12)
    $print.BackColor = [Drawing.Color]::White; $print.ForeColor = [Drawing.Color]::Black
    $print.Add_Click({ Invoke-HcInvoicePrint })
    $buttons.Controls.Add($close); $buttons.Controls.Add($print)

    $form.Controls.Add($scroll)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $close
    [void]$form.ShowDialog()
    foreach ($c in $scroll.Controls) { if ($c.Image) { $c.Image.Dispose() } }
    $form.Dispose()
}

function Invoke-HcInvoicePrint {
    $doc = New-Object Drawing.Printing.PrintDocument
    $doc.DocumentName = 'Housecall'
    $script:HcInvoicePrintAt = 0
    $doc.Add_PrintPage({
        param($sender, $e)
        $g = $e.Graphics
        # The printer draws in hundredths of an inch from its printable edge:
        # move back to the paper's corner, then scale 96 dpi pixels to it.
        $g.PageUnit = [Drawing.GraphicsUnit]::Display
        $g.TranslateTransform(-$e.PageSettings.HardMarginX, -$e.PageSettings.HardMarginY)
        $g.ScaleTransform([single](100 / 96), [single](100 / 96))
        Write-HcInvoicePage $g $script:HcInvoicePages[$script:HcInvoicePrintAt]
        $script:HcInvoicePrintAt++
        $e.HasMorePages = $script:HcInvoicePrintAt -lt $script:HcInvoicePages.Count
    })
    $dialog = New-Object Windows.Forms.PrintDialog
    $dialog.Document = $doc
    $dialog.UseEXDialog = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        try { $doc.Print() } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Housecall') }
    }
    $doc.Dispose()
}

# ==================================================== src\ai.ps1 ==
<#
    The AI chat (?): the problem in the client's own words, and Claude picks
    which of Housecall's checks to run.

    The loop runs here, one relay round at a time. Claude (behind the
    relay, which holds the key and the system prompt) answers with
    run_check calls; Housecall runs those checks on this PC -- the same
    read-only checks as the menu -- and sends the results back. Claude ends
    with give_answer: a plain summary, the problem it points to, the fixes
    it recommends and manual steps.

    The AI never changes anything. The fixes it names must be ones the check
    itself offered; they go through the normal Wat nu? menu with a J/N, the
    check again as proof, and U to undo. Only the problem text and the check
    results leave the PC.

    Each turn's content is kept exactly as the API returned it (as a JSON
    string) and sent back unchanged, because Claude's thinking blocks must
    come back as they were.
#>

$script:AiMaxChecks = 6
$script:AiMaxRounds = 10

# One check by code, without asking anything: A3 and A4 take the site or
# email address the AI passes along.
function Get-HcAiCheck {
    param([string]$Code, [string]$Value)
    switch ($Code) {
        'A3'    { return New-HcSiteCheck (ConvertTo-HcHostName $Value) }
        'A4'    { return New-HcMailCheck (ConvertTo-HcMailDomain $Value) }
        default {
            $handler = $script:ProblemHandlers[$Code]
            if ($handler) { return & $handler }
            return $null
        }
    }
}

# A report as text for the AI: the lines, the finding, the advice, and the
# fixes Housecall offers, by id.
function Format-HcReportForAi {
    param([pscustomobject]$Report)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($r in $Report.Results) { $lines.Add("[$($r.Status)] $($r.Text)") }
    if ($Report.FindingId) {
        $all = @('finding.' + $Report.FindingId) + @($Report.FindingArgs)
        $lines.Add("Finding ($($Report.FindingId)): $(T @all)")
        $lines.Add("Advice: $(T ('advice.' + $Report.FindingId))")
    }
    $actions = @($Report.Actions)
    if ($actions.Count) {
        $lines.Add('Offered fixes:')
        foreach ($a in $actions) { $lines.Add("- $($a.FixId): $(Get-HcFixLabel $a)") }
    } else {
        $lines.Add('Offered fixes: none')
    }
    $lines -join "`n"
}

function ConvertTo-HcContentJson {
    param([object[]]$Blocks)
    ConvertTo-Json -InputObject @($Blocks) -Depth 20 -Compress
}

<#
    One AI conversation. Returns the answer (the give_answer input), plus
    the reports and checks it ran, so the menu can offer the fixes.
#>
function Invoke-HcAiConversation {
    param([string]$Problem)
    $history = New-Object System.Collections.ArrayList
    $first = @(@{ type = 'text'; text = "[$script:Lang]`n$Problem" })
    [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $first) })

    $state = [pscustomobject]@{ Answer = $null; Text = $null; Reports = @{}; Checks = @{}; Error = $null; Refused = $false }
    $checksRun = 0
    for ($round = 0; $round -lt $script:AiMaxRounds; $round++) {
        Write-Dim (T 'ai.thinking')
        $r = Invoke-HcRelay @{ action = 'chat'; token = $script:HcToken; messages = @($history) }
        if (-not $r.Ok) { $state.Error = $r.Error; return $state }
        [void]$history.Add(@{ role = 'assistant'; content_json = [string]$r.Data.content_json })
        if ($r.Data.stop_reason -eq 'refusal') { $state.Refused = $true; return $state }

        $results = @()
        foreach ($block in @($r.Data.content)) {
            if ($block.type -eq 'text' -and $block.text) { $state.Text = $block.text }
            if ($block.type -ne 'tool_use') { continue }
            if ($block.name -eq 'give_answer') {
                $state.Answer = $block.input
                continue
            }
            $code = [string]$block.input.code
            $check = $null
            if ($checksRun -lt $script:AiMaxChecks) { $check = Get-HcAiCheck $code ([string]$block.input.input) }
            if ($null -eq $check) {
                $why = if ($checksRun -ge $script:AiMaxChecks) { 'The limit of checks for this conversation is reached; call give_answer now.' } else { "Check $code could not run with that input." }
                $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = $why; is_error = $true }
                continue
            }
            $checksRun++
            Write-Step (T 'ai.running' $code (T "problem.$code"))
            $report = & $check
            $state.Reports[$code] = $report
            $state.Checks[$code] = $check
            $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = (Format-HcReportForAi $report) }
        }
        if ($state.Answer -or $results.Count -eq 0) { return $state }
        [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $results) })
    }
    $state
}

function Invoke-HcAi {
    param([pscustomobject]$Environment, [string]$Text)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ?  ' + (T 'ai.title')) -ForegroundColor Yellow
    Write-Host ''
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }
    if (-not (Unlock-HcRelay)) {
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }
    if ($Text) {
        Write-Dim (T 'ai.youTyped' $Text)
    } else {
        $Text = "$(Read-HcLine (T 'ai.describe'))".Trim()
        if (-not $Text -or $Text -eq 'Q') { return }
    }
    Write-Dim (T 'ai.privacy')
    Write-Host ''

    $state = Invoke-HcAiConversation $Text
    Write-Host ''
    if ($state.Error) {
        Write-Warn2 (Get-HcRelayMessage $state.Error)
    } elseif ($state.Refused) {
        Write-Warn2 (T 'ai.refused')
    } elseif (-not $state.Answer) {
        if ($state.Text) { Write-HcLabelled (T 'ai.answer') $state.Text 'Yellow' } else { Write-Warn2 (T 'ai.noAnswer') }
    } else {
        $a = $state.Answer
        Write-HcLabelled (T 'ai.answer') ([string]$a.summary) 'Yellow'
        Write-Dim (T ('ai.confidence.' + $a.confidence))
        $steps = @($a.steps | Where-Object { $_ })
        if ($steps.Count) {
            Write-Host ''
            Write-Host ('  ' + (T 'ai.steps')) -ForegroundColor Cyan
            for ($i = 0; $i -lt $steps.Count; $i++) { Write-HcLabelled "$($i + 1)." ([string]$steps[$i]) 'Cyan' }
        }
        $code = [string]$a.problem_code
        if ($state.Reports.ContainsKey($code)) {
            # The fixes the AI chose, from what that check offered, through the normal menu.
            $script:HcCurrentCode = $code
            Save-HcVisit $code $state.Reports[$code]
            Write-Host ''
            Write-HcReport $state.Reports[$code] -LinesOnly
            Invoke-HcReportLoop $code $state.Checks[$code] $state.Reports[$code] -OnlyFixes @($a.fix_ids | ForEach-Object { [string]$_ })
            return
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}
'@


# The options, saved before the code loads: run as a file (a USB stick),
# this script's scope is Housecall's script: scope, and loading the code
# resets $script:Lang -- which is this same $Lang.
$HcOptions = @{ DryRun = [bool]$DryRun; Lang = $Lang; Start = $Start; NoAI = [bool]$NoAI }

. ([scriptblock]::Create($HcSource))
$script:HcSource = $HcSource
$script:HcBuild = $HcBuild
# Run from a file (a USB stick) rather than through irm | iex.
$script:HcFromFile = [bool]$PSCommandPath
Start-Housecall -DryRun:$HcOptions.DryRun -Lang $HcOptions.Lang -Start $HcOptions.Start -NoAI:$HcOptions.NoAI
