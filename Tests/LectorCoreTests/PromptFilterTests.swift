import Testing
@testable import LectorCore

private func joined(_ r: Result<PreparedPrompt, SkipReason>) -> String? {
    (try? r.get())?.chunks.joined(separator: "\n")
}

@Test func stripsFencedAndInlineCode() throws {
    let r = PromptFilter.prepare("Please refactor this function because it are too long.\n```swift\nlet x = 1\n```\nAlso rename `fooBar` please.")
    let text = try #require(joined(r))
    #expect(!text.contains("let x"))
    #expect(!text.contains("fooBar"))
    #expect(text.contains("it are too long"))
}

@Test func stripsPathsAndURLs() throws {
    let r = PromptFilter.prepare("Please look at /Users/me/x.swift and ~/a/b and src/app/main.ts and https://x.y/z because the test fails.")
    let text = try #require(joined(r))
    for gone in ["/Users/me", "~/a/b", "src/app/main.ts", "https://"] { #expect(!text.contains(gone)) }
    #expect(text.contains("Please look at"))
    #expect(text.contains("because the test fails"))
}

@Test func slashCommandSkipped() { #expect(PromptFilter.prepare("/grill-me") == .failure(.slashCommand)) }
@Test func shortSkipped() { #expect(PromptFilter.prepare("ok go") == .failure(.tooShort)) }
@Test func slovakSkipped() {
    #expect(PromptFilter.prepare("chcel by som vyrobit toolik ktory odchyti kazdy prompt od uzivatela") == .failure(.notEnglish))
}
@Test func englishWithSlovakNameAccepted() {
    #expect((try? PromptFilter.prepare("Please ask Lukáš whether the build is green today.").get()) != nil)
}

private let stackTrace = (1...20).map { "    at Foo.bar\($0) (file.js:\($0):3)" }.joined(separator: "\n")

@Test func logOnlySkipped() {
    #expect(PromptFilter.prepare("TypeError: x is undefined\n" + stackTrace) == .failure(.noProse))
}

@Test func dropsLogParagraphKeepsProse() throws {
    let prose = "The build started failing after I merged the branch, can you check why it happen?"
    let r = try PromptFilter.prepare(prose + "\n\n" + stackTrace).get()
    #expect(r.chunks == [prose])
    #expect(!r.truncated)
}

@Test func chunksAndTruncates() throws {
    let para = String(repeating: "This sentence is fine and short. ", count: 25)
    let r = try PromptFilter.prepare(Array(repeating: para, count: 5).joined(separator: "\n\n")).get()
    #expect(r.chunks.allSatisfy { $0.count <= 1000 })
    #expect(r.chunks.joined().count <= 3000)
    #expect(r.truncated)
}

@Test func splitsLongParagraphOnSentences() throws {
    let para = String(repeating: "This sentence is fine and short. ", count: 45) // ~1485 chars, one paragraph
    let r = try PromptFilter.prepare(para).get()
    #expect(r.chunks.count == 2)
    #expect(r.chunks.allSatisfy { $0.count <= 1000 })
    #expect(!r.truncated)
}

@Test func stripsPastedContent() throws {
    let r = PromptFilter.prepare("Can you summarize what this error mean for our deploy?\n\n<pasted_content id=\"7929\">\nWe are temporarily restricting new accounts because of abuse.\n</pasted_content>")
    let text = try #require(joined(r))
    #expect(!text.contains("temporarily restricting"))
    #expect(text.contains("what this error mean"))
}

@Test func onlyPastedContentIsTooShort() {
    #expect(PromptFilter.prepare("<pasted_content id=\"1\">\nSomebody else wrote this whole long sentence here.\n</pasted_content>") == .failure(.tooShort))
}

@Test func slovakWithTicketIdsSkipped() {
    let r = PromptFilter.prepare("mr235 mergnute, co bude s mr236?")
    #expect((try? r.get()) == nil)
}

@Test func shortSlovakSkipped() {
    #expect((try? PromptFilter.prepare("MD v repe").get()) == nil)
}

@Test(arguments: ["check pr review comments", "do the post-merge cleanup", "there are cr issues, check and fix them",
                  "is posible to use tdd in this project? and make it sense ?", "merged, watch and deploy it"])
func shortEnglishAccepted(_ s: String) {
    #expect((try? PromptFilter.prepare(s).get()) != nil)
}

@Test func textAfterRealPasteTagIsKept() throws {
    let r = PromptFilter.prepare("Can you look on this?\n\n<pasted_content id=\"7929\">\nWe are temporarily restricting new accounts because of abuse.\n</pasted_content id=\"7929\">\n\nI think it are broken and we needs a fix for it.")
    let text = try #require(joined(r))
    #expect(!text.contains("temporarily restricting"))
    #expect(text.contains("I think it are broken"))
}
