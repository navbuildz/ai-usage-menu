import Foundation

/// Release notes bundled with each build (Resources/ReleaseNotes.json, written by release.sh),
/// shown in "What's new" after an update.
enum ReleaseNotes {
    static func bullets(for version: String, bundle: Bundle = .main) -> [String] {
        guard let url = bundle.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        return all[version] ?? []
    }
}
