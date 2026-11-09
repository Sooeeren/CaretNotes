# Builds build\single_exe\CaretNotes.exe: one file that runs CaretNotes without
# anything next to it. Run `flutter build windows --release` first.
# Needs Visual Studio Build Tools (C++ workload).
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$release = "$root\build\windows\x64\runner\Release"
$out = "$root\build\single_exe"
if (-not (Test-Path "$release\caret_notes.exe")) { throw "Run 'flutter build windows --release' first." }

$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ build tools not found.' }

# The app plus the C++ runtime DLLs it needs, so it also runs on PCs without the VC++ redistributable.
$stage = "$out\stage"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item -Recurse "$release\*" $stage
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName | Select-Object -Last 1
foreach ($dll in 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item "$($crt.FullName)\$dll" $stage
}

$src = $PSScriptRoot
$script = "$out\build.cmd"
@"
@echo off
call "$vs\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "$out" || exit /b 1
rc /nologo /fo launcher.res "$src\launcher.rc" || exit /b 1
cl /nologo /O2 /EHsc /std:c++17 /MT /DUNICODE /D_UNICODE "$src\launcher.cpp" launcher.res /Fe:launcher.exe /link /SUBSYSTEM:WINDOWS cabinet.lib shlwapi.lib user32.lib || exit /b 1
cl /nologo /O2 /EHsc /std:c++20 /MT /DUNICODE /D_UNICODE "$src\pack.cpp" /Fe:pack.exe /link cabinet.lib || exit /b 1
"$out\pack.exe" stage launcher.exe CaretNotes.exe || exit /b 1
"@ | Set-Content -Encoding ascii $script
cmd /c "`"$script`""
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }
Write-Host "Built $out\CaretNotes.exe"
