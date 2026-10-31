# tools/godot.ps1: the only way to run Godot from PowerShell (BRIEF 2 and 7). Windows PowerShell 5.1.
# The twin of tools/godot.sh: same flags, same behaviour, same lock.
#
#   tools\godot.ps1 [wrapper flags] <godot args> [-- <user args>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\godot.ps1 ...   (how Node tools start it)
#
# Wrapper flags (consumed here, never passed to Godot; only before a literal --):
#   --lease=<n>          take n of the machine's Godot slots at once (default 1)
#   --lock-timeout=<s>   give up waiting for the slots after s seconds (default 2700): exit 75
#   --timeout=<s>        kill the whole Godot process tree after s seconds (default 1200): exit 124
#   --allow-hw           drop the hardware lock for this run (humans following docs/HARDWARE_TEST_PLAN.md only)
#   --allow-network      drop the network lock for this run (same)
#
# It sets WATTLANDS_NO_HW_CONTROL=1 and WATTLANDS_NO_NETWORK_INTEGRATIONS=1 for Godot (unless dropped),
# refuses -d and --debug, resolves the binary ($GODOT, tools\godot_bin.local here, then in the main
# checkout, then godot or godot4 on PATH), sets APPDATA to $env:WATTLANDS_USERDATA_DIR, else
# <checkout>\.userdata, except for exports, and runs Godot through tools\lib\godot_lock.mjs (slot lock,
# stdin closed, run timeout). Environment changes apply to Godot only; your PowerShell session keeps
# its own values.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

function Stop-GodotWrapper {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("godot.ps1: $Message")
    exit $Code
}

$checkout = Split-Path -Parent $PSScriptRoot
$lockJs = Join-Path $PSScriptRoot 'lib\godot_lock.mjs'
$onWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)

# ------------------------------------------------------------------ arguments
$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$allowHw = $false
$allowNet = $false
$lockOpts = New-Object System.Collections.Generic.List[string]
$godotArgs = New-Object System.Collections.Generic.List[string]
$userArgs = New-Object System.Collections.Generic.List[string]
$seenSep = $false
foreach ($a in $argv) {
    if ($seenSep) { $userArgs.Add($a); continue }
    if ($a -ceq '--') { $seenSep = $true; $userArgs.Add($a); continue }
    if ($a -ceq '--allow-hw') { $allowHw = $true; continue }
    if ($a -ceq '--allow-network') { $allowNet = $true; continue }
    if ($a -cmatch '^--(lease|lock-timeout|timeout)=') { $lockOpts.Add($a); continue }
    if ($a -cmatch '^--(lease|lock-timeout|timeout)$') { Stop-GodotWrapper 2 "$a needs a value: $a=<n>" }
    if (($a -ceq '-d') -or ($a -ceq '--debug')) {
        Stop-GodotWrapper 2 "refusing to pass $a to Godot: automated runs never start the debugger (BRIEF 7)"
    }
    $godotArgs.Add($a)
}

# ------------------------------------------------------------------ binary
function Read-GodotBinFile {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
    $line = Get-Content -LiteralPath $File -TotalCount 1
    if ($null -eq $line) { return $null }
    $line = ([string]$line).Trim()
    if ($line -eq '') { return $null }
    if (-not (Test-Path -LiteralPath $line)) {
        [Console]::Error.WriteLine("godot.ps1: $File names $line, which does not exist; trying the next candidate")
        return $null
    }
    return $line
}

function Invoke-GitQuiet {
    param([string[]]$GitArgs)
    $git = Find-WattlandsCommand @('git')
    if ($null -eq $git) { return $null }
    $r = Invoke-WattlandsCapture -FilePath $git -Arguments $GitArgs
    if ($r.Code -ne 0) { return $null }
    $first = @($r.Stdout -split "`r?`n" | Where-Object { $_.Trim() -ne '' }) | Select-Object -First 1
    if ($null -eq $first) { return $null }
    return ([string]$first).Trim()
}

