# Enumera los recursos RT_ICON (id 3) del .exe del instalador y compara cada
# uno contra las entradas de setup_icon.ico, reescalando por el factor de
# correspondencia. Confirma que el wizard usa el ico regenerado desde
# hs_icon.png.
# Uso: powershell -File tool/verify_setup_icon.ps1
param(
  [string]$Setup = "build\installer\HardstreetAdmin-setup-1.0.1.exe",
  [string]$RefIco = "windows\runner\resources\setup_icon.ico"
)
$ErrorActionPreference = "Stop"
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public static class ResEnum {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint flags);
  [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr h);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr FindResource(IntPtr h, string name, string type);
  [DllImport("kernel32.dll")] public static extern IntPtr LoadResource(IntPtr h, IntPtr r);
  [DllImport("kernel32.dll")] public static extern IntPtr LockResource(IntPtr r);
  [DllImport("kernel32.dll")] public static extern uint SizeofResource(IntPtr h, IntPtr r);

  public static byte[] Get(IntPtr h, string name) {
    IntPtr r = FindResource(h, name, "#3"); // RT_ICON = 3
    if (r == IntPtr.Zero) return null;
    uint sz = SizeofResource(h, r);
    IntPtr p = LockResource(LoadResource(h, r));
    byte[] b = new byte[sz];
    Marshal.Copy(p, b, 0, (int)sz);
    return b;
  }
  // Convierte un recurso DIB 32bpp (BITMAPINFOHEADER + BGRA bottom-up) en Bitmap.
  public static Bitmap ToBitmap(byte[] res) {
    int w = BitConverter.ToInt32(res, 4);
    int h = Math.Abs(BitConverter.ToInt32(res, 8)) / 2;
    int bpp = BitConverter.ToUInt16(res, 14);
    if (bpp != 32) return null;
    Bitmap bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
    for (int y = 0; y < h; y++) {
      int srcRow = h - 1 - y; // bottom-up
      for (int x = 0; x < w; x++) {
        int s = 20 + (srcRow * w + x) * 4; // 20 = sizeof(BITMAPINFOHEADER)
        byte b = res[s], g = res[s+1], r = res[s+2], a = res[s+3];
        bmp.SetPixel(x, y, Color.FromArgb(a, r, g, b));
      }
    }
    return bmp;
  }
}
"@

$setupFull = (Resolve-Path $Setup).Path
$h = [ResEnum]::LoadLibraryEx($setupFull, [IntPtr]::Zero, 2)
if ($h -eq [IntPtr]::Zero) { throw "LoadLibraryEx fallo" }

# Recorre ids 1..32 buscando recursos RT_ICON presentes.
$found = @()
for ($id = 1; $id -le 32; $id++) {
  $bytes = [ResEnum]::Get($h, "#$id")
  if ($bytes -ne $null) { $found += ,@{ id = $id; bytes = $bytes } }
}
[ResEnum]::FreeLibrary($h) | Out-Null
Write-Host ("RT_ICON encontrados en el setup: {0} (ids: {1})" -f $found.Count, (($found | ForEach-Object { $_.id }) -join ','))

# Entradas del ico de referencia (solo 32bpp), convertidas a Bitmap.
$ref = New-Object System.Drawing.Icon((Resolve-Path $RefIco).Path, 32, 32)
$refBmp = New-Object System.Drawing.Bitmap($ref.ToBitmap())

$bestDelta = 255
foreach ($f in $found) {
  $bmp = [ResEnum]::ToBitmap($f.bytes)
  if ($bmp -eq $null) { Write-Host ("  id {0}: bpp != 32, omitido" -f $f.id); continue }
  $w = [Math]::Min($bmp.Width, $refBmp.Width)
  $h2 = [Math]::Min($bmp.Height, $refBmp.Height)
  $delta = 0
  for ($y = 0; $y -lt $h2; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      $a = $bmp.GetPixel($x, $y); $b = $refBmp.GetPixel($x, $y)
      foreach ($c in @("R","G","B")) {
        $d = [Math]::Abs($a.$c - $b.$c); if ($d -gt $delta) { $delta = $d }
      }
    }
  }
  if ($delta -lt $bestDelta) { $bestDelta = $delta }
  Write-Host ("  id {0}: {1}x{2} deltaMax={3}" -f $f.id, $bmp.Width, $bmp.Height, $delta)
}
Write-Host ("mejor delta vs setup_icon.ico: {0}" -f $bestDelta)
if ($bestDelta -le 24) { Write-Host "OK: el wizard del setup usa setup_icon.ico (hs_icon.png)" }
else { Write-Host "REVISAR: el wizard del setup NO coincide con setup_icon.ico" }
