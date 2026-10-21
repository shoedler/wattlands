# tools/env.ps1: the hardware and network locks for this PowerShell session (BRIEF 1).
#
#   . .\tools\env.ps1     (dot-source it; environment variables are process-wide, so plain .\tools\env.ps1 works too)
#
# It sets exactly these two variables and leaves every other variable alone,
# including the art pipeline's, which only Simon sets (BRIEF 3.10).
$env:WATTLANDS_NO_HW_CONTROL = '1'
$env:WATTLANDS_NO_NETWORK_INTEGRATIONS = '1'
