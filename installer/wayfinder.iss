; =====================================================================
; Wayfinder Inno Setup Script
; =====================================================================
; Builds a lightweight, per-user Windows installer.
; Requires NO administrative privileges (installs to %LocalAppData%\Programs).

#define MyAppName "Wayfinder"
#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Wayfinder"
#define MyAppExeName "Wayfinder.exe"
#define MyAppPckName "Wayfinder.pck"

[Setup]
AppId={{D37E880B-30C5-4A3C-926B-952F372E9A68}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Wayfinder_Setup_v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Base executable and initial resource pack
Source: "..\client\.export\Build.exe"; DestDir: "{app}"; DestName: "{#MyAppExeName}"; Flags: ignoreversion
Source: "..\client\.export\Build.pck"; DestDir: "{app}"; DestName: "{#MyAppPckName}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Clean up any obsolete user:// cached update.pck from prior versions on fresh major install
procedure CurStepChanged(CurStep: TSetupStep);
var
  UserDataPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    UserDataPath := ExpandConstant('{userappdata}\Godot\app_userdata\Wayfinder');
    if FileExists(UserDataPath + '\update.pck') then
    begin
      DeleteFile(UserDataPath + '\update.pck');
    end;
    if FileExists(UserDataPath + '\update_meta.json') then
    begin
      DeleteFile(UserDataPath + '\update_meta.json');
    end;
  end;
end;
