import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var w: CFTypeRef?
_ = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &w)
let first = (w as! [AXUIElement])[0]
var names: CFArray?
print("names_status=\(AXUIElementCopyAttributeNames(first, &names).rawValue) names=\((names as? [String]) ?? [])")
for a in [kAXRoleAttribute, kAXSubroleAttribute, kAXSizeAttribute, kAXPositionAttribute, "AXFrame"] {
  var v: CFTypeRef?; print("\(a)=\(AXUIElementCopyAttributeValue(first, a as CFString, &v).rawValue)")
}
