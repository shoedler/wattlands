# tests/games/tank/sim/run_sims.ps1: the PowerShell twin of run_sims.sh (Windows PowerShell 5.1). Same
# scenarios (s1-s7, s9 and s10), same report names in build/tank/sims, same checker.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests/games/tank/sim/run_sims.ps1 [s1 s2 ...]
#
# Environment: TANK_SEEDS="1 2 3", TANK_SIMS_OUT, TANK_SKIP_CHECK=1, TANK_FIT=0, TANK_GODOT_TIMEOUT.
# A run that exits non-zero stops the script (75: the Godot lock wait timed out, rerun).
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Scenarios)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = (Resolve-Path (Join-Path $here '..\..\..\..')).Path
Set-Location $repo
Remove-Item Env:FAL_KEY -ErrorAction SilentlyContinue
Remove-Item Env:WATTLANDS_ALLOW_ART -ErrorAction SilentlyContinue

$out = if ($env:TANK_SIMS_OUT) { $env:TANK_SIMS_OUT } else { 'build/tank/sims' }
$seeds = if ($env:TANK_SEEDS) { $env:TANK_SEEDS -split '\s+' } else { @('1', '2', '3') }
$timeout = if ($env:TANK_GODOT_TIMEOUT) { $env:TANK_GODOT_TIMEOUT } else { '1800' }
New-Item -ItemType Directory -Force $out | Out-Null

$Erg = 'erg:compliance=1.0'
$DynamoDrop = 'erg+cadence_drop:rpm=30,at_phase=2,at_target_pct=60,for_s=30'
$Sprinter = 'intervals:on_w=300,off_w=150,on_s=12,off_s=28,rpm=100'
$Stop = 'erg+cadence_drop:rpm=0,at_phase=2,at_target_pct=60,for_s=60'
$GunlineDrop = 'erg+cadence_drop:rpm=30,at_phase=2,at_target_pct=60,for_s=30'

function Invoke-Sim([string]$Name, [string[]]$SimArgs) {
    Write-Host "== $Name"
    $all = @('--game=tank', '--sim-speed=200', "--godot-timeout=$timeout", "--report=$out/$Name.json") + $SimArgs
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\run_game_sim.ps1') @all
    if ($LASTEXITCODE -ne 0) {
        Write-Error "run_sims: $Name failed with exit $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}
function Test-Have([string]$Name) { Test-Path "$out/$Name.json" }
function Invoke-S1Run([string]$Crew, [string]$Seed) {
    Invoke-Sim "s1_c${Crew}_seed${Seed}" @('--content=ashfall_road', "--players=$Crew", '--bots=0', "--rider=$Erg", "--seed=$Seed")
}

function Invoke-S1 { foreach ($c in 1, 2, 3) { foreach ($s in $seeds) { Invoke-S1Run $c $s } } }
function Invoke-S2 {
    Invoke-Sim 's2_c3_zero' @('--content=ashfall_road', '--players=3', '--bots=0', '--rider=zero', '--seed=1')
    Invoke-Sim 's2_c1_zero' @('--content=ashfall_road', '--players=1', '--bots=0', '--rider=zero', '--seed=1')
}
function Invoke-S3 {
    foreach ($s in $seeds) {
        if (-not (Test-Have "s1_c3_seed$s")) { Invoke-S1Run '3' $s }
        Invoke-Sim "s3_c3_c85_seed$s" @('--content=ashfall_road', '--players=3', '--bots=0', '--rider=erg:compliance=0.85', "--seed=$s")
        Invoke-Sim "s3_c3_c70_seed$s" @('--content=ashfall_road', '--players=3', '--bots=0', '--rider=erg:compliance=0.70', "--seed=$s")
    }
}
function Invoke-S4 {
    foreach ($c in 1, 2, 3) {
        Invoke-Sim "s4_drill_c$c" @('--content=drill', "--players=$c", '--bots=0', "--rider=$Erg", '--seed=1')
    }
    foreach ($s in $seeds) { foreach ($c in 1, 2, 3) { if (-not (Test-Have "s1_c${c}_seed$s")) { Invoke-S1Run "$c" $s } } }
}
function Invoke-S5 {
    Invoke-Sim 's5_c3_dynamo_drop' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$Erg", "--rider=$DynamoDrop", "--rider=$Erg", '--seed=1')
    Invoke-Sim 's5_c3_gunline_drop' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$GunlineDrop", "--rider=$Erg", "--rider=$Erg", '--seed=1')
}
function Invoke-S6 {
    Invoke-Sim 's6_c3_haptics_off' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$Erg", '--haptics-off=0', '--seed=1')
}
function Invoke-S7 {
    if (-not (Test-Have 's1_c3_seed1')) { Invoke-S1Run '3' '1' }
    Invoke-Sim 's7_c3_seed1' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$Erg", '--seed=1')
}

function Invoke-S9 {
    Invoke-Sim 's9_c1_sprint' @('--content=ashfall_road', '--players=1', '--bots=0', "--rider=$Sprinter", '--seed=1')
}

function Invoke-S10 {
    Invoke-Sim 's10_c3_clients_sprint' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$Sprinter", '--seed=1')
    Invoke-Sim 's10_c3_dynamo_stop' @('--content=ashfall_road', '--players=3', '--bots=0', "--rider=$Erg", "--rider=$Stop", "--rider=$Erg", '--seed=1')
}

$order = @('s1', 's2', 's3', 's4', 's5', 's6', 's7', 's9', 's10')
$wanted = if ($Scenarios -and $Scenarios.Count -gt 0) { $Scenarios } elseif ($env:TANK_SIMS) { $env:TANK_SIMS -split '[,\s]+' } else { $order }
foreach ($sc in $wanted) {
    if ($order -notcontains $sc) { Write-Error "run_sims: unknown scenario $sc (one of: $($order -join ' '))"; exit 2 }
}
foreach ($sc in $order) {
    if ($wanted -contains $sc) { & "Invoke-$($sc.ToUpper())" }
}

if ($env:TANK_SKIP_CHECK -ne '1') {
    $checkArgs = @($out, "--seeds=$($seeds -join ',')")
    if ($env:TANK_FIT -ne '0') { $checkArgs += '--fit' }
    if ($Scenarios -or $env:TANK_SIMS) { $checkArgs += "--only=$((($wanted | ForEach-Object { 'S' + $_.Substring(1) }) -join ','))" }
    & node tests/games/tank/sim/check_sims.mjs @checkArgs
    exit $LASTEXITCODE
}
