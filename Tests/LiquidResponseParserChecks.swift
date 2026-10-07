import Foundation

@main struct LiquidResponseParserChecks {
    static func main() {
        let actual = #"{"kind":"contact","givenName":"Jack"}"#
        precondition(LiquidResponseParser.jsonAnswer(actual) == actual)
        precondition(LiquidResponseParser.jsonAnswer("```json\n" + actual + "\n```") == actual)
        precondition(LiquidResponseParser.jsonAnswer("<think>{\"ignored\":true}</think>" + actual) == actual)
        precondition(LiquidResponseParser.jsonAnswer("<think>unfinished {\"ignored\":true}") == nil)
        precondition(LiquidResponseParser.jsonAnswer(actual, expectsReasoning: true) == nil)
        precondition(LiquidResponseParser.jsonAfterReasoning("Considering {\"kind\":\"note\"}. </think>" + actual) == actual)
        precondition(LiquidResponseParser.jsonAfterReasoning("Reasoning {\"kind\":\"contact\"}") == nil, "Unfinished reasoning must never be interpreted as the answer")
        precondition(LiquidResponseParser.jsonAfterReasoning(actual) == nil, "Closing reasoning marker is required")
        precondition(LiquidResponseParser.jsonAfterReasoning("Done </think>\n```json\n" + actual + "\n```") == actual)
        let quoted = #"{"kind":"note","body":"Braces { and }; quote \" and slash \\","nested":{"x":1}}"#
        precondition(LiquidResponseParser.jsonAfterReasoning("</think>" + quoted) == quoted)
        precondition(LiquidResponseParser.jsonAfterReasoning("</think>{not JSON} then " + actual) == actual)
        precondition(LiquidResponseParser.jsonAfterReasoning("</think>{\"kind\":\"note\",\"body\":\"unfinished") == nil)
        let chunks = ["Reasoning {\"ignored\":true}", "</thi", "nk>\n```json\n", "{\"kind\":", "\"contact\",", "\"givenName\":\"Jack\"}", "\n```"]
        var accumulated = ""
        for (index, chunk) in chunks.enumerated() {
            accumulated += chunk
            let parsed = LiquidResponseParser.jsonAfterReasoning(accumulated)
            if index < 5 { precondition(parsed == nil, "Incomplete streamed JSON must not parse") }
            else { precondition(parsed == actual) }
        }
        print("Passed: reasoning JSON exclusion, required closing marker, markdown, quoted braces/escapes, invalid and unfinished JSON, accumulated split tokens.")
    }
}
