import SCCore

/// The few AX operations the frame policy needs, so the policy is testable with a recorder.
public protocol FrameOperations {
    func enhancedUserInterface() -> Bool?
    func setEnhancedUserInterface(_ enabled: Bool)
    func setSize(width: Double, height: Double) throws(WindowSystemError)
    func setPosition(x: Double, y: Double) throws(WindowSystemError)
}

/// Frame-setting policy (FR-11): size, then position, then size again, so that a window
/// pushed against a screen edge by its old size still reaches the planned size. Enhanced user
/// interface is switched off around the change and restored, because apps that keep it on
/// animate or reject AX resizes.
public func applyFrame(_ frame: FfiRect, with operations: some FrameOperations) throws(WindowSystemError) {
    let enhanced = operations.enhancedUserInterface()
    if enhanced == true { operations.setEnhancedUserInterface(false) }
    defer { if enhanced == true { operations.setEnhancedUserInterface(true) } }
    try operations.setSize(width: frame.width, height: frame.height)
    try operations.setPosition(x: frame.x, y: frame.y)
    try operations.setSize(width: frame.width, height: frame.height)
}
