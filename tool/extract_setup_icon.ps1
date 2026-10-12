# Extrae el icono de wizard desde el .exe del instalador (usando la API de
# Windows para leer el recurso RT_ICON) y lo compara contra setup_icon.ico,
# que es lo que el .iss declara como SetupIconFile.
# Uso: powershell -File tool/extract_setup_icon.ps1
param(
  [string]$Setup = "build\installer\HardstreetAdmin-setup-1.0.1.exe",
  [string]$RefIco = "windows\runner\resources\setup_icon.ico",
  [string]$OutPng = "build\_setup_icon_from_exe.png"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public static class IconPuller {
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadImage(IntPtr hInst, string name, uint type, int cx, int cy, uint fuLoad);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);
  [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr h);
  public static Bitmap Pull(string exe) {
    IntPtr h = LoadLibraryEx(exe, IntPtr.Zero, 2 /* LOAD_LIBRARY_AS_DATAFILE */);
    if (h == IntPtr.Zero) throw new Exception("LoadLibraryEx fallo");
    // IMAGE_ICON = 1, SM_CXICON = 11
    IntPtr hIcon = LoadImage(h, "#101", 1, 0, 0, 0);
    if (hIcon == IntPtr.Zero) hIcon = LoadImage(h, "#1", 1, 0, 0, 0);
    FreeLibrary(h);
    if (hIcon == IntPtr.Zero) throw new Exception("LoadImage icono fallo");
    using (Icon ico = System.Drawing.Icon.FromHandle(hIcon)) {
      return new Bitmap(ico.ToBitmap());
    }
  }
}
"@

$setupFull = (Resolve-Path $Setup).Path
$bmp = [IconPuller]::Pull($setupFull)
$bmp.Save((Join-Path (Get-Location) $OutPng), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("icono extraido del setup: {0}x{1} -> {2}" -f $bmp.Width, $bmp.Height, $OutPng)

# Compara contra la entrada 32x32 del ico de referencia reescalando al mismo tama;no.
$ref = New-Object System.Drawing.Icon((Resolve-Path $RefIco).Path, 32, 32)
$refBmp = New-Object System.Drawing.Bitmap($ref.ToBitmap())
$maxDelta = 0
$w = [Math]::Min($bmp.Width, $refBmp.Width)
$h = [Math]::Min($bmp.Height, $refBmp.Height)
for ($y = 0; $y -lt $h; $y++) {
  for ($x = 0; $x -lt $w; $x++) {
    $a = $bmp.GetPixel($x, $y); $b = $refBmp.GetPixel($x, $y)
    foreach ($c in @("R","G","B")) {
      $d = [Math]::Abs($a.$c - $b.$c); if ($d -gt $maxDelta) { $maxDelta = $d }
    }
  }
}
Write-Host ("delta max por canal vs {0}: {1}" -f $RefIco, $maxDelta)
if ($maxDelta -le 24) { Write-Host "OK: el wizard del setup coincide con setup_icon.ico (hs_icon.png)" }
else { Write-Host "REVISAR: el wizard del setup NO coincide con setup_icon.ico" }
