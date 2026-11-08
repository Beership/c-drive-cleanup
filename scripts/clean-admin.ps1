#Requires -Version 5.1
<#
.SYNOPSIS
    System-level cache cleanup. Requires an elevated PowerShell.

.DESCRIPTION
    Default behaviour is conservative: Windows Update download cache, Windows
    Temp, Prefetch, kernel reports, minidumps, and a DISM component cleanup
    that KEEPS the ability to uninstall updates.

    The destructive options below are opt-in because each one costs the user
    something (rollback ability, hibernate, or fast startup):

      -ResetBase           shrinks WinSxS further but installed updates can no
                           longer be uninstalled
      -DisableHibernate    deletes hiberfil.sys (often 8-32 GB) and turns off
                           hibernate + fast startup; reverse with powercfg -h on
      -DeleteRestorePoints deletes all system restore points
      -RemoveWindowsOld    deletes C:\Windows.old after taking ownership
      -SkipDism            skip the DISM component cleanup (it is slow)

.PARAMETER DryRun
    Report sizes and planned actions without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean-admin.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean-admin.ps1 -DisableHibernate -RemoveWindowsOld
#>
param(
    [switch]$DryRun,
    [switch]$ResetBase,
    [switch]$DisableHibernate,
    [switch]$DeleteRestorePoints,
    [switch]$RemoveWindowsOld,
    [switch]$SkipDism
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host 'This script needs administrator rights.' -ForegroundColor Red
    Write-Host 'Open PowerShell with "Run as administrator" and run it again.'
    Write-Host ''
    Write-Host 'Without elevation you can still run clean-safe.ps1, which handles'
    Write-Host 'all user-level caches (GPU shaders, temp, browser, updaters).'
    exit 1
}

function Get-FolderSize {
    param([string]$Path)
    $sum = 0
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
    } catch { }
    if ($null -eq $sum) { $sum = 0 }
    return [int64]$sum
}

$results = New-Object System.Collections.ArrayList
$freeBefore = (Get-PSDrive C).Free

function Clear-SystemFolder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $before = Get-FolderSize $Path
    if ($DryRun) {
        [void]$results.Add([PSCustomObject]@{ Item = $Label; MB = [math]::Round($before/1MB,0); Status = 'DRY-RUN' })
        return
    }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    $after = Get-FolderSize $Path
    $status = 'OK'
    if ($after -gt 1MB) { $status = 'PARTIAL (in use)' }
    [void]$results.Add([PSCustomObject]@{
        Item = $Label; MB = [math]::Round(($before-$after)/1MB,0); Status = $status
    })
}

