# tools/lib/wrapper_common.ps1: helpers shared by tools/godot.ps1 and tools/run_tests.ps1.
# Windows PowerShell 5.1: no ternary, no &&, no ?? operators.
#
# Get-WattlandsArgs returns the script's arguments as the caller typed them. Started with
# "powershell -File", PowerShell passes them through untouched. Called directly from a PowerShell
# prompt or script, it drops a bare -- separator, splits -gdir=res://tests at the colon and turns
# a,b into an array; this rebuilds the typed text from the parser's view of the calling line.
#
# Invoke-WattlandsNative starts a native program with exact Windows argument quoting (Windows
# PowerShell 5.1 drops embedded double quotes when it calls a native program itself), in the
# caller's current location, with temporary environment changes that do not leak into the session.

$script:WattlandsSep = [string][char]0 + 'wattlands-separator'

function ConvertTo-WattlandsWinArg {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq [char]'\') {
            $backslashes++
        } elseif ($ch -eq [char]'"') {
            [void]$sb.Append([string]::new([char]'\', $backslashes * 2 + 1))
            [void]$sb.Append('"')
            $backslashes = 0
        } else {
            if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]'\', $backslashes)) }
            $backslashes = 0
            [void]$sb.Append($ch)
        }
    }
    if ($backslashes -gt 0) { [void]$sb.Append([string]::new([char]'\', $backslashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-WattlandsArgsFromLine {
    # Returns the arguments of the command that starts at $Offset (1-based) in $Line, with
    # $script:WattlandsSep for a bare --, or $null when an argument is not a plain constant.
    param([string]$Line, [int]$Offset)
    $tokens = $null
    $errors = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
    } catch {
        return $null
    }
    $start = $Offset - 1
    $cmd = $ast.Find({
            param($node)
            ($node -is [System.Management.Automation.Language.CommandAst]) -and ($node.Extent.StartOffset -eq $start)
        }, $true)
    if ($null -eq $cmd) { return $null }
    $out = New-Object System.Collections.Generic.List[string]
    $elements = $cmd.CommandElements
    $prevEnd = -1
    $prevWasSep = $false
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $e = $elements[$i]
        $isSep = $false
        if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($e.Extent.Text -eq '--') { $text = $script:WattlandsSep; $isSep = $true } else { $text = $e.Extent.Text }
        } elseif ($e -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $text = $e.Value
        } elseif ($e -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($sub in $e.Elements) {
                if ($sub -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $parts.Add($sub.Value)
                } else {
                    return $null
                }
            }
            $text = ($parts.ToArray() -join ',')
        } else {
            return $null
        }
        # Elements with no whitespace between them were one word that the tokenizer split (-x=res://y).
        if (-not $isSep -and -not $prevWasSep -and $out.Count -gt 0 -and $e.Extent.StartOffset -eq $prevEnd) {
            $out[$out.Count - 1] = $out[$out.Count - 1] + $text
        } else {
            $out.Add($text)
        }
        $prevEnd = $e.Extent.EndOffset
        $prevWasSep = $isSep
    }
    return , $out.ToArray()
}

function Get-WattlandsArgs {
    # Writes each argument to the pipeline; call it as @(Get-WattlandsArgs ...).
    param($Invocation, [object[]]$RawArgs)
    $flat = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($RawArgs)) {
        if ($a -is [System.Array]) {
            $flat.Add((@($a | ForEach-Object { [string]$_ }) -join ','))
        } else {
            $flat.Add([string]$a)
        }
    }
    $line = $Invocation.Line
    if ([string]::IsNullOrEmpty($line)) {
        foreach ($a in $flat) { Write-Output $a }
        return
    }
    $rebuilt = Get-WattlandsArgsFromLine -Line $line -Offset $Invocation.OffsetInLine
    if ($null -ne $rebuilt) {
        $plain = (@($rebuilt | Where-Object { $_ -ne $script:WattlandsSep }) -join '')
        if ($plain -ceq ($flat.ToArray() -join '')) {
            foreach ($a in $rebuilt) {
                if ($a -eq $script:WattlandsSep) { Write-Output '--' } else { Write-Output $a }
            }
            return
        }
    }
    # Fallback: rejoin -name: + value pairs that PowerShell split, and warn about a lost separator.
    $items = $flat.ToArray()
    $i = 0
    while ($i -lt $items.Count) {
        $a = $items[$i]
        if ($a.StartsWith('-') -and $a.EndsWith(':') -and ($i + 1) -lt $items.Count -and $line.Contains($a + $items[$i + 1])) {
            Write-Output ($a + $items[$i + 1])
            $i += 2
            continue
        }
        Write-Output $a
        $i++
    }
    if ($line -match '(^|\s)--(\s|$)' -and -not ($items -ccontains '--')) {
        [Console]::Error.WriteLine("warning: PowerShell dropped a bare -- separator from this call; quote it as '--'")
    }
}

function Find-WattlandsCommand {
    # The first of $Names found as a program on PATH. Scans PATH itself when Get-Command finds
    # nothing, because Get-Command needs PATHEXT, which a stripped-down environment may lack.
    param([string[]]$Names)
    foreach ($name in $Names) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd) { return $cmd.Path }
    }
    $exts = @('.exe', '.com', '')
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) { $exts = @('') }
    $dirs = @()
    if (-not [string]::IsNullOrEmpty($env:PATH)) { $dirs = $env:PATH.Split([System.IO.Path]::PathSeparator) }
    foreach ($name in $Names) {
        foreach ($dir in $dirs) {
            if ([string]::IsNullOrEmpty($dir)) { continue }
            foreach ($ext in $exts) {
                $candidate = Join-Path $dir ($name + $ext)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }
    }
    return $null
}

function Invoke-WattlandsCapture {
    # Runs $FilePath with $Arguments and returns @{ Code; Stdout }. Uses Process directly rather than
    # the & operator, which opens a program like a document (asynchronously, no output) when PATHEXT
    # is missing from the environment.
    param([string]$FilePath, [string[]]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $quoted = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Arguments)) { $quoted.Add((ConvertTo-WattlandsWinArg $a)) }
    $psi.Arguments = ($quoted.ToArray() -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        $out = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        [void]$errTask.Result
        return @{ Code = $proc.ExitCode; Stdout = $out }
    } catch {
        return @{ Code = 127; Stdout = '' }
    }
}

function Invoke-WattlandsNative {
    # Runs $FilePath with $Arguments and returns its exit code. $Environment maps variable names to
    # values for the child only ($null removes one); the session's environment is restored afterwards.
    param([string]$FilePath, [string[]]$Arguments, [hashtable]$Environment)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $quoted = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Arguments)) { $quoted.Add((ConvertTo-WattlandsWinArg $a)) }
    $psi.Arguments = ($quoted.ToArray() -join ' ')
    $psi.UseShellExecute = $false
    $location = Get-Location
    if ($location.Provider.Name -eq 'FileSystem') {
        $psi.WorkingDirectory = $location.ProviderPath
    } else {
        $psi.WorkingDirectory = [Environment]::CurrentDirectory
    }
    if ($null -eq $Environment) { $Environment = @{} }
    $saved = @{}
    foreach ($k in $Environment.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
    $proc = $null
    try {
        foreach ($k in $Environment.Keys) { [Environment]::SetEnvironmentVariable($k, $Environment[$k], 'Process') }
        $proc = [System.Diagnostics.Process]::Start($psi)
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
    $proc.WaitForExit()
    return $proc.ExitCode
}
