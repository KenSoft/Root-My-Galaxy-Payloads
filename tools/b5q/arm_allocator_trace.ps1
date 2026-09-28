#requires -Version 5.1

<#
.SYNOPSIS
Arms a narrow CPU0 allocator trace for the Flip5 payload.

.DESCRIPTION
This script configures the top-level tracefs buffer because Linux 5.15
ftrace_dump_on_oops only dumps the global trace array. It does not launch the
payload or any application. Existing trace settings and the pre-arm trace are
saved locally before tracefs is changed.

.EXAMPLE
.\arm_allocator_trace.ps1 -Serial R5CW80JV8PD -StartPfn 0x123456 `
    -PageCount 8 -StateDirectory .\diagnostics\trace-run-01

.EXAMPLE
.\arm_allocator_trace.ps1 -Serial R5CW80JV8PD -StartPfn 0x123456 `
    -EndPfnExclusive 0x12345e -StateDirectory .\diagnostics\trace-run-01
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._:-]+$')]
    [string]$Serial,

    [Parameter(Mandatory = $true)]
    [string]$StartPfn,

    [string]$EndPfnExclusive,

    [ValidateRange(1, 1048576)]
    [uint32]$PageCount = 8,

    [string[]]$AdditionalPfn = @(),

    [Parameter(Mandatory = $true)]
    [string]$StateDirectory,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TraceRoot = '/sys/kernel/tracing'
$script:Events = @(
    'mm_page_free',
    'mm_page_free_batched',
    'mm_page_pcpu_drain',
    'mm_page_alloc',
    'mm_page_alloc_zone_locked'
)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-Pfn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $clean = $Value.Trim()
    if ($clean -match '^0[xX]([0-9a-fA-F]+)$') {
        return [Convert]::ToUInt64($Matches[1], 16)
    }
    if ($clean -notmatch '^[0-9]+$') {
        throw "Invalid PFN '$Value'. Use decimal or a 0x-prefixed hexadecimal value."
    }
    return [Convert]::ToUInt64($clean, 10)
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & $script:AdbPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd([char[]]"`r`n")
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "adb exited with code $exitCode while running: adb $($Arguments -join ' ')`n$text"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = $text
    }
}

function Invoke-Root {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [switch]$AllowFailure
    )

    if ($Command.Contains("'")) {
        throw 'Internal error: root command contains an unsupported single quote.'
    }
    # adb shell otherwise reconstructs the argument vector without preserving
    # the su -c boundary. That makes pipes/redirections run as the shell UID.
    $remoteCommand = "su -c '$Command'"
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', $remoteCommand) -AllowFailure:$AllowFailure
}

function Get-RemoteValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/[A-Za-z0-9_./:-]+$')]
        [string]$Path
    )

    return (Invoke-Root -Command "cat $Path").Text
}

function Set-RemoteValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/[A-Za-z0-9_./:-]+$')]
        [string]$Path,

        [AllowEmptyString()]
        [string]$Value,

        [switch]$Append
    )

    # Base64 keeps filter expressions and restored settings out of the shell
    # grammar. Only the fixed, validated destination path is interpolated.
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value + "`n")
    $encoded = [Convert]::ToBase64String($bytes)
    $operator = if ($Append) { '>>' } else { '>' }
    [void](Invoke-Root -Command "echo $encoded | base64 -d $operator $Path")
}

function Get-SelectedTraceClock {
    param([string]$TraceClockText)

    if ($TraceClockText -match '\[([^\]]+)\]') {
        return $Matches[1]
    }
    return $null
}

function Restore-TraceState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    Set-RemoteValue -Path "$script:TraceRoot/tracing_on" -Value '0'
    Set-RemoteValue -Path "$script:TraceRoot/events/enable" -Value '0'

    foreach ($eventName in $script:Events) {
        $savedEvent = $State.Previous.Events.PSObject.Properties[$eventName].Value
        $savedFilter = [string]$savedEvent.Filter
        if ([string]::IsNullOrWhiteSpace($savedFilter) -or $savedFilter -eq 'none') {
            $savedFilter = '0'
        }
        Set-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/filter" -Value $savedFilter
    }

    Set-RemoteValue -Path "$script:TraceRoot/buffer_size_kb" -Value ([string]$State.Previous.BufferSizeKb)
    Set-RemoteValue -Path "$script:TraceRoot/options/overwrite" -Value ([string]$State.Previous.Overwrite)
    Set-RemoteValue -Path "$script:TraceRoot/tracing_cpumask" -Value ([string]$State.Previous.CpuMask)

    if (-not [string]::IsNullOrWhiteSpace([string]$State.Previous.CurrentTracer)) {
        Set-RemoteValue -Path "$script:TraceRoot/current_tracer" -Value ([string]$State.Previous.CurrentTracer)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$State.Previous.SelectedTraceClock)) {
        Set-RemoteValue -Path "$script:TraceRoot/trace_clock" -Value ([string]$State.Previous.SelectedTraceClock)
    }

    Set-RemoteValue -Path "$script:TraceRoot/trace" -Value ''
    foreach ($enabledEvent in @($State.Previous.EnabledEvents)) {
        $eventText = [string]$enabledEvent
        if ($eventText -notmatch '^[A-Za-z0-9_.*-]+:[A-Za-z0-9_.*-]+$') {
            throw "Refusing to restore malformed trace event '$eventText'."
        }
        Set-RemoteValue -Path "$script:TraceRoot/set_event" -Value $eventText -Append
    }

    Set-RemoteValue -Path '/proc/sys/kernel/ftrace_dump_on_oops' -Value ([string]$State.Previous.FtraceDumpOnOops)
    Set-RemoteValue -Path "$script:TraceRoot/tracing_on" -Value ([string]$State.Previous.TracingOn)
}

