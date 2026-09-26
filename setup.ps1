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
    [string]$Lang
)

$ErrorActionPreference = 'Stop'


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
        ?  AI chat       0  back       L  language       Q  quit
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

    Kind is one of: empty, area, problem, ai, back, language, quit,
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
    Write-OptionRow @(@('L', (T 'menu.language')), @('Q', (T 'menu.quit')))
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
    Write-OptionRow @(@('0', (T 'menu.back')), @('L', (T 'menu.language')), @('Q', (T 'menu.quit')))
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'area.hint') }
}

# Runs the handler registered for $Code (see src\checks\), or says which
# checks will run once it is built.
function Invoke-HcProblem {
    param([pscustomobject]$Environment, [string]$Code)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + $Code + '  ' + (T "problem.$Code")) -ForegroundColor Yellow
    Write-Host ''
    $handler = $script:ProblemHandlers[$Code]
    if ($handler) {
        & $handler
    } else {
        Write-Warn2 (T 'problem.notBuilt')
        Write-Dim (T 'problem.willLook')
        Write-Dim ('  ' + (T ('looks.' + $Code.Substring(0, 1))))
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
        # For tests: answers to feed in instead of reading the keyboard.
        [string[]]$Answers
    )

    $script:DryRun = [bool]$DryRun
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

    $area = ''          # '' = home menu, otherwise the letter on screen
    $message = $null    # one-off warning shown under the menu

    while ($true) {
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
            'unknown'  { $message = T 'menu.unknown' $choice.Value }
            'quit'     {
                Write-Host ''
                Write-Ok (T 'goodbye')
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
    Phase 2 maps finding ids to fixes.
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
    }
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
    if ($f.Proxy) { Set-HcFinding $r 'proxy' }
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

function Invoke-HcA1 {
    Write-Dim (T 'run.checking')
    Write-Host ''
    Write-HcReport (Test-HcInternet (Get-HcNetworkFacts))
}

function Invoke-HcA2 {
    Write-Dim (T 'run.checking')
    Write-Host ''
    $facts = Get-HcNetworkFacts
    $quality = $null
    $drops = $null
    if ($facts.GatewayMs -ge 0) { $quality = Get-HcConnectionQuality $facts.Gateway }
    if ($facts.Active.IsWifi) { $drops = Get-HcWifiDrops }
    Write-HcReport (Test-HcConnectionQuality $facts $quality $drops)
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
    Write-Dim (T 'run.checking')
    Write-Host ''

    $base = Test-HcInternet (Get-HcNetworkFacts)
    if ($script:InternetWorks -notcontains $base.FindingId) {
        # The internet itself is down: that is the answer, not the site.
        Write-HcReport $base
        return
    }
    Write-HcReport (Test-HcSite (Get-HcSiteFacts $hostName))
}

$script:ProblemHandlers['A1'] = 'Invoke-HcA1'
$script:ProblemHandlers['A2'] = 'Invoke-HcA2'
$script:ProblemHandlers['A3'] = 'Invoke-HcA3'


Start-Housecall -DryRun:$DryRun -Lang $Lang
