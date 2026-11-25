[Setup]
AppId={{9EDAC514-B395-4D77-BB63-70B7844FE94F}
AppName=Periodify
AppVerName=Periodify
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Periodify
PrivilegesRequired=lowest
OutputDir=..\artifacts
OutputBaseFilename={#InstallerBasename}
SetupIconFile=..\windows\runner\resources\app_icon.ico
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
Filename: "{app}\periodify.exe"; Flags: nowait skipifnotsilent; Check: IsPeriodifyUpdate
[Code]
function IsPeriodifyUpdate: Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ParamCount do
    if CompareText(ParamStr(Index), '/PERIODIFYUPDATE') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;
