import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Atomic write-then-rename save for `.local` origins
/// (projectRules.md, Data Safety; AGENTS.md §5).
///
/// ## Why rename, and why that satisfies "no truncated files, ever" (M5)
///
/// The obvious implementation — open the destination, truncate, write — has a
/// window between the truncate and the last byte in which the file on disk is
/// neither the old document nor the new one. A crash, a full disk, or a kernel
/// panic inside that window leaves the user with a partial file and no copy of
/// what they had. The window is small; the loss is total.
///
/// `rename(2)` closes it. POSIX requires that renaming over an existing name
/// within a filesystem is atomic with respect to other processes: a concurrent
/// reader sees either the complete old file or the complete new one, never a
/// blend and never a zero-length stand-in. So the sequence is:
///
/// 1. Write the complete new contents to a temp file **in the destination's own
///    directory**. Cross-filesystem `rename` fails with `EXDEV`, and
///    `/tmp` is a different filesystem from a user's home on macOS — a temp
///    file elsewhere would force a copy, which is exactly the non-atomic write
///    this is avoiding.
/// 2. `fsync` the file descriptor, so the bytes are on the medium before any
///    name points at them. Without this the rename can be durable while the
///    data behind it is not, and the crash produces a correctly-named empty file.
/// 3. `rename` the temp over the destination — one atomic step.
/// 4. `fsync` the parent directory, so the rename itself is durable.
///
/// At every instant, the destination name refers to a complete file. That is
/// the guarantee, and it is a property of the ordering, not of luck.
///
/// ## What the new file inherits, and what it cannot
///
/// The destination gets a **new inode**. POSIX permissions are read from the
/// original and reapplied deliberately (see `preservedMode`), minus setuid/setgid.
/// Extended attributes, ACLs, resource forks, and the original inode number do
/// not survive — that is inherent to every atomic-rename editor, and it is the
/// accepted trade: metadata for the guarantee that content is never truncated.
///
/// Two consequences worth stating (pen finding L-2): because the inode is new,
/// **hard links to the old inode keep the old content**, and **the new file is
/// owned by the saving user** — editing a root-owned file in a user-writable
/// directory yields a user-owned file. This matches every atomic-rename editor;
/// it is disclosed here rather than surprising a caller.
///
/// The save path resolves the parent directory to its real path once, opens it
/// refusing a symlink in any component (`O_NOFOLLOW_ANY`), and then creates,
/// renames and fsyncs relative to that open directory (`openat`, `renameat`).
/// A local attacker able to write to an intermediate parent directory used to be
/// able, within the save window, to swap a directory component for a symlink and
/// redirect where the write landed (a classic TOCTOU; pen finding M-2, closed
/// 2026-10-12): a swap before the open now fails the save, and one after it
/// cannot move a directory already held open. The final-component race is
/// benign — `renameat` does not follow a symlink at the target, so a swapped-in
/// link is simply replaced.
///
/// ## Symlinks
///
/// A symlinked destination is **followed** — the target is replaced atomically,
/// the symlink itself is left alone. This is standard editor behavior and the
/// behavior users rely on for dotfile farms (`~/.zshrc` → a symlink into a
/// checked-out repo): saving must write the repo file, not replace the link
/// with a regular file. Because the temp file must live in the *target's*
/// directory for the rename to be atomic, resolution happens before anything
/// is created.
public enum AtomicSaver: Sendable {

    /// Mode applied to a file this save creates for the first time.
    ///
    /// Fixed rather than `0o666 & ~umask` because reading the umask requires
    /// setting it and setting it back, and that pair is a data race against any
    /// other thread creating a file in between. A predictable 0644 is worth more
    /// than a umask-faithful one obtained unsafely.
    private static let defaultNewFileMode: mode_t = 0o644

    // MARK: - Origin-aware entry points

    /// Save a snapshot's content back to where it came from.
    ///
    /// - Throws: `EditorError.notSaveable` for `.remote` and `.ephemeral`.
    public static func save(_ snapshot: DocumentSnapshot) throws {
        try save(snapshot.content, encoding: snapshot.encoding, to: snapshot.origin)
    }

    /// Save to an origin, refusing the origins this package does not own.
    ///
    /// `.remote` throws rather than falling back to some best-effort write:
    /// glas.sh's transfer layer owns remote commit and already verifies it
    /// (INTEGRATION.md B1). A second, weaker implementation here would be the
    /// one that eventually gets called by accident.
    public static func save(
        _ content: String,
        encoding: DetectedEncoding,
        to origin: DocumentOrigin
    ) throws {
        switch origin {
        case .local(let url):
            try save(content, encoding: encoding, to: url)
        case .remote(let ref):
            throw EditorError.notSaveable(origin: "remote(\(ref.host):\(ref.path))")
        case .ephemeral(let id):
            throw EditorError.notSaveable(origin: "ephemeral(\(id.uuidString))")
        }
    }

