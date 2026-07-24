import Foundation

/// A deterministic baseline for chapter recaps used by the evaluation suite.
///
/// It intentionally measures only reader-visible structure. Faithfulness remains
/// a human/model-judge concern when Evaluations.framework is available on a
/// supported development machine.
struct ChapterRecapQualityReport: Equatable {
    let hasRecap: Bool
    let hasKeyIdeas: Bool
    let hasReflectionQuestions: Bool
    let reflectionQuestionCount: Int
    let wordCount: Int

    var meetsBaseline: Bool {
        hasRecap && hasKeyIdeas && hasReflectionQuestions && reflectionQuestionCount <= 3 && wordCount > 0 && wordCount <= 400
    }
}

enum ChapterRecapQualityEvaluator {
    static func evaluate(_ text: String) -> ChapterRecapQualityReport {
        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasRecap = containsSection("Recap:", in: lines)
        let hasKeyIdeas = containsSection("Key ideas:", in: lines)
        let hasReflectionQuestions = containsSection("Reflection questions:", in: lines)
        let reflectionQuestionCount = lines.filter(isNumberedQuestion).count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        return ChapterRecapQualityReport(
            hasRecap: hasRecap,
            hasKeyIdeas: hasKeyIdeas,
            hasReflectionQuestions: hasReflectionQuestions,
            reflectionQuestionCount: reflectionQuestionCount,
            wordCount: wordCount
        )
    }

    private static func containsSection(_ title: String, in lines: [String]) -> Bool {
        lines.contains { $0.caseInsensitiveCompare(title) == .orderedSame }
    }

    private static func isNumberedQuestion(_ line: String) -> Bool {
        guard let firstNonNumber = line.firstIndex(where: { !$0.isNumber }) else {
            return false
        }
        guard firstNonNumber > line.startIndex,
              line[firstNonNumber] == "." else {
            return false
        }
        return line.contains("?")
    }
}
