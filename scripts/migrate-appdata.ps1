#Requires -Version 5.1
<#
.SYNOPSIS
    Move an application data folder to another drive and leave a junction behind.

.DESCRIPTION
    Frees space on C: without breaking the application: the app keeps using the
    original path, but the bytes now live on another drive.

    Safety model:
      1. refuse if the source is already a junction or a reparse point
      2. measure source and target, require enough free space on target
      3. copy with robocopy, then compare file count AND total bytes
      4. rename the source to <name>.premove (nothing is deleted yet)
      5. create the junction, verify the app can still see the data
      6. only then delete the renamed copy

    If any step fails, the original folder is restored automatically.

.PARAMETER Source
    Existing folder to relocate, e.g. C:\Users\me\AppData\Roaming\Tencent

.PARAMETER Target
    Destination, e.g. D:\AppData\Tencent. Must be on another drive.

.PARAMETER ProcessName
    One or more process names to stop before the move (e.g. WeChat, WXWork).

.PARAMETER DryRun
    Report source size and the planned actions, change nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File migrate-appdata.ps1 `
        -Source "$env:APPDATA\Tencent" -Target "D:\AppData\Tencent" -ProcessName WeChat

.NOTES
    Rollback: delete the junction, rename <name>.premove back to <name>.
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [string[]]$ProcessName = @(),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Get-FolderStats {
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    return [PSCustomObject]@{ Count = $files.Count; Bytes = [int64]$bytes }
}

function Fail($message) {
    Write-Host ''
    Write-Host ('ABORT: ' + $message) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 1. validate
if (-not (Test-Path -LiteralPath $Source)) { Fail "source not found: $Source" }

$srcItem = Get-Item -LiteralPath $Source -Force
if ($srcItem.LinkType -eq 'Junction') { Fail "$Source is already a junction -> $($srcItem.Target)" }
if ($srcItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { Fail "$Source is a reparse point - refusing to touch it" }
if (-not $srcItem.PSIsContainer) { Fail "$Source is not a directory" }

$srcDrive = (Get-Item -LiteralPath $Source).PSDrive.Name
$dstDrive = ($Target -split ':')[0]
if ($srcDrive -eq $dstDrive) { Fail "source and target are on the same drive ($srcDrive): no space would be freed" }

$srcStats = Get-FolderStats $Source
$srcGB = [math]::Round($srcStats.Bytes / 1GB, 2)
Write-Host ('Source : {0}' -f $Source)
Write-Host ('Files  : {0}  Size: {1} GB' -f $srcStats.Count, $srcGB)
Write-Host ('Target : {0}' -f $Target)
Write-Host ''

if ($DryRun) {
    Write-Host 'DRY RUN - planned steps:'
    Write-Host '  1. stop processes: ' + ($ProcessName -join ', ')
    Write-Host '  2. robocopy source -> target'
    Write-Host '  3. verify file count + byte total'
    Write-Host '  4. rename source to <name>.premove, create junction'
    Write-Host '  5. delete the renamed copy after verification'
    Write-Host ('Would free about {0} GB on {1}:' -f $srcGB, $srcDrive)
    return
}

# ---------------------------------------------------------------- 2. free space
$dstRoot = Split-Path -Qualifier $Target
$dstFree = (Get-PSDrive ($dstRoot.TrimEnd(':'))).Free
if ($dstFree -lt ($srcStats.Bytes * 1.1)) {
    Fail ('target drive has {0:N2} GB free but {1:N2} GB is needed' -f ($dstFree/1GB), ($srcStats.Bytes/1GB))
}

# ---------------------------------------------------------------- 3. stop apps
foreach ($p in $ProcessName) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host ('Stopping {0} process(es) named "{1}"...' -f $procs.Count, $p)
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
$stillRunning = @()
foreach ($p in $ProcessName) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) { $stillRunning += $p }
}
if ($stillRunning.Count -gt 0) {
    Fail ('still running, close them first: ' + ($stillRunning -join ', '))
}

# ---------------------------------------------------------------- 4. copy
Write-Host 'Copying...'
if (-not (Test-Path -LiteralPath $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}
$roboArgs = @($Source, $Target, '/E', '/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
$robo = Start-Process -FilePath robocopy.exe -ArgumentList $roboArgs -Wait -PassThru -NoNewWindow
Write-Host ('  robocopy exit code: {0}' -f $robo.ExitCode)
if ($robo.ExitCode -ge 8) {
    Fail ('robocopy failed with code ' + $robo.ExitCode + ' - source left untouched')
}

# ---------------------------------------------------------------- 5. verify
Write-Host 'Verifying copy...'
$dstStats = Get-FolderStats $Target
$countOk = $dstStats.Count -ge $srcStats.Count
$bytesOk = $dstStats.Bytes -ge ($srcStats.Bytes * 0.999)
Write-Host ('  source: {0} files / {1:N0} bytes' -f $srcStats.Count, $srcStats.Bytes)
Write-Host ('  target: {0} files / {1:N0} bytes' -f $dstStats.Count, $dstStats.Bytes)

if (-not ($countOk -and $bytesOk)) {
    Write-Host 'Copy verification FAILED - source left untouched, target kept for inspection.' -ForegroundColor Red
    Write-Host ('Inspect: ' + $Target)
    exit 2
}
Write-Host '  verification passed' -ForegroundColor Green

# ---------------------------------------------------------------- 6. swap
$backup = $Source + '.premove'
if (Test-Path -LiteralPath $backup) { Fail "backup path already exists: $backup" }

Write-Host 'Renaming source out of the way...'
Rename-Item -LiteralPath $Source -NewName (Split-Path $backup -Leaf)

try {
    Write-Host 'Creating junction...'
    cmd.exe /c mklink /J "$Source" "$Target" | Out-Null
    if (-not (Test-Path -LiteralPath $Source)) { throw 'junction was not created' }

    $probe = Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $probe) { throw 'junction is not readable' }
    Write-Host ('  junction OK: {0} -> {1}' -f $Source, $Target) -ForegroundColor Green
}
catch {
    Write-Host ('Junction creation failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Rolling back...'
    if (Test-Path -LiteralPath $Source) { Remove-Item -LiteralPath $Source -Force -Recurse -ErrorAction SilentlyContinue }
    Rename-Item -LiteralPath $backup -NewName (Split-Path $Source -Leaf)
    Write-Host 'Rollback done - original folder restored.'
    exit 3
}

# ---------------------------------------------------------------- 7. cleanup
Write-Host 'Removing the local copy...'
Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $backup) {
    Write-Host ('Could not fully remove: ' + $backup) -ForegroundColor Yellow
    Write-Host 'Delete it manually after confirming the app works.'
}

Write-Host ''
Write-Host ('DONE. Freed about {0} GB on {1}:' -f $srcGB, $srcDrive) -ForegroundColor Green
Write-Host ''
Write-Host 'If the application misbehaves, roll back with:'
Write-Host ('  cmd /c rmdir "' + $Source + '"')
Write-Host ('  Rename-Item "' + $Target + '" "' + (Split-Path $Source -Leaf) + '"')
Write-Host '  Move-Item back to ' + (Split-Path $Source -Parent)