    // MARK: - The save

    /// Encode and atomically write `content` to `url`.
    ///
    /// - Throws: `EditorError.saveFailed` for encoding and write failures,
    ///   `EditorError.atomicRenameFailed` if the final rename does not land.
    ///   In every failure case the destination is left exactly as it was and no
    ///   temp file remains.
    public static func save(_ content: String, encoding: DetectedEncoding, to url: URL) throws {
        let data = try EncodingDetector.encode(content, as: encoding)
        try writeAtomically(data, to: url)
    }

    /// The byte-level half, exposed for callers that already hold encoded data.
    public static func writeAtomically(_ data: Data, to url: URL) throws {
        try writeAtomically(data, to: url, afterChoosingDirectory: {})
    }

    /// `afterChoosingDirectory` runs once the folder is chosen and before anything is written into
    /// it: the window a swapped folder would use (pen finding M-2). For tests.
    static func writeAtomically(_ data: Data, to url: URL, afterChoosingDirectory: () throws -> Void) throws {
        // Resolve first: the temp file has to be a sibling of the *real* file.
        // `resolveDestination` follows a leaf symlink to its target explicitly,
        // including a *dangling* one whose target does not exist yet —
        // `URL.resolvingSymlinksInPath()` leaves that case pointing at the link,
        // so the rename would clobber the link into a regular file instead of
        // writing through it (pen-suite finding).
        let destination = resolveDestination(url)
        let name = destination.lastPathComponent

        // The folder by its real path, every link in it resolved, then held open: from here on the
        // temp file, the rename and the sync are made relative to that open folder, so a component
        // swapped for a link afterwards cannot redirect them (pen finding M-2, closed 2026-10-12).
        // It is opened refusing a link anywhere in the path — the resolved path has none, so one
        // there now was swapped in, and the save stops rather than follow it.
        let directoryPath = try canonicalPath(of: destination.deletingLastPathComponent().path)
        let directory = directoryPath.withCString { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | noFollowAnywhere) }
        guard directory >= 0 else {
            throw EditorError.saveFailed(reason: "could not open the folder \(directoryPath): \(errnoDescription())")
        }
        defer { close(directory) }
        try afterChoosingDirectory()

        let mode = preservedMode(of: name, in: directory) ?? defaultNewFileMode
        let temporary = temporaryName(for: name)

        // Created 0600, then widened to `mode` once the content is in place:
        // there is never an instant where a file that is about to hold private
        // content is readable by anyone else.
        let descriptor = temporary.withCString {
            openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else {
            throw EditorError.saveFailed(
                reason: "could not create temporary file in \(directoryPath): \(errnoDescription())"
            )
        }

        func removeTemporary() { _ = temporary.withCString { unlinkat(directory, $0, 0) } }

        // From here on every exit path removes the temp file. A save that fails
        // must not litter the user's directory with half-written droppings.
        func failing(_ error: EditorError) -> EditorError {
            close(descriptor)
            removeTemporary()
            return error
        }

        do {
            try writeAll(data, to: descriptor)
        } catch let error as EditorError {
            throw failing(error)
        }

        guard fchmod(descriptor, mode) == 0 else {
            throw failing(.saveFailed(reason: "could not set permissions on temporary file: \(errnoDescription())"))
        }

        // Bytes on the medium before any name points at them.
        guard fsync(descriptor) == 0 else {
            throw failing(.saveFailed(reason: "fsync failed: \(errnoDescription())"))
        }

        guard close(descriptor) == 0 else {
            // Capture close's errno *before* unlink overwrites it (pen finding L-1).
            let reason = errnoDescription()
            removeTemporary()
            throw EditorError.saveFailed(reason: "close failed: \(reason)")
        }

        // The atomic step, within the one folder held open.
        let renamed = temporary.withCString { source in
            name.withCString { target in renameat(directory, source, directory, target) }
        }
        guard renamed == 0 else {
            let reason = errnoDescription()
            removeTemporary()
            throw EditorError.atomicRenameFailed(reason: "\(directoryPath)/\(temporary) -> \(name): \(reason)")
        }

        // Make the rename itself durable. Best-effort: the data is already committed and named.
        _ = fsync(directory)
    }

    /// `open` refusing a symbolic link in any component of the path, where the platform offers it.
    #if canImport(Darwin)
    private static let noFollowAnywhere = O_NOFOLLOW_ANY
    #else
    private static let noFollowAnywhere: Int32 = 0
    #endif

