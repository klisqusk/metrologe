import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CountedStatement {
    let line: Int
    let name: String
    let isControl: Bool
}

struct GilbMetrics {
    var cl = 0
    var n = 0
    var maxNesting = 0
    var statements: [CountedStatement] = []

    var clRel: Double {
        n == 0 ? 0 : Double(cl) / Double(n)
    }

    var cli: Int {
        max(0, maxNesting - 1)
    }
}

struct AnalysisError: LocalizedError {
    let line: Int
    let message: String

    var errorDescription: String? {
        "Строка \(line): \(message)"
    }
}

private struct Token {
    let text: String
    let line: Int
    let isLiteral: Bool

    init(_ text: String, _ line: Int, literal: Bool = false) {
        self.text = text
        self.line = line
        self.isLiteral = literal
    }
}

private final class Lexer {
    private let chars: [Character]
    private var i = 0
    private var line = 1
    private var tokens: [Token] = []
    private let operatorCharacters = Set("+-*/%=!<>&|^~.?")

    init(_ code: String) {
        chars = Array(
            code
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        )
    }

    private func starts(_ value: String) -> Bool {
        let part = Array(value)
        guard i + part.count <= chars.count else {
            return false
        }
        return Array(chars[i..<(i + part.count)]) == part
    }

    private func advance() {
        if chars[i] == "\n" {
            line += 1
        }
        i += 1
    }

    private func skipComment() throws {
        if starts("//") {
            while i < chars.count && chars[i] != "\n" {
                advance()
            }
            return
        }

        let startLine = line
        i += 2
        var depth = 1

        while i < chars.count {
            if starts("/*") {
                depth += 1
                i += 2
            } else if starts("*/") {
                depth -= 1
                i += 2

                if depth == 0 {
                    return
                }
            } else {
                advance()
            }
        }

        throw AnalysisError(
            line: startLine,
            message: "Не закрыт комментарий /* ... */."
        )
    }

    private func skipString() throws {
        let startLine = line
        let multiline = starts("\"\"\"")
        let delimiter = multiline ? "\"\"\"" : "\""

        i += multiline ? 3 : 1

        while i < chars.count {
            if starts(delimiter) {
                i += multiline ? 3 : 1
                return
            }

            if chars[i] == "\\" {
                advance()

                if i < chars.count {
                    if chars[i] == "(" {
                        advance()
                        var depth = 1

                        while i < chars.count && depth > 0 {
                            if chars[i] == "(" {
                                depth += 1
                            } else if chars[i] == ")" {
                                depth -= 1
                            }
                            advance()
                        }
                    } else {
                        advance()
                    }
                }
            } else {
                if chars[i] == "\n" && !multiline {
                    throw AnalysisError(
                        line: startLine,
                        message: "Не закрыта строка в кавычках."
                    )
                }
                advance()
            }
        }

        throw AnalysisError(
            line: startLine,
            message: "Не закрыта строка в кавычках."
        )
    }

    func scan() throws -> [Token] {
        while i < chars.count {
            let c = chars[i]

            if c == "\n" {
                tokens.append(Token("\n", line))
                advance()
            } else if c.isWhitespace {
                advance()
            } else if starts("//") || starts("/*") {
                let oldLine = line
                try skipComment()

                if line > oldLine {
                    tokens.append(Token("\n", oldLine))
                }
            } else if c == "\"" {
                let startLine = line
                try skipString()
                tokens.append(Token("<строка>", startLine, literal: true))
            } else if c == "#" || c == "`" || c == "@" {
                throw AnalysisError(
                    line: line,
                    message: "Конструкция не поддерживается."
                )
            } else if c.isLetter || c.isNumber || c == "_" {
                let start = i

                while i < chars.count &&
                        (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    advance()
                }

                tokens.append(Token(String(chars[start..<i]), line))
            } else if operatorCharacters.contains(c) {
                let start = i

                while i < chars.count && operatorCharacters.contains(chars[i]) {
                    if starts("//") || starts("/*") {
                        break
                    }
                    advance()
                }

                tokens.append(Token(String(chars[start..<i]), line))
            } else {
                tokens.append(Token(String(c), line))
                advance()
            }
        }

        return tokens
    }
}

final class Parser {
    func analyze(code: String) throws -> GilbMetrics {
        let engine = Engine(tokens: try Lexer(code).scan())
        return try engine.run()
    }
}

private final class Engine {
    private let tokens: [Token]
    private var i = 0
    private var metrics = GilbMetrics()

    private let unsupported: Set<String> = [
        "defer", "do", "catch", "throw", "throws", "rethrows",
        "fallthrough", "struct", "class", "enum", "extension",
        "protocol", "actor", "init", "deinit", "subscript",
        "typealias", "async", "await"
    ]

    private let continuation: Set<String> = [
        "=", "+=", "-=", "*=", "/=", "%=",
        "+", "-", "*", "/", "%",
        "&&", "||", "==", "!=", "<", ">", "<=", ">=",
        "??", "?", ",", ".", ":",
        "...", "..<", "->", "in"
    ]

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: String {
        i < tokens.count ? tokens[i].text : "<EOF>"
    }

