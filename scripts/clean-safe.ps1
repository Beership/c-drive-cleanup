#Requires -Version 5.1
<#
.SYNOPSIS
    Deletes regenerable caches on the system drive. Does NOT require admin.

.DESCRIPTION
    Only touches locations whose contents are recreated automatically by the
    owning application. Never deletes user documents, application settings,
    login state, or anything under Program Files.

    Run scan.ps1 first. Every path below is reported there with verdict SAFE.

.PARAMETER DryRun
    Show what would be deleted, delete nothing.

.PARAMETER IncludeBrowserCache
    Also clear browser HTTP/GPU caches (Edge, Chrome, Brave, 360, Firefox).
    Bookmarks, passwords and logins are untouched - only Cache/Code Cache/
    GPUCache directories are removed.

.PARAMETER IncludeNpmCache
    Also clear npm / pnpm / yarn / uv package caches.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean-safe.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File clean-safe.ps1 -IncludeBrowserCache -IncludeNpmCache
#>
param(
    [switch]$DryRun,
    [switch]$IncludeBrowserCache,
    [switch]$IncludeNpmCache
)

$ErrorActionPreference = 'SilentlyContinue'

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

$selfRoot = $PSScriptRoot
$results = New-Object System.Collections.ArrayList
$totalFreed = [int64]0

# A path that sits under a junction lives on another drive, so deleting it frees
# nothing on C:. Walking up the tree catches both "<x> is a junction" and
# "a parent of <x> is a junction".
function Test-UnderReparsePoint {
    param([string]$Path)
    $probe = $Path
    while ($probe -and $probe.Length -gt 3) {
        $item = Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $true }
        $probe = Split-Path $probe -Parent
    }
    return $false
}

function Clear-Cache {
    param([string]$Path, [string]$Label)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }

    # Never delete the directory this script lives in (protects running script).
    if ($selfRoot -and $Path.StartsWith($selfRoot, [StringComparison]::OrdinalIgnoreCase)) { return }

    if (Test-UnderReparsePoint $Path) {
        [void]$results.Add([PSCustomObject]@{
            Item = $Label; MB = 0; Status = 'SKIP (junction -> other drive)'
        })
        return
    }

    $before = Get-FolderSize $Path

    if ($DryRun) {
        [void]$results.Add([PSCustomObject]@{
            Item = $Label; MB = [math]::Round($before/1MB,0); Status = 'DRY-RUN'
        })
        return
    }

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.FullName -eq $PSCommandPath) { return }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    $after = Get-FolderSize $Path
    $got = $before - $after
    $totalFreed += $got

    $status = 'OK'
    if ($after -gt 1MB) {
        if ($after -lt ($before * 0.3)) { $status = 'PARTIAL (files in use)' }
        else { $status = 'LOCKED' }
    }

    [void]$results.Add([PSCustomObject]@{
        Item = $Label; MB = [math]::Round($got/1MB,0); Status = $status
    })
}

$freeBefore = (Get-PSDrive C).Free

# ---------------------------------------------------------------- GPU shader caches
Write-Host 'Cleaning GPU shader caches...'
Clear-Cache "$env:LOCALAPPDATA\NVIDIA\DXCache"     'NVIDIA DXCache'
Clear-Cache "$env:LOCALAPPDATA\NVIDIA\GLCache"     'NVIDIA GLCache'
Clear-Cache "$env:LOCALAPPDATA\D3DSCache"          'DirectX D3DSCache'
Clear-Cache "$env:LOCALAPPDATA\AMD\DxCache"        'AMD DxCache'
Clear-Cache "$env:LOCALAPPDATA\AMD\GLCache"        'AMD GLCache'
Clear-Cache "$env:LOCALAPPDATA\AMD\DxcCache"       'AMD DxcCache'
Clear-Cache "$env:LOCALAPPDATA\Intel\ShaderCache"  'Intel ShaderCache'
Clear-Cache "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache" 'NVIDIA NV_Cache'

# ---------------------------------------------------------------- temp & diagnostics
Write-Host 'Cleaning temp and diagnostics...'
Clear-Cache $env:TEMP                              'User Temp'
Clear-Cache "$env:LOCALAPPDATA\CrashDumps"         'CrashDumps'
Clear-Cache "$env:LOCALAPPDATA\Microsoft\Windows\WER" 'Windows Error Reporting'
Clear-Cache "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'Thumbnail / icon cache'
Clear-Cache "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" 'INetCache'