    /// The path with every link in it resolved (`realpath(3)`). Unlike `URL.resolvingSymlinksInPath()`,
    /// which turns `/private/var/…` back into `/var/…` — a link.
    private static func canonicalPath(of path: String) throws -> String {
        guard let resolved = realpath(path, nil) else {
            throw EditorError.saveFailed(reason: "could not find the folder \(path): \(errnoDescription())")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Primitives

    /// `write(2)` in a loop. A single call is permitted to write fewer bytes
    /// than asked, and treating a short write as success is how a file ends up
    /// truncated by a code path that believed it was atomic.
    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw EditorError.saveFailed(reason: "write failed: \(errnoDescription())")
                }
                if written == 0 {
                    throw EditorError.saveFailed(reason: "write made no progress")
                }
                offset += written
            }
        }
    }

    /// Follow a leaf symlink to the path it names, even when that target does
    /// not exist yet.
    ///
    /// `URL.resolvingSymlinksInPath()` resolves a chain of *existing* links; a
    /// dangling link (`~/.zshrc` → a not-yet-created repo file) is left pointing
    /// at the link itself, which would make the atomic rename replace the link
    /// with a regular file. Resolving the leaf explicitly writes through to the
    /// target, leaving the symlink intact — the dotfile-farm behavior the class
    /// documents. Intermediate directory symlinks are still resolved by
    /// Foundation. Bounded so a symlink cycle terminates instead of looping.
    private static func resolveDestination(_ url: URL, depth: Int = 0) -> URL {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let leaf = parent.appendingPathComponent(url.lastPathComponent)
        guard depth < 40 else { return leaf }

        var info = stat()
        let isSymlink = leaf.path.withCString { lstat($0, &info) } == 0
            && (info.st_mode & S_IFMT) == S_IFLNK
        guard isSymlink else { return leaf }

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let count = leaf.path.withCString { readlink($0, &buffer, buffer.count - 1) }
        guard count >= 0 else { return leaf }
        buffer[Int(count)] = 0
        let target = String(cString: buffer)

        let targetURL = target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : leaf.deletingLastPathComponent().appendingPathComponent(target)
        return resolveDestination(targetURL, depth: depth + 1)
    }

    /// A temp-file name that is unique, hidden, marked, and — critically — always
    /// within `NAME_MAX`.
    ///
    /// The fixed decoration (leading dot, `.glasseditor-`, a 36-char UUID,
    /// `.tmp`) is ~54 bytes; embedding a long-but-legal destination name on top
    /// of it overflowed the 255-byte filename limit and failed the save
    /// (pen-suite finding). The destination name is only a debugging hint, so it
    /// is truncated on a UTF-8 scalar boundary to whatever budget remains.
    private static func temporaryName(for destinationName: String) -> String {
        let uuid = UUID().uuidString
        let suffix = ".glasseditor-\(uuid).tmp"
        let nameMax = 255
        let budget = nameMax - 1 /* leading dot */ - suffix.utf8.count
        let hint = budget > 0 ? truncatedToUTF8Bytes(destinationName, max: budget) : ""
        return ".\(hint)\(suffix)"
    }

    /// The longest prefix of `string` whose UTF-8 encoding is at most `max`
    /// bytes, cut on a Unicode scalar boundary so no character is split.
    private static func truncatedToUTF8Bytes(_ string: String, max: Int) -> String {
        if string.utf8.count <= max { return string }
        var result = ""
        var used = 0
        for scalar in string.unicodeScalars {
            let width = String(scalar).utf8.count
            if used + width > max { break }
            result.unicodeScalars.append(scalar)
            used += width
        }
        return result
    }

    /// POSIX mode of an existing destination in `directory`, or `nil` if there is nothing there.
    ///
    /// Follows a symlink, matching the follow-the-link save policy: the mode
    /// that matters is the target's.
    ///
    /// The setuid and setgid bits are **stripped** (pen finding M-1). The kernel
    /// clears them on write to a file's content; re-arming them via `fchmod`
    /// onto freshly-written bytes on a new inode is the wrong default and a
    /// privilege-escalation footgun. The sticky bit is preserved (it is
    /// meaningful only on directories, which this never writes, but costs
    /// nothing to keep). A save therefore clears setuid/setgid — documented
    /// behavior, matching every mainstream editor.
    private static func preservedMode(of name: String, in directory: Int32) -> mode_t? {
        var info = stat()
        guard name.withCString({ fstatat(directory, $0, &info, 0) }) == 0 else { return nil }
        return info.st_mode & 0o1777
    }

    private static func errnoDescription() -> String {
        String(cString: strerror(errno))
    }
}
