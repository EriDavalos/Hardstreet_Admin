# Lanza el instalador, espera a que aparezca su ventana y la captura como PNG.
# Uso: powershell -File tool/capture_wizard.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
public static class Cap {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static Bitmap Capture(IntPtr wnd) {
    RECT r; GetWindowRect(wnd, out r);
    int w = r.Right - r.Left, h = r.Bottom - r.Top;
    Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(bmp)) {
      g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h));
    }
    return bmp;
  }
}
"@

$setup = "C:\Workspace\Hardstreet\Hardstreet_Admin\build\installer\HardstreetAdmin-setup-1.0.1.exe"
if (-not (Test-Path $setup)) { Write-Host "No existe el instalador: $setup"; exit 1 }

# Lanza el instalador (sin /SILENT: queremos ver el wizard).
Start-Process -FilePath $setup | Out-Null

# Espera a que el wizard pinte su ventana (Inno tarda unos ms).
$proc = $null
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 400
  $proc = Get-Process | Where-Object { $_.ProcessName -like "HardstreetAdmin-setup*" -and $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if ($proc) { break }
}
if (-not $proc) { Write-Host "El wizard no abrio ventana"; exit 1 }
Write-Host ("ventana detectada: pid {0}" -f $proc.Id)

[Cap]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500

$bmp = [Cap]::Capture($proc.MainWindowHandle)
$out = "build\_wizard_window.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("captura {0}x{1} -> {2}" -f $bmp.Width, $bmp.Height, $out)