    private var line: Int {
        i < tokens.count ? tokens[i].line : (tokens.last?.line ?? 1)
    }

    private func fail(_ message: String) -> AnalysisError {
        AnalysisError(line: line, message: message)
    }

    private func skipLines() {
        while current == "\n" {
            i += 1
        }
    }

    private func separators() {
        while current == "\n" || current == ";" {
            i += 1
        }
    }

    private func expect(_ value: String) throws {
        guard current == value else {
            throw fail("Ожидалось «\(value)», найдено «\(current)».")
        }
        i += 1
    }

    private func addSimple(_ name: String, at line: Int) {
        metrics.n += 1
        metrics.statements.append(
            CountedStatement(
                line: line,
                name: name,
                isControl: false
            )
        )
    }

    private func addControl(_ name: String, at line: Int, depth: Int) {
        metrics.n += 1
        metrics.cl += 1
        metrics.maxNesting = max(metrics.maxNesting, depth)

        metrics.statements.append(
            CountedStatement(
                line: line,
                name: name,
                isControl: true
            )
        )
    }

    private func expression(until stop: String? = nil) throws -> [Token] {
        var result: [Token] = []
        var stack: [String] = []

        while i < tokens.count {
            let token = tokens[i]

            if stack.isEmpty {
                if let stop, current == stop {
                    break
                }

                if current == "}" ||
                    current == ";" ||
                    current == "case" ||
                    current == "default" {
                    break
                }

                if current == "\n" {
                    var j = i + 1

                    while j < tokens.count && tokens[j].text == "\n" {
                        j += 1
                    }

                    let next = j < tokens.count ? tokens[j].text : "<EOF>"

                    if stop == nil &&
                        !continuation.contains(result.last?.text ?? "") &&
                        next != "." {
                        break
                    }
                }
            }

            if current == "{" {
                throw fail("Неожиданный блок.")
            }

            if unsupported.contains(current) ||
                current == "if" ||
                current == "switch" {
                throw fail("Конструкция «\(current)» внутри выражения не поддерживается.")
            }

            if current == "(" {
                stack.append(")")
            } else if current == "[" {
                stack.append("]")
            } else if current == ")" || current == "]" {
                guard stack.last == current else {
                    throw fail("Несогласованные скобки.")
                }
                stack.removeLast()
            }

            if current != "\n" {
                result.append(token)
            }

            i += 1
        }

        guard stack.isEmpty else {
            throw fail("Не закрыта скобка в выражении.")
        }

        guard !result.isEmpty else {
            throw fail("Ожидалось выражение.")
        }

        return result
    }

    private func block(depth: Int) throws {
        skipLines()
        try expect("{")
        try sequence(depth: depth, inCase: false)
        try expect("}")
    }

    private func closureBlock(depth: Int) throws {
        skipLines()
        try expect("{")
        skipLines()

        var foundIn = false

        while i < tokens.count {
            if current == "in" {
                foundIn = true
                i += 1
                break
            }

            if current == "\n" || current == "}" || current == "{" {
                break
            }

            i += 1
        }

        guard foundIn else {
            throw fail("В forEach ожидалось ключевое слово in.")
        }

        try sequence(depth: depth, inCase: false)
        try expect("}")
    }

    private func looksLikeForEachStatement() -> Bool {
        var j = i
        var roundDepth = 0
        var squareDepth = 0

        while j < tokens.count {
            let text = tokens[j].text

            if text == "(" {
                roundDepth += 1
            } else if text == ")" {
                roundDepth -= 1
            } else if text == "[" {
                squareDepth += 1
            } else if text == "]" {
                squareDepth -= 1
            }

            if roundDepth == 0 && squareDepth == 0 {
                if text == "{" {
                    return tokens[i..<j].contains(where: { $0.text == "forEach" })
                }

                if text == "\n" || text == ";" || text == "}" {
                    return false
                }
            }

            j += 1
        }

        return false
    }

    private func sequence(depth: Int, inCase: Bool) throws {
        separators()

        while i < tokens.count &&
                current != "}" &&
                !(inCase && (current == "case" || current == "default")) {
            try statement(depth: depth)
            separators()
        }
    }

