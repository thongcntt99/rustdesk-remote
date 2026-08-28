<#
.SYNOPSIS
  Mở phiên RustDesk tới máy Mac trong machines.csv (chạy trên Windows).

.EXAMPLE
  .\connect.ps1            # hiện danh sách, chọn số
  .\connect.ps1 Mac-01     # kết nối theo tên máy
  .\connect.ps1 123456789  # kết nối theo ID
  .\connect.ps1 -All       # mở tất cả máy trong bảng
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Target,
    [switch] $All,
    [string] $Csv = (Join-Path $PSScriptRoot 'machines.csv')
)

$ErrorActionPreference = 'Stop'

# ---- tìm rustdesk.exe ----
$candidates = @(
    "$env:ProgramFiles\RustDesk\rustdesk.exe",
    "${env:ProgramFiles(x86)}\RustDesk\rustdesk.exe",
    "$env:LOCALAPPDATA\Programs\RustDesk\rustdesk.exe",
    "$env:LOCALAPPDATA\rustdesk\rustdesk.exe"
)
$rd = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $rd) {
    $cmd = Get-Command rustdesk.exe -ErrorAction SilentlyContinue
    if ($cmd) { $rd = $cmd.Source }
}
if (-not $rd) {
    Write-Error "Không tìm thấy rustdesk.exe. Cài từ https://github.com/rustdesk/rustdesk/releases"
}

# ---- đọc bảng máy ----
if (-not (Test-Path $Csv)) { Write-Error "Không thấy file $Csv. Sao chép machines.example.csv thành machines.csv rồi điền vào." }
$rows = Import-Csv -Path $Csv -Encoding UTF8 | ForEach-Object {
    $props = @($_.PSObject.Properties)
    [pscustomobject]@{
        Id       = ("$($props[0].Value)").Trim()
        Name     = ("$($props[1].Value)").Trim()
        Password = ("$($props[2].Value)").Trim()
    }
} | Where-Object { $_.Id }

if (-not $rows) { Write-Error "machines.csv chưa có dòng nào. Dán các dòng ID/Tên/Mật khẩu từ script rd-setup.sh vào." }

function Connect-Machine($m) {
    Write-Host ("→ {0}  (ID {1})" -f $m.Name, $m.Id) -ForegroundColor Green
    $tune = Join-Path $PSScriptRoot 'tune.ps1'
    if (Test-Path $tune) { & $tune $m.Id 3>$null | Out-Null }   # Translate mode, VP9, 15 FPS trước khi mở phiên
    $rdArgs = @('--connect', $m.Id)
    if ($m.Password) { $rdArgs += @('--password', $m.Password) }
    Start-Process -FilePath $rd -ArgumentList $rdArgs
}

if ($All) {
    foreach ($m in $rows) { Connect-Machine $m; Start-Sleep -Milliseconds 800 }
    return
}

if ($Target) {
    $m = $rows | Where-Object { $_.Name -eq $Target -or $_.Id -eq $Target } | Select-Object -First 1
    if (-not $m) { Write-Error "Không có máy '$Target' trong $Csv" }
    Connect-Machine $m
    return
}

# ---- menu chọn ----
for ($i = 0; $i -lt $rows.Count; $i++) {
    Write-Host ("  [{0}] {1,-12} {2}" -f ($i + 1), $rows[$i].Name, $rows[$i].Id)
}
$choice = Read-Host "Chọn số (Enter để thoát)"
if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $rows.Count) {
    Connect-Machine $rows[[int]$choice - 1]
}
