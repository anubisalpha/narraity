; Inno Setup script for Narraity's Windows installer.
;
; Deliberately unsigned -- see PLAN.md's "Windows packaging" decision and
; DEVELOPMENT.md's "Building the Windows installer" section for why the
; earlier signed-MSIX approach was dropped. Users see a one-time "Windows
; protected your PC" SmartScreen prompt on first run; there's no certificate
; to install or trust.
;
; AppVersion is passed in from build_installer.ps1 via /DAppVersion=X.Y.Z so
; it stays in sync with pubspec.yaml without editing this file per release.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8F5C6E3A-2B4A-4C5D-9E1F-3A7B8C9D0E1F}
AppName=Narraity
AppVersion={#AppVersion}
AppPublisher=Anubis Productions
DefaultDirName={autopf}\Narraity
DefaultGroupName=Narraity
UninstallDisplayIcon={app}\narraity.exe
Compression=lzma2
SolidCompression=yes
OutputDir=..\build\windows\x64\runner\Release
OutputBaseFilename=narraity-setup
SetupIconFile=runner\resources\app_icon.ico
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "narraity-setup.exe"

[Icons]
Name: "{group}\Narraity"; Filename: "{app}\narraity.exe"
Name: "{group}\{cm:UninstallProgram,Narraity}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Narraity"; Filename: "{app}\narraity.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\narraity.exe"; Description: "{cm:LaunchProgram,Narraity}"; Flags: nowait postinstall skipifsilent
