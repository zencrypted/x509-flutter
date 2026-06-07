#!/bin/bash

# Build Script for x509-flutter (Release with Obfuscation)
# Reference: https://docs.flutter.dev/deployment/obfuscate

export JAVA_HOME=/opt/homebrew/opt/openjdk@21

echo "==> Building Android Release with Obfuscation..."
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools

flutter build apk --release \
  --obfuscate \
  --split-debug-info=./out/android-debug-info \
  --extra-gen-snapshot-options=--save-obfuscation-map=./out/android-obfuscation-map.json

echo "==> Building iOS Release with Obfuscation..."
flutter build ios --release --no-codesign \
  --obfuscate \
  --split-debug-info=./out/ios-debug-info

echo "==> Building macOS Release with Obfuscation..."
flutter build macos --release \
  --obfuscate \
  --split-debug-info=./out/macos-debug-info

echo "==> Done. Debug symbols saved to ./out/"
