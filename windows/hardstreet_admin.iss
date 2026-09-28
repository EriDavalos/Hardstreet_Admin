; Instalador profesional de Hardstreet Admin (Inno Setup 6).
; Se compila con:  ISCC /DHS_VERSION=1.2.0 hardstreet_admin.iss
; (build_installer.ps1 lo hace automatico; HS_VERSION es la version.)

#ifdef HS_VERSION
  #define MyAppVersion HS_VERSION
#else
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "Hardstreet Admin"
#define MyAppExeName "HardstreetAdmin.exe"

[Setup]
; ID fijo de la aplicacion: Windows reconoce actualizaciones sobre la anterior.
AppId={{7E1B2C64-9A5D-4B1E-9C2F-HARDSTREET01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Hardstreet
DefaultDirName={autopf}\HardstreetAdmin
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
; Instala por máquina (Program Files) pidiendo admin; cambia a lowest+user para por-usuario.
PrivilegesRequired=admin
OutputDir=..\build\installer
OutputBaseFilename=HardstreetAdmin-setup-{#MyAppVersion}
; Icono ligero para el instalador (app_icon.ico pesa 4.8MB: excede el
; límite de recursos del setup). Generado desde app_icon.ico sin el frame
; 256x256 sin comprimir.
SetupIconFile=runner\resources\setup_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Todo el contenido de Release\ (exe + dll + data) menos los instaladores.
Source: "..\build\windows\x64\runner\Release\*"; \
    Excludes: "HardstreetAdmin-setup-*.exe,*.iss"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Limpia cachés temporales propios de la app.
Type: filesandordirs; Name: "{userappdata}\..\Local\Temp\hardstreet_cache"
