# TOoT:R installer for Windows (driven by Switch2Recomp):
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Nup C:\path\game.nup] [-Dir C:\Games\TOoT-R]
param(
    [string]$Nup = "",
    [string]$Dir = "",
    [string]$Msys = "C:\msys64",
    [string]$ShortcutName = "The Legend of Zelda - Ocarina of Time",
    [string]$IconPath = "",
    [string]$LauncherUiPath = "",
    [switch]$NoDesktopShortcut
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
function Say($msg) { Write-Host "[TOoT:R] $msg" -ForegroundColor Cyan }

if (-not [Environment]::Is64BitOperatingSystem) { Say "a 64-bit Windows is required"; exit 1 }

# ---- MSYS2 ---------------------------------------------------------------------------------------
$bash = Join-Path $Msys "usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    Say "installing MSYS2 (build environment) into $Msys"
    $installed = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id MSYS2.MSYS2 -e --silent --accept-package-agreements --accept-source-agreements --location $Msys
        $installed = Test-Path $bash
    }
    if (-not $installed) {
        $setup = Join-Path $env:TEMP "msys2-installer.exe"
        Invoke-WebRequest "https://repo.msys2.org/distrib/msys2-x86_64-latest.exe" -OutFile $setup
        & $setup in --confirm-command --accept-messages --root ($Msys -replace '\\', '/') | Out-Null
        Remove-Item $setup -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $bash)) { Say "MSYS2 could not be installed; install it from https://www.msys2.org and run this again"; exit 1 }
}

function Msys($cmd) {
    $env:MSYSTEM = "CLANG64"
    $env:CHERE_INVOKING = "1"
    & $bash -lc $cmd
    if ($LASTEXITCODE -ne 0) { throw "MSYS2 command failed: $cmd" }
}
Say "updating MSYS2 and installing the build tools (this takes a while the first time)"
& $bash -lc "pacman -Syu --noconfirm" | Out-Host   # (may update the core and stop; run twice)
& $bash -lc "pacman -Syu --noconfirm" | Out-Host
$packages = "clang lld cmake ninja python pkgconf sdl3 opus ffmpeg vulkan-loader vulkan-headers fmt zstd lz4" -split " " |
    ForEach-Object { "mingw-w64-clang-x86_64-$_" }
Msys ("pacman -S --needed --noconfirm " + ($packages -join " "))

# ---- source ---------------------------------------------------------------------------------------
$source = $PSScriptRoot
if (-not (Test-Path (Join-Path $source "tools\build_game.py"))) {
    Say "error: tools\build_game.py not found in $source"
    exit 1
}

# ---- the game -------------------------------------------------------------------------------------
if (-not $Nup) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select your dump of The Legend of Zelda: Ocarina of Time (Switch 2, v131072)"
    $dialog.Filter = "Switch 2 package (*.nup)|*.nup|All files (*.*)|*.*"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Say "no game file selected"; exit 1 }
    $Nup = $dialog.FileName
}
if (-not (Test-Path -LiteralPath $Nup)) { Say "no such file: $Nup"; exit 1 }
if (-not $Dir) {
    $default = Join-Path $env:LOCALAPPDATA "tootr"
    Add-Type -AssemblyName System.Windows.Forms
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.Description = "Choose where to install TOoT:R (a TOoT-R folder is made there). Cancel: $default"
    $folder.ShowNewFolderButton = $true
    if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $folder.SelectedPath) { $Dir = Join-Path $folder.SelectedPath "TOoT-R" }
    else { $Dir = $default }
}
$Dir = [System.IO.Path]::GetFullPath($Dir)
Say "installing into $Dir"

# ---- build ----------------------------------------------------------------------------------------
$clang64 = Join-Path $Msys "clang64\bin"
$env:PATH = "$clang64;" + (Join-Path $Msys "usr\bin") + ";$env:PATH"
$env:MSYSTEM = "CLANG64"
$python = Join-Path $clang64 "python.exe"
& $python (Join-Path $source "tools\launcher.py") install --source $source --nup $Nup --dir $Dir
if ($LASTEXITCODE -ne 0) { Say "the build failed; see the messages above"; exit 1 }
if ($temp) { Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue }

