#!/bin/bash
# Baut den KiCad-Workspace-Fork als .deb-Paket fuer Ubuntu 24.04 / Linux Mint 22.
# Wird von .github/workflows/linux-paket.yml aufgerufen, laeuft aber genauso auf einem
# eigenen Rechner mit Ubuntu 24.04 oder Linux Mint 22:
#
#   bash ci/linux-build.sh [arbeitsverzeichnis]
#
# Ergebnis: <arbeitsverzeichnis>/dist/kicad-riegl-ws_<version>_amd64.deb
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(realpath -m "${1:-$HOME/kicad-fork-build}")"
TAG=10.0.8
EXTRA=riegl-ws2
PKGVERSION="$TAG+rieglws2"
PREFIX=/opt/kicad-riegl-ws
PATCH="$REPO/patch/kicad-$TAG-riegl-workspace.patch"

echo "==== Build-Abhaengigkeiten ===="
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git gettext swig file dpkg-dev pkg-config \
    libwxgtk3.2-dev libwxgtk-webview3.2-dev python3-wxgtk4.0 python3-dev libboost-all-dev \
    libglew-dev libglm-dev libcairo2-dev libcurl4-openssl-dev libgtk-3-dev libx11-dev \
    libocct-data-exchange-dev libocct-modeling-algorithms-dev libocct-modeling-data-dev \
    libocct-foundation-dev libocct-ocaf-dev libocct-visualization-dev \
    libngspice0-dev ngspice libgit2-dev libsecret-1-dev libprotobuf-dev protobuf-compiler \
    libnng-dev libzstd-dev unixodbc-dev libspnav-dev libharfbuzz-dev libfontconfig-dev \
    libfreetype-dev libbz2-dev libssl-dev libpoppler-dev libpoppler-glib-dev libpoppler-cpp-dev \
    libglu1-mesa-dev libegl-dev libfribidi-dev

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d kicad/.git ]; then
    echo "==== KiCad $TAG holen ===="
    rm -rf kicad
    git clone --depth 1 --branch "$TAG" https://gitlab.com/kicad/code/kicad.git kicad ||
        git clone --depth 1 --branch "$TAG" https://github.com/KiCad/kicad-source-mirror.git kicad

    echo "==== Fork-Patch anwenden ===="
    git -C kicad checkout -q -b riegl-workspace
    git -C kicad -c user.name="fork-build" -c user.email="fork-build@localhost" am "$PATCH"
    git -C kicad log --oneline -n 8
fi

echo "==== Konfigurieren ===="
# Das System-Python festnageln: nur dazu passt das wxPython-Paket der Distribution.
PYVER="$(/usr/bin/python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"

cmake -G Ninja -S kicad -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-g0" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR:STRING=lib \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib:$ORIGIN/../..:$ORIGIN/../../..' \
    -DKICAD_BUILD_I18N=ON \
    -DKICAD_BUILD_QA_TESTS=OFF \
    -DKICAD_UPDATE_CHECK=OFF \
    -DKICAD_USE_CMAKE_FINDPROTOBUF=ON \
    -DKICAD_VERSION_EXTRA="$EXTRA" \
    -DPYTHON_EXECUTABLE=/usr/bin/python3 \
    -DPYTHON_INCLUDE_DIR="/usr/include/python$PYVER" \
    -DPYTHON_LIBRARY="/usr/lib/x86_64-linux-gnu/libpython$PYVER.so"

echo "==== Kompilieren ===="
ninja -C build

echo "==== Paket bauen ===="
mkdir -p "$WORK/dist"
bash "$REPO/ci/make_deb.sh" "$WORK/build" "$WORK/dist" "$PKGVERSION"

echo "==== Kurztest: Paket installieren und starten ===="
sudo apt-get install -y "$WORK"/dist/kicad-riegl-ws_*.deb
kicad-riegl-ws-cli version --format about | head -5
PYTHONPATH="$PREFIX/lib/python3/dist-packages" /usr/bin/python3 -c "import pcbnew; print('pcbnew', pcbnew.Version())"

( cd "$WORK/dist" && sha256sum *.deb > SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "Fertig: $WORK/dist"
