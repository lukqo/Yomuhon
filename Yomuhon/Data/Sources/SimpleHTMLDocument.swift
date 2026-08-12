//
//  SimpleHTMLDocument.swift
//  Yomuhon
//
//  A small tolerant HTML DOM and CSS selector engine for the exact selector
//  subset documented by Yomuhon-Sources. It intentionally does not execute JS.
//

import Foundation

protocol YomuhonHTMLScope {
    func select(_ selector: String) -> [YomuhonHTMLElement]
    func first(_ selector: String) -> YomuhonHTMLElement?
    func attr(_ name: String) -> String?
    var text: String { get }
    var html: String { get }
}

protocol YomuhonHTMLDocument: YomuhonHTMLScope {
    var rawHTML: String { get }
}

protocol YomuhonHTMLElement: YomuhonHTMLScope {}

private enum HTMLContent {
    case text(String)
    case element(HTMLNode)
}

private final class HTMLNode {
    let tagName: String
    let attributes: [String: String]
    weak var parent: HTMLNode?
    var contents: [HTMLContent] = []

    init(tagName: String, attributes: [String: String], parent: HTMLNode? = nil) {
        self.tagName = tagName.lowercased()
        self.attributes = attributes
        self.parent = parent
    }

    var descendants: [HTMLNode] {
        var output: [HTMLNode] = []
        for content in contents {
            guard case .element(let child) = content else { continue }
            output.append(child)
            output.append(contentsOf: child.descendants)
        }
        return output
    }

    var children: [HTMLNode] {
        contents.compactMap { content -> HTMLNode? in
            guard case .element(let child) = content else { return nil }
            return child
        }
    }

    /// The next element sibling, for the `+` adjacent-sibling combinator.
    var nextElementSibling: HTMLNode? {
        guard let parent, let index = parent.children.firstIndex(where: { $0 === self }) else {
            return nil
        }
        let siblings = parent.children
        return index + 1 < siblings.count ? siblings[index + 1] : nil
    }

    /// All later element siblings, for the `~` general-sibling combinator.
    var followingElementSiblings: [HTMLNode] {
        guard let parent, let index = parent.children.firstIndex(where: { $0 === self }) else {
            return []
        }
        let siblings = parent.children
        return index + 1 < siblings.count ? Array(siblings[(index + 1)...]) : []
    }

    var textContent: String {
        contents.compactMap { content -> String? in
            switch content {
            case .text(let value):
                return value
            case .element(let node):
                return node.textContent
            }
        }
        .joined(separator: " ")
        .yomuhonDecodeHTMLEntities()
        .yomuhonNormalizeWhitespace()
    }

    var serializedHTML: String {
        if tagName == "#document" {
            return contents.map { content in
                switch content {
                case .text(let value): return value
                case .element(let node): return node.serializedHTML
                }
            }.joined()
        }

        let attributesText = attributes
            .sorted { $0.key < $1.key }
            .map { key, value in " \(key)=\"\(value)\"" }
            .joined()
        let inner = contents.map { content in
            switch content {
            case .text(let value): return value
            case .element(let node): return node.serializedHTML
            }
        }.joined()

        if HTMLParser.voidTags.contains(tagName) {
            return "<\(tagName)\(attributesText)>"
        }

        return "<\(tagName)\(attributesText)>\(inner)</\(tagName)>"
    }
}

struct SimpleHTMLDocument: YomuhonHTMLDocument {
    let rawHTML: String
    private let root: HTMLNode

    init(html: String) {
        rawHTML = html
        root = HTMLParser.parse(html)
    }

    static func supports(_ selector: String) -> Bool {
        CSSSelectorEngine.supports(selector)
    }

    func select(_ selector: String) -> [YomuhonHTMLElement] {
        CSSSelectorEngine.select(selector, descendantsOf: root)
            .map(SimpleHTMLElement.init)
    }

    func first(_ selector: String) -> YomuhonHTMLElement? {
        select(selector).first
    }

    func attr(_ name: String) -> String? {
        switch name.lowercased() {
        case "text": return text
        case "html": return html
        default: return nil
        }
    }