# ---- shortcuts & pre-launch UI -------------------------------------------------------------------
$data = $Dir
$launcherUiDst = Join-Path $data "game_launcher.py"
$launcherUiSrc = $LauncherUiPath
if (-not $launcherUiSrc -or -not (Test-Path -LiteralPath $launcherUiSrc)) {
    $toolsExe = Join-Path $source "..\..\game_launcher.exe"
    $exeCand = Join-Path $source "..\..\..\game_launcher.exe"
    if (Test-Path -LiteralPath $toolsExe) { $launcherUiSrc = $toolsExe }
    elseif (Test-Path -LiteralPath $exeCand) { $launcherUiSrc = $exeCand }
    else { $launcherUiSrc = Join-Path $source "..\..\..\src\game_launcher.py" }
}
$isLauncherExe = $launcherUiSrc -match "\.exe$"
$launcherUiDst = Join-Path $data $(if ($isLauncherExe) { "game_launcher.exe" } else { "game_launcher.py" })
if (Test-Path -LiteralPath $launcherUiSrc) {
    Copy-Item -LiteralPath $launcherUiSrc -Destination $launcherUiDst -Force
}

$globalSaveDir = Join-Path (Split-Path $data -Parent) "Saves\The Legend of Zelda - Ocarina of Time"
New-Item -ItemType Directory -Force -Path $globalSaveDir | Out-Null
$localSaveDir = Join-Path $data "save"
if ((Test-Path -LiteralPath $localSaveDir) -and -not (Get-ChildItem -LiteralPath $globalSaveDir -Force | Select-Object -First 1)) {
    Get-ChildItem -LiteralPath $localSaveDir -Force | Copy-Item -Destination $globalSaveDir -Recurse -Force -ErrorAction SilentlyContinue
}

$templatePath = Join-Path $source "launch_options_template.json"
$launchConfigPath = Join-Path $data "launch_options.json"
if (Test-Path -LiteralPath $templatePath) {
    $tpl = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tpl | Add-Member -NotePropertyName "working_dir" -NotePropertyValue $data -Force
    $tpl | Add-Member -NotePropertyName "command" -NotePropertyValue @($python, (Join-Path $data "source\tools\launcher.py"), "run") -Force
    $tpl | Add-Member -NotePropertyName "env" -NotePropertyValue @{
        "PATH" = "$clang64;$Msys\usr\bin"
        "MSYSTEM" = "CLANG64"
        "OOT_RECOMP_HOME" = $data
        "OOT_SAVE_DIR" = $globalSaveDir
    } -Force
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($launchConfigPath, ($tpl | ConvertTo-Json -Depth 10), $utf8NoBom)
}

$hostPythonw = $null
$pyCandidates = @(Get-Command pythonw.exe -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) +
                @(Get-Command python.exe -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
foreach ($cand in $pyCandidates) {
    if ($cand -and ($cand -notmatch "\\msys64\\")) {
        $probeExe = if ($cand -match "pythonw\.exe$") { $cand -replace "pythonw\.exe$", "python.exe" } else { $cand }
        if (Test-Path -LiteralPath $probeExe) {
            & $probeExe -c "import PySide6" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $hostPythonw = $cand
                break
            }
        }
    }
}

$runner = Join-Path $data "tootr.cmd"
if ($isLauncherExe -and (Test-Path -LiteralPath $launcherUiDst) -and (Test-Path -LiteralPath $launchConfigPath)) {
@"
@echo off
cd /d "$data"
"$launcherUiDst" --config "$launchConfigPath" %*
"@ | Set-Content -Encoding ASCII $runner
} elseif ($hostPythonw -and (Test-Path -LiteralPath $launcherUiDst) -and (Test-Path -LiteralPath $launchConfigPath)) {
@"
@echo off
cd /d "$data"
"$hostPythonw" "$launcherUiDst" --config "$launchConfigPath" %*
"@ | Set-Content -Encoding ASCII $runner
} else {
@"
@echo off
rem tootr: starts the game.
set "PATH=$clang64;$Msys\usr\bin;%PATH%"
set MSYSTEM=CLANG64
set OOT_MESH_NOCULL=1
set "OOT_RECOMP_HOME=$data"
cd /d "$data"
"$python" "$data\source\tools\launcher.py" run %*
if errorlevel 1 pause
"@ | Set-Content -Encoding ASCII $runner
}

$iconSrc = $IconPath
if (-not $iconSrc -or -not (Test-Path -LiteralPath $iconSrc)) {
    $iconSrc = Join-Path $source "game_icon.ico"
}
$iconDst = Join-Path $data "game_icon.ico"
if (Test-Path -LiteralPath $iconSrc) {
    Copy-Item -LiteralPath $iconSrc -Destination $iconDst -Force
}
$pngSrc = Join-Path $source "game_icon.png"
$pngDst = Join-Path $data "game_icon.png"
if (Test-Path -LiteralPath $pngSrc) {
    Copy-Item -LiteralPath $pngSrc -Destination $pngDst -Force
}

