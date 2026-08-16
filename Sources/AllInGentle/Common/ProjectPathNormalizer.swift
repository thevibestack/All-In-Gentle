import Foundation

/// Normalizes filesystem paths so equivalent paths produce the same key.
///
/// The normalization steps are:
/// 1. Expand a leading tilde to the user's home directory.
/// 2. Standardize the path (resolve `.`, `..`, and redundant separators).
/// 3. Resolve symbolic links.
/// 4. Trim a trailing slash unless the path is the root `/`.
public enum ProjectPathNormalizer {
    public static func normalize(_ path: String) -> String {
        var normalized = (path as NSString).expandingTildeInPath
        normalized = (normalized as NSString).standardizingPath

        let resolved =
            FileManager.default.fileExists(atPath: normalized)
            ? (normalized as NSString).resolvingSymlinksInPath
            : normalized

        normalized = resolved
        if normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
