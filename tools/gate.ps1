# tools/gate.ps1: the merge gates in concurrent lanes, the bulletproofing check and the worktree chores
# (Windows PowerShell 5.1). The twin of tools/gate; both call tools\lib\gate.mjs.
#
#   tools\gate.ps1 check|fast|strict|matrix|stamp-ok|floor|fmt|wt-add|wt-gc|pin-safety [options]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\gate.ps1 ...

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$node = Find-WattlandsCommand @('node')
if ($null -eq $node) {
    [Console]::Error.WriteLine('gate.ps1: node not found on PATH (Node 22.12+ is required)')
    exit 127
}
$nodeArgs = New-Object System.Collections.Generic.List[string]
$nodeArgs.Add((Join-Path $PSScriptRoot 'lib\gate.mjs'))
$nodeArgs.Add('--shell=ps')
$nodeArgs.AddRange([string[]]$argv)
$childEnv = @{ 'WATTLANDS_NO_HW_CONTROL' = '1'; 'WATTLANDS_NO_NETWORK_INTEGRATIONS' = '1' }
# run_sims.sh and tools/run_game_sim need Git Bash, never WSL's System32\bash.exe.
foreach ($candidate in @('C:\Program Files\Git\usr\bin\bash.exe', 'C:\Program Files\Git\bin\bash.exe')) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $childEnv['WATTLANDS_BASH'] = $candidate
        break
    }
}
$code = Invoke-WattlandsNative -FilePath $node -Arguments $nodeArgs.ToArray() -Environment $childEnv
exit $code
