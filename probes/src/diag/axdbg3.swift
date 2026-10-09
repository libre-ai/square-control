import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func role(_ e: AXUIElement) -> String { var v: CFTypeRef?; let s = AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v); return "\(s.rawValue):\(v as? String ?? "-")" }
var w: CFTypeRef?
_ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &w)
let arr = w as! [AXUIElement]
print("count=\(arr.count) roles=\(arr.map(role)) app_role=\(role(app)) equal_app=\(CFEqual(arr[0], app))")
var f: CFTypeRef?
_ = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &f)
let fw = f as! AXUIElement
var pidOut: pid_t = 0; AXUIElementGetPid(fw, &pidOut)
print("focused role=\(role(fw)) pid=\(pidOut) equal_app=\(CFEqual(fw, app))")
var mw: CFTypeRef?
print("main status=\(AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &mw).rawValue)")
