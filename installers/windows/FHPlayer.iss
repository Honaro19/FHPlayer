#define MyAppName "FHPlayer"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "FHPlayer"
#define MyAppExeName "FHPlayer.exe"
#define MyAppId "{{F9F3836C-78A0-4691-A5FB-17CF066409AC}}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\FHPlayer
DefaultGroupName=FHPlayer
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist-installer
OutputBaseFilename=FHPlayer-Setup
SetupIconFile=..\..\assets\branding\fhplayer.ico
UninstallDisplayIcon={app}\FHPlayer.exe
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Dirs]
Name: "{localappdata}\FHPlayer\Library\Videos"
Name: "{localappdata}\FHPlayer\Library\Funscripts"
Name: "{localappdata}\FHPlayer\Library\Exports"

[Files]
Source: "..\..\dist\FHPlayer\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FHPlayer"; Filename: "{app}\FHPlayer.exe"; IconFilename: "{app}\FHPlayer.exe"
Name: "{autodesktop}\FHPlayer"; Filename: "{app}\FHPlayer.exe"; Tasks: desktopicon; IconFilename: "{app}\FHPlayer.exe"

[Run]
Filename: "{app}\FHPlayer.exe"; Description: "Launch FHPlayer"; Flags: nowait postinstall skipifsilent
