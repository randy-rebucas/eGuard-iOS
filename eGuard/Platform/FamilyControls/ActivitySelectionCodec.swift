import FamilyControls
import Foundation

/// Converts between Apple's opaque `FamilyActivitySelection` and eGuard's privacy-preserving snapshot.
nonisolated enum ActivitySelectionCodec {
    static func snapshot(from selection: FamilyActivitySelection) -> ActivitySelectionSnapshot {
        ActivitySelectionSnapshot(
            encodedSelection: try? JSONEncoder().encode(selection),
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    static func selection(from snapshot: ActivitySelectionSnapshot) -> FamilyActivitySelection? {
        guard let data = snapshot.encodedSelection else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}
