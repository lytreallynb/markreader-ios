import SwiftUI
import MarkdownUI

struct NativeCodeBlockHighlighter: CodeSyntaxHighlighter {

    func highlightCode(_ code: String, language: String?) -> Text {
        guard let lang = Self.language(for: language) else {
            return Text(code)
        }
        let tokens = Self.tokenize(code, language: lang)
        return tokens.reduce(Text("")) { partial, token in
            partial + Self.render(token)
        }
    }

    private enum Language {
        case swift, python, javascript, json, shell, cLike, javaKotlin, sql, html, css
    }

    private enum TokenKind {
        case comment, string, number, keyword, type, plain
    }

    private struct Token {
        let text: String
        let kind: TokenKind
    }

    private struct LanguageSpec {
        let lineComment: String?
        let blockCommentStart: String?
        let blockCommentEnd: String?
        let stringDelimiters: Set<Character>
        let allowTripleQuoted: Bool
        let keywords: Set<String>
        let constants: Set<String>
    }

    private static func render(_ token: Token) -> Text {
        switch token.kind {
        case .comment:
            return Text(token.text).foregroundStyle(.gray)
        case .string:
            return Text(token.text).foregroundStyle(.red)
        case .number:
            return Text(token.text).foregroundStyle(.orange)
        case .keyword:
            return Text(token.text).foregroundStyle(.purple).bold()
        case .type:
            return Text(token.text).foregroundStyle(.blue)
        case .plain:
            return Text(token.text).foregroundStyle(.primary)
        }
    }

