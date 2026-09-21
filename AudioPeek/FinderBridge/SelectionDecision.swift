import Foundation

struct SelectionFacts: Equatable {
    var url: URL
    var exists: Bool
    var isDirectory: Bool
    var isPackage: Bool
    var isUbiquitous: Bool
    var isDownloaded: Bool
}

enum SelectionDecision: Equatable {
    case open(URL)
    case dismiss
}

enum SelectionDecisionMaker {
    static func decide(_ urls: [URL]) -> SelectionDecision {
        decide(facts: urls.map(facts(for:)))
    }

    static func decide(facts: [SelectionFacts]) -> SelectionDecision {
        guard facts.count == 1, let only = facts.first, isOpenable(only) else {
            return .dismiss
        }
        return .open(only.url)
    }

    static func isOpenable(_ facts: SelectionFacts) -> Bool {
        guard AudioFileKind.isSupportedExtension(facts.url) else { return false }
        guard facts.exists, !facts.isDirectory, !facts.isPackage else { return false }
        if facts.isUbiquitous && !facts.isDownloaded { return false }
        return true
    }

    private static func facts(for url: URL) -> SelectionFacts {
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        let values = try? url.resourceValues(forKeys: [
            .isPackageKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        let downloaded = values?.ubiquitousItemDownloadingStatus == .current
        return SelectionFacts(
            url: url,
            exists: exists,
            isDirectory: directory.boolValue,
            isPackage: values?.isPackage == true,
            isUbiquitous: values?.isUbiquitousItem == true,
            isDownloaded: downloaded
        )
    }
}
