# tools/run_tests.ps1: every gate in BRIEF 7, in one command (Windows PowerShell 5.1).
# The twin of tools/run_tests: same options, same steps; Godot steps run through tools/godot.ps1.
#
#   tools\run_tests.ps1 [--only=<step,...>] [--skip=<step,...>] [--min-count=<n>] [--gdir=<res path>]
#                       [--gut-arg=<arg>]... [--no-lint] [--project=<dir>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_tests.ps1 ...
#
# Steps: import (never a gate), gut, scaffold, static, sim, fit, node, e2e. Exits non-zero if any
# gate failed and prints a summary table. Each step is one function in tools\lib\run_tests.mjs.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$node = Find-WattlandsCommand @('node')
if ($null -eq $node) {
    [Console]::Error.WriteLine('run_tests.ps1: node not found on PATH (Node 22.12+ is required)')
    exit 127
}
$nodeArgs = New-Object System.Collections.Generic.List[string]
$nodeArgs.Add((Join-Path $PSScriptRoot 'lib\run_tests.mjs'))
$nodeArgs.Add('--shell=ps')
$nodeArgs.AddRange([string[]]$argv)
$childEnv = @{ 'WATTLANDS_NO_HW_CONTROL' = '1'; 'WATTLANDS_NO_NETWORK_INTEGRATIONS' = '1' }
$code = Invoke-WattlandsNative -FilePath $node -Arguments $nodeArgs.ToArray() -Environment $childEnv
exit $code
