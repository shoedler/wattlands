# tools/new_game.ps1: the PowerShell twin of tools/new_game (Windows PowerShell 5.1). Scaffolds a new
# game from the template (BRIEF 3.6); both run tools/lib/new_game.mjs, which explains the rules.
#
#   tools\new_game.ps1 <id> [--dry-run]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\new_game.ps1 <id>   (from other tools)
#
# Exit codes: 0 done, 1 refused (a target already exists; nothing written), 2 usage (no id or a bad id).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$node = Find-WattlandsCommand @('node')
if ($null -eq $node) {
    [Console]::Error.WriteLine('new_game.ps1: node not found on PATH (Node 22.12+ is required)')
    exit 127
}
$nodeArgs = New-Object System.Collections.Generic.List[string]
$nodeArgs.Add((Join-Path $PSScriptRoot 'lib\new_game.mjs'))
$nodeArgs.AddRange([string[]]$argv)
$code = Invoke-WattlandsNative -FilePath $node -Arguments $nodeArgs.ToArray() -Environment @{}
exit $code
