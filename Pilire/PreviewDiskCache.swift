import UIKit

// MARK: - Preview thumbnails on disk
//
// The catalogue's 3D thumbnails cost 8–60 ms each to render (the stables close
// to 200 ms), on the main thread, the first time each card scrolls into view —
// so the first scroll after every launch stuttered. Rendered once, they're kept
// in Caches and loaded as plain images from then on.
//
// The folder is keyed to the exact binary: any new build or update, including
// one where a model was reworked, starts a fresh folder, so a thumbnail can
// never show an old version of a building. Older folders are cleared away.

enum PreviewDiskCache {
    private static let root: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Previews", isDirectory: true)

    /// App version + build + the executable's modification date, which changes
    /// with every build even when the version number doesn't.
    private static let stamp: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        var built = "0"
        if let exe = Bundle.main.executableURL,
           let date = try? FileManager.default.attributesOfItem(atPath: exe.path)[.modificationDate] as? Date {
            built = String(Int(date.timeIntervalSince1970))
        }
        return "\(version)-\(build)-\(built)"
    }()

    private static let folder: URL? = {
        guard let root else { return nil }
        let fm = FileManager.default
        if let old = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in old where url.lastPathComponent != stamp {
                try? fm.removeItem(at: url)
            }
        }
        let dir = root.appendingPathComponent(stamp, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ key: String) -> URL? {
        folder?.appendingPathComponent(key).appendingPathExtension("png")
    }

    static func load(_ key: String) -> UIImage? {
        guard let url = url(key), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Encoding and writing happen off the main thread — the image is already
    /// on screen by then.
    static func save(_ image: UIImage, _ key: String) {
        guard let url = url(key) else { return }
        Task.detached(priority: .utility) {
            try? image.pngData()?.write(to: url, options: .atomic)
        }
    }
}
