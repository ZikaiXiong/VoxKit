import Foundation

/// One-time migration from the app's previous identity (VoxNote, com.zikai.voxnote).
/// The rename changed the bundle id, so UserDefaults, the Keychain service, and the
/// data directory all moved — this carries existing users over silently.
enum Migration {
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromVoxNote") else { return }
        defaults.set(true, forKey: "migratedFromVoxNote")

        // 1. Settings: import the old preferences domain wholesale (existing keys win)
        let oldPlist = NSHomeDirectory() + "/Library/Preferences/com.zikai.voxnote.plist"
        if let dict = NSDictionary(contentsOfFile: oldPlist) as? [String: Any] {
            for (key, value) in dict where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // 2. Data directory: move ~/Library/Application Support/VoxNote → VoxKit
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = base.appendingPathComponent("VoxNote", isDirectory: true)
            let new = base.appendingPathComponent("VoxKit", isDirectory: true)
            if FileManager.default.fileExists(atPath: old.path),
               !FileManager.default.fileExists(atPath: new.path) {
                try? FileManager.default.moveItem(at: old, to: new)
            }
        }
        // 3. Keychain entries migrate lazily on first read (see Keychain.get)
    }
}
