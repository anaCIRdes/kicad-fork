# kicad-fork – Windows-Installer per GitHub Actions

Dieses Repository baut den **KiCad Workspace-Fork (RIEGL)** für Windows 10/11 (64 Bit):
offizielles KiCad 10.0.8 plus der Patch in `patch/`, übersetzt mit Microsoft-Compiler (MSVC)
und vcpkg nach KiCads eigener Paketliste. Ergebnis ist ein Installer
`kicad-riegl-ws-10.0.8-rieglws1-x86_64.exe`.

> Stand: Der Ablauf ist vollständig vorbereitet, aber **noch nie gelaufen**. Der erste Lauf
> zeigt, ob alle Schritte auf dem GitHub-Server durchgehen; mit Korrekturen ist zu rechnen.

## Inhalt

| Pfad | Zweck |
|---|---|
| `.github/workflows/windows-installer.yml` | Ablauf auf dem GitHub-Server (zwei Jobs) |
| `ci/build.ps1` | Alle Build-Schritte als PowerShell-Skript (auch lokal verwendbar) |
| `ci/installer.nsi` | Installer-Beschreibung (NSIS) |
| `ci/triplets/x64-windows.cmake` | vcpkg-Einstellung: nur Release-Varianten der Abhängigkeiten |
| `patch/kicad-10.0.8-riegl-workspace.patch` | Die Fork-Änderungen gegenüber KiCad 10.0.8 |

## Ablauf starten

Der Ablauf startet automatisch, sobald diese Dateien im Zweig `main` liegen, und lässt sich
jederzeit von Hand starten: **Actions → Windows-Installer → Run workflow**.

1. **Job 1 – Abhängigkeiten**: baut wxWidgets, OpenCASCADE, Python, wxPython, ngspice usw.
   Beim ersten Mal mehrere Stunden. Das Ergebnis wird zwischengespeichert.
   Bricht der Job an der Zeitgrenze (knapp 6 Stunden) ab: einfach neu starten, er macht
   dort weiter, wo der Zwischenspeicher steht.
2. **Job 2 – KiCad und Installer**: kompiliert KiCad, stellt das Paket zusammen, prüft es
   (fehlende DLLs, `kicad-cli`, Python-Modul), macht Bildschirmfotos des Projektmanagers und
   baut den Installer.

## Installer herunterladen

**Actions →** den Lauf mit grünem Haken öffnen **→** unten bei *Artifacts*:

- `kicad-riegl-ws-windows-installer` – der Installer (als ZIP verpackt) mit Prüfsumme
- `bildschirmfotos` – Sichtkontrolle vom Build-Server
- `protokolle-…` – Protokolle, wichtig bei einem Fehler

## Was der Installer macht

- Installiert nach `C:\Program Files\KiCad-RIEGL-Workspace\10.0`, eigener Startmenü-Eintrag
  „KiCad Workspace (RIEGL)“. Ein vorhandenes Standard-KiCad bleibt unverändert; es werden keine
  Dateitypen umgestellt.
- Die Einstellungen (`%APPDATA%\kicad\10.0`) werden mit einem Standard-KiCad 10.0 geteilt.
- Option „Bibliotheken des Standard-KiCad 10.0 mitbenutzen“: bindet dessen Symbol-,
  Footprint- und 3D-Bibliotheken als Verknüpfung ein. Ohne Standard-KiCad müssen die Pfade in
  KiCad unter *Einstellungen → Pfade konfigurieren* gesetzt werden.
- Der Installer ist **nicht signiert**; Windows SmartScreen zeigt deshalb beim Start eine
  Warnung („Weitere Informationen → Trotzdem ausführen“).

## Bei einem Fehler

Den fehlgeschlagenen Schritt im Lauf öffnen; die letzten Zeilen des Protokolls nennen die
Ursache. Zusätzlich liegen unter *Artifacts* die vollständigen Protokolle. Nach einer Korrektur
in `ci/` startet der Ablauf von selbst neu; die bereits gebauten Abhängigkeiten kommen aus dem
Zwischenspeicher.

## Lizenz

KiCad und dieser Fork stehen unter der GNU GPL Version 3 oder neuer.
