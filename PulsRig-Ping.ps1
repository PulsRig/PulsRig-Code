# PulsRig - Ping-Test für Spieler: Verzögerung, Schwankung und verlorene Pakete, getrennt nach "zu Hause" (Router)
# und "Internet" (drei große DNS-Anbieter, die zuverlässig auf Ping antworten). So zeigt sich, ob ein Problem im
# eigenen WLAN oder Router steckt oder auf dem Weg zum Anbieter. Viele Spieleserver beantworten keinen Ping - darum
# bewusst keine Spieleserver als Ziel. Wird von PulsRig.ps1 nach PulsRig-Monitor.ps1 eingebunden.
# Einstieg: "Was ist los?" → Internet.

$script:Queries.Ping = @'
param($a)
$r = @{ Targets = @(); Link = ''; Adapter = ''; Rounds = 20 }
# Router: das Standard-Gateway des Netzwerkadapters, über den der Weg ins Internet führt
$gateway = ''
try {
    $config = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -ErrorAction Stop | Where-Object { @($_.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }).Count -gt 0 } | Sort-Object { [int]$_.IPConnectionMetric })[0]
    if ($config) {
        $gateway = @($config.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })[0]
        $adapter = Get-CimInstance Win32_NetworkAdapter -Filter "Index = $($config.Index)" -ErrorAction SilentlyContinue
        $r.Adapter = "$($adapter.Name)"
        # WLAN oder Kabel: aus dem Medium des Adapters, notfalls aus dem Namen
        $wifi = $false
        try { $net = Get-CimInstance -Namespace root\StandardCimv2 -ClassName MSFT_NetAdapter -Filter "InterfaceIndex = $($config.InterfaceIndex)" -ErrorAction Stop; $wifi = [int]$net.NdisPhysicalMedium -eq 9 } catch { }
        if (-not $wifi -and "$($adapter.Name) $($adapter.NetConnectionID)" -match 'Wi-?Fi|WLAN|Wireless|802\.11') { $wifi = $true }
        $r.Link = if ($wifi) { 'wifi' } else { 'cable' }
    }
}
catch { }
$targets = @()
if ($gateway) { $targets += @{ Name = 'Router'; Address = $gateway; Kind = 'home' } }
$targets += @{ Name = 'Cloudflare'; Address = '1.1.1.1'; Kind = 'net' }
$targets += @{ Name = 'Google'; Address = '8.8.8.8'; Kind = 'net' }
$targets += @{ Name = 'Quad9'; Address = '9.9.9.9'; Kind = 'net' }
# alle Ziele je Runde gleichzeitig anpingen: 20 Runden dauern so nur rund acht Sekunden
$times = @{}; foreach ($t in $targets) { $times[$t.Address] = New-Object Collections.Generic.List[double] }
$lost = @{}; foreach ($t in $targets) { $lost[$t.Address] = 0 }
for ($round = 0; $round -lt $r.Rounds; $round++) {
    $pending = @()
    foreach ($t in $targets) { $ping = New-Object Net.NetworkInformation.Ping; $pending += @{ Address = $t.Address; Ping = $ping; Task = $ping.SendPingAsync($t.Address, 1000) } }
    foreach ($p in $pending) {
        try {
            $reply = $p.Task.GetAwaiter().GetResult()
            if ($reply.Status -eq 'Success') { $times[$p.Address].Add([double]$reply.RoundtripTime) } else { $lost[$p.Address]++ }
        }
        catch { $lost[$p.Address]++ }
        finally { $p.Ping.Dispose() }
    }
    Start-Sleep -Milliseconds 250
}
foreach ($t in $targets) {
    $list = $times[$t.Address]
    $entry = @{ Name = $t.Name; Address = $t.Address; Kind = $t.Kind; Sent = $r.Rounds; Lost = $lost[$t.Address]; Avg = $null; Min = $null; Max = $null; Jitter = $null; Series = @($list) }
    if ($list.Count -gt 0) {
        $entry.Avg = ($list | Measure-Object -Average).Average
        $entry.Min = ($list | Measure-Object -Minimum).Minimum
        $entry.Max = ($list | Measure-Object -Maximum).Maximum
        # Schwankung: mittlerer Unterschied zwischen zwei aufeinanderfolgenden Antworten
        $diffs = for ($i = 1; $i -lt $list.Count; $i++) { [Math]::Abs($list[$i] - $list[$i - 1]) }
        $entry.Jitter = if (@($diffs).Count) { (@($diffs) | Measure-Object -Average).Average } else { 0.0 }
    }
    $r.Targets += $entry
}
$r
'@

