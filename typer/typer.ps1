<#
  typer.ps1 — Gõ phím tự động sau N giây với tốc độ tuỳ chọn.
  Chạy:  bấm đúp typer.cmd   (hoặc)   powershell -STA -ExecutionPolicy Bypass -File typer.ps1
  Dừng giữa chừng: giữ phím Esc.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- SendInput (Unicode) qua P/Invoke: gõ được mọi ký tự, kể cả tiếng Việt, không cần escape ----
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Typer {
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public INPUTUNION u; }
    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 2, KEYEVENTF_UNICODE = 4;
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);

    static void Send(ushort vk, ushort scan, uint flags) {
        var down = new INPUT { type = INPUT_KEYBOARD };
        down.u.ki = new KEYBDINPUT { wVk = vk, wScan = scan, dwFlags = flags };
        var up = down; up.u.ki.dwFlags = flags | KEYEVENTF_KEYUP;
        SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void Char(char c) {
        if (c == '\n') Send(0x0D, 0, 0);            // Enter
        else if (c == '\t') Send(0x09, 0, 0);       // Tab
        else if (c == '\r') return;
        else Send(0, c, KEYEVENTF_UNICODE);
    }
    public static bool EscDown() { return (GetAsyncKeyState(0x1B) & 0x8000) != 0; }
}
'@

# ---- GUI ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Auto Typer"
$form.ClientSize = New-Object System.Drawing.Size(420, 132)
$form.StartPosition = "Manual"
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea   # vùng màn hình trừ taskbar
$form.Add_Load({ $form.Location = New-Object System.Drawing.Point(($wa.Right - $form.Width - 8), ($wa.Bottom - $form.Height - 8)) })
$form.FormBorderStyle = "FixedToolWindow"
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$txt = New-Object System.Windows.Forms.TextBox
$txt.Multiline = $true
$txt.AcceptsReturn = $true
$txt.AcceptsTab = $true
$txt.ScrollBars = "Vertical"
$txt.WordWrap = $false
$txt.Location = New-Object System.Drawing.Point(8, 8)
$txt.Size = New-Object System.Drawing.Size(404, 58)
$txt.Text = "type-this-line"

$lblDelay = New-Object System.Windows.Forms.Label
$lblDelay.Text = "Chờ"
$lblDelay.Location = New-Object System.Drawing.Point(8, 77)
$lblDelay.AutoSize = $true

$numDelay = New-Object System.Windows.Forms.NumericUpDown
$numDelay.Location = New-Object System.Drawing.Point(38, 73)
$numDelay.Size = New-Object System.Drawing.Size(46, 23)
$numDelay.Minimum = 0; $numDelay.Maximum = 60; $numDelay.Value = 5

$lblSec = New-Object System.Windows.Forms.Label
$lblSec.Text = "s"
$lblSec.Location = New-Object System.Drawing.Point(86, 77)
$lblSec.AutoSize = $true

$lblSpeed = New-Object System.Windows.Forms.Label
$lblSpeed.Text = "Tốc độ"
$lblSpeed.Location = New-Object System.Drawing.Point(108, 77)
$lblSpeed.AutoSize = $true

$numSpeed = New-Object System.Windows.Forms.NumericUpDown
$numSpeed.Location = New-Object System.Drawing.Point(156, 73)
$numSpeed.Size = New-Object System.Drawing.Size(46, 23)
$numSpeed.Minimum = 1; $numSpeed.Maximum = 10; $numSpeed.Value = 5

$chkEnter = New-Object System.Windows.Forms.CheckBox
$chkEnter.Text = "Enter cuối"
$chkEnter.Location = New-Object System.Drawing.Point(214, 75)
$chkEnter.AutoSize = $true

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Bắt đầu"
$btn.Location = New-Object System.Drawing.Point(330, 71)
$btn.Size = New-Object System.Drawing.Size(82, 26)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ctrl+Enter = Bắt đầu · click vào cửa sổ đích khi đếm ngược · Esc = dừng"
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$lblStatus.Location = New-Object System.Drawing.Point(8, 106)
$lblStatus.Size = New-Object System.Drawing.Size(404, 18)

$txt.Add_KeyDown({ if ($_.Control -and $_.KeyCode -eq "Return") { $_.SuppressKeyPress = $true; $btn.PerformClick() } })
$form.Controls.AddRange(@($txt, $lblDelay, $numDelay, $lblSec, $lblSpeed, $numSpeed, $chkEnter, $btn, $lblStatus))

# ---- Logic ----
$script:remaining = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000

function Set-Busy([bool]$busy) {
    $btn.Enabled = -not $busy
    $txt.Enabled = -not $busy
    $numDelay.Enabled = -not $busy
    $numSpeed.Enabled = -not $busy
    $chkEnter.Enabled = -not $busy
}

function Invoke-Typing {
    $text = $txt.Text
    if ($chkEnter.Checked) { $text += "`n" }
    # speed 10 → 30 ms/ký tự, speed 1 → 300 ms/ký tự
    $delayMs = (11 - [int]$numSpeed.Value) * 30
    $lblStatus.Text = "Đang gõ... (giữ Esc để dừng)"
    $stopped = $false
    foreach ($c in $text.ToCharArray()) {
        if ([Typer]::EscDown()) { $stopped = $true; break }
        [Typer]::Char($c)
        Start-Sleep -Milliseconds $delayMs
        [System.Windows.Forms.Application]::DoEvents()
    }
    $lblStatus.Text = if ($stopped) { "Đã dừng (Esc)." } else { "Xong." }
    Set-Busy $false
}

$timer.Add_Tick({
    $script:remaining--
    if ($script:remaining -gt 0) {
        $lblStatus.Text = "Gõ sau $($script:remaining)s — click vào cửa sổ đích!"
        return
    }
    $timer.Stop()
    Invoke-Typing
})

$btn.Add_Click({
    if ([string]::IsNullOrEmpty($txt.Text)) { $lblStatus.Text = "Chưa nhập nội dung."; return }
    Set-Busy $true
    $script:remaining = [int]$numDelay.Value
    if ($script:remaining -le 0) { Invoke-Typing; return }
    $lblStatus.Text = "Gõ sau $($script:remaining)s — click vào cửa sổ đích!"
    $timer.Start()
})

$form.Add_FormClosing({ $timer.Stop() })
[void]$form.ShowDialog()