$adbCommand = Get-Command adb -ErrorAction Stop
$script:AdbPath = $adbCommand.Source

$start = ConvertTo-Pfn -Value $StartPfn
if ([string]::IsNullOrWhiteSpace($EndPfnExclusive)) {
    if ($start -gt ([uint64]::MaxValue - [uint64]$PageCount)) {
        throw 'The PFN range overflows UInt64.'
    }
    $end = $start + [uint64]$PageCount
}
else {
    $end = ConvertTo-Pfn -Value $EndPfnExclusive
}
if ($end -le $start) {
    throw 'EndPfnExclusive must be greater than StartPfn.'
}

$additional = New-Object System.Collections.Generic.List[uint64]
foreach ($additionalText in $AdditionalPfn) {
    $additionalValue = ConvertTo-Pfn -Value $additionalText
    if ($additionalValue -ge $start -and $additionalValue -lt $end) {
        continue
    }
    if (-not $additional.Contains($additionalValue)) {
        [void]$additional.Add($additionalValue)
    }
}

$filterClauses = New-Object System.Collections.Generic.List[string]
[void]$filterClauses.Add(
    ('(pfn >= 0x{0:x} && pfn < 0x{1:x})' -f $start, $end)
)
foreach ($additionalValue in $additional) {
    [void]$filterClauses.Add(('pfn == 0x{0:x}' -f $additionalValue))
}
$targetFilter = $filterClauses -join ' || '

$stateDirectoryFull = [IO.Path]::GetFullPath($StateDirectory)
[void][IO.Directory]::CreateDirectory($stateDirectoryFull)
$stateFile = Join-Path $stateDirectoryFull 'trace-state.json'
$preArmTraceFile = Join-Path $stateDirectoryFull 'pre-arm-trace.txt'
if ((Test-Path -LiteralPath $stateFile) -and -not $Force) {
    throw "State file already exists: $stateFile. Use a new directory or pass -Force."
}

$deviceState = (Invoke-Adb -Arguments @('-s', $Serial, 'get-state')).Text.Trim()
if ($deviceState -ne 'device') {
    throw "Device $Serial is not ready (adb state: '$deviceState')."
}

$rootIdentity = (Invoke-Root -Command 'id').Text
if ($rootIdentity -notmatch 'uid=0\(root\)') {
    throw "KernelSU root is unavailable on ${Serial}: $rootIdentity"
}

$previousTracingOn = (Get-RemoteValue -Path "$script:TraceRoot/tracing_on").Trim()
if ($previousTracingOn -ne '0' -and -not $Force) {
    throw 'Global tracefs is already active. Refusing to replace it without -Force.'
}

