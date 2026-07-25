; DCS Pre-Flight Launcher - Inno Setup script
; Per-user install (no admin) so apps.json stays writable next to the scripts.

#define AppName    "DCS Pre-Flight Launcher"
#define AppVersion "1.0.0"
#define AppPublisher "ExpertFett"
#define AppExeName "DCS-Preflight-Manager.bat"

[Setup]
AppId={{7C4B1E90-2F6A-4D51-9A3C-DCSPREFLIGHT01}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\DCS-Preflight
DefaultGroupName=DCS Pre-Flight
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=DCS-Preflight-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create desktop shortcuts"; GroupDescription: "Shortcuts:"

[Files]
Source: "DCS-Preflight.ps1";           DestDir: "{app}"; Flags: ignoreversion
Source: "DCS-Preflight-Manager.ps1";   DestDir: "{app}"; Flags: ignoreversion
Source: "Native.ps1";                  DestDir: "{app}"; Flags: ignoreversion
Source: "Common.ps1";                  DestDir: "{app}"; Flags: ignoreversion
Source: "DCS-Preflight.bat";           DestDir: "{app}"; Flags: ignoreversion
Source: "DCS-Preflight-Manager.bat";   DestDir: "{app}"; Flags: ignoreversion
Source: "README.md";                   DestDir: "{app}"; Flags: ignoreversion

; Shortcuts call powershell.exe directly so no console window flashes for the GUI.
[Icons]
Name: "{group}\DCS Pre-Flight Manager"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DCS-Preflight-Manager.ps1"""; \
    WorkingDir: "{app}"; Comment: "Edit your pre-flight program list"
Name: "{group}\DCS Pre-Flight"; Filename: "{app}\DCS-Preflight.bat"; \
    WorkingDir: "{app}"; Comment: "Run the pre-flight sequence"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

Name: "{autodesktop}\DCS Pre-Flight Manager"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DCS-Preflight-Manager.ps1"""; \
    WorkingDir: "{app}"; Tasks: desktopicon
Name: "{autodesktop}\DCS Pre-Flight"; Filename: "{app}\DCS-Preflight.bat"; \
    WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\DCS-Preflight-Manager.ps1"""; \
    Description: "Open the Manager and set up my programs"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\apps.json"