function Open-PingSheet {
    $opened = Open-Sheet @{
        Title     = 'Ping-Test'
        Sub       = 'Wie schnell und stabil die Verbindung ist – zu Hause und ins Internet'
        Glyph     = 0xE774
        Primary   = 'Neu messen'
        Show      = { param($tab) Show-PingTab }
        OnPrimary = { Start-PingMeasure }
        OnAction  = { param($item) if ($item.Data -and $item.Data.Do -eq 'fix') { Close-Sheet; Invoke-Later 350 { Open-Tool 'FixNetwork' } } }
    }
    if (-not $opened) { return }
    Start-PingMeasure
}

function Start-PingMeasure {
    $script:Sheet.Ping = $null
    $ui.SheetChips.Children.Clear()
    Start-SheetLoader 'Messe 20 Runden zu Router und Internet (etwa zehn Sekunden) …'
    Start-Query 'Ping' { param($result) Complete-PingQuery $result }
}

# "12 ms"; unter einer Millisekunde (Router am Kabel) "unter 1 ms"
function Format-PingMs([double]$Ms) { if ($Ms -lt 1) { 'unter 1 ms' } else { '{0:N0} ms' -f $Ms } }

# Bewertung einer Strecke: Ton und kurze Einordnung
function Get-PingTone($Target) {
    if ($null -eq $Target.Avg) { return 'bad' }
    $loss = 100.0 * $Target.Lost / [Math]::Max(1, $Target.Sent)
    if ($Target.Kind -eq 'home') {
        if ($loss -gt 0 -or $Target.Avg -gt 20 -or $Target.Jitter -gt 10) { return 'warn' }
        return 'good'
    }
    if ($loss -ge 5 -or $Target.Avg -gt 80) { return 'bad' }
    if ($loss -gt 0 -or $Target.Avg -gt 40 -or $Target.Jitter -gt 15) { return 'warn' }
    'good'
}

function Complete-PingQuery($Result) {
    if (-not $script:Sheet -or $script:Sheet.Title -ne 'Ping-Test') { return }
    $script:Sheet.Ping = $Result
    $best = @($Result.Targets | Where-Object { $_.Kind -eq 'net' -and $null -ne $_.Avg } | Sort-Object Avg)[0]
    if ($best) { Set-CardState 'Ping' @{ Text = ('{0:N0} ms' -f $best.Avg); Tone = (Get-PingTone $best) } }
    Show-PingTab
}

