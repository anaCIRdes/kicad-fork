#!/bin/bash
# Baut aus einem fertigen Build-Verzeichnis ein .deb-Paket des KiCad-Workspace-Forks.
#
# Aufruf:  tools/make_deb.sh <build-verzeichnis> <ausgabe-verzeichnis> [paketversion]
#
# Das Paket installiert nach /opt/kicad-riegl-ws und laesst ein vorhandenes Standard-KiCad
# (aus der Distribution oder dem KiCad-PPA) unangetastet.
set -euo pipefail

BUILD="$(realpath "$1")"
OUT="$(realpath "$2")"
VERSION="${3:-10.0.8+rieglws3}"
PREFIX=/opt/kicad-riegl-ws
PKG=kicad-riegl-ws
ARCH="$(dpkg --print-architecture)"
STAGE="$(mktemp -d)"
chmod 0755 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

echo ">> Installiere nach $STAGE"
DESTDIR="$STAGE" cmake --install "$BUILD" > "$STAGE/../install-$$.log" 2>&1 || {
    tail -20 "$STAGE/../install-$$.log"; exit 1; }
rm -f "$STAGE/../install-$$.log"

echo ">> Entferne Debug-Symbole"
find "$STAGE$PREFIX" -type f \( -name '*.so*' -o -name '*.kiface' -o -perm -u+x \) -print0 |
    while IFS= read -r -d '' f; do
        if file -b "$f" | grep -q ELF; then strip --strip-unneeded "$f" 2>/dev/null || true; fi
    done

# Starter, Desktop-Eintrag und Symbol ausserhalb von /opt
mkdir -p "$STAGE/usr/bin" "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/scalable/apps" \
         "$STAGE/usr/share/mime/packages"
ln -s "$PREFIX/bin/kicad" "$STAGE/usr/bin/kicad-riegl-ws"
ln -s "$PREFIX/bin/kicad-cli" "$STAGE/usr/bin/kicad-riegl-ws-cli"

ICON_SRC="$(find "$STAGE$PREFIX/share/icons" -name 'kicad.svg' | head -1 || true)"
if [ -n "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$STAGE/usr/share/icons/hicolor/scalable/apps/kicad-riegl-ws.svg"
fi

cat > "$STAGE/usr/share/applications/kicad-riegl-ws.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=KiCad Workspace (RIEGL-Fork)
GenericName=EDA Suite
Comment=KiCad 10 mit Workspace-Manager fuer mehrere Projekte und Netzwerk-Sperranzeige
Exec=$PREFIX/bin/kicad %f
Icon=kicad-riegl-ws
Terminal=false
Categories=Science;Electronics;Engineering;
MimeType=application/x-kicad-workspace;
StartupWMClass=kicad
EOF

cat > "$STAGE/usr/share/mime/packages/kicad-riegl-ws.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-kicad-workspace">
    <comment>KiCad workspace</comment>
    <glob pattern="*.kicad_workspace"/>
  </mime-type>
</mime-info>
EOF

echo ">> Ermittle Abhaengigkeiten"
DEPS=""
(
    cd "$STAGE"
    mkdir -p debian
    printf 'Source: %s\n\nPackage: %s\nArchitecture: %s\n' "$PKG" "$PKG" "$ARCH" > debian/control
    ELFS=$(find ".$PREFIX" -type f \( -name '*.so*' -o -name '*.kiface' -o -path '*/bin/*' \) \
              -exec sh -c 'file -b "$1" | grep -q ELF && echo "$1"' _ {} \;)
    # shellcheck disable=SC2086
    dpkg-shlibdeps -O --ignore-missing-info -l".$PREFIX/lib" $ELFS 2>/dev/null > "$STAGE/shlibdeps.txt" || true
)
rm -rf "$STAGE/debian"
if [ -s "$STAGE/shlibdeps.txt" ]; then
    DEPS="$(sed -e 's/^shlibs:Depends=//' "$STAGE/shlibdeps.txt")"
fi
rm -f "$STAGE/shlibdeps.txt"
[ -n "$DEPS" ] && DEPS="$DEPS, "
DEPS="${DEPS}python3, python3-wxgtk4.0"

SIZE_KB=$(du -sk "$STAGE" | cut -f1)
mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: electronics
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE_KB
Depends: $DEPS
Recommends: kicad-symbols, kicad-footprints, kicad-packages3d, kicad-templates
Maintainer: RIEGL Elektronikentwicklung (interner Fork)
Homepage: https://www.kicad.org
Description: KiCad 10.0.8 mit Workspace-Manager (interner Fork)
 KiCad EDA Suite 10.0.8 mit zusaetzlichem Workspace-Bereich im Projektmanager:
 mehrere Projekte gleichzeitig (aehnlich Altium Designer) und eine Live-Anzeige,
 welcher Benutzer an welchem PC welche Datei geoeffnet hat.
 Installiert nach $PREFIX und kann parallel zum Standard-KiCad betrieben werden.
EOF

cat > "$STAGE/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
# Standard-Bibliotheken eines installierten Standard-KiCad mitbenutzen
for d in symbols footprints 3dmodels; do
    if [ -d "/usr/share/kicad/\$d" ] && [ ! -e "$PREFIX/share/kicad/\$d" ]; then
        ln -s "/usr/share/kicad/\$d" "$PREFIX/share/kicad/\$d"
    fi
done
# Vorlagen und Standard-Bibliothekstabellen (sym-lib-table, fp-lib-table, Projektvorlagen)
if [ -d /usr/share/kicad/template ]; then
    for f in /usr/share/kicad/template/*; do
        [ -e "\$f" ] || continue
        t="$PREFIX/share/kicad/template/\$(basename "\$f")"
        [ -e "\$t" ] || ln -s "\$f" "\$t"
    done
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q || true
command -v update-mime-database >/dev/null 2>&1 && update-mime-database /usr/share/mime || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
exit 0
EOF

cat > "$STAGE/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e
for d in symbols footprints 3dmodels; do
    if [ -L "$PREFIX/share/kicad/\$d" ]; then
        rm -f "$PREFIX/share/kicad/\$d"
    fi
done
for t in "$PREFIX"/share/kicad/template/*; do
    if [ -L "\$t" ]; then rm -f "\$t"; fi
done
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"

mkdir -p "$OUT"
DEB="$OUT/${PKG}_${VERSION}_${ARCH}.deb"
echo ">> Baue $DEB"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" > /dev/null
ls -lh "$DEB"
