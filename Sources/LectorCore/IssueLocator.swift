import Foundation

/// An issue pinned to a range of the checked text. Offsets count `Character`s.
public struct LocatedIssue: Codable, Sendable, Equatable {
    public var issue: Issue
    public var offset: Int
    public var length: Int

    public init(issue: Issue, offset: Int, length: Int) {
        self.issue = issue
        self.offset = offset
        self.length = length
    }

    var end: Int { offset + length }
}

/// Validates model output against the text it was asked about. Anything the
/// model invented (text not present, no-op replacement, overlaps, extra
/// "natural" tips) is dropped — a false correction is worse than none.
public enum IssueLocator {
    public static func locate(_ issues: [Issue], in text: String) -> [LocatedIssue] {
        var accepted: [LocatedIssue] = []
        var cursor = text.startIndex
        var hasNatural = false

        for issue in issues {
            guard !issue.original.isEmpty, !isNoOp(issue) else { continue }
            if issue.category == .natural && hasNatural { continue }

            let candidates = [cursor..<text.endIndex, text.startIndex..<text.endIndex]
            var placed: LocatedIssue?
            var placedEnd = cursor
            for searchRange in candidates {
                var from = searchRange.lowerBound
                while let r = text.range(of: issue.original, range: from..<text.endIndex) {
                    // "a" must not match the "a" inside "have": require word boundaries.
                    guard isWordAligned(r, original: issue.original, in: text) else {
                        from = text.index(after: r.lowerBound)
                        continue
                    }
                    let li = LocatedIssue(issue: issue,
                                          offset: text.distance(from: text.startIndex, to: r.lowerBound),
                                          length: text.distance(from: r.lowerBound, to: r.upperBound))
                    if !accepted.contains(where: { overlaps($0, li) }) {
                        placed = li
                        placedEnd = r.upperBound
                        break
                    }
                    // Only the first non-overlapping occurrence counts on the fallback pass;
                    // an overlapping one means the model double-reported the same words.
                    if searchRange.lowerBound == text.startIndex { break }
                    from = r.upperBound
                }
                if placed != nil { break }
            }
            guard let li = placed else { continue }
            accepted.append(li)
            cursor = max(cursor, placedEnd)
            if issue.category == .natural { hasNatural = true }
        }
        return accepted.sorted { $0.offset < $1.offset }
    }

    /// True unless the match starts or ends in the middle of a word.
    static func isWordAligned(_ r: Range<String.Index>, original: String, in text: String) -> Bool {
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        if let first = original.first, isWordChar(first), r.lowerBound > text.startIndex,
           isWordChar(text[text.index(before: r.lowerBound)]) { return false }
        if let last = original.last, isWordChar(last), r.upperBound < text.endIndex,
           isWordChar(text[r.upperBound]) { return false }
        return true
    }

    static func isNoOp(_ issue: Issue) -> Bool {
        let a = issue.original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = issue.replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a == b
    }

    static func overlaps(_ a: LocatedIssue, _ b: LocatedIssue) -> Bool {
        a.offset < b.end && b.offset < a.end
    }
}
