import Foundation

/// E0 state file: launch records (build stamp, AX trust) used by the grant-persistence probe.
/// Directory 0700, file 0600, no symlink followed (NFR-S6); it never holds a title or a bundle id.
public struct StateFile: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("e0-state.txt")
    }

    public static func standard() -> StateFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StateFile(directory: base.appendingPathComponent("org.libre-ai.square-control", isDirectory: true))
    }

    public enum Failure: Error, Equatable { case notADirectory, open(Int32), write(Int32) }

    public func append(_ line: String) throws(Failure) {
        let directory = url.deletingLastPathComponent().path
        var status = stat()
        if lstat(directory, &status) != 0 {
            guard mkdir(directory, 0o700) == 0 else { throw .open(errno) }
        } else if (status.st_mode & S_IFMT) != S_IFDIR {
            throw .notADirectory
        }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .open(errno) }
        defer { close(descriptor) }
        let bytes = Array((line + "\n").utf8)
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { throw .write(errno) }
    }
}
