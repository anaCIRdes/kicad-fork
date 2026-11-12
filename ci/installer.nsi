; Installer fuer den KiCad-Workspace-Fork (RIEGL) - Windows 10/11, 64 Bit
;
; Aufruf:  makensis /DSTAGE=<Paketbaum> /DOUTFILE=<installer.exe> /DPKGVERSION=<version> installer.nsi
;
; Installiert in einen eigenen Ordner neben einem vorhandenen Standard-KiCad und laesst
; dieses unangetastet (keine Dateizuordnungen, keine Aenderung an dessen Installation).

Unicode true
ManifestDPIAware true
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!ifndef STAGE
  !error "STAGE (Paketbaum) nicht angegeben"
!endif
!ifndef OUTFILE
  !define OUTFILE "kicad-riegl-ws-setup.exe"
!endif
!ifndef PKGVERSION
  !define PKGVERSION "10.0.8-rieglws2"
!endif

!define APPNAME    "KiCad Workspace (RIEGL-Fork)"
!define APPID      "KiCadRieglWorkspace10"
!define UNINSTKEY  "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}"
!define STOCKDIR   "$PROGRAMFILES64\KiCad\10.0"

!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

Name "${APPNAME} ${PKGVERSION}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\KiCad-RIEGL-Workspace\10.0"
InstallDirRegKey HKLM "${UNINSTKEY}" "InstallLocation"
ShowInstDetails show
ShowUninstDetails show
BrandingText "${APPNAME} ${PKGVERSION}"

!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\kicad.exe"
!define MUI_FINISHPAGE_RUN_TEXT "KiCad Workspace jetzt starten"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${STAGE}\LICENSE.GPLv3.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "German"
!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------------------------
; Hilfsfunktionen
; ---------------------------------------------------------------------------------------------

; Entfernt eine Verzeichnisverknuepfung (Junction), ohne deren Ziel anzufassen.
; "rmdir" ohne /s loescht bei einer Junction nur die Verknuepfung selbst.
!macro RemoveJunction un
Function ${un}RemoveJunction
    Exch $0
    ${If} ${FileExists} "$0\*.*"
        nsExec::ExecToLog 'cmd.exe /c rmdir "$0"'
        Pop $1
    ${EndIf}
    Pop $0
FunctionEnd
!macroend
!insertmacro RemoveJunction ""
!insertmacro RemoveJunction "un."

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_ICONSTOP "Dieses Programm benötigt ein 64-Bit-Windows."
        Abort
    ${EndIf}
    SetRegView 64
FunctionEnd

Function un.onInit
    SetRegView 64
FunctionEnd

; ---------------------------------------------------------------------------------------------
; Installation
; ---------------------------------------------------------------------------------------------

Section "KiCad Workspace (erforderlich)" SecMain
    SectionIn RO
    SetShellVarContext all

    ; Bei einer Aktualisierung zuerst vorhandene Bibliotheks-Verknuepfungen loesen, damit
    ; niemals in die Bibliotheken des Standard-KiCad hineingeschrieben wird.
    Push "$INSTDIR\share\kicad\symbols"
    Call RemoveJunction
    Push "$INSTDIR\share\kicad\footprints"
    Call RemoveJunction
    Push "$INSTDIR\share\kicad\3dmodels"
    Call RemoveJunction

    SetOutPath "$INSTDIR"
    File /r "${STAGE}\*.*"

    WriteUninstaller "$INSTDIR\uninstall.exe"

    WriteRegStr   HKLM "${UNINSTKEY}" "DisplayName"     "${APPNAME} ${PKGVERSION}"
    WriteRegStr   HKLM "${UNINSTKEY}" "DisplayVersion"  "${PKGVERSION}"
    WriteRegStr   HKLM "${UNINSTKEY}" "Publisher"       "RIEGL (interner Fork von KiCad)"
    WriteRegStr   HKLM "${UNINSTKEY}" "DisplayIcon"     "$INSTDIR\bin\kicad.exe"
    WriteRegStr   HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr   HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr   HKLM "${UNINSTKEY}" "URLInfoAbout"    "https://www.kicad.org"
    WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
    WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1

    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" "$0"
SectionEnd

Section "Startmenü-Eintrag" SecStartMenu
    SetShellVarContext all
    SetOutPath "$INSTDIR\bin"
    CreateDirectory "$SMPROGRAMS\KiCad Workspace (RIEGL)"
    CreateShortCut "$SMPROGRAMS\KiCad Workspace (RIEGL)\KiCad Workspace.lnk" "$INSTDIR\bin\kicad.exe"
    CreateShortCut "$SMPROGRAMS\KiCad Workspace (RIEGL)\Deinstallieren.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section /o "Desktop-Verknüpfung" SecDesktop
    SetShellVarContext all
    SetOutPath "$INSTDIR\bin"
    CreateShortCut "$DESKTOP\KiCad Workspace (RIEGL).lnk" "$INSTDIR\bin\kicad.exe"
SectionEnd