# ---------------------------------------------------------------- Windows Update
Write-Host 'Stopping Windows Update services...'
if (-not $DryRun) {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service -Name bits     -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host 'Clearing Windows Update cache...'
Clear-SystemFolder 'C:\Windows\SoftwareDistribution\Download'           'Windows Update download cache'
Clear-SystemFolder 'C:\Windows\SoftwareDistribution\DeliveryOptimization' 'Delivery Optimization cache'
if (-not $DryRun) {
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Start-Service -Name bits     -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- system temp
Write-Host 'Clearing system temp and diagnostics...'
Clear-SystemFolder 'C:\Windows\Temp'              'Windows Temp'
Clear-SystemFolder 'C:\Windows\Prefetch'          'Prefetch'
Clear-SystemFolder 'C:\Windows\LiveKernelReports' 'LiveKernelReports'
Clear-SystemFolder 'C:\Windows\Minidump'          'Minidump'

$dmp = 'C:\Windows\MEMORY.DMP'
if (Test-Path -LiteralPath $dmp) {
    $mb = [math]::Round((Get-Item -LiteralPath $dmp -Force).Length / 1MB, 0)
    if ($DryRun) {
        [void]$results.Add([PSCustomObject]@{ Item = 'MEMORY.DMP'; MB = $mb; Status = 'DRY-RUN' })
    } else {
        Remove-Item -LiteralPath $dmp -Force -ErrorAction SilentlyContinue
        [void]$results.Add([PSCustomObject]@{ Item = 'MEMORY.DMP'; MB = $mb; Status = 'OK' })
    }
}

# ---------------------------------------------------------------- hiberfil.sys
if ($DisableHibernate) {
    Write-Host 'Disabling hibernation...'
    $hib = 'C:\hiberfil.sys'
    $mb = 0
    if (Test-Path -LiteralPath $hib) {
        $mb = [math]::Round((Get-Item -LiteralPath $hib -Force).Length / 1MB, 0)
    }
    if ($DryRun) {
        [void]$results.Add([PSCustomObject]@{ Item = 'hiberfil.sys (would remove)'; MB = $mb; Status = 'DRY-RUN' })
    } else {
        powercfg.exe /hibernate off | Out-Null
        [void]$results.Add([PSCustomObject]@{ Item = 'hiberfil.sys'; MB = $mb; Status = 'OK (powercfg -h on to revert)' })
    }
} else {
    if (Test-Path -LiteralPath 'C:\hiberfil.sys') {
        $mb = [math]::Round((Get-Item -LiteralPath 'C:\hiberfil.sys' -Force).Length / 1MB, 0)
        Write-Host ('hiberfil.sys is {0:N0} MB - pass -DisableHibernate to reclaim it.' -f $mb) -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- restore points
if ($DeleteRestorePoints) {
    Write-Host 'Deleting system restore points...'
    if ($DryRun) {
        Write-Host '  vssadmin delete shadows /for=C: /all /quiet (dry-run)'
    } else {
        $out = vssadmin.exe delete shadows /for=C: /all /quiet 2>&1
        Write-Host ('  ' + ($out -join ' '))
    }
} else {
    $vss = vssadmin.exe list shadowstorage 2>&1
    if ($vss -match 'GB|MB') {
        Write-Host 'Existing shadow storage (pass -DeleteRestorePoints to remove):' -ForegroundColor Yellow
        $vss | Where-Object { $_ -match 'GB|MB' } | ForEach-Object { Write-Host ('  ' + $_) }
    }
}

# ---------------------------------------------------------------- Windows.old
if ($RemoveWindowsOld) {
    $old = 'C:\Windows.old'
    if (Test-Path -LiteralPath $old) {
        $gb = [math]::Round((Get-FolderSize $old)/1GB, 2)
        Write-Host ('Removing C:\Windows.old ({0} GB)...' -f $gb)
        if (-not $DryRun) {
            takeown.exe /f $old /r /d y | Out-Null
            icacls.exe $old /grant '*S-1-5-32-544:F' /t | Out-Null
            Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $old) {
                [void]$results.Add([PSCustomObject]@{ Item = 'Windows.old'; MB = [math]::Round($gb*1024,0); Status = 'PARTIAL - use cleanmgr' })
            } else {
                [void]$results.Add([PSCustomObject]@{ Item = 'Windows.old'; MB = [math]::Round($gb*1024,0); Status = 'OK' })
            }
        }
    } else {
        Write-Host 'C:\Windows.old not present.'
    }
}

# ---------------------------------------------------------------- DISM
if (-not $SkipDism) {
    Write-Host ''
    if ($DryRun) {
        Write-Host 'DISM StartComponentCleanup would run here (dry-run).'
    } else {
        Write-Host 'Running DISM component cleanup - this can take 5-20 minutes...'
        $dismArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($ResetBase) { $dismArgs += '/ResetBase' }
        & dism.exe $dismArgs | Out-Host
    }
}

# ---------------------------------------------------------------- report
Write-Host ''
Write-Host '==================== RESULT ===================='
$results | Where-Object { $_.MB -ge 1 } | Sort-Object MB -Descending |
    ForEach-Object { Write-Host ('{0,9:N0} MB  {1,-42} {2}' -f $_.MB, $_.Item, $_.Status) }

$freeAfter = (Get-PSDrive C).Free
Write-Host ''
Write-Host ('Free before : {0:N2} GB' -f ($freeBefore/1GB))
Write-Host ('Free after  : {0:N2} GB' -f ($freeAfter/1GB))
Write-Host ('Freed       : {0:N2} GB' -f (($freeAfter - $freeBefore)/1GB))

if ($DryRun) {
    Write-Host ''
    Write-Host 'DRY RUN - nothing was changed.'
}
