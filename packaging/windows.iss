[Setup]
AppId={{9EDAC514-B395-4D77-BB63-70B7844FE94F}
AppName=Periodify
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Periodify
PrivilegesRequired=lowest
OutputDir=..\artifacts
OutputBaseFilename={#InstallerBasename}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\periodify.exe
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{autoprograms}\Periodify"; Filename: "{app}\periodify.exe"
[Run]
Filename: "{app}\periodify.exe"; Description: "Open Periodify"; Flags: nowait postinstall skipifsilent
