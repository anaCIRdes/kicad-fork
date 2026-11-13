# Baut den KiCad-Workspace-Fork unter Windows (MSVC + vcpkg) und erzeugt den Installer.
# Wird stufenweise von .github/workflows/windows-installer.yml aufgerufen, laesst sich aber
# genauso auf einem eigenen Windows-PC mit Visual Studio 2022 Build Tools ausfuehren:
#
#   pwsh ci\build.ps1 -Stage prepare
#   pwsh ci\build.ps1 -Stage configure
#   pwsh ci\build.ps1 -Stage build
#   pwsh ci\build.ps1 -Stage package
#   pwsh ci\build.ps1 -Stage smoke
#   pwsh ci\build.ps1 -Stage installer
#
# Arbeitsverzeichnis ist C:\k (kurz wegen der Windows-Pfadlaengen), aenderbar ueber KWS_ROOT.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('prepare', 'configure', 'build', 'package', 'smoke', 'gui', 'installer', 'logs')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$KicadTag   = '10.0.8'
$VersionExtra = 'riegl-ws3'
$PkgVersion = '10.0.8-rieglws3'

$Repo  = Split-Path -Parent $PSScriptRoot
$Root  = if ($env:KWS_ROOT) { $env:KWS_ROOT } else { 'C:\k' }
$Src   = Join-Path $Root 'src'
$Bld   = Join-Path $Root 'b'
$Stg   = Join-Path $Root 'stage'
$Out   = Join-Path $Root 'out'
$Logs  = Join-Path $Out  'logs'
$Vcpkg = Join-Path $Root 'vcpkg'
$Cache = Join-Path $Root 'vc'
$Triplet = 'x64-windows'
$VcInst  = Join-Path $Bld "vcpkg_installed\$Triplet"

function Section([string]$Text) { Write-Host ''; Write-Host "==== $Text ====" -ForegroundColor Cyan }

function Ensure-Dir([string]$Path) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }

function Check-Exit([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What fehlgeschlagen (Exit-Code $LASTEXITCODE)" }
}

# Laedt die Umgebung des 64-Bit-MSVC-Compilers (vcvars64.bat) in diesen Prozess.
function Import-VsEnv {
    if ($env:VSCMD_VER -and $env:VSCMD_ARG_TGT_ARCH -eq 'x64') { return }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe nicht gefunden - ist Visual Studio 2022 (Build Tools) installiert?' }

    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Keine Visual-Studio-Installation mit C++-Werkzeugen gefunden.' }

    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    Write-Host "MSVC-Umgebung: $vcvars"

    $lines = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }

    if (-not $env:VSCMD_VER) { throw 'vcvars64.bat konnte nicht geladen werden.' }
    Write-Host "Visual Studio $env:VSCMD_VER, Compiler-Werkzeuge $env:VCToolsVersion"
}

