import Foundation
import Testing
import YcodeAssistant

@Suite struct LegacySkillsCoreTests {
    private static let skillMarkdown = """
    # Example Skill

    A small example skill used to exercise the parser.

    ## Guidance

    - Prefer real implementations over placeholders.
    - Keep the change surface small.
    """

    @Test func parsesSkillNameAndSummary() throws {
        let skill = try SkillsParser().parse(content: Self.skillMarkdown)
        #expect(skill.name == "Example Skill")
        #expect(skill.description == "A small example skill used to exercise the parser.")
        #expect(skill.content.contains("Prefer real implementations"))
    }

    @Test func validatorAcceptsParsedSkill() throws {
        let skill = try SkillsParser().parse(content: Self.skillMarkdown)
        #expect(SkillsValidator().validate(skill: skill))
    }

    @Test func parserFallsBackOnMissingTitle() throws {
        let skill = try SkillsParser().parse(content: "No title here.\nJust body text.\n")
        #expect(skill.name == "Unknown Skill")
    }
}
