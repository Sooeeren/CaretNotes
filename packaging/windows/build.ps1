# Builds the Windows downloads (run `flutter build windows --release` first):
#   build\installer\CaretNotes-Setup-<version>.exe   installer (Inno Setup 6)
#   build\installer\CaretNotes-<version>-portable.exe  one file, no install (tool\single_exe)
# Needs Inno Setup 6 (ISCC.exe) and Visual Studio Build Tools (C++ workload).
param([string]$Version)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
if (-not $Version) { $Version = (Select-String -Path "$root\pubspec.yaml" -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value }
$release = "$root\build\windows\x64\runner\Release"
if (-not (Test-Path "$release\caret_notes.exe")) { throw "Run 'flutter build windows --release' first." }
$out = "$root\build\installer"
New-Item -ItemType Directory -Force $out | Out-Null

# The app plus the C++ runtime DLLs, so it also runs on PCs without the VC++ redistributable.
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ build tools not found.' }
$stage = "$root\build\installer\stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item -Recurse "$release\*" $stage
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName | Select-Object -Last 1
foreach ($dll in 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item "$($crt.FullName)\$dll" $stage
}

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source }
if (-not $iscc) { throw 'Inno Setup 6 not found (winget install JRSoftware.InnoSetup).' }
& $iscc /Q "/DAppVersion=$Version" "/DSourceDir=$stage" "$PSScriptRoot\caretnotes.iss"
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

& "$root\tool\single_exe\build.ps1"
Copy-Item "$root\build\single_exe\CaretNotes.exe" "$out\CaretNotes-$Version-portable.exe" -Force
Get-ChildItem $out -Filter *.exe | Format-Table Name, Length
