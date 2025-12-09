; Clean Inno Setup script with "Run at startup" via HKCU\Run

#define MyAppName "PCluster"
#define MyAppVersion "0.3"
#define MyAppPublisher "Systhetic"
#define MyAppURL "www.systhetic.com"
#define MyAppExeName "PCluster_PC_Utility.exe"
#define MyAppManifestName "PCluster_PC_Utility.exe.manifest"
#define MyAppIconName "PClusterIcon.ico"

[Setup]
AppId={{CA461BA6-5B7B-4BE1-835E-63530D342B33}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputBaseFilename=PCluster_Installer
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Optional desktop icon
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
; Run on startup – checked by default on first install
Name: "runonstartup"; Description: "Run {#MyAppName} when Windows starts"; GroupDescription: "Startup options:"; Flags: checkedonce

[Files]
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\{#MyAppManifestName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\config.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\HidLibrary.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\HidLibrary.pdb"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\Newtonsoft.Json.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\Newtonsoft.Json.xml"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\OpenHardwareMonitorLib.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\bin\Release\PCluster_PC_Utility.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\repos\PCluster_Software\windows_src\PCluster_PC_Utility\PCluster_PC_Utility\PClusterIcon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start menu / program list
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\PClusterIcon.ico"
; Desktop icon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\PClusterIcon.ico"; Tasks: desktopicon

[Registry]
; Run at logon for all users (shows in Task Manager -> Startup as a registry startup)
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
    ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; \
    Flags: uninsdeletevalue; Tasks: runonstartup
    
[Run]
; Normal "Launch now" entry
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec runascurrentuser
