import Foundation
import SwiftParser
import SwiftSyntax

struct Entry: Codable {
    let file: String
    let line: Int
    let english: String
    let simplified: String
    let traditional: String
    let expressions: [String]
}

func template(_ literal: StringLiteralExprSyntax) -> (String, [String]) {
    var copy = literal.representedLiteralValue ?? ""
    var expressions: [String] = []
    if literal.representedLiteralValue == nil {
        for segment in literal.segments {
            if let string = segment.as(StringSegmentSyntax.self) {
                copy += string.content.text
            } else if let expression = segment.as(ExpressionSegmentSyntax.self) {
                expressions.append(expression.expressions.trimmedDescription)
                copy += "{\(expressions.count)}"
            }
        }
    }
    return (copy, expressions)
}

final class Collector: SyntaxVisitor {
    let file: String
    let map: SourceLocationConverter
    var entries = [Entry]()
    var skipped = [Int]()
    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        self.map = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard ["T", "TDetached"].contains(node.calledExpression.trimmedDescription) else { return .visitChildren }
        let line = map.location(for: node.positionAfterSkippingLeadingTrivia).line
        let values = node.arguments.prefix(3).compactMap { $0.expression.as(StringLiteralExprSyntax.self) }.map(template)
        if values.count == 3 {
            entries.append(Entry(file: file, line: line, english: values[0].0, simplified: values[1].0, traditional: values[2].0, expressions: values[0].1))
        } else if file != "MobileStrings.swift" {
            skipped.append(line)
        }
        return .visitChildren
    }
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var entries = [Entry]()
for file in files {
    let tree = Parser.parse(source: try String(contentsOf: file, encoding: .utf8))
    let collector = Collector(file: file.lastPathComponent, tree: tree)
    collector.walk(tree)
    for line in collector.skipped {
        FileHandle.standardError.write(Data("\(file.lastPathComponent):\(line): non-literal T call needs review\n".utf8))
    }
    entries += collector.entries
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(entries))
