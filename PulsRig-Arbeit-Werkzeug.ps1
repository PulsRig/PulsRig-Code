# PulsRig - Arbeitsbereich: ein Werkzeug ausführen. Wird von PulsRig.ps1 als Text geladen.
param($a)
$global:DryRun = [bool]$a.DryRun
$global:Yes = $false
$global:BoostPlan = $null
$global:RuntimePlan = $null
# die Spiel-Beschleunigung merkt sich ihren Zustand immer am festen Ort, alles andere schreibt in den Zielordner
$global:OutDir = if ($a.Name -eq 'GameBoost' -or -not $a.TargetDir) { $global:DD_BaseDir } else { $a.TargetDir }
if ($a.Name -eq 'GameBoost' -and $a.BoostPlan) {
    $global:BoostPlan = $a.BoostPlan
    if ($null -eq $global:BoostPlan.Services) { $global:BoostPlan.Services = @($script:BoostServices) }
}
if ($a.Name -eq 'GameRuntimes' -and $a.RuntimePlan) { $global:RuntimePlan = @($a.RuntimePlan) }
$script:ExitCode = 0
Invoke-Tool $a.Name | Out-Null
@{ Failed = [bool]$script:ExitCode }
