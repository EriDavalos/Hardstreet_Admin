# build_installer.ps1 - Compila Hardstreet Admin y genera el instalador.
# Uso:  .\build_installer.ps1              (usa la version de pubspec.yaml)
#       .\build_installer.ps1 1.2.0        (compila con version 1.2.0)
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# ---------- 1. Version ----------
if ($Version -eq "") {
    # Lee version de pubspec.yaml (linea: version: 1.0.0+1)
    $line = (Get-Content pubspec.yaml | Where-Object { $_ -match '^version:\s*(.+)$' })[0]
    $Version = $Matches[1].Split('+')[0].Trim()
}
Write-Host "==> Compilando Hardstreet Admin v$Version ..." -ForegroundColor Cyan

# ---------- 2. Build Windows (SP_VERSION congela la version en el exe) ----------
flutter build windows --release --dart-define=SP_VERSION=$Version
if ($LASTEXITCODE -ne 0) { throw "flutter build windows fallo" }

$release = Join-Path $root "build\windows\x64\runner\Release"
if (-not (Test-Path "$release\HardstreetAdmin.exe")) {
    throw "No se encontro HardstreetAdmin.exe en $release"
}

# ---------- 3. Nombre del artefacto con version ----------
Write-Host "`n==> Build listo en: $release" -ForegroundColor Green

# ---------- 4. Instalador con Inno Setup ----------
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
    Write-Host "`n==> Generando instalador (Inno Setup)..." -ForegroundColor Cyan
    & $iscc /DHS_VERSION=$Version (Join-Path $root "windows\hardstreet_admin.iss") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ISCC fallo" }
    $installer = Join-Path $root "build\installer\HardstreetAdmin-setup-$Version.exe"
    Write-Host "`nINSTALADOR LISTO: $installer" -ForegroundColor Green
} else {
    Write-Warning "Inno Setup 6 no encontrado; se crea ZIP portable."
    $zip = Join-Path $root "build\installer\HardstreetAdmin-$Version-portable.zip"
    Compress-Archive -Path "$release\*" -DestinationPath $zip -Force
    Write-Host "`nZIP PORTABLE LISTO: $zip" -ForegroundColor Green
    Write-Host "Descarga Inno Setup en https://jrsoftware.org/isdl.php para el instalador completo."
}
