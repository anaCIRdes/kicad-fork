# kicad-fork – Builds per GitHub Actions

Dieses Repository baut den **KiCad Workspace-Fork (RIEGL)** auf den Servern von GitHub:

| Ablauf (Workflow) | Ergebnis | Dauer |
|---|---|---|
| **Windows-Installer** | `kicad-riegl-ws-10.0.8-rieglws3-x86_64.exe` (Windows 10/11, 64 Bit) | mehrere Stunden; am längsten, wenn der Zwischenspeicher leer ist |
| **Linux-Paket** | `kicad-riegl-ws_10.0.8+rieglws3_amd64.deb` (Ubuntu 24.04 / Linux Mint 22) | geschätzt 1–2 Stunden |

Gebaut wird jeweils das offizielle KiCad 10.0.8 plus der Patch in `patch/`.

> Der Windows-Ablauf ist mit Version rieglws1 erfolgreich gelaufen. Ob er mit rieglws2 und dem
> Linux-Ablauf gelaufen ist, weiß ich nicht. Der neue Code von rieglws3 (xSignals) ist
> **nur unter Linux gebaut und getestet**; mit dem Microsoft-Compiler ist er noch nie übersetzt
> worden. Schlägt der Windows-Lauf im Schritt „KiCad kompilieren“ fehl, bitte den Namen der
> Datei und die Fehlermeldung schicken (Abschnitt E).

## Inhalt

| Pfad | Zweck |
|---|---|
| `patch/kicad-10.0.8-riegl-workspace.patch` | Alle Fork-Änderungen gegenüber KiCad 10.0.8 – **das ist die Datei, die sich mit jeder neuen Version ändert** |
| `ci/build.ps1` | Windows: alle Build-Schritte (enthält die Versionsnummer) |
| `ci/installer.nsi` | Windows: Installer-Beschreibung (NSIS) |
| `ci/triplets/x64-windows.cmake` | Windows: vcpkg-Einstellung |
| `ci/linux-build.sh` | Linux: alle Build-Schritte (enthält die Versionsnummer) |
| `ci/make_deb.sh` | Linux: erzeugt das .deb-Paket |
| `workflow-dateien/*.yml` | Vorlagen der beiden Workflow-Dateien zum Einfügen (siehe unten) |
| `.github/workflows/*.yml` | Die aktiven Workflow-Dateien (nur im Repository auf GitHub) |

Für Version rieglws3 sind **keine Workflow-Dateien zu ändern**. Hochzuladen sind wie immer
`ci`, `patch` und `README.md` (Abschnitt A).

## A – Neue Version hochladen (Normalfall)

1. Im Browser `https://github.com/anaCIRdes/kicad-fork` öffnen.
2. **Add file → Upload files**.
3. Aus dem Ordner `KiCAD-Fork\github` die Ordner **`ci`** und **`patch`** sowie **`README.md`** in das Browserfenster ziehen. Vorhandene Dateien werden dabei ersetzt.
4. Unten bei *Commit changes* einen kurzen Text eintragen (z. B. „Version rieglws3“) und **Commit changes** klicken.
5. Beide Abläufe starten von selbst. Kontrolle unter **Actions**.

Die Workflow-Dateien müssen dabei nicht angefasst werden, solange sich an ihnen nichts ändert. Ob sich eine geändert hat, steht jeweils in der Readme der Lieferung.

## B – Workflow-Datei erstellen (einmalig je Ablauf)

Der Windows-Ablauf existiert bereits. Für den **Linux-Ablauf** einmalig:

1. Im Repository **Add file → Create new file**.
2. Als Dateinamen exakt eintippen: `.github/workflows/linux-paket.yml`
   (die Schrägstriche erzeugen die Unterordner automatisch).
3. Die Datei `KiCAD-Fork\github\workflow-dateien\linux-paket.yml` in einem Texteditor öffnen, alles markieren, kopieren und in das große Textfeld einfügen.
4. **Commit changes…** → **Commit changes**.

Eine bestehende Workflow-Datei ändern: im Repository `.github/workflows/<name>.yml` anklicken → Stift-Symbol (*Edit this file*) → Inhalt komplett durch die neue Vorlage ersetzen → **Commit changes**.

## C – Ablauf starten und verfolgen

- **Automatisch**: nach jedem Hochladen von Dateien unter `ci/` oder `patch/`.
- **Von Hand**: **Actions** → links den Ablauf wählen (*Windows-Installer* oder *Linux-Paket*) → rechts **Run workflow** → **Run workflow**.
- Ein laufender Ablauf hat einen gelben Punkt, ein fertiger einen grünen Haken, ein fehlgeschlagener ein rotes Kreuz.
- Wird während eines Laufs erneut hochgeladen, bricht GitHub den alten Lauf ab und startet neu.
- Windows, Job 1 (Abhängigkeiten): Das Ergebnis liegt im Zwischenspeicher. Wird dieser länger als 7 Tage nicht benutzt, löscht GitHub ihn und der nächste Lauf baut die Abhängigkeiten neu (mehrere Stunden). Bricht Job 1 an der Zeitgrenze ab, einfach neu starten.

## D – Ergebnis herunterladen

**Actions** → den Lauf mit grünem Haken öffnen → ganz unten **Artifacts**:

- `kicad-riegl-ws-windows-installer` – Installer und Prüfsumme (als ZIP)
- `kicad-riegl-ws-linux-paket` – .deb-Paket und Prüfsumme (als ZIP)
- `bildschirmfotos` – Sichtkontrolle des Projektmanagers vom Windows-Server
- `protokolle-…` – vollständige Protokolle

Artefakte werden nach 30 Tagen gelöscht (Protokolle und Bildschirmfotos nach 14).

## E – Bei einem Fehler

Den Lauf öffnen → den Job mit rotem Kreuz anklicken → der fehlgeschlagene Schritt ist aufgeklappt. Für die Fehlersuche werden gebraucht: der **Name des Schritts** und die **letzten 30–50 Zeilen** seines Protokolls. Nach einer Korrektur unter `ci/` oder `patch/` startet der Ablauf von selbst neu; unter Windows kommen die bereits gebauten Abhängigkeiten aus dem Zwischenspeicher.

## Was die Pakete machen

**Windows-Installer**

- Installiert nach `C:\Program Files\KiCad-RIEGL-Workspace\10.0`, Startmenü-Eintrag „KiCad Workspace (RIEGL)“. Eine vorhandene ältere Fork-Version wird dabei ersetzt. Ein Standard-KiCad bleibt unverändert; es werden keine Dateitypen umgestellt.
- Die Einstellungen (`%APPDATA%\kicad\10.0`) werden mit einem Standard-KiCad 10.0 geteilt.
- Enthält keine Symbol-, Footprint- und 3D-Bibliotheken (deshalb rund 125 MB statt rund 1 GB). Die Option „Bibliotheken des Standard-KiCad 10.0 mitbenutzen“ bindet die eines installierten Standard-KiCad ein.
- Nicht signiert: Windows SmartScreen warnt beim Start („Weitere Informationen → Trotzdem ausführen“).

**Linux-Paket**

- `sudo apt install ./kicad-riegl-ws_10.0.8+rieglws3_amd64.deb`, installiert nach `/opt/kicad-riegl-ws`, Start mit `kicad-riegl-ws`.
- Nur für Ubuntu 24.04 und Linux Mint 22; auf Ubuntu 22.04 fehlen die nötigen Bibliotheksversionen.

## Lizenz

KiCad und dieser Fork stehen unter der GNU GPL Version 3 oder neuer.