# ---------------------------------------------------------------- updater staging
Write-Host 'Cleaning updater staging folders...'
Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*-updater' } |
    ForEach-Object { Clear-Cache $_.FullName ('Updater: ' + $_.Name) }

# ---------------------------------------------------------------- NVIDIA driver cache
Write-Host 'Cleaning NVIDIA driver download cache...'
Clear-Cache 'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework' 'NVIDIA driver packages'

# ---------------------------------------------------------------- browser caches
if ($IncludeBrowserCache) {
    Write-Host 'Cleaning browser caches...'
    $browserRoots = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:LOCALAPPDATA\360ChromeX\User Data",
        "$env:LOCALAPPDATA\360se6\User Data",
        "$env:LOCALAPPDATA\Chromium\User Data"
    )
    foreach ($root in $browserRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile*' -or $_.Name -eq 'Guest Profile' } |
            ForEach-Object {
                $profileDir = $_.FullName
                $tag = (Split-Path -Leaf (Split-Path -Parent $profileDir)) + '/' + $_.Name
                Clear-Cache (Join-Path $profileDir 'Cache')            ('Browser Cache: ' + $tag)
                Clear-Cache (Join-Path $profileDir 'Code Cache')       ('Browser CodeCache: ' + $tag)
                Clear-Cache (Join-Path $profileDir 'GPUCache')         ('Browser GPUCache: ' + $tag)
                Clear-Cache (Join-Path $profileDir 'Service Worker\CacheStorage') ('Browser SW-Cache: ' + $tag)
            }
    }
    $ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $ffProfiles) {
        Get-ChildItem -LiteralPath $ffProfiles -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Clear-Cache (Join-Path $_.FullName 'cache2') 'Firefox cache2' }
    }
}

# ---------------------------------------------------------------- package caches
if ($IncludeNpmCache) {
    Write-Host 'Cleaning package manager caches...'
    Clear-Cache "$env:LOCALAPPDATA\npm-cache"  'npm cache'
    Clear-Cache "$env:APPDATA\npm-cache"       'npm cache (roaming)'
    Clear-Cache "$env:LOCALAPPDATA\pnpm\store" 'pnpm store'
    Clear-Cache "$env:LOCALAPPDATA\Yarn\Cache" 'Yarn cache'
    Clear-Cache "$env:LOCALAPPDATA\uv\cache"   'uv cache'
    Clear-Cache "$env:LOCALAPPDATA\pip\Cache"  'pip cache'
}

# ---------------------------------------------------------------- recycle bin
Write-Host 'Emptying recycle bin...'
$binSize = 0
try {
    $binSize = (Get-ChildItem -LiteralPath 'C:\$Recycle.Bin' -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
} catch { }
if ($null -eq $binSize) { $binSize = 0 }
if ($DryRun) {
    [void]$results.Add([PSCustomObject]@{ Item = 'Recycle Bin'; MB = [math]::Round($binSize/1MB,0); Status = 'DRY-RUN' })
} else {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    $totalFreed += $binSize
    [void]$results.Add([PSCustomObject]@{ Item = 'Recycle Bin'; MB = [math]::Round($binSize/1MB,0); Status = 'OK' })
}

# ---------------------------------------------------------------- report
Write-Host ''
Write-Host '==================== RESULT ===================='
$results | Where-Object { $_.MB -ge 1 -or $_.Status -like 'SKIP*' } | Sort-Object MB -Descending |
    ForEach-Object { Write-Host ('{0,9:N0} MB  {1,-42} {2}' -f $_.MB, $_.Item, $_.Status) }

$freeAfter = (Get-PSDrive C).Free
Write-Host ''
Write-Host ('Free before : {0:N2} GB' -f ($freeBefore/1GB))
Write-Host ('Free after  : {0:N2} GB' -f ($freeAfter/1GB))
Write-Host ('Freed       : {0:N2} GB' -f (($freeAfter - $freeBefore)/1GB))

if ($DryRun) {
    Write-Host ''
    Write-Host 'DRY RUN - nothing was deleted.'
    Write-Host 'Re-run without -DryRun to apply.'
}

Write-Host ''
Write-Host 'Next: run clean-admin.ps1 from an elevated PowerShell for system-level caches.'
