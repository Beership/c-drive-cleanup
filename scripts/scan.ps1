#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only C: drive space diagnostic. Deletes nothing.

.DESCRIPTION
    Produces a prioritized inventory of what occupies the system drive so that
    cleanup decisions are evidence-based. Every item printed is a candidate, not
    a verdict - the operator decides what to remove.

.PARAMETER Full
    Also measure C:\Windows and every top-level directory. Slower (1-3 min).

.PARAMETER Json
    Emit machine-readable JSON instead of tables.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan.ps1 -Full -Json > report.json
#>
param(
    [switch]$Full,
    [switch]$Json
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

function To-GB { param($Bytes) return [math]::Round($Bytes / 1GB, 2) }

$rows = New-Object System.Collections.ArrayList
$script:seenPaths = @{}
function Add-Row {
    param($Category, $Name, $Bytes, $Path, $Verdict, $Note)
    if ($Path) {
        $key = $Path.TrimEnd('\').ToLowerInvariant()
        if ($script:seenPaths.ContainsKey($key)) { return }
        $script:seenPaths[$key] = $Category
    }
    [void]$rows.Add([PSCustomObject]@{
        Category = $Category
        Name     = $Name
        GB       = To-GB $Bytes
        MB       = [math]::Round($Bytes / 1MB, 0)
        Path     = $Path
        Verdict  = $Verdict
        Note     = $Note
    })
}

# ---------------------------------------------------------------- disk
$disk = Get-PSDrive C -ErrorAction SilentlyContinue
$diskInfo = [PSCustomObject]@{
    DriveLetter = 'C:'
    TotalGB     = To-GB ($disk.Used + $disk.Free)
    UsedGB      = To-GB $disk.Used
    FreeGB      = To-GB $disk.Free
    FreePercent = if (($disk.Used + $disk.Free) -gt 0) {
        [math]::Round($disk.Free / ($disk.Used + $disk.Free) * 100, 1)
    } else { 0 }
}

# ---------------------------------------------------------------- root files
foreach ($f in @('C:\pagefile.sys', 'C:\hiberfil.sys', 'C:\swapfile.sys', 'C:\Windows\MEMORY.DMP')) {
    $item = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($item) {
        $verdict = switch ($f) {
            'C:\hiberfil.sys'    { 'REVIEW' }
            'C:\Windows\MEMORY.DMP' { 'SAFE' }
            default              { 'KEEP' }
        }
        Add-Row 'SystemFile' (Split-Path $f -Leaf) $item.Length $f $verdict 'PowerShell-level system file'
    }
}

# ---------------------------------------------------------------- old OS payloads
foreach ($d in @('C:\Windows.old', 'C:\$WINDOWS.~BT', 'C:\$WINDOWS.~WS', 'C:\$WinREAgent', 'C:\$GetCurrent')) {
    if (Test-Path -LiteralPath $d) {
        Add-Row 'OldOS' (Split-Path $d -Leaf) (Get-FolderSize $d) $d 'SAFE' 'Leftover from an OS upgrade - removable'
    }
}

# ---------------------------------------------------------------- known caches
$cacheTargets = [ordered]@{
    'NVIDIA DXCache'      = @("$env:LOCALAPPDATA\NVIDIA\DXCache",   'SAFE', 'GPU shader cache - regenerates on next launch')
    'NVIDIA GLCache'      = @("$env:LOCALAPPDATA\NVIDIA\GLCache",   'SAFE', 'OpenGL shader cache')
    'DirectX D3DSCache'   = @("$env:LOCALAPPDATA\D3DSCache",        'SAFE', 'DirectX shader cache')
    'AMD DxCache'         = @("$env:LOCALAPPDATA\AMD\DxCache",      'SAFE', 'AMD shader cache')
    'AMD GLCache'         = @("$env:LOCALAPPDATA\AMD\GLCache",      'SAFE', 'AMD OpenGL cache')
    'Intel ShaderCache'   = @("$env:LOCALAPPDATA\Intel\ShaderCache",'SAFE', 'Intel shader cache')
    'User Temp'           = @("$env:LOCALAPPDATA\Temp",             'SAFE', 'Temporary files')
    'CrashDumps'          = @("$env:LOCALAPPDATA\CrashDumps",       'SAFE', 'Application crash dumps')
    'Windows Error Report'= @("$env:LOCALAPPDATA\Microsoft\Windows\WER", 'SAFE', 'WER crash reports')
    'WU Download'         = @('C:\Windows\SoftwareDistribution\Download', 'SAFE', 'Windows Update payload cache')
    'DeliveryOptimization'= @('C:\Windows\SoftwareDistribution\DeliveryOptimization', 'SAFE', 'Update peer-cache')
    'Prefetch'            = @('C:\Windows\Prefetch',                'SAFE', 'Prefetch traces')
    'Windows Temp'        = @('C:\Windows\Temp',                    'SAFE', 'System temporary files')
    'Windows Installer'   = @('C:\Windows\Installer',               'NEVER', 'Deleting breaks uninstall/repair - use PatchCleaner')
    'WinSxS'              = @('C:\Windows\WinSxS',                  'DISM',  'Only via DISM StartComponentCleanup')
    'Recycle Bin'         = @('C:\$Recycle.Bin',                    'SAFE', 'Deleted files awaiting purge')
    'NVIDIA driver cache' = @('C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework', 'SAFE', 'Downloaded driver packages')
    'NVIDIA NGX models'   = @('C:\ProgramData\NVIDIA\NGX',          'KEEP',  'DLSS/NGX model data')
    'LGHUB cache'         = @('C:\ProgramData\LGHUB\cache',         'REVIEW','Logitech G HUB cache')
    'LGHUB depots'        = @('C:\ProgramData\LGHUB\depots',        'REVIEW','Logitech firmware payloads')
}
$cacheRoots = @()
foreach ($key in $cacheTargets.Keys) {
    $path = $cacheTargets[$key][0]
    $cacheRoots += $path.TrimEnd('\').ToLowerInvariant()
    if (Test-Path -LiteralPath $path) {
        $size = Get-FolderSize $path
        if ($size -gt 50MB) {
            Add-Row 'Cache' $key $size $path $cacheTargets[$key][1] $cacheTargets[$key][2]
        }
    }
}

# ---------------------------------------------------------------- updater staging
foreach ($base in @($env:LOCALAPPDATA)) {
    Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*-updater' } |
        ForEach-Object {
            $size = Get-FolderSize $_.FullName
            if ($size -gt 20MB) {
                Add-Row 'UpdaterStaging' $_.Name $size $_.FullName 'SAFE' 'Electron auto-update staging - app is installed elsewhere'
            }
        }
}

# ---------------------------------------------------------------- top level
if ($Full) {
    Get-ChildItem -LiteralPath 'C:\' -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('$Recycle.Bin', 'System Volume Information') } |
        ForEach-Object {
            $size = Get-FolderSize $_.FullName
            if ($size -gt 300MB) {
                $verdict = switch ($_.Name) {
                    'Windows'        { 'REVIEW' }
                    'Users'          { 'REVIEW' }
                    'Program Files'  { 'REVIEW' }
                    'Program Files (x86)' { 'REVIEW' }
                    'ProgramData'    { 'REVIEW' }
                    default          { 'REVIEW' }
                }
                Add-Row 'TopLevel' $_.Name $size $_.FullName $verdict 'Container - drill down'
            }
        }
}

# ---------------------------------------------------------------- app data
$appBases = @(
    @{ Path = "$env:LOCALAPPDATA"; Label = 'Local' },
    @{ Path = "$env:APPDATA";      Label = 'Roaming' },
    @{ Path = 'C:\ProgramData';    Label = 'ProgramData' },
    @{ Path = 'C:\Program Files';  Label = 'ProgramFiles' },
    @{ Path = 'C:\Program Files (x86)'; Label = 'ProgramFilesX86' }
)
foreach ($base in $appBases) {
    if (-not (Test-Path -LiteralPath $base.Path)) { continue }
    Get-ChildItem -LiteralPath $base.Path -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $childKey = $_.FullName.TrimEnd('\').ToLowerInvariant()
            # Skip containers that were already broken down in the Cache section,
            # otherwise the same GB gets reported twice with conflicting verdicts.
            $isCacheParent = $false
            foreach ($cr in $cacheRoots) {
                if ($cr.StartsWith($childKey + '\')) { $isCacheParent = $true; break }
            }
            if ($isCacheParent) { return }
            $size = Get-FolderSize $_.FullName
            if ($size -gt 500MB) {
                Add-Row ('App:' + $base.Label) $_.Name $size $_.FullName 'REVIEW' 'Application data - check before touching'
            }
        }
}

# ---------------------------------------------------------------- junctions
$junctionRows = @()
foreach ($probe in @("$env:APPDATA", "$env:LOCALAPPDATA", "$env:LOCALAPPDATA\Programs", "$env:USERPROFILE")) {
    Get-ChildItem -LiteralPath $probe -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -eq 'Junction' } |
        ForEach-Object {
            $junctionRows += [PSCustomObject]@{
                Path   = $_.FullName
                Target = ($_.Target -join '; ')
            }
        }
}

# ---------------------------------------------------------------- output
if ($Json) {
    [PSCustomObject]@{
        Generated = (Get-Date).ToString('s')
        Disk      = $diskInfo
        Items     = $rows
        Junctions = $junctionRows
    } | ConvertTo-Json -Depth 5
    return
}

Write-Host ''
Write-Host '==================== DISK ===================='
Write-Host ('{0}  total {1} GB | used {2} GB | FREE {3} GB ({4}%)' -f `
    $diskInfo.DriveLetter, $diskInfo.TotalGB, $diskInfo.UsedGB, $diskInfo.FreeGB, $diskInfo.FreePercent)
if ($diskInfo.FreeGB -lt 2) {
    Write-Host 'WARNING: under 2 GB free - Windows updates and many apps will fail.' -ForegroundColor Red
} elseif ($diskInfo.FreeGB -lt 10) {
    Write-Host 'CAUTION: under 10 GB free - expect problems soon.' -ForegroundColor Yellow
}

$order = @('SystemFile', 'OldOS', 'Cache', 'UpdaterStaging', 'TopLevel', 'App:Local', 'App:Roaming', 'App:ProgramData', 'App:ProgramFiles', 'App:ProgramFilesX86')
foreach ($cat in $order) {
    $group = $rows | Where-Object { $_.Category -eq $cat } | Sort-Object GB -Descending
    if (-not $group) { continue }
    Write-Host ''
    Write-Host ('==================== ' + $cat + ' ====================')
    $group | ForEach-Object {
        Write-Host ('{0,8:N2} GB  [{1,-6}] {2}' -f $_.GB, $_.Verdict, $_.Path)
        if ($_.Note) { Write-Host ('                    ' + $_.Note) -ForegroundColor DarkGray }
    }
}

if ($junctionRows) {
    Write-Host ''
    Write-Host '==================== EXISTING JUNCTIONS ===================='
    $junctionRows | ForEach-Object { Write-Host ('  {0} -> {1}' -f $_.Path, $_.Target) }
}

Write-Host ''
Write-Host '==================== VERDICT KEY ===================='
Write-Host '  SAFE   - regenerable cache, safe to delete'
Write-Host '  REVIEW - decide after inspecting (app data, system folder)'
Write-Host '  DISM   - only via DISM component cleanup'
Write-Host '  KEEP   - do not delete'
Write-Host '  NEVER  - deleting breaks the OS or app uninstall'
Write-Host ''
Write-Host 'Nothing was deleted. Re-run with -Full to include C:\Windows sizing.'