function Resolve-GodotBin {
    if (-not [string]::IsNullOrEmpty($env:GODOT)) { return $env:GODOT }
    $bin = Read-GodotBinFile (Join-Path $checkout 'tools\godot_bin.local')
    if ($null -ne $bin) { return $bin }
    $common = Invoke-GitQuiet @('-C', $checkout, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if ($null -ne $common) {
        $bin = Read-GodotBinFile (Join-Path (Split-Path -Parent $common) 'tools\godot_bin.local')
        if ($null -ne $bin) { return $bin }
    }
    return (Find-WattlandsCommand @('godot', 'godot4'))
}

$godotBin = Resolve-GodotBin
if ([string]::IsNullOrEmpty($godotBin)) {
    Stop-GodotWrapper 127 'no Godot binary: set GODOT, or put its path in tools\godot_bin.local (one line), or put godot on PATH'
}

# ------------------------------------------------------------------ environment for Godot
$childEnv = @{}
if ($allowHw) {
    $childEnv['WATTLANDS_NO_HW_CONTROL'] = $null
    [Console]::Error.WriteLine('godot.ps1: hardware lock dropped for this run (--allow-hw)')
} else {
    $childEnv['WATTLANDS_NO_HW_CONTROL'] = '1'
}
if ($allowNet) {
    $childEnv['WATTLANDS_NO_NETWORK_INTEGRATIONS'] = $null
    [Console]::Error.WriteLine('godot.ps1: network lock dropped for this run (--allow-network)')
} else {
    $childEnv['WATTLANDS_NO_NETWORK_INTEGRATIONS'] = '1'
}

# ------------------------------------------------------------------ user dir per checkout
$isExport = $false
$projectPath = $null
for ($i = 0; $i -lt $godotArgs.Count; $i++) {
    $a = $godotArgs[$i]
    if ($a -ceq '--path') {
        if (($i + 1) -lt $godotArgs.Count) { $projectPath = $godotArgs[$i + 1] }
    } elseif ($a.StartsWith('--path=')) {
        $projectPath = $a.Substring(7)
    } elseif (@('--export-release', '--export-debug', '--export-pack', '--export-patch') -ccontains $a) {
        $isExport = $true
    }
}

if (-not $isExport) {
    $location = Get-Location
    if ($location.Provider.Name -eq 'FileSystem') { $cwd = $location.ProviderPath } else { $cwd = [Environment]::CurrentDirectory }
    $root = $null
    if (-not [string]::IsNullOrEmpty($projectPath)) {
        $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($cwd, $projectPath))
        if (Test-Path -LiteralPath $full -PathType Container) { $root = $full }
    } else {
        $top = Invoke-GitQuiet @('-C', $cwd, 'rev-parse', '--show-toplevel')
        if ($null -ne $top) { $root = [System.IO.Path]::GetFullPath($top) } else { $root = $cwd }
    }
    if ($null -ne $root) {
        if ([string]::IsNullOrEmpty($env:WATTLANDS_USERDATA_DIR)) {
            $userData = Join-Path $root '.userdata'
        } else {
            # Godot changes directory to --path; a relative value must not follow it.
            $userData = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($cwd, $env:WATTLANDS_USERDATA_DIR))
        }
        if (-not (Test-Path -LiteralPath $userData -PathType Container)) {
            New-Item -ItemType Directory -Path $userData -Force | Out-Null
        }
        if ($onWindows) { $childEnv['APPDATA'] = $userData } else { $childEnv['XDG_DATA_HOME'] = $userData }
    }
}

# ------------------------------------------------------------------ run under the lock
$node = Find-WattlandsCommand @('node')
if ($null -eq $node) { Stop-GodotWrapper 127 'node not found on PATH (Node 22.12+ runs the Godot lock)' }

$nodeArgs = New-Object System.Collections.Generic.List[string]
$nodeArgs.Add($lockJs)
$nodeArgs.Add('run')
$nodeArgs.AddRange($lockOpts)
$nodeArgs.Add('--')
$nodeArgs.Add($godotBin)
$nodeArgs.AddRange($godotArgs)
$nodeArgs.AddRange($userArgs)

$code = Invoke-WattlandsNative -FilePath $node -Arguments $nodeArgs.ToArray() -Environment $childEnv
exit $code
