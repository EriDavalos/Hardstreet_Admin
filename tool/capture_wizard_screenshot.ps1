# Captura la ventana del instalador en ejecución como PNG.
# Uso: powershell -File tool/capture_wizard_screenshot.ps1
$ErrorActionPreference = "Stop"
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
public static class Shot {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr FindByPid(uint pid) {
    IntPtr wnd = IntPtr.Zero, res = IntPtr.Zero;
    do {
      wnd = FindWindowEx(IntPtr.Zero, wnd, null, null);
      if (wnd == IntPtr.Zero) break;
      uint p; GetWindowThreadProcessId(wnd, out p);
      if (p == pid) { res = wnd; break; }
    } while (true);
    return res;
  }
  public static Bitmap Capture(IntPtr wnd) {
    RECT r; GetWindowRect(wnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    Graphics g = Graphics.FromImage(bmp);
    g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h));
    return bmp;
  }
}
"@

$proc = Get-Process | Where-Object { $_.ProcessName -like "HardstreetAdmin-setup*" } | Select-Object -First 1
if (-not $proc) { Write-Host "No hay instalador en ejecucion"; exit 1 }
$wnd = [Shot]::FindByPid([uint32]$proc.Id)
if ($wnd -eq [IntPtr]::Zero) { Write-Host "No se encontro la ventana"; exit 1 }
[Shot]::SetForegroundWindow($wnd) | Out-Null
Start-Sleep -Milliseconds 500
$bmp = [Shot]::Capture($wnd)
$out = "build\_wizard_window.png"
$bmp.Save($out, [ImageFormat]::Png)
Write-Host ("captura: {0}x{1} -> {2}" -f $bmp.Width, $bmp.Height, $out)
