#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="$ROOT/.build/self-tests"
mkdir -p "$OUT"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/CaptureGeometry.swift" \
  "$ROOT/Tests/CaptureGeometryIntegration/main.swift" \
  -framework CoreGraphics \
  -o "$OUT/capture-geometry-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/Diagnostics.swift" \
  "$ROOT/Sources/CatchIt/HotKeyManager.swift" \
  "$ROOT/Sources/CatchIt/ShortcutSettings.swift" \
  "$ROOT/Tests/HotKeyIntegration/main.swift" \
  -framework AppKit \
  -framework Carbon \
  -o "$OUT/hotkey-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/ScreenshotStore.swift" \
  "$ROOT/Tests/StorageIntegration/main.swift" \
  -framework AppKit \
  -o "$OUT/storage-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/ScreenSelectionController.swift" \
  "$ROOT/Tests/SelectionIntegration/main.swift" \
  -framework AppKit \
  -o "$OUT/selection-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/ScreenshotStore.swift" \
  "$ROOT/Sources/CatchIt/AnnotationEditor.swift" \
  "$ROOT/Tests/AnnotationIntegration/main.swift" \
  -framework AppKit \
  -o "$OUT/annotation-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/ScreenshotStore.swift" \
  "$ROOT/Tests/PerformanceIntegration/main.swift" \
  -framework AppKit \
  -framework ImageIO \
  -o "$OUT/performance-integration"

xcrun swiftc \
  "$ROOT/Sources/CatchIt/UpdateChecker.swift" \
  "$ROOT/Tests/UpdateIntegration/main.swift" \
  -framework Foundation \
  -o "$OUT/update-integration"

"$OUT/hotkey-integration"
"$OUT/capture-geometry-integration"
"$OUT/storage-integration"
"$OUT/selection-integration"
"$OUT/annotation-integration"
"$OUT/performance-integration"
"$OUT/update-integration"
