# Verifica que la ventana de Hardstreet Admin este maximizada: su rect debe
# coincidir con el area de trabajo (excluye la barra de tareas).
# Uso: powershell -ExecutionPolicy Bypass -File tool\verify_maximized.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinProbe {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [StructLayout(LayoutKind.Sequential)]
  public struct WINDOWPLACEMENT {
    public int length; public int flags; public int showCmd;
    public POINT ptMinPosition; public POINT ptMaxPosition; public RECT rcNormalPosition;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int x, y; }
}
"@

$proc = Get-Process -Name "HardstreetAdmin" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Host "Hardstreet Admin no esta en ejecucion"; exit 2 }
$h = $proc.MainWindowHandle

$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$rect = New-Object WinProbe+RECT
[WinProbe]::GetWindowRect($h, [ref]$rect) | Out-Null
$zoomed = [WinProbe]::IsZoomed($h)

Write-Host ("area de trabajo : {0},{1}  {2}x{3}" -f $wa.X, $wa.Y, $wa.Width, $wa.Height)
Write-Host ("ventana         : {0},{1}  {2}x{3}" -f $rect.Left, $rect.Top, `
            ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
Write-Host ("IsZoomed        : {0}" -f $zoomed)

# Una ventana maximizada en Win10/11 incluye el borde invisible de DWM (~7px
# por lado): GetWindowRect queda algo MAYOR que el area de trabajo. Comparamos
# borde a borde (Left vs X, Right vs X+Width, etc.) con tolerancia de 8px y
# exigimos IsZoomed.
$winRight  = $rect.Right
$winBottom = $rect.Bottom
$dx = [Math]::Abs($rect.Left - $wa.X)
$dy = [Math]::Abs($rect.Top - $wa.Y)
$dr = [Math]::Abs($winRight - ($wa.X + $wa.Width))
$db = [Math]::Abs($winBottom - ($wa.Y + $wa.Height))
$tol = 8
$fullWorkArea = ($dx -le $tol) -and ($dy -le $tol) -and ($dr -le $tol) -and ($db -le $tol)

Write-Host ("delta borde a borde (L,T,R,B): {0},{1},{2},{3}  tol={4}" -f $dx, $dy, $dr, $db, $tol)
if ($zoomed -and $fullWorkArea) {
  Write-Host "OK: la app arranca maximizada (IsZoomed=true, cubre el area de trabajo)"
  exit 0
} elseif ($fullWorkArea -and -not $zoomed) {
  Write-Host "PARCIAL: cubre el area de trabajo pero sin estado maximizado"
  exit 1
} else {
  Write-Host "FALLA: la ventana NO esta maximizada"
  exit 1
}