$shortcutDirs = @([Environment]::GetFolderPath("Programs"))
if (-not $NoDesktopShortcut) {
    $shortcutDirs += [Environment]::GetFolderPath("Desktop")
}

$safeShortcutName = ($ShortcutName -replace '[<>:"/\\|?*]+', ' -').Trim()
if (-not $safeShortcutName) { $safeShortcutName = "The Legend of Zelda - Ocarina of Time" }

$shell = New-Object -ComObject WScript.Shell
foreach ($dir in $shortcutDirs) {
    $link = $shell.CreateShortcut((Join-Path $dir "$safeShortcutName.lnk"))
    $link.TargetPath = $runner
    $link.WorkingDirectory = $data
    $link.Description = "$safeShortcutName - Native PC port"
    if (Test-Path -LiteralPath $iconDst) {
        $link.IconLocation = "$iconDst,0"
    }
    $link.Save()
}

# Clean up temporary build/intermediate directories if present
foreach ($tmpDir in @(
    (Join-Path $data "_builder"),
    (Join-Path $data "_extracted"),
    (Join-Path $data "_work"),
    (Join-Path $data "build\CMakeFiles")
)) {
    if (Test-Path -LiteralPath $tmpDir) {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

# Register in Windows Installed Apps + create uninstaller (never deletes the .nup ROM)
$uninstKeyName = "Switch2Recomp_" + ($safeShortcutName -replace '[^A-Za-z0-9_-]', '_')
$uninstRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$uninstKeyName"
$uninstPs1 = Join-Path $data "uninstall.ps1"
$desktopLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "$safeShortcutName.lnk"
$startMenuLnk = Join-Path ([Environment]::GetFolderPath("Programs")) "$safeShortcutName.lnk"
$uninstScript = @"
Add-Type -AssemblyName System.Windows.Forms
`$res = [System.Windows.Forms.MessageBox]::Show(
    "Voulez-vous désinstaller $safeShortcutName ?`n`nLe dossier d'installation et les raccourcis seront supprimés.`nVotre fichier ROM (.nup) et vos sauvegardes ne seront PAS supprimés.",
    "Désinstaller $safeShortcutName",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)
if (`$res -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }
foreach (`$lnk in @("$desktopLnk", "$startMenuLnk")) {
    if (Test-Path -LiteralPath `$lnk) { Remove-Item -LiteralPath `$lnk -Force -ErrorAction SilentlyContinue }
}
if (Test-Path -LiteralPath "$uninstRegPath") {
    Remove-Item -LiteralPath "$uninstRegPath" -Recurse -Force -ErrorAction SilentlyContinue
}
Set-Location `$env:TEMP
Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 1 /nobreak >nul & rmdir /s /q ``"$data``"" -WindowStyle Hidden
"@
[System.IO.File]::WriteAllText($uninstPs1, $uninstScript, (New-Object System.Text.UTF8Encoding($true)))

$sizeKb = [int](((Get-ChildItem -LiteralPath $data -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) / 1KB)
New-Item -Path $uninstRegPath -Force | Out-Null
Set-ItemProperty -Path $uninstRegPath -Name "DisplayName" -Value $safeShortcutName
Set-ItemProperty -Path $uninstRegPath -Name "Publisher" -Value "Switch2Recomp (NUP Studio)"
Set-ItemProperty -Path $uninstRegPath -Name "InstallLocation" -Value $data
if (Test-Path -LiteralPath $iconDst) { Set-ItemProperty -Path $uninstRegPath -Name "DisplayIcon" -Value "$iconDst,0" }
$uninstCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$uninstPs1`""
Set-ItemProperty -Path $uninstRegPath -Name "UninstallString" -Value $uninstCmd
Set-ItemProperty -Path $uninstRegPath -Name "QuietUninstallString" -Value $uninstCmd
Set-ItemProperty -Path $uninstRegPath -Name "NoModify" -Value 1 -Type DWord
Set-ItemProperty -Path $uninstRegPath -Name "NoRepair" -Value 1 -Type DWord
Set-ItemProperty -Path $uninstRegPath -Name "EstimatedSize" -Value $sizeKb -Type DWord

Say "installed. Start the game from the Start menu or the desktop shortcut."
