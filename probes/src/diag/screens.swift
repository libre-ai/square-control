import AppKit
let screens = NSScreen.screens
let h = screens.first!.frame.height
for (i, s) in screens.enumerated() {
  let f = s.frame, v = s.visibleFrame
  print("screen \(i) appkit_frame=\(f) appkit_visible=\(v) topleft_frame=\(f.minX),\(h - f.maxY),\(f.width),\(f.height) topleft_visible=\(v.minX),\(h - v.maxY),\(v.width),\(v.height) scale=\(s.backingScaleFactor)")
}
print("separate_spaces=\(NSScreen.screensHaveSeparateSpaces)")
