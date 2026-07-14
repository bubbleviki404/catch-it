import AppKit

let result = runAnnotationCropSelfTest()
let expectedFocusedAspect: CGFloat = 1000.0 / 800.0
let expectedCommittedAspect: CGFloat = 400.0 / 480.0

guard abs(result.focusedAspect - expectedFocusedAspect) < 0.01 else {
    fputs("FAIL: crop focus should display the original image aspect ratio\n", stderr)
    exit(1)
}

guard abs(result.committedAspect - expectedCommittedAspect) < 0.01 else {
    fputs("FAIL: crop blur should display only the cropped image aspect ratio\n", stderr)
    exit(1)
}

guard result.outputSize == NSSize(width: 400, height: 480) else {
    fputs("FAIL: crop output size was \(result.outputSize), expected 400x480\n", stderr)
    exit(1)
}

guard result.didLeaveCropTool else {
    fputs("FAIL: committing crop should return to the select tool\n", stderr)
    exit(1)
}

guard max(result.mosaicCacheSize.width, result.mosaicCacheSize.height) <= 150 else {
    fputs("FAIL: mosaic cache should stay thumbnail-sized, got \(result.mosaicCacheSize)\n", stderr)
    exit(1)
}

print("PASS: crop output is 400x480 and mosaic cache stays thumbnail-sized")

let history = runAnnotationHistorySelfTest()
guard history.countAfterEdit == 2,
      history.countAfterUndo == 1,
      history.countAfterRedo == 2 else {
    fputs("FAIL: undo/redo history counts were \(history.countAfterEdit)/\(history.countAfterUndo)/\(history.countAfterRedo)\n", stderr)
    exit(1)
}

print("PASS: annotation undo and redo restore complete snapshots")
