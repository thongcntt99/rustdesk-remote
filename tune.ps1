<#
.SYNOPSIS
  Áp thiết lập phiên tối ưu (Map mode + Swap Ctrl↔Cmd, VP9, 5 FPS, chất lượng 10%) cho mọi máy Mac trong machines.csv
  và mọi peer đã từng kết nối. Chạy trên Windows, KHI KHÔNG CÓ PHIÊN NÀO ĐANG MỞ (RustDesk ghi đè file peer lúc đóng phiên).

.EXAMPLE
  .\tune.ps1                 # áp cho tất cả
  .\tune.ps1 413615288       # áp cho 1 ID
  .\tune.ps1 -Mode translate -NoSwap   # dùng Translate mode thay vì Map+Swap
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Id,
    [ValidateSet('translate', 'map', 'legacy')] [string] $Mode = 'map',
    [switch] $NoSwap,
    [ValidateSet('auto', 'vp8', 'vp9', 'av1', 'h264', 'h265')] [string] $Codec = 'vp9',
    [int] $Fps = 5,
    [int] $Quality = 10,
    [string] $Csv = (Join-Path $PSScriptRoot 'machines.csv')
)
$ErrorActionPreference = 'Stop'
$peersDir = Join-Path $env:APPDATA 'RustDesk\config\peers'
New-Item -ItemType Directory -Force $peersDir | Out-Null

function Set-TopLevel([string[]]$lines, [string]$key, [string]$value) {
    if (-not $lines) { $lines = @() }
    $idx = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match "^\s*$([regex]::Escape($key))\s*=" })
    if ($idx -ge 0) { $lines[$idx] = "$key = $value"; return $lines }
    $first = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^\s*\[' })
    if ($first -lt 0) { return $lines + "$key = $value" }
    return $lines[0..($first - 1)] + "$key = $value" + $lines[$first..($lines.Count - 1)]
}

function Set-Option([string[]]$lines, [string]$key, [string]$value) {
    if (-not $lines) { $lines = @() }
    $sec = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^\s*\[options\]' })
    if ($sec -lt 0) { return $lines + '' + '[options]' + "$key = $value" }
    $end = $lines.Count
    for ($i = $sec + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end = $i; break } }
    for ($i = $sec + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($key))\s*=") { $lines[$i] = "$key = $value"; return $lines }
    }
    return $lines[0..$sec] + "$key = $value" + $(if ($sec + 1 -lt $lines.Count) { $lines[($sec + 1)..($lines.Count - 1)] } else { @() })
}

function Tune-Peer([string]$peerId) {
    $file = Join-Path $peersDir "$peerId.toml"
    $lines = if (Test-Path $file) { @(Get-Content $file -Encoding UTF8) } else { @() }
    $lines = Set-TopLevel $lines 'keyboard_mode'        "'$Mode'"
    $lines = Set-TopLevel $lines 'allow_swap_key'       $(if ($NoSwap) { 'false' } else { 'true' })
    $lines = Set-TopLevel $lines 'image_quality'        "'custom'"
    $lines = Set-TopLevel $lines 'custom_image_quality' "[$Quality]"
    $lines = Set-TopLevel $lines 'show_remote_cursor'   'false'
    $lines = Set-Option   $lines 'codec-preference'     "'$Codec'"
    $lines = Set-Option   $lines 'custom-fps'           "'$Fps'"
    [IO.File]::WriteAllLines($file, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    Write-Host ("  {0,-12} keyboard={1} swap={2} codec={3} fps={4} quality={5}%" -f $peerId, $Mode, (-not $NoSwap), $Codec, $Fps, $Quality)
}

# ---- danh sách ID ----
$ids = [System.Collections.Generic.List[string]]::new()
if ($Id) { $ids.Add($Id.Trim()) }
else {
    if (Test-Path $Csv) {
        Import-Csv $Csv -Encoding UTF8 | ForEach-Object { $v = ("$(@($_.PSObject.Properties)[0].Value)").Trim(); if ($v) { $ids.Add($v) } }
    }
    Get-ChildItem "$peersDir\*.toml" -ErrorAction SilentlyContinue | ForEach-Object { $ids.Add($_.BaseName) }
}
$ids = $ids | Sort-Object -Unique
if (-not $ids) { Write-Warning "Không có ID nào (machines.csv trống và chưa có peer nào)."; return }

$sessions = @(Get-Process rustdesk -ErrorAction SilentlyContinue).Count
if ($sessions -gt 1) { Write-Warning "Có vẻ đang mở phiên RustDesk ($sessions tiến trình). Hãy đóng các phiên trước, nếu không thiết lập sẽ bị ghi đè khi đóng phiên." }

Write-Host "Áp thiết lập cho $($ids.Count) máy:" -ForegroundColor Cyan
foreach ($p in $ids) { Tune-Peer $p }
Write-Host "Xong. Mở lại phiên để có hiệu lực." -ForegroundColor Green
