; CaretNotes installer (Inno Setup 6). Built by packaging\windows\build.ps1:
;   ISCC /DAppVersion=1.3.0 /DSourceDir=<Release folder + VC++ runtime> caretnotes.iss
; Installs per user (no admin prompt), so the in-app updater can run it with /SILENT.
; Uninstalling never touches the notes in %APPDATA%\dev.caretnotes.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{429CC1BC-A825-41BF-803B-086739FA8B34}
AppName=CaretNotes
AppVersion={#AppVersion}
AppVerName=CaretNotes {#AppVersion}
AppPublisher=Sooeeren
AppPublisherURL=https://github.com/Sooeeren/CaretNotes
AppSupportURL=https://github.com/Sooeeren/CaretNotes/issues
AppUpdatesURL=https://github.com/Sooeeren/CaretNotes/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\CaretNotes
DefaultGroupName=CaretNotes
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=CaretNotes-Setup-{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\caret_notes.exe
UninstallDisplayName=CaretNotes
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; an update closes the running app (it saves its notes on close)
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; old Flutter assets from the previous version
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; tells the in-app updater that this copy was installed with the installer
Source: "install_kind"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\CaretNotes"; Filename: "{app}\caret_notes.exe"
Name: "{autodesktop}\CaretNotes"; Filename: "{app}\caret_notes.exe"; Tasks: desktopicon

[Run]
; also after a silent update, so the new version opens again
Filename: "{app}\caret_notes.exe"; Description: "{cm:LaunchProgram,CaretNotes}"; Flags: nowait postinstall