    private static func language(for raw: String?) -> Language? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "swift":
            return .swift
        case "python", "py", "py3":
            return .python
        case "javascript", "js", "jsx", "mjs", "cjs", "typescript", "ts", "tsx":
            return .javascript
        case "json", "json5", "jsonc":
            return .json
        case "bash", "sh", "shell", "zsh", "console", "shell-session":
            return .shell
        case "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "c++", "objective-c", "objc", "objectivec":
            return .cLike
        case "java", "kotlin", "kt", "kts":
            return .javaKotlin
        case "sql", "mysql", "postgresql", "psql", "sqlite":
            return .sql
        case "html", "htm", "xhtml", "xml":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        default:
            return nil
        }
    }

    private static func spec(for language: Language) -> LanguageSpec {
        switch language {
        case .swift:
            return LanguageSpec(
                lineComment: "//",
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["\""],
                allowTripleQuoted: true,
                keywords: [
                    "func", "var", "let", "if", "else", "guard", "for", "while", "repeat", "switch",
                    "case", "default", "break", "continue", "return", "struct", "class", "enum",
                    "protocol", "extension", "import", "init", "deinit", "self", "Self", "super",
                    "static", "final", "private", "fileprivate", "internal", "public", "open",
                    "throws", "throw", "try", "catch", "do", "as", "is", "in", "where", "typealias",
                    "associatedtype", "subscript", "inout", "lazy", "mutating", "nonmutating",
                    "override", "required", "convenience", "weak", "unowned", "some", "any",
                    "async", "await", "defer", "operator", "rethrows", "willSet", "didSet", "get", "set"
                ],
                constants: ["true", "false", "nil"]
            )
        case .python:
            return LanguageSpec(
                lineComment: "#",
                blockCommentStart: nil,
                blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: true,
                keywords: [
                    "def", "class", "if", "elif", "else", "for", "while", "break", "continue",
                    "return", "import", "from", "as", "pass", "try", "except", "finally", "raise",
                    "with", "lambda", "yield", "global", "nonlocal", "assert", "del", "in", "is",
                    "not", "and", "or", "async", "await", "self", "cls"
                ],
                constants: ["True", "False", "None"]
            )
        case .javascript:
            return LanguageSpec(
                lineComment: "//",
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'", "`"],
                allowTripleQuoted: false,
                keywords: [
                    "function", "var", "let", "const", "if", "else", "for", "while", "do", "break",
                    "continue", "return", "switch", "case", "default", "try", "catch", "finally",
                    "throw", "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends",
                    "super", "this", "import", "export", "from", "as", "async", "await", "yield",
                    "static", "get", "set", "interface", "type", "enum", "implements", "public",
                    "private", "protected", "readonly", "namespace", "declare"
                ],
                constants: ["true", "false", "null", "undefined", "NaN"]
            )
        case .json:
            return LanguageSpec(
                lineComment: nil,
                blockCommentStart: nil,
                blockCommentEnd: nil,
                stringDelimiters: ["\""],
                allowTripleQuoted: false,
                keywords: [],
                constants: ["true", "false", "null"]
            )
        case .shell:
            return LanguageSpec(
                lineComment: "#",
                blockCommentStart: nil,
                blockCommentEnd: nil,
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: false,
                keywords: [
                    "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
                    "function", "return", "export", "local", "readonly", "shift", "break", "continue",
                    "in", "select", "until", "echo", "exit"
                ],
                constants: ["true", "false"]
            )
        case .cLike:
            return LanguageSpec(
                lineComment: "//",
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: false,
                keywords: [
                    "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                    "struct", "union", "enum", "typedef", "if", "else", "for", "while", "do", "switch",
                    "case", "default", "break", "continue", "return", "goto", "sizeof", "static",
                    "const", "volatile", "extern", "inline", "class", "public", "private", "protected",
                    "virtual", "namespace", "template", "typename", "new", "delete", "this", "using",
                    "friend", "operator", "explicit", "auto", "constexpr", "override", "final"
                ],
                constants: ["true", "false", "NULL", "nullptr"]
            )
        case .javaKotlin:
            return LanguageSpec(
                lineComment: "//",
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: false,
                keywords: [
                    "class", "interface", "object", "fun", "val", "var", "if", "else", "for", "while",
                    "do", "switch", "when", "case", "default", "break", "continue", "return", "throw",
                    "try", "catch", "finally", "import", "package", "public", "private", "protected",
                    "static", "final", "abstract", "override", "extends", "implements", "new", "this",
                    "super", "void", "int", "long", "double", "float", "boolean", "char", "byte",
                    "short", "companion", "init", "constructor", "is", "as", "in", "out", "sealed",
                    "data", "enum", "suspend"
                ],
                constants: ["true", "false", "null"]
            )
        case .sql:
            return LanguageSpec(
                lineComment: "--",
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["'"],
                allowTripleQuoted: false,
                keywords: [
                    "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                    "create", "table", "alter", "drop", "join", "inner", "left", "right", "outer",
                    "on", "group", "by", "order", "having", "limit", "offset", "as", "and", "or",
                    "not", "null", "is", "in", "like", "between", "distinct", "union", "all", "case",
                    "when", "then", "else", "end", "primary", "key", "foreign", "references",
                    "index", "view", "with"
                ],
                constants: ["true", "false", "null"]
            )
        case .html:
            return LanguageSpec(
                lineComment: nil,
                blockCommentStart: "<!--",
                blockCommentEnd: "-->",
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: false,
                keywords: [],
                constants: []
            )
        case .css:
            return LanguageSpec(
                lineComment: nil,
                blockCommentStart: "/*",
                blockCommentEnd: "*/",
                stringDelimiters: ["\"", "'"],
                allowTripleQuoted: false,
                keywords: [
                    "important", "media", "supports", "keyframes", "from", "to", "root", "import",
                    "charset", "font-face"
                ],
                constants: []
            )
        }
    }

    private static func tokenize(_ code: String, language: Language) -> [Token] {
        let spec = spec(for: language)
        let chars = Array(code)
        var tokens: [Token] = []
        var plainBuffer = ""
        var position = 0

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            tokens.append(Token(text: plainBuffer, kind: .plain))
            plainBuffer = ""
        }

        func matches(_ literal: String, at start: Int) -> Bool {
            let literalChars = Array(literal)
            guard start + literalChars.count <= chars.count else { return false }
            for offset in 0..<literalChars.count where chars[start + offset] != literalChars[offset] {
                return false
            }
            return true
        }

        while position < chars.count {
            let char = chars[position]

            if let start = spec.blockCommentStart, let end = spec.blockCommentEnd, matches(start, at: position) {
                flushPlain()
                var scan = position + start.count
                while scan < chars.count && !matches(end, at: scan) {
                    scan += 1
                }
                let closing = min(scan + end.count, chars.count)
                tokens.append(Token(text: String(chars[position..<closing]), kind: .comment))
                position = closing
                continue
            }

            if let lineComment = spec.lineComment, matches(lineComment, at: position) {
                flushPlain()
                var scan = position
                while scan < chars.count && chars[scan] != "\n" {
                    scan += 1
                }
                tokens.append(Token(text: String(chars[position..<scan]), kind: .comment))
                position = scan
                continue
            }

            if spec.stringDelimiters.contains(char) {
                flushPlain()
                let quote = char
                var tripleQuoted = false
                var openLength = 1
                if spec.allowTripleQuoted, quote == "\"", matches("\"\"\"", at: position) {
                    tripleQuoted = true
                    openLength = 3
                }
                var scan = position + openLength
                if tripleQuoted {
                    while scan < chars.count && !matches("\"\"\"", at: scan) {
                        if chars[scan] == "\\" && scan + 1 < chars.count {
                            scan += 2
                        } else {
                            scan += 1
                        }
                    }
                    scan = min(scan + 3, chars.count)
                } else {
                    while scan < chars.count && chars[scan] != quote && chars[scan] != "\n" {
                        if chars[scan] == "\\" && scan + 1 < chars.count {
                            scan += 2
                        } else {
                            scan += 1
                        }
                    }
                    if scan < chars.count && chars[scan] == quote {
                        scan += 1
                    }
                }
                tokens.append(Token(text: String(chars[position..<scan]), kind: .string))
                position = scan
                continue
            }

            if char.isNumber {
                flushPlain()
                var scan = position
                while scan < chars.count && isNumberContinuation(chars[scan]) {
                    scan += 1
                }
                tokens.append(Token(text: String(chars[position..<scan]), kind: .number))
                position = scan
                continue
            }

            if char.isLetter || char == "_" {
                flushPlain()
                var scan = position
                while scan < chars.count && (chars[scan].isLetter || chars[scan].isNumber || chars[scan] == "_") {
                    scan += 1
                }
                let word = String(chars[position..<scan])
                if spec.constants.contains(word) {
                    tokens.append(Token(text: word, kind: .type))
                } else if spec.keywords.contains(word) {
                    tokens.append(Token(text: word, kind: .keyword))
                } else if let firstCharacter = word.first, firstCharacter.isUppercase {
                    tokens.append(Token(text: word, kind: .type))
                } else {
                    tokens.append(Token(text: word, kind: .plain))
                }
                position = scan
                continue
            }

            plainBuffer.append(char)
            position += 1
        }

        flushPlain()
        return tokens
    }

    private static func isNumberContinuation(_ char: Character) -> Bool {
        if char.isNumber || char == "." || char == "_" {
            return true
        }
        let lowered = Character(char.lowercased())
        return "abcdefx".contains(lowered)
    }
}
