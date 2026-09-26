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
    [string]$Start
)

$ErrorActionPreference = 'Stop'

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

        'looks.A' = 'network adapter, address from the router, router, DNS, internet, proxy, Wi-Fi signal'
        'looks.B' = 'default sound device, mute and volume, audio service, camera and microphone access, screen scale'
        'looks.C' = 'print service, stuck print jobs, default printer, USB devices with errors, Bluetooth'
        'looks.D' = 'free disk space, programs using memory and CPU, startup programs, recent crashes, time since restart'
        'looks.E' = 'Windows Update service, last successful update, waiting restart'
        'looks.F' = 'remote-access programs such as AnyDesk, sites allowed to send pop-ups, Microsoft Defender, unknown scheduled tasks'

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
        'note.contact'        = 'Questions?'
        'note.footer'         = 'This note is not saved anywhere: it disappears when you close it. Print it if you want to keep it.'
        'note.print'          = 'Print'
        'note.close'          = 'Close'
        'note.windowTitle'    = 'Housecall - note'

        # ---- restarting as administrator
        'fix.elevateAsk'      = 'This needs admin. Restart Housecall as administrator now? Windows will ask for permission. (Y/N)'
        'fix.elevated'        = 'Housecall carries on in the new administrator window. This window can be closed.'
        'fix.elevateFailed'   = 'Windows did not start the administrator window ({0}).'
    }

    nl = @{
        'tagline'          = 'vindt en verhelpt computerproblemen, altijd met uw akkoord'
        'promise'          = 'Er verandert niets op deze pc zonder uw ja.'

        'status.admin'     = 'beheerder'
        'status.notAdmin'  = 'geen beheerder'
        'status.online'    = 'online'
        'status.offline'   = 'offline'
        'status.dryRun'    = 'PROEFDRAAI: alleen controleren, er wordt niets hersteld'

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

        'looks.A' = 'netwerkadapter, adres van de router, router, DNS, internet, proxy, wifi-signaal'
        'looks.B' = 'standaard geluidsapparaat, dempen en volume, audioservice, toegang tot camera en microfoon, schermschaal'
        'looks.C' = 'afdrukservice, vastgelopen printopdrachten, standaardprinter, USB-apparaten met fouten, Bluetooth'
        'looks.D' = 'vrije schijfruimte, programma''s die geheugen en processor gebruiken, opstartprogramma''s, recente crashes, tijd sinds herstart'
        'looks.E' = 'Windows Update-service, laatste geslaagde update, wachtende herstart'
        'looks.F' = 'programma''s voor overname op afstand zoals AnyDesk, sites die meldingen mogen sturen, Microsoft Defender, onbekende geplande taken'

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
        'note.contact'        = 'Vragen?'
        'note.footer'         = 'Dit briefje wordt nergens bewaard: het verdwijnt als u het sluit. Druk het af als u het wilt houden.'
        'note.print'          = 'Afdrukken'
        'note.close'          = 'Sluiten'
        'note.windowTitle'    = 'Housecall - briefje'

        # ---- restarting as administrator
        'fix.elevateAsk'      = 'Hiervoor is beheerder nodig. Housecall nu opnieuw starten als beheerder? Windows vraagt om toestemming. (J/N)'
        'fix.elevated'        = 'Housecall gaat verder in het nieuwe beheerdersvenster. Dit venster mag dicht.'
        'fix.elevateFailed'   = 'Windows heeft het beheerdersvenster niet gestart ({0}).'
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
    if ($null -eq $line) { return '' }
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
        ?  AI chat    0  back    L  language    U  undo this session's fixes    Q  quit
#>

$script:Areas = [ordered]@{
    A = @('A1', 'A2', 'A3', 'A4')
    B = @('B1', 'B2', 'B3')
    C = @('C1', 'C2', 'C3')
    D = @('D1', 'D2', 'D3', 'D4')
    E = @('E1', 'E2', 'E3')
    F = @('F1', 'F2', 'F3')
}

<#
    Turn what was typed into one decision. Pure: no output, no state, so the
    tests can cover every kind of input.

    Kind is one of: empty, area, problem, ai, back, language, undo, quit,
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
    Write-Option '?' (T 'menu.ai')
    Write-Host ''
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
    Write-Option '?' (T 'area.ai')
    Write-Host ''
    Write-OptionRow (@(, @('0', (T 'menu.back'))) + (Get-HcFooter))
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'area.hint') }
}

