include("${VCPKG_ROOT_DIR}/triplets/x64-windows.cmake")

# wie KiCads eigenes Triplet (tools/custom_vcpkg_triplets)
set(VCPKG_DISABLE_COMPILER_TRACKING ON)

# Nur Release-Varianten der Abhaengigkeiten bauen (halbiert die Bauzeit)
set(VCPKG_BUILD_TYPE release)
