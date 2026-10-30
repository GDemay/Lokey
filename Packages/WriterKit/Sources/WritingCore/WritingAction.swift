import Foundation

/// A user-facing operation. `id` is the key of its prompt in prompts.json.
public struct WritingAction: Identifiable, Hashable, Sendable {
    public enum Group: String, Sendable, CaseIterable {
        case fix, enhance, translate, ask
    }

    public let id: String
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    public let group: Group

    public init(id: String, title: String, symbol: String, group: Group) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.group = group
    }

    /// Minimal edit: spelling, grammar, punctuation, capitalization.
    public static let fix = WritingAction(id: "fix", title: "Fix", symbol: "checkmark.circle.fill", group: .fix)
    /// Free-form writing from a request ("write a reply saying…").
    public static let ask = WritingAction(id: "ask", title: "Ask AI", symbol: "sparkles", group: .ask)

    public static let enhance: [WritingAction] = [
        .init(id: "rephrase", title: "Rephrase", symbol: "arrow.triangle.2.circlepath", group: .enhance),
        .init(id: "professional", title: "Professional", symbol: "briefcase", group: .enhance),
        .init(id: "friendly", title: "Friendly", symbol: "face.smiling", group: .enhance),
        .init(id: "casual", title: "Casual", symbol: "cup.and.saucer", group: .enhance),
        .init(id: "confident", title: "Confident", symbol: "bolt", group: .enhance),
        .init(id: "persuasive", title: "Persuasive", symbol: "megaphone", group: .enhance),
        .init(id: "shorter", title: "Shorter", symbol: "arrow.down.right.and.arrow.up.left", group: .enhance),
        .init(id: "longer", title: "Longer", symbol: "arrow.up.left.and.arrow.down.right", group: .enhance),
        .init(id: "emojify", title: "Emojify", symbol: "face.smiling.inverse", group: .enhance),
    ]

    public static let translate: [WritingAction] = [
        .init(id: "to_english", title: "To English", symbol: "globe", group: .translate),
        .init(id: "to_french", title: "To French", symbol: "globe.europe.africa", group: .translate),
        .init(id: "to_spanish", title: "To Spanish", symbol: "globe.americas", group: .translate),
        .init(id: "to_german", title: "To German", symbol: "globe.europe.africa", group: .translate),
    ]

    public static let all: [WritingAction] = [fix] + enhance + translate + [ask]

    public static func with(id: String) -> WritingAction? { all.first { $0.id == id } }
}
