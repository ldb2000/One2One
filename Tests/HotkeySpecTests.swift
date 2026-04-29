import Testing
import Foundation
@testable import OneToOne

@Suite("HotkeySpec encode/decode")
struct HotkeySpecTests {

    @Test("Round-trip ⌃⌥⌘A")
    func roundTripCmdOptCtrlA() throws {
        let spec = HotkeySpec(modifiers: [.command, .option, .control], keyChar: "A")
        let str = spec.serialized
        #expect(str == "⌃⌥⌘A")

        let parsed = try #require(HotkeySpec(serialized: str))
        #expect(parsed.modifiers == [.command, .option, .control])
        #expect(parsed.keyChar == "A")
    }

    @Test("Modifier order is canonical (⌃⌥⇧⌘ regardless of input order)")
    func canonicalModifierOrder() {
        let s1 = HotkeySpec(modifiers: [.command, .control, .shift, .option], keyChar: "K").serialized
        let s2 = HotkeySpec(modifiers: [.shift, .option, .command, .control], keyChar: "K").serialized
        #expect(s1 == s2)
        #expect(s1 == "⌃⌥⇧⌘K")
    }

    @Test("Function key F1")
    func functionKey() throws {
        let spec = HotkeySpec(modifiers: [.command], keyChar: "F1")
        #expect(spec.serialized == "⌘F1")
        let parsed = try #require(HotkeySpec(serialized: "⌘F1"))
        #expect(parsed.keyChar == "F1")
    }

    @Test("Empty / malformed string fails to parse")
    func malformedRejected() {
        #expect(HotkeySpec(serialized: "") == nil)
        #expect(HotkeySpec(serialized: "ABC") == nil)  // pas de modifier
    }
}
