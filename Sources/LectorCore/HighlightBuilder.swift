import Foundation

/// Marks a run of text as belonging to an issue of the given category. Views pick colours.
public enum IssueCategoryAttribute: AttributedStringKey {
    public typealias Value = IssueCategory
    public static let name = "cz.lukisk.lector.issueCategory"
}

public enum HighlightBuilder {
    /// The checked text with every issue's original words marked.
    public static func original(_ text: String, issues: [LocatedIssue]) -> AttributedString {
        var out = AttributedString(text)
        for li in issues {
            let start = out.characters.index(out.startIndex, offsetBy: li.offset)
            let end = out.characters.index(start, offsetBy: li.length)
            out[start..<end][IssueCategoryAttribute.self] = li.issue.category
        }
        return out
    }

    /// The text with replacements applied and the replacements marked.
    public static func corrected(_ text: String, issues: [LocatedIssue]) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for li in issues.sorted(by: { $0.offset < $1.offset }) {
            let start = text.index(text.startIndex, offsetBy: li.offset)
            let end = text.index(start, offsetBy: li.length)
            guard start >= cursor else { continue }
            out += AttributedString(String(text[cursor..<start]))
            var replacement = AttributedString(li.issue.replacement)
            replacement[IssueCategoryAttribute.self] = li.issue.category
            out += replacement
            cursor = end
        }
        out += AttributedString(String(text[cursor...]))
        return out
    }
}