    var text: String { root.textContent }
    var html: String { rawHTML }
}

private struct SimpleHTMLElement: YomuhonHTMLElement {
    let node: HTMLNode

    func select(_ selector: String) -> [YomuhonHTMLElement] {
        CSSSelectorEngine.select(selector, descendantsOf: node)
            .map(SimpleHTMLElement.init)
    }

    func first(_ selector: String) -> YomuhonHTMLElement? {
        select(selector).first
    }

    func attr(_ name: String) -> String? {
        switch name.lowercased() {
        case "text":
            return text
        case "html":
            return html
        default:
            return node.attributes[name.lowercased()]
        }
    }

    var text: String { node.textContent }
    var html: String { node.serializedHTML }
}

private enum HTMLParser {
    static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    private static let rawTextTags: Set<String> = ["script", "style"]

    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(tagName: "#document", attributes: [:])
        var stack: [HTMLNode] = [root]
        var cursor = html.startIndex

        while cursor < html.endIndex {
            guard let openingBracket = html[cursor...].firstIndex(of: "<") else {
                appendText(String(html[cursor...]), to: stack.last)
                break
            }

            if openingBracket > cursor {
                appendText(String(html[cursor..<openingBracket]), to: stack.last)
            }

            if html[openingBracket...].hasPrefix("<!--") {
                if let end = html.range(of: "-->", range: openingBracket..<html.endIndex)?.upperBound {
                    cursor = end
                } else {
                    break
                }
                continue
            }

            guard let tagEnd = closingBracket(in: html, startingAt: openingBracket) else {
                appendText(String(html[openingBracket...]), to: stack.last)
                break
            }

            let tokenStart = html.index(after: openingBracket)
            let token = String(html[tokenStart..<tagEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = html.index(after: tagEnd)

            guard !token.isEmpty else { continue }

            if token.hasPrefix("!") || token.hasPrefix("?") {
                continue
            }

            if token.hasPrefix("/") {
                let tag = token.dropFirst()
                    .split(whereSeparator: { $0.isWhitespace || $0 == ">" })
                    .first
                    .map(String.init)?
                    .lowercased() ?? ""
                close(tag: tag, stack: &stack)
                continue
            }

            let parsed = parseOpeningTag(token)
            guard !parsed.name.isEmpty else { continue }

            let parent = stack.last ?? root
            let node = HTMLNode(tagName: parsed.name, attributes: parsed.attributes, parent: parent)
            parent.contents.append(.element(node))

            let selfClosing = parsed.selfClosing || voidTags.contains(parsed.name)
            if selfClosing {
                continue
            }

            if rawTextTags.contains(parsed.name) {
                let closingToken = "</\(parsed.name)"
                if let closingRange = html.range(
                    of: closingToken,
                    options: [.caseInsensitive],
                    range: cursor..<html.endIndex
                ), let closingEnd = closingBracket(in: html, startingAt: closingRange.lowerBound) {
                    cursor = html.index(after: closingEnd)
                } else {
                    cursor = html.endIndex
                }
                continue
            }

            stack.append(node)
        }

        return root
    }

    private static func appendText(_ text: String, to node: HTMLNode?) {
        guard let node, !text.isEmpty else { return }
        node.contents.append(.text(text))
    }

    private static func close(tag: String, stack: inout [HTMLNode]) {
        guard !tag.isEmpty, stack.count > 1 else { return }
        if let index = stack.lastIndex(where: { $0.tagName == tag }) {
            stack.removeSubrange(index..<stack.count)
        }
    }

    private static func closingBracket(in html: String, startingAt start: String.Index) -> String.Index? {
        var cursor = html.index(after: start)
        var quote: Character?

        while cursor < html.endIndex {
            let character = html[cursor]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = html.index(after: cursor)
        }

        return nil
    }

    private static func parseOpeningTag(_ token: String) -> (name: String, attributes: [String: String], selfClosing: Bool) {
        let characters = Array(token)
        var index = 0

        func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }

        skipWhitespace()
        let nameStart = index
        while index < characters.count, isNameCharacter(characters[index]) {
            index += 1
        }

        let name = String(characters[nameStart..<index]).lowercased()
        var attributes: [String: String] = [:]
        var selfClosing = false

        while index < characters.count {
            skipWhitespace()
            guard index < characters.count else { break }

            if characters[index] == "/" {
                selfClosing = true
                index += 1
                continue
            }

            let attributeStart = index
            while index < characters.count,
                  !characters[index].isWhitespace,
                  characters[index] != "=",
                  characters[index] != "/" {
                index += 1
            }

            let attributeName = String(characters[attributeStart..<index]).lowercased()
            guard !attributeName.isEmpty else {
                index += 1
                continue
            }

            skipWhitespace()
            var value = ""

            if index < characters.count, characters[index] == "=" {
                index += 1
                skipWhitespace()

                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    let valueStart = index
                    while index < characters.count, characters[index] != quote {
                        index += 1
                    }
                    value = String(characters[valueStart..<index])
                    if index < characters.count { index += 1 }
                } else {
                    let valueStart = index
                    while index < characters.count,
                          !characters[index].isWhitespace,
                          characters[index] != "/" {
                        index += 1
                    }
                    value = String(characters[valueStart..<index])
                }
            }

            attributes[attributeName] = value.yomuhonDecodeHTMLEntities()
        }