    private func statement(depth: Int) throws {
        let startLine = line
        let keyword = current

        if unsupported.contains(keyword) {
            throw fail("Конструкция «\(keyword)» не поддерживается.")
        }

        if looksLikeForEachStatement() {
            _ = try expression(until: "{")
            addControl("forEach", at: startLine, depth: depth + 1)
            try closureBlock(depth: depth + 1)
            return
        }

        switch keyword {
        case "import":
            i += 1
            _ = try expression()

        case "func":
            i += 1
            _ = try expression(until: "{")
            try block(depth: 0)

        case "if":
            i += 1
            _ = try expression(until: "{")
            addControl("if", at: startLine, depth: depth + 1)
            try block(depth: depth + 1)

            skipLines()

            if current == "else" {
                i += 1
                skipLines()

                if current == "if" {
                    try statement(depth: depth + 1)
                } else {
                    try block(depth: depth + 1)
                }
            }

        case "guard":
            i += 1
            _ = try expression(until: "else")
            try expect("else")
            addControl("guard", at: startLine, depth: depth + 1)
            try skipGuardBlock()

        case "for", "while":
            i += 1
            let header = try expression(until: "{")

            if keyword == "for" &&
                !header.contains(where: { $0.text == "in" }) {
                throw fail("Ожидался цикл for ... in ... .")
            }

            addControl(keyword, at: startLine, depth: depth + 1)
            try block(depth: depth + 1)

        case "repeat":
            i += 1
            addControl("repeat-while", at: startLine, depth: depth + 1)
            try block(depth: depth + 1)
            skipLines()
            try expect("while")
            _ = try expression()

        case "switch":
            i += 1
            _ = try expression(until: "{")
            try expect("{")
            separators()

            var sawDefault = false
            var caseNumber = 0

            while current != "}" && i < tokens.count {
                let caseLine = line

                if current == "case" {
                    guard !sawDefault else {
                        throw fail("default должен быть последней веткой.")
                    }

                    i += 1
                    _ = try expression(until: ":")
                    try expect(":")

                    caseNumber += 1
                    addControl(
                        "case → if №\(caseNumber)",
                        at: caseLine,
                        depth: depth + 1
                    )

                    try sequence(
                        depth: depth + 1,
                        inCase: true
                    )
                } else if current == "default" {
                    sawDefault = true
                    i += 1
                    skipLines()
                    try expect(":")

                    try sequence(
                        depth: depth + 1,
                        inCase: true
                    )
                } else {
                    throw fail("В switch ожидалось case или default.")
                }

                separators()
            }

            try expect("}")

            guard sawDefault else {
                throw AnalysisError(
                    line: startLine,
                    message: "В switch ожидается default."
                )
            }

        case "continue", "break", "return":
            _ = try expressionOrSingleKeyword()

        case "print":
            _ = try expression()

        case "else", "case", "default", "{":
            throw fail("Неожиданная конструкция «\(keyword)».")

        default:
            let parts = try expression()
            let name = parts.map { $0.text }.joined(separator: " ")

            if parts.contains(where: { $0.text == "?" }) {
                addControl(
                    "тернарный оператор ?:",
                    at: startLine,
                    depth: depth + 1
                )
            } else {
                addSimple(name, at: startLine)
            }
        }
    }

    private func skipGuardBlock() throws {
        skipLines()
        try expect("{")

        var braces = 1

        while i < tokens.count && braces > 0 {
            if current == "{" {
                braces += 1
            } else if current == "}" {
                braces -= 1
            }
            i += 1
        }

        if braces != 0 {
            throw fail("Не закрыт блок guard.")
        }
    }

    private func expressionOrSingleKeyword() throws -> [Token] {
        let start = i

        while i < tokens.count &&
                current != "\n" &&
                current != ";" &&
                current != "}" {
            i += 1
        }

        return Array(tokens[start..<i])
    }

    func run() throws -> GilbMetrics {
        try sequence(depth: 0, inCase: false)

        guard i == tokens.count else {
            throw fail("Лишняя закрывающая скобка.")
        }

        return metrics
    }
}

struct ContentView: View {
    @State private var fileContent = ""
    @State private var resultText =
        "Нажмите «Рассчитать». Можно редактировать код прямо в окне."
    @State private var fileName = "Введённый код"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Метрика Джилба — анализ Swift")
                .font(.title2)
                .bold()

            HStack {
                Button("Открыть файл", action: openFile)

                Button("Рассчитать", action: analyze)
                    .buttonStyle(.borderedProminent)
            }

            Text("switch → вложенные if; внешний уровень = 1; CLI считается с нуля.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $fileContent)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 230)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.4))
                )
                .onChange(of: fileContent) {
                    resultText =
                        "Код изменён. Нажмите «Рассчитать», чтобы обновить результат."
                }

            ScrollView {
                Text(resultText)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 190)
            .background(Color.primary.opacity(0.04))
        }
        .padding()
        .frame(minWidth: 780, minHeight: 650)
    }

    private func analyze() {
        do {
            let m = try Parser().analyze(code: fileContent)

            resultText = """
            Файл: \(fileName)

            Абсолютная сложность CL:       \(m.cl)
            Общее число операторов N:      \(m.n)
            Относительная сложность cl:    \(String(format: "%.4f", m.clRel))
            Максимальная вложенность CLI:  \(m.cli)
            """
        } catch {
            resultText =
                "Расчёт не выполнен.\n\(error.localizedDescription)"
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .swiftSource,
            .plainText,
            .text
        ]

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            fileContent = try String(contentsOf: url, encoding: .utf8)
            fileName = url.lastPathComponent
            resultText = "Файл загружен. Нажмите «Рассчитать»."
        } catch {
            resultText =
                "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }
}