function Show-PingTab {
    $data = $script:Sheet.Ping
    if (-not $data) { Start-SheetLoader 'Messe 20 Runden zu Router und Internet (etwa zehn Sekunden) …'; return }
    $ui.SheetChips.Children.Clear()
    $rows = @()
    $router = @($data.Targets | Where-Object { $_.Kind -eq 'home' })[0]
    $net = @($data.Targets | Where-Object { $_.Kind -eq 'net' })
    $reach = @($net | Where-Object { $null -ne $_.Avg })
    $best = @($reach | Sort-Object Avg)[0]
    $routerTone = if ($router) { Get-PingTone $router } else { '' }
    $netTone = if ($best) { Get-PingTone $best } else { 'bad' }
    if ($best) { Add-ResultChip ('Internet ' + (Format-PingMs $best.Avg)) $(switch ($netTone) { 'good' { 'Good' } 'warn' { 'Warn' } default { 'Bad' } }) $ui.SheetChips }
    if ($router -and $null -ne $router.Avg) { Add-ResultChip ('Router ' + (Format-PingMs $router.Avg)) $(if ($routerTone -eq 'good') { 'Good' } else { 'Warn' }) $ui.SheetChips }

    # Einordnung zuerst: wo liegt das Problem?
    $rows += New-SheetRow -Kind 'head' -Title 'EINORDNUNG'
    if ($reach.Count -eq 0) {
        $rows += New-SheetRow -Title 'Keine Antwort aus dem Internet' -Sub 'Keiner der drei Anbieter hat geantwortet. Entweder ist die Verbindung weg, oder eine Firewall blockiert Ping.' -Glyph 0xE7BA -Tone 'bad' -Action 'Netzwerk reparieren' -Data @{ Do = 'fix' }
    }
    elseif ($routerTone -eq 'warn') {
        $rows += New-SheetRow -Title 'Das Problem liegt zu Hause' -Sub $(if ($data.Link -eq 'wifi') { 'Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Typisch für WLAN: näher an den Router, ein anderes Funkband (5 GHz) oder ein Netzwerkkabel helfen meist.' } else { 'Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Kabel, Anschluss und Router prüfen; ein Neustart des Routers hilft oft.' }) -Glyph 0xE7BA -Tone 'warn'
    }
    elseif ($netTone -eq 'good') {
        $rows += New-SheetRow -Title 'Alles im grünen Bereich' -Sub ('Zu Hause stabil, ins Internet {0:N0} ms ohne nennenswerte Schwankung. Das reicht auch für schnelle Shooter.' -f $best.Avg) -Glyph 0xE73E -Tone 'good'
    }
    else {
        $rows += New-SheetRow -Title 'Zu Hause stabil, der Weg ins Internet nicht' -Sub 'Bis zum Router ist alles in Ordnung; die Verzögerung oder die Aussetzer entstehen beim Anbieter oder auf dem Weg dorthin. Zu einer anderen Tageszeit noch einmal messen; bleibt es so, hilft nur der Anbieter.' -Glyph 0xE7BA -Tone $netTone
    }
    if ($data.Link) {
        $rows += New-SheetRow -Title $(if ($data.Link -eq 'wifi') { 'Verbunden über WLAN' } else { 'Verbunden über Kabel' }) -Sub $(if ($data.Link -eq 'wifi') { 'Für Spiele ist ein Netzwerkkabel stabiler: WLAN schwankt durch Wände, Nachbarnetze und andere Geräte.' } else { 'Die stabilste Verbindung für Spiele.' }) -Glyph $(if ($data.Link -eq 'wifi') { 0xE701 } else { 0xE839 }) -Tone $(if ($data.Link -eq 'wifi') { 'accent' } else { 'good' })
    }
    $rows += New-SheetRow -Kind 'head' -Title 'MESSUNG (20 RUNDEN JE ZIEL)'
    foreach ($target in @($data.Targets)) {
        $label = if ($target.Kind -eq 'home') { 'Router (zu Hause)' } else { "$($target.Name) (Internet)" }
        if ($null -eq $target.Avg) {
            $rows += New-SheetRow -Title $label -Sub "Keine Antwort von $($target.Address)" -Glyph 0xE774 -Tone 'bad' -State 'keine Antwort'
            continue
        }
        $loss = [int][Math]::Round(100.0 * $target.Lost / [Math]::Max(1, $target.Sent))
        $tone = Get-PingTone $target
        $rows += New-SheetRow -Title $label -Sub ('Schnitt {0:N0} ms · schnellste {1:N0} · langsamste {2:N0} · Schwankung {3:N0} ms · {4} % verloren' -f $target.Avg, $target.Min, $target.Max, $target.Jitter, $loss) `
            -Glyph $(if ($target.Kind -eq 'home') { 0xE80F } else { 0xE774 }) -Tone $tone -State (Format-PingMs $target.Avg)
    }
    $rows += New-SheetRow -Kind 'head' -Title 'SO LIEST MAN DAS'
    $rows += New-SheetRow -Title 'Ping (Verzögerung)' -Sub 'Bis 30 ms ist sehr gut, bis 60 ms für die meisten Spiele in Ordnung. Zum Spieleserver kommt je nach Entfernung noch etwas dazu.' -Glyph 0xE916 -Tone 'accent'
    $rows += New-SheetRow -Title 'Schwankung und Verlust' -Sub 'Stärker als ein hoher Ping stören Sprünge und verlorene Pakete: Figuren springen, Treffer zählen nicht. Mehr als 1 % Verlust spürt man.' -Glyph 0xE9D9 -Tone 'accent'
    Show-SheetList $rows
    Set-SheetStateText 'Gemessen mit Ping zu Router, Cloudflare, Google und Quad9'
}