        return (name, attributes, selfClosing)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == ":" || character == "-" || character == "_"
    }
}

private final class CSSSimpleSelector {
    enum AttributeOperator {
        case exists
        case equals(String)
        case contains(String)
    }

    struct AttributeRule {
        let name: String
        let operation: AttributeOperator
    }

    let tag: String?
    let id: String?
    let classes: [String]
    let attributes: [AttributeRule]
    let hasDescendant: CSSSimpleSelector?

    init(
        tag: String?,
        id: String?,
        classes: [String],
        attributes: [AttributeRule],
        hasDescendant: CSSSimpleSelector?
    ) {
        self.tag = tag
        self.id = id
        self.classes = classes
        self.attributes = attributes
        self.hasDescendant = hasDescendant
    }

    func matches(_ node: HTMLNode) -> Bool {
        if let tag, tag != "*", node.tagName != tag {
            return false
        }

        if let id, node.attributes["id"] != id {
            return false
        }

        if !classes.isEmpty {
            let classValue = node.attributes["class"] ?? ""
            let nodeClasses = Set(
                classValue
                    .split(whereSeparator: { character in
                        character.isWhitespace
                    })
                    .map { String($0) }
            )

            guard classes.allSatisfy({ nodeClasses.contains($0) }) else {
                return false
            }
        }

        for rule in attributes {
            guard let value = node.attributes[rule.name] else {
                return false
            }

            switch rule.operation {
            case .exists:
                continue
            case .equals(let expected):
                guard value == expected else { return false }
            case .contains(let fragment):
                guard value.contains(fragment) else { return false }
            }
        }

        if let hasDescendant,
           !node.descendants.contains(where: { hasDescendant.matches($0) }) {
            return false
        }

        return true
    }
}

private enum CSSSelectorEngine {
    /// A combinator connects one compound selector to the next.
    /// `descendant` is the implicit combinator represented by whitespace.
    enum Combinator {
        case descendant
        case child
        case adjacentSibling
        case generalSibling
    }

    static func supports(_ selector: String) -> Bool {
        let groups = split(selector, separator: ",")
        guard !groups.isEmpty else { return false }

        return groups.allSatisfy { group in
            guard let steps = tokenizeSteps(group) else { return false }
            return steps.allSatisfy { parseSimpleSelector($0.selector) != nil }
        }
    }

    private static func removingAttributeSelectors(from selector: String) -> String {
        var output = ""
        var bracketDepth = 0
        var quote: Character?

        for character in selector {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                if bracketDepth == 0 { output.append(character) }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                if bracketDepth == 0 { output.append(character) }
            } else if character == "[" {
                bracketDepth += 1
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            } else if bracketDepth == 0 {
                output.append(character)
            }
        }

