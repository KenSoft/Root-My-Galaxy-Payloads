#requires -Version 5.1

<#
.SYNOPSIS
Stops a Flip5 allocator trace, collects diagnostics, and restores tracefs.

.DESCRIPTION
The matching arm script records every setting this script changes. Collection
stops tracing first, copies the global trace and runtime diagnostics to the
requested directory, collects pstore and last_kmsg when available, and restores
the prior trace configuration when the device is still on the same boot.

.EXAMPLE
.\collect_allocator_trace.ps1 -Serial R5CW80JV8PD `
    -StateFile .\diagnostics\trace-run-01\trace-state.json `
    -OutputDirectory .\diagnostics\trace-run-01\collected
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._:-]+$')]
    [string]$Serial,

    [Parameter(Mandatory = $true)]
    [string]$StateFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

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
    # Keep the entire command inside su. Without this quoting, adb's remote
    # shell applies pipes/redirections before privilege elevation.
    $remoteCommand = "su -c '$Command'"
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', $remoteCommand) -AllowFailure:$AllowFailure
}

function Get-RemoteValue {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/[A-Za-z0-9_./:-]+$')]
        [string]$Path,
        [switch]$AllowFailure
    )

    return Invoke-Root -Command "cat $Path" -AllowFailure:$AllowFailure
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

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value + "`n")
    $encoded = [Convert]::ToBase64String($bytes)
    $operator = if ($Append) { '>>' } else { '>' }
    [void](Invoke-Root -Command "echo $encoded | base64 -d $operator $Path")
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [AllowEmptyString()]
        [string]$Text
    )

    [IO.File]::WriteAllText($Path, $Text + "`n", $script:Utf8NoBom)
}

function Save-RootCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $result = Invoke-Root -Command $Command -AllowFailure
    Write-TextFile -Path (Join-Path $outputDirectoryFull $Name) -Text $result.Text
    if ($result.ExitCode -ne 0) {
        Write-Warning "Collection command failed ($Name): $Command"
    }
}

function Save-AdbShellCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $result = Invoke-Adb -Arguments @('-s', $Serial, 'shell', $Command) -AllowFailure
    Write-TextFile -Path (Join-Path $outputDirectoryFull $Name) -Text $result.Text
    if ($result.ExitCode -ne 0) {
        Write-Warning "Collection command failed ($Name): $Command"
    }
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

$stateFileFull = (Resolve-Path -LiteralPath $StateFile).Path
$state = ConvertFrom-Json ([IO.File]::ReadAllText($stateFileFull))
if ([int]$state.SchemaVersion -ne 1) {
    throw "Unsupported trace state schema: $($state.SchemaVersion)"
}
if ([string]$state.Serial -ne $Serial -and -not $Force) {
    throw "State belongs to $($state.Serial), not $Serial. Pass -Force only if this is intentional."
}

$outputDirectoryFull = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($outputDirectoryFull)
$stateCopy = Join-Path $outputDirectoryFull 'trace-state.json'
if ($stateFileFull -ne $stateCopy) {
    Copy-Item -LiteralPath $stateFileFull -Destination $stateCopy -Force
}

$deviceState = (Invoke-Adb -Arguments @('-s', $Serial, 'get-state')).Text.Trim()
if ($deviceState -ne 'device') {
    throw "Device $Serial is not ready (adb state: '$deviceState')."
}

$rootProbe = Invoke-Root -Command 'id' -AllowFailure
$hasRoot = $rootProbe.ExitCode -eq 0 -and $rootProbe.Text -match 'uid=0\(root\)'
$collection = [ordered]@{
    SchemaVersion = 1
    CollectedAtUtc = [DateTime]::UtcNow.ToString('o')
    Serial = $Serial
    RootAvailable = $hasRoot
    RootIdentity = $rootProbe.Text
    ArmedBootId = [string]$state.BootId
    CurrentBootId = $null
    SameBoot = $false
    TraceStopped = $false
    PreviousSettingsRestored = $false
    RestoreError = $null
}

