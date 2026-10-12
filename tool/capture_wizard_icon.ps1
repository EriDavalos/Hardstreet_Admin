# Captura el icono mostrado por la ventana del instalador en ejecución.
# Lee el icono de la barra de título de la ventana del proceso y lo guarda como PNG.
# Uso: powershell -File tool/capture_wizard_icon.ps1
$ErrorActionPreference = "Stop"
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public static class WinIcon {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static IntPtr FindByPid(uint pid) {
    IntPtr res = IntPtr.Zero, wnd = IntPtr.Zero;
    do {
      wnd = FindWindowEx(IntPtr.Zero, wnd, null, null);
      if (wnd == IntPtr.Zero) break;
      uint p; GetWindowThreadProcessId(wnd, out p);
      if (p == pid) { res = wnd; break; }
    } while (true);
    return res;
  }
}
"@

$proc = Get-Process | Where-Object { $_.ProcessName -like "HardstreetAdmin-setup*" } | Select-Object -First 1
if (-not $proc) { Write-Host "No hay ningun instalador en ejecucion"; exit 1 }
Write-Host ("instalador en ejecucion: pid {0}" -f $proc.Id)

$wnd = [WinIcon]::FindByPid([uint32]$proc.Id)
if ($wnd -eq [IntPtr]::Zero) { Write-Host "No se encontro la ventana"; exit 1 }

# WM_GETICON: ICON_SMALL2=2, ICON_SMALL=0, ICON_BIG=1
$hIcon = [IntPtr]::Zero
foreach ($m in @(2, 0, 1)) {
  $hIcon = [WinIcon]::SendMessage($wnd, 0x007F, [IntPtr]$m, [IntPtr]::Zero)
  if ($hIcon -ne [IntPtr]::Zero) { break }
}
if ($hIcon -eq [IntPtr]::Zero) {
  $hIcon = [WinIcon]::SendMessage($wnd, 0x0080, [IntPtr]::Zero, [IntPtr]::Zero) # WM_SETICON fallback
}
if ($hIcon -eq [IntPtr]::Zero) { Write-Host "No se pudo leer el icono de la ventana"; exit 1 }

$ico = System.Drawing.Icon::FromHandle($hIcon)
$bmp = New-Object System.Drawing.Bitmap($ico.ToBitmap())
$out = "build\_wizard_icon_from_window.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("icono del wizard capturado: {0}x{1} -> {2}" -f $bmp.Width, $bmp.Height, $out)
[WinIcon]::DestroyIcon($hIcon) | Out-Null
