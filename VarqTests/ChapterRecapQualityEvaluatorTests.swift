import Testing
@testable import Varq

struct ChapterRecapQualityEvaluatorTests {
    @Test func acceptsAReaderReadyRecap() {
        let response = """
        Recap:
        Mira discovers that the missing letter was hidden in the observatory.

        Key ideas:
        - Curiosity leads Mira to examine overlooked evidence.
        - The observatory connects the letter to her family history.

        Reflection questions:
        1. Why does Mira return to the observatory?
        2. What does the letter change about her understanding of her family?
        """

        let report = ChapterRecapQualityEvaluator.evaluate(response)

        #expect(report.hasRecap)
        #expect(report.hasKeyIdeas)
        #expect(report.reflectionQuestionCount == 2)
        #expect(report.meetsBaseline)
    }

    @Test func rejectsMissingRequiredSections() {
        let response = """
        The protagonist finds an old letter.
        1. What does it mean?
        """

        let report = ChapterRecapQualityEvaluator.evaluate(response)

        #expect(!report.hasRecap)
        #expect(!report.hasKeyIdeas)
        #expect(!report.meetsBaseline)
    }

    @Test func rejectsMoreThanThreeReflectionQuestions() {
        let response = """
        Recap:
        A brief recap.

        Key ideas:
        - One idea.

        Reflection questions:
        1. First question?
        2. Second question?
        3. Third question?
        4. Fourth question?
        """

        let report = ChapterRecapQualityEvaluator.evaluate(response)

        #expect(report.reflectionQuestionCount == 4)
        #expect(!report.meetsBaseline)
    }
}
