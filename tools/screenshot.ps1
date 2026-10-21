# tools/screenshot.ps1: capture PNGs of a game session, a scene or an app screen (BRIEF 3.6, 7.8).
# Windows PowerShell 5.1. The twin of tools/screenshot: both are thin shims over
# tools/qa/screenshot.mjs, which runs Godot windowed through tools/godot.ps1 with
# tools/qa/screenshot_main.gd.
#
#   tools\screenshot.ps1 --game=<id> --content=<id> --at=<s>[,<s>...] [--players=<n>] [--bots=<n>]
#                        [--rider=<profile>] [--autopilot=all|none] [--seed=<n>] [--out=<dir>]
#   tools\screenshot.ps1 --scene=res://addons/wattlands/world2d/demo.tscn [--frames=<n>]
#   tools\screenshot.ps1 --app-screen=title|picker|lobby|session [--app-game=<id>] [--app-role=client|host|solo]
#   tools\screenshot.ps1 --app-screen=results [--app-riders=<1..8>]
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\screenshot.ps1 ...   (how Node tools start it)
#
# It always passes --mock-trainer and refuses to run without one (BRIEF 1).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\wrapper_common.ps1')

$argv = @(Get-WattlandsArgs -Invocation $MyInvocation -RawArgs $args)
$node = Find-WattlandsCommand @('node')
if ($null -eq $node) {
    [Console]::Error.WriteLine('screenshot.ps1: node not found on PATH (Node 22.12+ is required)')
    exit 127
}
$nodeArgs = New-Object System.Collections.Generic.List[string]
$nodeArgs.Add((Join-Path $PSScriptRoot 'qa\screenshot.mjs'))
$nodeArgs.Add('--shell=ps')
$nodeArgs.AddRange([string[]]$argv)
$childEnv = @{ 'WATTLANDS_NO_HW_CONTROL' = '1'; 'WATTLANDS_NO_NETWORK_INTEGRATIONS' = '1' }
$code = Invoke-WattlandsNative -FilePath $node -Arguments $nodeArgs.ToArray() -Environment $childEnv
exit $code
