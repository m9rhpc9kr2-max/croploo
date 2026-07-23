; Inno Setup script for the Croploo Windows installer.
; Compiled by build-windows.sh via ISCC (Inno Setup 6) when available.
; Invoke with: iscc /DAppVersion=1.0.0 windows\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{4A6B2C6E-8B3B-4C4B-9C7A-2F6E7C9C2B10}}
AppName=Croploo
AppVersion={#AppVersion}
AppPublisher=Croploo
DefaultDirName={autopf}\Croploo
DefaultGroupName=Croploo
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=croploo-windows-setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\croploo.exe
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\Croploo"; Filename: "{app}\croploo.exe"
Name: "{commondesktop}\Croploo"; Filename: "{app}\croploo.exe"

[Run]
Filename: "{app}\croploo.exe"; Description: "Launch Croploo"; Flags: nowait postinstall skipifsilent