# The footer keys shared by every menu screen. U only shows once something
# was changed in this session.
function Get-HcFooter {
    $row = @(, @('L', (T 'menu.language')))
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

    while (@($report.Actions).Count -gt 0 -or @(Get-HcSteps $report).Count -gt 0) {
        $result = Invoke-HcActionMenu $report
        if ($result -eq 'back') { return }
        if ($result -eq 'changed') {
            Write-Host ''
            Write-Dim (T 'fix.checkingAgain')
            Write-Host ''
            $report = & $check
            Write-HcReport $report
            Save-HcVisit $Code $report
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

# Phase 0 placeholder for the AI chat. It already tells the offline case
# apart, because that answer stays the same once the chat exists.
function Invoke-HcAi {
    param([pscustomobject]$Environment, [string]$Text)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ?  ' + (T 'ai.title')) -ForegroundColor Yellow
    Write-Host ''
    if ($Text) { Write-Dim (T 'ai.youTyped' $Text) }
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
    } else {
        Write-Warn2 (T 'ai.notBuilt')
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

# ---------------------------------------------------------------- main loop --

function Start-Housecall {
    param(
        [switch]$DryRun,
        [string]$Lang,
        # A problem code to open straight away, e.g. after restarting as admin.
        [string]$Start,
        # For tests: answers to feed in instead of reading the keyboard.
        [string[]]$Answers
    )

    $script:DryRun = [bool]$DryRun
    $script:HcChanges.Clear()
    $script:HcVisit.Clear()
    $script:HandedOff = $false
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

    $first = Resolve-HcChoice $Start
    if ($first.Kind -eq 'problem') {
        $area = $first.Value.Substring(0, 1)
        Invoke-HcProblem $environment $first.Value
    }

    while (-not $script:HandedOff) {
        if ($area) { Show-HcArea $environment $area $message } else { Show-HcHome $environment $message }
        $message = $null

        $choice = Resolve-HcChoice (Read-HcLine (T 'menu.prompt')) -CurrentArea $area
        switch ($choice.Kind) {
            'area'     { $area = $choice.Value }
            'problem'  { $area = $choice.Value.Substring(0, 1); Invoke-HcProblem $environment $choice.Value }
            'ai'       { Invoke-HcAi $environment }
            'freetext' { Invoke-HcAi $environment $choice.Value }
            'back'     { $area = '' }
            'language' { $script:Lang = if ($script:Lang -eq 'nl') { 'en' } else { 'nl' } }
            'undo'     { $message = Invoke-HcUndo }
            'unknown'  { $message = T 'menu.unknown' $choice.Value }
            'quit'     {
                Show-HcNote
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
    param([pscustomobject]$Report)
    foreach ($line in $Report.Results) {
        $style = $script:ResultStyle[$line.Status]
        Write-Host ('  ' + $style[0] + ' ') -NoNewline -ForegroundColor $style[1]
        $colour = if ($line.Status -eq 'skipped') { 'DarkGray' } else { 'Gray' }
        Write-Host $line.Text -ForegroundColor $colour
    }
    if ($Report.FindingId) {
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
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.dnsOk')

    # The web
    switch ($f.Web) {
        'ok'          { Add-HcLine $r ok (T 'net.webOk') }
        'intercepted' { Add-HcLine $r problem (T 'net.webIntercepted'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }) }
        'failed'      { Add-HcLine $r problem (T 'net.webFailed'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }) }
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
    # Not .GetNewClosure(): a closure cannot see Housecall's functions when it
    # runs through [scriptblock]::Create. A script variable carries the site.
    $script:HcSiteHost = $hostName
    {
        $base = Test-HcInternet (Get-HcNetworkFacts)
        # The internet itself is down: that is the answer, not the site.
        if ($script:InternetWorks -notcontains $base.FindingId) { return $base }
        Test-HcSite (Get-HcSiteFacts $script:HcSiteHost)
    }
}

$script:ProblemHandlers['A1'] = 'Invoke-HcA1'
$script:ProblemHandlers['A2'] = 'Invoke-HcA2'
$script:ProblemHandlers['A3'] = 'Invoke-HcA3'

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
        }
        $p = $tool.Pattern
        if ($p) {
            $entry = $installed | Where-Object { $_.DisplayName -match $p } | Select-Object -First 1
            if ($entry) {
                $found.Installed = $true
                $found.InstallDate = ConvertFrom-HcInstallDate $entry.InstallDate
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

function Invoke-HcSecurityCheck {
    param([string]$Code)
    # A script variable, not a closure; see Invoke-HcA3.
    $script:HcSecurityPlan = $script:SecurityChecks[$Code]
    { Test-HcSecurity (Get-HcSecurityFacts $script:HcSecurityPlan.Parts) $script:HcSecurityPlan.Parts $script:HcSecurityPlan.Clean }
}

function Invoke-HcF1 { Invoke-HcSecurityCheck 'F1' }
function Invoke-HcF2 { Invoke-HcSecurityCheck 'F2' }
function Invoke-HcF3 { Invoke-HcSecurityCheck 'F3' }

$script:ProblemHandlers['F1'] = 'Invoke-HcF1'
$script:ProblemHandlers['F2'] = 'Invoke-HcF2'
$script:ProblemHandlers['F3'] = 'Invoke-HcF3'

# ==================================================== src\fixes.ps1 ==
<#
    Fixes: the only code in Housecall that changes the PC.

    Every fix is on this list; nothing else, and never the AI, may change
    anything. A report offers fixes (Add-HcAction), the person picks one and
    confirms it, and only then does Apply run. Each fix says:

      Label    fix.<id> in strings.ps1, filled from the target, and
               fix.<id>.done for the note and undo ("Disabled task X")
      Note     undo = can be undone, safe = harmless and needs no undo,
               restart = closes a program, which can simply be started again
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

    try {
        & $fix.Apply $action.Target
    } catch {
        Write-Warn2 (T 'fix.failed' $_.Exception.Message)
        return 'none'
    }
    $done = T ('fix.' + $action.FixId + '.done') $action.Target.Label
    [void]$script:HcChanges.Add([pscustomobject]@{ FixId = $action.FixId; Target = $action.Target; Label = $done })
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

# Your contact line for the bottom of the note, e.g. 'Shamil, 06-12345678'.
# Left empty, the "Questions?" part is simply not shown.
$script:Contact = ''

# The problems opened in this session, each with its latest finding (the
# one after any fixes). Filled by Invoke-HcProblem.
$script:HcVisit = New-Object System.Collections.ArrayList

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
    $visits = @($script:HcVisit)
    if ($visits.Count -eq 0) { return @() }
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }

    & $block 'title' (T 'note.title' $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture)))

    & $block 'heading' (T 'note.asked')
    foreach ($v in $visits) { & $block 'text' (T "problem.$($v.Code)") }

    & $block 'heading' (T 'note.found')
    foreach ($v in $visits | Where-Object { $_.FindingId }) {
        $all = @('finding.' + $v.FindingId) + @($v.FindingArgs)
        & $block 'text' (T @all)
    }

    & $block 'heading' (T 'note.done')
    $changes = @($script:HcChanges)
    if ($changes.Count -eq 0) {
        & $block 'text' (T 'note.nothingChanged')
    } else {
        foreach ($c in $changes) { & $block 'text' $c.Label }
    }

    if ($script:Contact) {
        & $block 'heading' (T 'note.contact')
        & $block 'text' $script:Contact
    }
    & $block 'small' (T 'note.footer')
}

function Show-HcNote {
    $blocks = @(Get-HcNoteBlocks)
    if ($blocks.Count -eq 0) { return }

    # A scripted run (the tests) prints the note instead of opening a window.
    if ($null -ne $script:HcInputQueue) {
        Write-Host ''
        foreach ($b in $blocks) { Write-Host ('  [note] ' + $b.Text) }
        return
    }
    try {
        if ($script:NoConsole) { throw 'nobody to close a window' }
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        Show-HcNoteWindow $blocks
    } catch {
        # No desktop to show a window on: show the note in the console.
        Write-Host ''
        foreach ($b in $blocks) { Write-Host ('  ' + $b.Text) }
    }
}

function Show-HcNoteWindow {
    param([object[]]$Blocks)
    [Windows.Forms.Application]::EnableVisualStyles()
    $family = 'Segoe UI'
    $script:HcNoteFonts = @{
        title   = New-Object Drawing.Font($family, 20, [Drawing.FontStyle]::Bold)
        heading = New-Object Drawing.Font($family, 14, [Drawing.FontStyle]::Bold)
        text    = New-Object Drawing.Font($family, 13)
        small   = New-Object Drawing.Font($family, 10, [Drawing.FontStyle]::Italic)
    }
    $script:HcNoteBlocks = $Blocks

    $form = New-Object Windows.Forms.Form
    $form.Text = T 'note.windowTitle'
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
        $gap = if ($b.Style -in @('heading', 'small')) { "`n" } else { '' }
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
    $close.Add_Click({ $this.FindForm().Close() })
    $form.CancelButton = $close

    $print = New-Object Windows.Forms.Button
    $print.Text = T 'note.print'
    $print.Size = New-Object Drawing.Size(150, 44)
    $print.Font = New-Object Drawing.Font($family, 12)
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
            if ($b.Style -in @('heading', 'small')) { $y += $font.GetHeight($e.Graphics) * 0.6 }
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
'@


. ([scriptblock]::Create($HcSource))
$script:HcSource = $HcSource
Start-Housecall -DryRun:$DryRun -Lang $Lang -Start $Start
