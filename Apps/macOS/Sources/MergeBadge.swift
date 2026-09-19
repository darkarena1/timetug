import TimeTugCore

/// Words for the merge indicator. Rule merges are silent; model and manual merges are labelled.
enum MergeBadge {
    static func text(_ provenance: MergeProvenance?) -> String? {
        guard let provenance else { return nil }
        switch provenance {
        case .rule: return nil
        case .inference(_, let engineName): return "Merged with \(engineName)"
        case .userConfirmed: return "Merged manually"
        }
    }
}
