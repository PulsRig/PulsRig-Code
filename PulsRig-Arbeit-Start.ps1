# PulsRig - Arbeitsbereich: richtet ihn ein. Wird von PulsRig.ps1 als Text geladen und dort ausgeführt.
# die Namen dürfen nicht mit den Parametern des eingebundenen Skripts zusammenfallen (z.B. $OutDir):
# beide landen im selben Bereich, und das Skript würde sie mit seinen Vorgabewerten überschreiben
param($ddBackendPath, $ddTargetDir, $ddBackendCode, $ddToolsCode)
$ErrorActionPreference = 'Stop'
# der Ordner des Programms: unter "Programme" dürfen nur Administratoren schreiben (siehe Install-CatalogDriver)
$global:DD_ProgramDir = Split-Path -Parent $ddBackendPath
if ($ddBackendCode) {
    # installiertes Programm: die beiden Skripte stecken in PulsRig.exe und kommen als Text
    $global:DD_Embedded = $true
    . ([scriptblock]::Create($ddBackendCode))
    . ([scriptblock]::Create($ddToolsCode))
}
else { . $ddBackendPath }
$global:OutDir = $ddTargetDir
$global:DD_BaseDir = $ddTargetDir

# Ausgaben, Fortschritt und Rückfragen der Skripte ans Fenster weiterreichen
function global:Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)] $Object, $ForegroundColor, $BackgroundColor, $Separator, [switch]$NoNewline)
    $text = (@($Object) | ForEach-Object { "$_" }) -join ' '
    $sync.Queue.Enqueue(@{ Type = 'log'; Text = $text; Color = "$ForegroundColor"; NoNewline = [bool]$NoNewline })
}
function global:Write-Progress {
    param([Parameter(Position = 0)] $Activity, [Parameter(Position = 1)] $Status, $PercentComplete = -1, [switch]$Completed, $Id, $CurrentOperation, $ParentId, $SecondsRemaining)
    $sync.Queue.Enqueue(@{ Type = 'progress'; Activity = "$Activity"; Status = "$Status"; Percent = [int]$PercentComplete; Completed = [bool]$Completed })
}
function global:Read-Host {
    param([Parameter(Position = 0)] $Prompt)
    [void]$sync.ReplyEvent.Reset()   # keine liegengebliebene Antwort eines abgebrochenen Laufs übernehmen
    $sync.Queue.Enqueue(@{ Type = 'input'; Text = "$Prompt" })
    [void]$sync.ReplyEvent.WaitOne()
    "$($sync.Reply)"
}
function global:Confirm-Action([string]$Question, [switch]$Optional) {
    # im Probelauf (ohne Adminrechte) wie im Skript: Hauptschritte zeigen, Zusatzschritte auslassen
    if ($DryRun) { return -not $Optional }
    [void]$sync.ReplyEvent.Reset()
    $sync.Queue.Enqueue(@{ Type = 'confirm'; Text = $Question })
    [void]$sync.ReplyEvent.WaitOne()
    [bool]$sync.Reply
}
# Tabellen passen nicht in den schmalen Dialog - jede Zeile als eine Textzeile ausgeben
function global:Show-Table($Rows) {
    foreach ($row in @($Rows)) {
        Write-Host ('  ' + (($row.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join '  ·  '))
    }
}
$sync.Queue.Enqueue(@{ Type = 'ready' })
