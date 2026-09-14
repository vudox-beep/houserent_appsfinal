#!/usr/bin/env bash
# Always build from THIS folder (houserent), not the parent flutter_application_1 folder.
set -euo pipefail
cd "$(dirname "$0")"
echo "Building HouseRent from: $(pwd)"
echo "Expected package: com.houserent.africa | version in pubspec.yaml"
flutter clean
flutter pub get
flutter run "$@"
