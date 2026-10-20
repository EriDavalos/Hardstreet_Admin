#!/usr/bin/env bash
# ==================================================================
# HARDSTREET PLATFORM · compilar para iOS
# ==================================================================
# SOLO funciona en macOS con Xcode instalado: Flutter no puede compilar
# iOS desde Windows/Linux (el subcomando `flutter build ios` ni existe allí).
#
# Uso:
#   ./tool/build_ios.sh              → IPA firmado (requiere cuenta/equipo en Xcode)
#   ./tool/build_ios.sh --simulator  → .app para el simulador (sin firma)
#   ./tool/build_ios.sh --no-codesign → .app de release sin firma (para CI)
# ==================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "✘ iOS solo se compila en macOS (este equipo es $(uname -s))." >&2
  exit 1
fi

flutter pub get

if ! command -v pod >/dev/null 2>&1; then
  echo "✘ Falta CocoaPods. Instálalo con: sudo gem install cocoapods" >&2
  exit 1
fi

(cd ios && pod install)

case "${1:-}" in
  --simulator)
    flutter build ios --simulator
    echo "✔ App para el simulador: build/ios/iphonesimulator/Runner.app"
    ;;
  --no-codesign)
    flutter build ios --release --no-codesign
    echo "✔ App sin firma: build/ios/iphoneos/Runner.app"
    ;;
  *)
    flutter build ipa --release
    echo "✔ IPA: build/ios/ipa/*.ipa"
    ;;
esac