if ($hasRoot) {
    $currentBoot = (Get-RemoteValue -Path '/proc/sys/kernel/random/boot_id').Text.Trim()
    $collection.CurrentBootId = $currentBoot
    $collection.SameBoot = $currentBoot -eq [string]$state.BootId

    Set-RemoteValue -Path "$script:TraceRoot/tracing_on" -Value '0'
    $collection.TraceStopped = $true

    Save-RootCommand -Name 'trace.txt' -Command "cat $script:TraceRoot/trace"
    Save-RootCommand -Name 'trace-cpu0.txt' -Command "cat $script:TraceRoot/per_cpu/cpu0/trace"
    Save-RootCommand -Name 'trace-kprobe-profile.txt' -Command "cat $script:TraceRoot/kprobe_profile"
    Save-RootCommand -Name 'dmesg.txt' -Command 'dmesg'
    Save-RootCommand -Name 'getprop.txt' -Command 'getprop'
    Save-RootCommand -Name 'proc-meminfo.txt' -Command 'cat /proc/meminfo'
    Save-RootCommand -Name 'proc-vmstat.txt' -Command 'cat /proc/vmstat'
    Save-RootCommand -Name 'proc-buddyinfo.txt' -Command 'cat /proc/buddyinfo'
    Save-RootCommand -Name 'proc-pagetypeinfo.txt' -Command 'cat /proc/pagetypeinfo'
    Save-RootCommand -Name 'proc-slabinfo.txt' -Command 'cat /proc/slabinfo'
    Save-RootCommand -Name 'pressure-memory.txt' -Command 'cat /proc/pressure/memory'
    Save-RootCommand -Name 'pressure-cpu.txt' -Command 'cat /proc/pressure/cpu'
    Save-RootCommand -Name 'pressure-io.txt' -Command 'cat /proc/pressure/io'
    Save-RootCommand -Name 'processes.txt' -Command 'ps -AZT'

    $lastKmsg = Get-RemoteValue -Path '/proc/last_kmsg' -AllowFailure
    if ($lastKmsg.ExitCode -eq 0) {
        Write-TextFile -Path (Join-Path $outputDirectoryFull 'last_kmsg.txt') -Text $lastKmsg.Text
    }

    $pstoreDirectory = Join-Path $outputDirectoryFull 'pstore'
    [void][IO.Directory]::CreateDirectory($pstoreDirectory)
    $pstoreList = Invoke-Root -Command 'ls -1 /sys/fs/pstore' -AllowFailure
    $pstoreFiles = @(
        $pstoreList.Text -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9_.-]+$' }
    )
    foreach ($pstoreFile in $pstoreFiles) {
        $pstoreResult = Invoke-Root -Command "cat /sys/fs/pstore/$pstoreFile" -AllowFailure
        Write-TextFile -Path (Join-Path $pstoreDirectory $pstoreFile) -Text $pstoreResult.Text
    }
    if ($pstoreFiles.Count -eq 0) {
        Write-TextFile -Path (Join-Path $pstoreDirectory 'EMPTY.txt') -Text 'No pstore files were present.'
    }
}
else {
    Write-Warning 'Root is unavailable. The live trace cannot be stopped or read; collecting shell-visible post-reboot data only.'
    $bootResult = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'cat', '/proc/sys/kernel/random/boot_id') -AllowFailure
    $collection.CurrentBootId = $bootResult.Text.Trim()
    $collection.SameBoot = $collection.CurrentBootId -eq [string]$state.BootId
}

Save-AdbShellCommand -Name 'logcat-all.txt' -Command 'logcat -b all -d -v threadtime'
Save-AdbShellCommand -Name 'app-exploit-log.txt' -Command 'run-as dev.kensoft.rootmygalaxy cat files/exploit.log'

if ($hasRoot -and $collection.SameBoot) {
    try {
        Restore-TraceState -State $state
        $collection.PreviousSettingsRestored = $true
    }
    catch {
        $collection.RestoreError = $_.Exception.Message
        Write-Warning "Trace data was collected, but restoring the prior tracefs settings failed: $($collection.RestoreError)"
    }
}
elseif ($hasRoot) {
    Write-Warning 'Boot ID changed; prior-boot trace settings were not applied to the new kernel instance.'
}

Write-TextFile -Path (Join-Path $outputDirectoryFull 'collection-summary.json') `
    -Text ($collection | ConvertTo-Json -Depth 6)

Write-Host "Trace collection finished: $outputDirectoryFull"
if ($collection.PreviousSettingsRestored) {
    Write-Host 'Previous tracefs settings were restored.'
}
elseif (-not $hasRoot) {
    Write-Host 'Root was unavailable; inspect logcat and obtain a bugreport/last-kmsg before the next root attempt.'
}