function Find-MakeNsis {
    $cmd = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-Swig {
    $cmd = Get-Command swig.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $hit = Get-ChildItem 'C:\ProgramData\chocolatey\lib\swig' -Recurse -Filter swig.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

# ---------------------------------------------------------------------------------------------
switch ($Stage) {

'prepare' {
    Ensure-Dir $Root; Ensure-Dir $Out; Ensure-Dir $Logs; Ensure-Dir $Cache

    Section 'Werkzeuge'
    if (-not (Find-Swig)) {
        choco install swig --no-progress -y
        Check-Exit 'Installation von SWIG'
    }
    if (-not (Find-MakeNsis)) {
        choco install nsis --no-progress -y
        Check-Exit 'Installation von NSIS'
    }
    Write-Host "SWIG: $(Find-Swig)"
    Write-Host "NSIS: $(Find-MakeNsis)"
    cmake --version | Select-Object -First 1
    ninja --version

    Section "KiCad $KicadTag holen"
    if (-not (Test-Path (Join-Path $Src '.git'))) {
        $ok = $false
        foreach ($url in @('https://gitlab.com/kicad/code/kicad.git', 'https://github.com/KiCad/kicad-source-mirror.git')) {
            Write-Host "Quelle: $url"
            if (Test-Path $Src) { Remove-Item -Recurse -Force $Src }
            git -c core.autocrlf=false clone --depth 1 --branch $KicadTag $url $Src
            if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        }
        if (-not $ok) { throw 'KiCad-Quellcode konnte nicht geholt werden.' }

        git -C $Src config core.autocrlf false
        git -C $Src checkout -q -b riegl-workspace
        Check-Exit 'git checkout'

        Section 'Fork-Patch anwenden'
        $patch = Join-Path $Repo "patch\kicad-$KicadTag-riegl-workspace.patch"
        git -C $Src -c user.name='fork-build' -c user.email='fork-build@localhost' am $patch
        Check-Exit 'git am (Patch)'
        git -C $Src log --oneline -n 8
    }

    Section 'vcpkg holen'
    if (-not (Test-Path (Join-Path $Vcpkg 'vcpkg.exe'))) {
        if (Test-Path $Vcpkg) { Remove-Item -Recurse -Force $Vcpkg }
        git clone https://github.com/microsoft/vcpkg.git $Vcpkg
        Check-Exit 'git clone vcpkg'
        & (Join-Path $Vcpkg 'bootstrap-vcpkg.bat') -disableMetrics
        Check-Exit 'vcpkg bootstrap'
    }
    & (Join-Path $Vcpkg 'vcpkg.exe') version
}

'configure' {
    Import-VsEnv
    Ensure-Dir $Logs; Ensure-Dir $Cache

    $env:VCPKG_DEFAULT_BINARY_CACHE = $Cache
    $env:VCPKG_ROOT = $Vcpkg
    $swig = Find-Swig
    if (-not $swig) { throw 'swig.exe nicht gefunden (Stufe prepare ausfuehren).' }

    Section 'CMake konfigurieren (baut beim ersten Mal alle Abhaengigkeiten mit vcpkg)'
    $cmakeArgs = @(
        '-G', 'Ninja',
        '-S', $Src,
        '-B', $Bld,
        "-DCMAKE_TOOLCHAIN_FILE=$Vcpkg\scripts\buildsystems\vcpkg.cmake",
        "-DVCPKG_TARGET_TRIPLET=$Triplet",
        "-DVCPKG_OVERLAY_TRIPLETS=$Repo\ci\triplets",
        '-DVCPKG_INSTALL_OPTIONS=--clean-after-build',
        '-DCMAKE_BUILD_TYPE=Release',
        "-DCMAKE_INSTALL_PREFIX=$Stg",
        "-DSWIG_EXECUTABLE=$swig",
        '-DKICAD_SCRIPTING_WXPYTHON=ON',
        '-DKICAD_BUILD_I18N=ON',
        '-DKICAD_BUILD_QA_TESTS=OFF',
        '-DKICAD_WIN32_DPI_AWARE=ON',
        '-DKICAD_UPDATE_CHECK=OFF',
        "-DKICAD_VERSION_EXTRA=$VersionExtra"
    )
    Write-Host "cmake $($cmakeArgs -join ' ')"
    & cmake @cmakeArgs 2>&1 | Tee-Object -FilePath (Join-Path $Logs 'configure.log')
    Check-Exit 'CMake-Konfiguration'
}

'build' {
    Import-VsEnv
    Ensure-Dir $Logs

    Section 'KiCad kompilieren'
    & cmake --build $Bld 2>&1 | Tee-Object -FilePath (Join-Path $Logs 'build.log')
    Check-Exit 'Kompilieren'
}

'package' {
    Import-VsEnv
    Ensure-Dir $Logs
    $bin = Join-Path $Stg 'bin'

    Section 'Installieren in den Paketbaum'
    if (Test-Path $Stg) { Remove-Item -Recurse -Force $Stg }
    & cmake --install $Bld 2>&1 | Out-File -FilePath (Join-Path $Logs 'install.log') -Encoding utf8
    Check-Exit 'cmake --install'
    if (-not (Test-Path (Join-Path $bin 'kicad.exe'))) { throw "kicad.exe fehlt in $bin" }

    Section 'Laufzeitbibliotheken der Abhaengigkeiten (vcpkg)'
    $n = 0
    Get-ChildItem (Join-Path $VcInst 'bin') -Filter *.dll -File | ForEach-Object {
        $dst = Join-Path $bin $_.Name
        if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst; $n++ }
    }
    Write-Host "$n DLLs kopiert"

    Section 'Python-Laufzeit'
    # KiCad erwartet unter MSVC das Python-Home im Ordner der Programme (bin\Lib, bin\DLLs).
    $py = Join-Path $VcInst 'tools\python3'
    if (-not (Test-Path (Join-Path $py 'python.exe'))) { throw "Python fehlt unter $py" }
    # /XC /XN /XO: nichts ueberschreiben, was cmake --install bereits abgelegt hat (pcbnew.py, _pcbnew.pyd)
    & robocopy $py $bin /E /XC /XN /XO /NFL /NDL /NJH /NJS /NP /XD __pycache__ test tests idlelib turtledemo | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy (Python) fehlgeschlagen ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0

    Section 'ngspice-Zusatzdateien'
    $cm = Join-Path $VcInst 'lib\ngspice'
    if (Test-Path $cm) {
        Ensure-Dir (Join-Path $Stg 'lib\ngspice')
        Copy-Item (Join-Path $cm '*') (Join-Path $Stg 'lib\ngspice') -Recurse -Force
        Write-Host "Code-Modelle: $((Get-ChildItem (Join-Path $Stg 'lib\ngspice') -Filter *.cm).Count)"
    } else {
        Write-Warning "Keine ngspice-Code-Modelle unter $cm gefunden"
    }
    $ngShare = Join-Path $VcInst 'share\ngspice'
    if (Test-Path $ngShare) {
        Ensure-Dir (Join-Path $Stg 'share\ngspice')
        Copy-Item (Join-Path $ngShare '*') (Join-Path $Stg 'share\ngspice') -Recurse -Force
    }

    Section 'Microsoft-C++-Laufzeit (lokal neben den Programmen)'
    $crtNames = @('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'msvcp140_atomic_wait.dll',
                  'msvcp140_codecvt_ids.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'concrt140.dll', 'vcomp140.dll')
    $crtDirs = @()
    if ($env:VCToolsRedistDir) {
        $crtDirs = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '\.(CRT|OpenMP)$' } | ForEach-Object { $_.FullName }
    }
    foreach ($name in $crtNames) {
        $dst = Join-Path $bin $name
        if (Test-Path $dst) { continue }
        $srcFile = $null
        foreach ($d in $crtDirs) { if (Test-Path (Join-Path $d $name)) { $srcFile = Join-Path $d $name; break } }
        if (-not $srcFile -and (Test-Path (Join-Path "$env:WINDIR\System32" $name))) { $srcFile = Join-Path "$env:WINDIR\System32" $name }
        if ($srcFile) { Copy-Item $srcFile $dst; Write-Host "  $name  <-  $srcFile" }
        else { Write-Warning "  $name nicht gefunden" }
    }

    Section 'Lizenztext'
    foreach ($lic in @('LICENSE', 'LICENSE.GPLv3', 'LICENSE.README')) {
        if (Test-Path (Join-Path $Src $lic)) { Copy-Item (Join-Path $Src $lic) (Join-Path $Stg "$lic.txt") -Force }
    }

    Section 'Pruefung: sind alle benoetigten DLLs im Paket?'
    $have = @{}
    Get-ChildItem $bin -Filter *.dll -File | ForEach-Object { $have[$_.Name.ToLower()] = $true }
    $sys32 = Join-Path $env:WINDIR 'System32'
    $missingRoot = @{}
    $missingOther = @{}
    $files = Get-ChildItem $Stg -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll', '.kiface', '.pyd', '.cm' }
    Write-Host "$($files.Count) Programmdateien werden geprueft"
    foreach ($f in $files) {
        $dump = & dumpbin /nologo /dependents $f.FullName 2>$null
        foreach ($line in $dump) {
            if ($line -notmatch '^\s+(\S+\.dll)\s*$') { continue }
            $dll = $matches[1].ToLower()
            if ($have[$dll]) { continue }
            if (Test-Path (Join-Path $f.DirectoryName $dll)) { continue }
            if ($dll -match '^(api-ms-|ext-ms-)') { continue }
            $isCrt = $dll -match '^(msvcp|vcruntime|concrt|vcomp|vccorlib|mfc)\d'
            if (-not $isCrt -and (Test-Path (Join-Path $sys32 $dll))) { continue }
            if ($f.DirectoryName -ieq $bin) { $missingRoot["$dll  (benoetigt von $($f.Name))"] = $true }
            else { $missingOther["$dll  (benoetigt von $($f.FullName.Substring($Stg.Length + 1)))"] = $true }
        }
    }
    $global:LASTEXITCODE = 0
    if ($missingOther.Count -gt 0) {
        Write-Warning 'Fehlende DLLs bei Zusatzmodulen (nicht fatal):'
        $missingOther.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
    }
    if ($missingRoot.Count -gt 0) {
        Write-Host 'FEHLENDE DLLs bei Hauptprogrammen:' -ForegroundColor Red
        $missingRoot.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" }
        throw 'Das Paket ist unvollstaendig (siehe Liste oben).'
    }
    Write-Host 'Alle DLL-Abhaengigkeiten der Hauptprogramme sind im Paket vorhanden.'

    $size = (Get-ChildItem $Stg -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("Paketbaum: {0:N0} MB in {1}" -f $size, $Stg)
}

'smoke' {
    $bin = Join-Path $Stg 'bin'
    $tmp = Join-Path $Root 'smoke'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Ensure-Dir $tmp
    $env:KICAD_CONFIG_HOME = Join-Path $tmp 'config'
    # Sicherstellen, dass nur das Paket selbst benutzt wird, nicht der Build-Baum
    $env:PATH = "$env:WINDIR\System32;$env:WINDIR"

    Section 'kicad-cli version'
    & (Join-Path $bin 'kicad-cli.exe') version --format about
    Check-Exit 'kicad-cli version'

    $demo = Join-Path $Stg 'share\kicad\demos\pic_programmer'
    Copy-Item $demo (Join-Path $tmp 'pic_programmer') -Recurse

    Section 'Schaltplan-Modul (Netzliste exportieren)'
    & (Join-Path $bin 'kicad-cli.exe') sch export netlist -o (Join-Path $tmp 'test.net') (Join-Path $tmp 'pic_programmer\pic_programmer.kicad_sch')
    Check-Exit 'kicad-cli sch export netlist'
    if (-not (Test-Path (Join-Path $tmp 'test.net'))) { throw 'Netzliste wurde nicht erzeugt.' }

    Section 'Leiterplatten-Modul (Bohrdatei exportieren)'
    Ensure-Dir (Join-Path $tmp 'drill')
    & (Join-Path $bin 'kicad-cli.exe') pcb export drill -o ((Join-Path $tmp 'drill') + '\') (Join-Path $tmp 'pic_programmer\pic_programmer.kicad_pcb')
    Check-Exit 'kicad-cli pcb export drill'

    Section 'Python-Modul pcbnew'
    & (Join-Path $bin 'python.exe') -c "import pcbnew; print('pcbnew', pcbnew.Version())"
    Check-Exit 'python import pcbnew'

    Section 'wxPython (nicht fatal)'
    & (Join-Path $bin 'python.exe') -c "import wx; print('wxPython', wx.version())"
    if ($LASTEXITCODE -ne 0) { Write-Warning 'wxPython liess sich nicht laden - Plugins mit eigener Oberflaeche funktionieren dann nicht.'; $global:LASTEXITCODE = 0 }

    Write-Host ''
    Write-Host 'Kurztests bestanden.' -ForegroundColor Green
}

'gui' {
    # Startet den Projektmanager auf dem Build-Server und speichert Bildschirmfotos.
    # Reine Sichtkontrolle; Fehler hier brechen den Lauf nicht ab.
    $bin = Join-Path $Stg 'bin'
    $tmp = Join-Path $Root 'gui'
    $shots = Join-Path $Out 'screenshots'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Ensure-Dir $tmp; Ensure-Dir $shots
    $env:KICAD_CONFIG_HOME = Join-Path $tmp 'config'
    $env:PATH = "$env:WINDIR\System32;$env:WINDIR"

    Copy-Item (Join-Path $Stg 'share\kicad\demos\pic_programmer') (Join-Path $tmp 'pic_programmer') -Recurse
    Copy-Item (Join-Path $Stg 'share\kicad\demos\complex_hierarchy') (Join-Path $tmp 'complex_hierarchy') -Recurse

    # Eine fremde Sperre simulieren, damit die Anzeige "wer hat was offen" sichtbar wird
    '{"app":"kicad","hostname":"PC-LAYOUT07","pid":4711,"since":"2026-11-11T08:15:00","username":"mueller"}' |
        Out-File -FilePath (Join-Path $tmp 'pic_programmer\~pic_programmer.kicad_pcb.lck') -Encoding ascii -NoNewline

    # Workspace mit zwei Projekten vorbereiten
    $cfg = Join-Path $env:KICAD_CONFIG_HOME '10.0'
    Ensure-Dir $cfg
    $ws = @{ version = 1; projects = @(
        @{ path = (Join-Path $tmp 'pic_programmer\pic_programmer.kicad_pro') },
        @{ path = (Join-Path $tmp 'complex_hierarchy\complex_hierarchy.kicad_pro') } ) }
    $ws | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $cfg 'default.kicad_workspace') -Encoding utf8NoBOM

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Save-Shot([string]$Name) {
        try {
            $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
            $bmp.Save((Join-Path $shots "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose()
            Write-Host "Bildschirmfoto $Name.png"
        } catch { Write-Warning "Bildschirmfoto $Name fehlgeschlagen: $_" }
    }

    $proc = Start-Process -FilePath (Join-Path $bin 'kicad.exe') -ArgumentList "`"$(Join-Path $tmp 'pic_programmer\pic_programmer.kicad_pro')`"" -PassThru
    Start-Sleep -Seconds 25
    Save-Shot '1-nach-start'

    # Einrichtungsassistent des ersten Starts durchklicken (Enter = Weiter / Fertig)
    $shell = New-Object -ComObject WScript.Shell
    for ($i = 0; $i -lt 6; $i++) {
        try { [void]$shell.AppActivate($proc.Id); Start-Sleep -Milliseconds 500; $shell.SendKeys('{ENTER}') } catch { }
        Start-Sleep -Seconds 3
    }
    Start-Sleep -Seconds 20
    Save-Shot '2-projektmanager'
    Start-Sleep -Seconds 10
    Save-Shot '3-projektmanager'

    Write-Host "kicad.exe laeuft noch: $(-not $proc.HasExited)"
    Get-Process kicad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}

'installer' {
    $makensis = Find-MakeNsis
    if (-not $makensis) { throw 'makensis.exe nicht gefunden (Stufe prepare ausfuehren).' }
    Ensure-Dir $Out

    Section 'Installer bauen (NSIS)'
    $exe = Join-Path $Out "kicad-riegl-ws-$PkgVersion-x86_64.exe"
    & $makensis /V2 /INPUTCHARSET UTF8 "/DSTAGE=$Stg" "/DOUTFILE=$exe" "/DPKGVERSION=$PkgVersion" (Join-Path $Repo 'ci\installer.nsi')
    Check-Exit 'makensis'

    $sha = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
    "$sha  $(Split-Path -Leaf $exe)" | Out-File -FilePath (Join-Path $Out 'SHA256SUMS.txt') -Encoding ascii
    Write-Host ("Installer: {0}  ({1:N0} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))
    Write-Host "SHA256: $sha"
}

'logs' {
    # Sammelt nach einem Fehler die Protokolle der vcpkg-Pakete ein.
    Ensure-Dir $Logs
    $bt = Join-Path $Vcpkg 'buildtrees'
    if (Test-Path $bt) {
        Get-ChildItem $bt -Directory | ForEach-Object {
            $port = $_.Name
            Get-ChildItem $_.FullName -Filter *.log -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -lt 20MB } | ForEach-Object {
                    Ensure-Dir (Join-Path $Logs "vcpkg\$port")
                    Copy-Item $_.FullName (Join-Path $Logs "vcpkg\$port") -Force
                }
        }
    }
    foreach ($f in @('CMakeFiles\CMakeError.log', 'CMakeFiles\CMakeConfigureLog.yaml', 'vcpkg-manifest-install.log', 'CMakeCache.txt')) {
        $p = Join-Path $Bld $f
        if (Test-Path $p) { Copy-Item $p $Logs -Force }
    }
    $global:LASTEXITCODE = 0
}

}