Section "Bibliotheken des Standard-KiCad 10.0 mitbenutzen" SecLibs
    ; Der Fork bringt keine Symbol-, Footprint- und 3D-Bibliotheken mit. Ist ein Standard-KiCad
    ; 10.0 installiert, werden dessen Bibliotheksordner als Verknuepfung eingebunden.
    StrCpy $R0 ""
    ReadRegStr $R1 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\KiCad 10.0" "InstallLocation"
    ${If} $R1 != ""
    ${AndIf} ${FileExists} "$R1\share\kicad\*.*"
        StrCpy $R0 "$R1"
    ${ElseIf} ${FileExists} "${STOCKDIR}\share\kicad\*.*"
        StrCpy $R0 "${STOCKDIR}"
    ${EndIf}

    ${If} $R0 == ""
        DetailPrint "Kein Standard-KiCad 10.0 gefunden - Bibliothekspfade bitte in KiCad unter Einstellungen > Pfade konfigurieren setzen."
    ${ElseIf} $R0 == $INSTDIR
        DetailPrint "Installationsordner ist der des Standard-KiCad - keine Verknüpfungen nötig."
    ${Else}
        DetailPrint "Standard-KiCad gefunden: $R0"

        ${If} ${FileExists} "$R0\share\kicad\symbols\*.*"
        ${AndIfNot} ${FileExists} "$INSTDIR\share\kicad\symbols\*.*"
            nsExec::ExecToLog 'cmd.exe /c mklink /J "$INSTDIR\share\kicad\symbols" "$R0\share\kicad\symbols"'
            Pop $1
        ${EndIf}
        ${If} ${FileExists} "$R0\share\kicad\footprints\*.*"
        ${AndIfNot} ${FileExists} "$INSTDIR\share\kicad\footprints\*.*"
            nsExec::ExecToLog 'cmd.exe /c mklink /J "$INSTDIR\share\kicad\footprints" "$R0\share\kicad\footprints"'
            Pop $1
        ${EndIf}
        ${If} ${FileExists} "$R0\share\kicad\3dmodels\*.*"
        ${AndIfNot} ${FileExists} "$INSTDIR\share\kicad\3dmodels\*.*"
            nsExec::ExecToLog 'cmd.exe /c mklink /J "$INSTDIR\share\kicad\3dmodels" "$R0\share\kicad\3dmodels"'
            Pop $1
        ${EndIf}

        ; Standard-Bibliothekstabellen und Projektvorlagen (nur was noch fehlt)
        ${If} ${FileExists} "$R0\share\kicad\template\*.*"
            nsExec::ExecToLog 'cmd.exe /c robocopy "$R0\share\kicad\template" "$INSTDIR\share\kicad\template" /E /XC /XN /XO /NFL /NDL /NJH /NJS /NP'
            Pop $1
        ${EndIf}
    ${EndIf}
SectionEnd

LangString DESC_SecMain      ${LANG_GERMAN}  "KiCad 10.0.8 mit Workspace-Bereich (Programme, Python, Übersetzungen, Demos)."
LangString DESC_SecStartMenu ${LANG_GERMAN}  "Eintrag im Startmenü."
LangString DESC_SecDesktop   ${LANG_GERMAN}  "Verknüpfung auf dem Desktop."
LangString DESC_SecLibs      ${LANG_GERMAN}  "Bindet Symbole, Footprints und 3D-Modelle eines installierten Standard-KiCad 10.0 ein (als Verknüpfung, ohne Kopie)."
LangString DESC_SecMain      ${LANG_ENGLISH} "KiCad 10.0.8 with workspace pane (programs, Python, translations, demos)."
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Start menu entry."
LangString DESC_SecDesktop   ${LANG_ENGLISH} "Desktop shortcut."
LangString DESC_SecLibs      ${LANG_ENGLISH} "Links the symbol, footprint and 3D model libraries of an installed stock KiCad 10.0 (junctions, no copy)."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain}      $(DESC_SecMain)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} $(DESC_SecStartMenu)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop}   $(DESC_SecDesktop)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecLibs}      $(DESC_SecLibs)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; ---------------------------------------------------------------------------------------------
; Deinstallation
; ---------------------------------------------------------------------------------------------

Section "Uninstall"
    SetShellVarContext all

    ; Zuerst die Verknuepfungen zu den Bibliotheken des Standard-KiCad loesen ...
    Push "$INSTDIR\share\kicad\symbols"
    Call un.RemoveJunction
    Push "$INSTDIR\share\kicad\footprints"
    Call un.RemoveJunction
    Push "$INSTDIR\share\kicad\3dmodels"
    Call un.RemoveJunction

    ; ... und abbrechen, falls eine davon noch existiert: Ein rekursives Loeschen wuerde
    ; sonst den Verknuepfungen folgen und die Bibliotheken des Standard-KiCad loeschen.
    ${If} ${FileExists} "$INSTDIR\share\kicad\symbols\*.*"
    ${OrIf} ${FileExists} "$INSTDIR\share\kicad\footprints\*.*"
    ${OrIf} ${FileExists} "$INSTDIR\share\kicad\3dmodels\*.*"
        MessageBox MB_ICONSTOP "Die Bibliotheks-Verknüpfungen unter$\r$\n$INSTDIR\share\kicad$\r$\nkonnten nicht entfernt werden. Die Deinstallation wird abgebrochen, damit die Bibliotheken des Standard-KiCad nicht gelöscht werden.$\r$\n$\r$\nBitte die Ordner 'symbols', 'footprints' und '3dmodels' dort von Hand entfernen (nur die Verknüpfung) und die Deinstallation erneut starten."
        Abort
    ${EndIf}

    Delete "$SMPROGRAMS\KiCad Workspace (RIEGL)\KiCad Workspace.lnk"
    Delete "$SMPROGRAMS\KiCad Workspace (RIEGL)\Deinstallieren.lnk"
    RMDir  "$SMPROGRAMS\KiCad Workspace (RIEGL)"
    Delete "$DESKTOP\KiCad Workspace (RIEGL).lnk"

    RMDir /r "$INSTDIR\bin"
    RMDir /r "$INSTDIR\lib"
    RMDir /r "$INSTDIR\share"
    Delete "$INSTDIR\LICENSE.txt"
    Delete "$INSTDIR\LICENSE.GPLv3.txt"
    Delete "$INSTDIR\LICENSE.README.txt"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"
    RMDir "$PROGRAMFILES64\KiCad-RIEGL-Workspace"

    DeleteRegKey HKLM "${UNINSTKEY}"
SectionEnd
