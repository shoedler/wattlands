# tools/run_game_sim.ps1: the PowerShell twin of tools/run_game_sim (Windows PowerShell 5.1).
# Runs a game headless with MockTrainer riders and writes a JSON report and FIT files (BRIEF 3.6);
# docs/GAME_SDK.md explains every flag, the slot rules and the report.
#
#   tools\run_game_sim.ps1 --game=<id> --content=<id> --players=<n> --bots=<n> --rider=<profile> `
#       --sim-speed=<x> --seed=<n> --report=<path> [--autopilot=all|none|<slot,...>] [--ftp=<w>[,<w>...]] `
#       [--unverified] [--haptics-off=<slot,...>] [--options=<json object>] [--player-options=<json array>] `
#       [--override=<json file>] [--max-sim-seconds=<n>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_game_sim.ps1 ...   (from other tools)
#
# Wrapper flags (consumed here): --godot-timeout=<s> (default 1800) and --godot-lock-timeout=<s>.
# Every rider is a MockTrainer: it sets WATTLANDS_NO_HW_CONTROL=1 and WATTLANDS_NO_NETWORK_INTEGRATIONS=1
# for Godot, refuses --allow-hw and --allow-network, adds --mock-trainer=erg and --caller-cwd, and runs
#   tools\godot.ps1 --headless --path <repo> -s tools/sdk/run_game_sim_main.gd -- <flags>
# in its own powershell -File process, so every argument (JSON included) reaches Godot unchanged.
# Exit codes as tools/run_game_sim: 0 completed, 2 flags or locks, 3 setup, 4 report, 75, 124.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$repo = Split-Path -Parent $PSScriptRoot
$timeout = '1800'
$lockTimeout = $null
$flags = New-Object System.Collections.Generic.List[string]
foreach ($a in $argv) {
    if (($a -ceq '--allow-hw') -or ($a -ceq '--allow-network')) {
        [Console]::Error.WriteLine("run_game_sim: $a is refused: simulations always ride MockTrainer with the locks on")
        exit 2
    }
    if ($a -cmatch '^--godot-timeout=(.+)$') { $timeout = $Matches[1]; continue }
    if ($a -cmatch '^--godot-lock-timeout=(.+)$') { $lockTimeout = $Matches[1]; continue }
    if (($a -cmatch '^--mock-trainer(=.*)?$') -or ($a -cmatch '^--caller-cwd=')) { continue }
    $flags.Add($a)
}

$location = Get-Location
if ($location.Provider.Name -eq 'FileSystem') { $cwd = $location.ProviderPath } else { $cwd = [Environment]::CurrentDirectory }
$powershell = (Get-Process -Id $PID).Path
$call = New-Object System.Collections.Generic.List[string]
foreach ($x in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'godot.ps1'), "--timeout=$timeout")) {
    $call.Add($x)
}
if ($null -ne $lockTimeout) { $call.Add("--lock-timeout=$lockTimeout") }
foreach ($x in @('--headless', '--path', $repo, '-s', 'tools/sdk/run_game_sim_main.gd', '--', '--mock-trainer=erg', "--caller-cwd=$cwd")) {
    $call.Add($x)
}
$call.AddRange([string[]]$flags.ToArray())
$childEnv = @{ 'WATTLANDS_NO_HW_CONTROL' = '1'; 'WATTLANDS_NO_NETWORK_INTEGRATIONS' = '1' }
$code = Invoke-WattlandsNative -FilePath $powershell -Arguments $call.ToArray() -Environment $childEnv
exit $code