        return output
    }

    static func select(_ selector: String, descendantsOf root: HTMLNode) -> [HTMLNode] {
        var output: [HTMLNode] = []
        var seen = Set<ObjectIdentifier>()

        for group in split(selector, separator: ",") {
            guard let steps = tokenizeSteps(group) else { continue }

            let parsed = steps.compactMap { step -> (Combinator, CSSSimpleSelector)? in
                guard let simple = parseSimpleSelector(step.selector) else { return nil }
                return (step.combinator, simple)
            }
            guard parsed.count == steps.count else { continue }

            var scopes = [root]
            for (index, step) in parsed.enumerated() {
                // The first compound selector in a group has no combinator
                // before it; it's always evaluated against every descendant
                // of the search root, same as before this combinator support
                // was added.
                let combinator = index == 0 ? .descendant : step.0
                let simpleSelector = step.1

                var matches: [HTMLNode] = []
                var levelSeen = Set<ObjectIdentifier>()

                func consider(_ candidate: HTMLNode) {
                    guard simpleSelector.matches(candidate) else { return }
                    let identifier = ObjectIdentifier(candidate)
                    if levelSeen.insert(identifier).inserted {
                        matches.append(candidate)
                    }
                }

                for scope in scopes {
                    switch combinator {
                    case .descendant:
                        scope.descendants.forEach(consider)
                    case .child:
                        scope.children.forEach(consider)
                    case .adjacentSibling:
                        if let sibling = scope.nextElementSibling {
                            consider(sibling)
                        }
                    case .generalSibling:
                        scope.followingElementSiblings.forEach(consider)
                    }
                }

                scopes = matches
                if scopes.isEmpty { break }
            }

            for node in scopes {
                let identifier = ObjectIdentifier(node)
                if seen.insert(identifier).inserted {
                    output.append(node)
                }
            }
        }

        return output
    }

    private static func parseSimpleSelector(_ token: String) -> CSSSimpleSelector? {
        guard let splitSelector = splitHasPseudoSelector(token) else {
            return nil
        }

        let baseToken = splitSelector.base
        let characters = Array(baseToken)
        var index = 0
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attributes: [CSSSimpleSelector.AttributeRule] = []

        if index < characters.count, characters[index] == "*" {
            tag = "*"
            index += 1
        } else if index < characters.count, isSelectorNameCharacter(characters[index]) {
            let start = index
            while index < characters.count, isSelectorNameCharacter(characters[index]) {
                index += 1
            }
            tag = String(characters[start..<index]).lowercased()
        }

        while index < characters.count {
            switch characters[index] {
            case ".":
                index += 1
                let start = index
                while index < characters.count, isSelectorNameCharacter(characters[index]) {
                    index += 1
                }
                guard start < index else { return nil }
                classes.append(String(characters[start..<index]))

            case "#":
                index += 1
                let start = index
                while index < characters.count, isSelectorNameCharacter(characters[index]) {
                    index += 1
                }
                guard start < index else { return nil }
                id = String(characters[start..<index])

            case "[":
                guard let closingIndex = closingBracket(in: characters, startingAt: index) else {
                    return nil
                }
                let content = String(characters[(index + 1)..<closingIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let rule = parseAttributeRule(content) else { return nil }
                attributes.append(rule)
                index = closingIndex + 1

            default:
                return nil
            }
        }

        let hasDescendant: CSSSimpleSelector?
        if let descendantToken = splitSelector.descendant {
            hasDescendant = parseSimpleSelector(descendantToken)
            guard hasDescendant != nil else { return nil }
        } else {
            hasDescendant = nil
        }

        return CSSSimpleSelector(
            tag: tag,
            id: id,
            classes: classes,
            attributes: attributes,
            hasDescendant: hasDescendant
        )
    }

    private static func splitHasPseudoSelector(_ token: String) -> (base: String, descendant: String?)? {
        let pattern = #"^(.+):has\(([^()]+)\)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
           let baseRange = Range(match.range(at: 1), in: token),
           let descendantRange = Range(match.range(at: 2), in: token) {
            let base = String(token[baseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let descendant = String(token[descendantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty,
                  !descendant.isEmpty,
                  !removingAttributeSelectors(from: base).contains(":"),
                  !removingAttributeSelectors(from: descendant).contains(":"),
                  !descendant.contains(" ")
            else {
                return nil
            }
            return (base, descendant)
        }

        guard !removingAttributeSelectors(from: token).contains(":") else {
            return nil
        }
        return (token, nil)
    }

    private static func parseAttributeRule(_ content: String) -> CSSSimpleSelector.AttributeRule? {
        if let range = content.range(of: "*=") {
            let name = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = unquote(String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !name.isEmpty else { return nil }
            return .init(name: name, operation: .contains(value))
        }

        if let range = content.range(of: "=") {
            let name = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = unquote(String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !name.isEmpty else { return nil }
            return .init(name: name, operation: .equals(value))
        }

        let name = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return nil }
        return .init(name: name, operation: .exists)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }

    private static func closingBracket(in characters: [Character], startingAt start: Int) -> Int? {
        var index = start + 1
        var quote: Character?

        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "]" {
                return index
            }
            index += 1
        }

        return nil
    }

    private static func split(_ value: String, separator: Character) -> [String] {
        var output: [String] = []
        var current = ""
        var bracketDepth = 0
        var quote: Character?

        for character in value {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            } else if character == separator, bracketDepth == 0 {
                let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { output.append(part) }
                current = ""
            } else {
                current.append(character)
            }
        }

        let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !part.isEmpty { output.append(part) }
        return output
    }

    /// Splits a selector group (no top-level commas) into a sequence of
    /// (combinator, compoundSelectorText) steps. Whitespace is the implicit
    /// `descendant` combinator; `>`, `+`, and `~` are explicit combinators
    /// that may additionally be surrounded by whitespace (`a > b` and `a>b`
    /// both tokenize the same way).
    private static func tokenizeSteps(_ value: String) -> [(combinator: Combinator, selector: String)]? {
        var steps: [(Combinator, String)] = []
        var pendingCombinator: Combinator = .descendant
        var current = ""
        var bracketDepth = 0
        var quote: Character?

        func flush() {
            let token = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                steps.append((pendingCombinator, token))
                pendingCombinator = .descendant
            }
            current = ""
        }

        for character in value {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            } else if bracketDepth == 0, character == ">" || character == "+" || character == "~" {
                flush()
                pendingCombinator = character == ">" ? .child : (character == "+" ? .adjacentSibling : .generalSibling)
            } else if bracketDepth == 0, character.isWhitespace {
                flush()
            } else {
                current.append(character)
            }
        }

        flush()
        return steps.isEmpty ? nil : steps
    }

    private static func isSelectorNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == ":"
    }
}

extension String {
    func yomuhonNormalizeWhitespace() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func yomuhonStripHTML() -> String {
        replacingOccurrences(of: #"<script[^>]*>.*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style[^>]*>.*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    func yomuhonDecodeHTMLEntities() -> String {
        var output = self
        let named: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"), ("&quot;", "\""),
            ("&apos;", "'"), ("&nbsp;", " "), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&rdquo;", "”"), ("&ldquo;", "“"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&hellip;", "…"), ("&copy;", "©")
        ]

        for (entity, replacement) in named {
            output = output.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));?"#) else {
            return output
        }

        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: output) else { continue }

            let scalarValue: UInt32?
            if let hexRange = Range(match.range(at: 1), in: output) {
                scalarValue = UInt32(output[hexRange], radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: output) {
                scalarValue = UInt32(output[decimalRange], radix: 10)
            } else {
                scalarValue = nil
            }

            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            output.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return output
    }

    func yomuhonRegexMatches(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: self) else { return "" }
                return String(self[range])
            }
        }
    }

    func yomuhonFirstRegexCapture(pattern: String) -> String? {
        yomuhonRegexMatches(pattern: pattern)
            .first
            .flatMap { $0.count > 1 && !$0[1].isEmpty ? $0[1] : nil }
    }
}