$eventState = [ordered]@{}
foreach ($eventName in $script:Events) {
    $eventState[$eventName] = [ordered]@{
        Enable = (Get-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/enable").Trim()
        Filter = (Get-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/filter").Trim()
    }
}

$setEventText = Get-RemoteValue -Path "$script:TraceRoot/set_event"
$enabledEvents = @(
    $setEventText -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$traceClockText = Get-RemoteValue -Path "$script:TraceRoot/trace_clock"
$state = [ordered]@{
    SchemaVersion = 1
    ArmedAtUtc = [DateTime]::UtcNow.ToString('o')
    Serial = $Serial
    BootId = (Get-RemoteValue -Path '/proc/sys/kernel/random/boot_id').Trim()
    BuildFingerprint = (Invoke-Root -Command 'getprop ro.build.fingerprint').Text.Trim()
    RootIdentity = $rootIdentity.Trim()
    Target = [ordered]@{
        StartPfn = ('0x{0:x}' -f $start)
        EndPfnExclusive = ('0x{0:x}' -f $end)
        PageCount = [uint64]($end - $start)
        AdditionalPfns = @($additional | ForEach-Object { '0x{0:x}' -f $_ })
        Filter = $targetFilter
    }
    Previous = [ordered]@{
        TracingOn = $previousTracingOn
        CpuMask = (Get-RemoteValue -Path "$script:TraceRoot/tracing_cpumask").Trim()
        BufferSizeKb = ((Get-RemoteValue -Path "$script:TraceRoot/buffer_size_kb").Trim() -split '\s+')[0]
        Overwrite = (Get-RemoteValue -Path "$script:TraceRoot/options/overwrite").Trim()
        CurrentTracer = (Get-RemoteValue -Path "$script:TraceRoot/current_tracer").Trim()
        TraceClock = $traceClockText.Trim()
        SelectedTraceClock = Get-SelectedTraceClock -TraceClockText $traceClockText
        FtraceDumpOnOops = (Get-RemoteValue -Path '/proc/sys/kernel/ftrace_dump_on_oops').Trim()
        EnabledEvents = $enabledEvents
        Events = $eventState
    }
    Files = [ordered]@{
        PreArmTrace = $preArmTraceFile
        State = $stateFile
    }
}

$preArmTrace = (Invoke-Root -Command "cat $script:TraceRoot/trace").Text
[IO.File]::WriteAllText($preArmTraceFile, $preArmTrace + "`n", $script:Utf8NoBom)
[IO.File]::WriteAllText(
    $stateFile,
    (($state | ConvertTo-Json -Depth 8) + "`n"),
    $script:Utf8NoBom
)

$configurationStarted = $false
try {
    $configurationStarted = $true
    Set-RemoteValue -Path "$script:TraceRoot/tracing_on" -Value '0'
    Set-RemoteValue -Path "$script:TraceRoot/events/enable" -Value '0'
    Set-RemoteValue -Path "$script:TraceRoot/buffer_size_kb" -Value '16'
    Set-RemoteValue -Path "$script:TraceRoot/options/overwrite" -Value '1'
    Set-RemoteValue -Path "$script:TraceRoot/tracing_cpumask" -Value '1'
    Set-RemoteValue -Path "$script:TraceRoot/trace" -Value ''

    foreach ($eventName in $script:Events) {
        Set-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/filter" -Value $state.Target.Filter
        Set-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/enable" -Value '1'
    }

    Set-RemoteValue -Path '/proc/sys/kernel/ftrace_dump_on_oops' -Value '1'
    Set-RemoteValue -Path "$script:TraceRoot/tracing_on" -Value '1'

    $verification = [ordered]@{
        TracingOn = (Get-RemoteValue -Path "$script:TraceRoot/tracing_on").Trim()
        CpuMask = (Get-RemoteValue -Path "$script:TraceRoot/tracing_cpumask").Trim()
        BufferSizeKb = ((Get-RemoteValue -Path "$script:TraceRoot/buffer_size_kb").Trim() -split '\s+')[0]
        Overwrite = (Get-RemoteValue -Path "$script:TraceRoot/options/overwrite").Trim()
        FtraceDumpOnOops = (Get-RemoteValue -Path '/proc/sys/kernel/ftrace_dump_on_oops').Trim()
        Events = [ordered]@{}
    }
    foreach ($eventName in $script:Events) {
        $verification.Events[$eventName] = [ordered]@{
            Enable = (Get-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/enable").Trim()
            Filter = (Get-RemoteValue -Path "$script:TraceRoot/events/kmem/$eventName/filter").Trim()
        }
    }

    # tracefs normalizes hexadecimal CPU masks (for example 1 -> 01) and
    # rounds ring-buffer storage to its internal page geometry (16 -> 19 on
    # this kernel). Verify the effective constraints, not textual identity.
    $cpuMaskOk = $verification.CpuMask -match '^0*1$'
    $bufferSizeOk = [uint64]$verification.BufferSizeKb -ge 16
    if ($verification.TracingOn -ne '1' -or
        -not $cpuMaskOk -or
        -not $bufferSizeOk -or
        $verification.Overwrite -ne '1' -or
        $verification.FtraceDumpOnOops -ne '1') {
        throw "Tracefs verification failed: $($verification | ConvertTo-Json -Depth 6 -Compress)"
    }
    foreach ($eventName in $script:Events) {
        if ($verification.Events[$eventName].Enable -ne '1' -or
            $verification.Events[$eventName].Filter -eq 'none') {
            throw "Trace event verification failed for kmem:$eventName."
        }
    }

    $state['Verification'] = $verification
    [IO.File]::WriteAllText(
        $stateFile,
        (($state | ConvertTo-Json -Depth 8) + "`n"),
        $script:Utf8NoBom
    )
}
catch {
    $armError = $_
    if ($configurationStarted) {
        try {
            Restore-TraceState -State ([pscustomobject](ConvertFrom-Json ([IO.File]::ReadAllText($stateFile))))
        }
        catch {
            Write-Warning "Automatic tracefs rollback also failed: $($_.Exception.Message)"
        }
    }
    throw $armError
}

Write-Host "Allocator tracing is armed on $Serial."
Write-Host "PFN filter: $($state.Target.Filter)"
Write-Host "State: $stateFile"
Write-Host 'No exploit or application was started.'
