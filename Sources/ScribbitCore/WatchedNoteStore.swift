import Foundation
import Darwin

/// A one-note, on-demand RAM cache. Events invalidate rather than reload an
/// editor. Metadata is a conservative fallback, never the save-conflict authority.
/// NoteStore calls must remain serialized by SessionWorker; callbacks use lock.
public final class WatchedNoteStore: NoteStore, @unchecked Sendable {
    private struct Signature: Equatable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        init?(_ url: URL) {
            var value = stat()
            guard fstatat(AT_FDCWD, url.path, &value, 0) == 0,
                  value.st_mode & S_IFMT == S_IFREG else { return nil }
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }
    private let store: NoteStore
    private let queue = DispatchQueue(label: "com.stephenhe.Scribbit.file-observation", qos: .utility)
    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var cached: (url: URL, signature: Signature, bytes: Data)?
    private var generation: UInt64 = 0

    public init(store: NoteStore = DiskNoteStore()) { self.store = store }
    deinit { sources.forEach { $0.cancel() } }

    /// Called by the serialized session worker, including explicit reset. Event
    /// callbacks only invalidateSnapshot, never mutate the worker-owned sources.
    public func invalidateCache() {
        stopObserving()
        invalidateSnapshot()
    }

    private func invalidateSnapshot() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        cached = nil
    }

    private func stopObserving() {
        sources.forEach { $0.cancel() }
        sources = []
    }

    private func observe(_ url: URL) -> Bool {
        stopObserving()
        for path in [url, url.deletingLastPathComponent()] {
            let descriptor = Darwin.open(path.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
                stopObserving()
                return false
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke], queue: queue)
            source.setEventHandler { [weak self] in self?.invalidateSnapshot() }
            source.setCancelHandler { Darwin.close(descriptor) }
            sources.append(source)
            source.resume()
        }
        return true
    }

    public func read(_ url: URL) throws -> Data {
        // Always check path identity/size/nanosecond mtime + ctime on the worker.
        // This catches replacement and most edits even before event delivery.
        let before = Signature(url)
        lock.lock()
        if let cached, cached.url == url, cached.signature == before {
            let bytes = cached.bytes
            lock.unlock()
            return bytes
        }
        cached = nil
        lock.unlock()
        let observing = observe(url)
        lock.lock(); let revision = generation; lock.unlock()
        let bytes: Data
        do { bytes = try store.read(url) }
        catch { stopObserving(); throw error }
        let after = Signature(url)
        lock.lock(); defer { lock.unlock() }
        // Never publish a snapshot across a detected change or failed watcher.
        if observing, before == after, let after, generation == revision,
           bytes.count <= DiskNoteStore.maximumBytes {
            cached = (url, after, bytes)
        }
        return bytes
    }

    public func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        // Always delegate the actual coordinated reread and exact byte compare.
        // Cancel before atomic replacement, avoiding a descriptor holding the
        // old unlinked vnode alive after saving when there is no reusable cache.
        invalidateCache()
        try store.save(data, to: url, replacing: baseline)
    }
}
