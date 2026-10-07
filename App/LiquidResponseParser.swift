import Foundation

enum LiquidResponseParser {
    /// The assistant prompt already opened <think>. Ignore all output until its
    /// first closing tag, including any JSON examples inside reasoning.
    static func jsonAfterReasoning(_ output: String) -> String? {
        guard let reasoningEnd = output.range(of: "</think>") else { return nil }
        return balancedObject(in: output[reasoningEnd.upperBound...])
    }

    static func jsonAnswer(_ output: String, expectsReasoning: Bool = false) -> String? {
        if expectsReasoning { return jsonAfterReasoning(output) }
        if let opening = output.range(of: "<think>") {
            guard let closing = output.range(of: "</think>", range: opening.upperBound..<output.endIndex) else { return nil }
            return balancedObject(in: output[closing.upperBound...])
        }
        // Also tolerate a closing marker when the opening tag was in the prompt.
        if let closing = output.range(of: "</think>") { return balancedObject(in: output[closing.upperBound...]) }
        return balancedObject(in: output[...])
    }

    private static func balancedObject(in answer: Substring) -> String? {
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaped = false
        for index in answer.indices {
            let character = answer[index]
            if start == nil {
                guard character == "{" else { continue }
                start = index
                depth = 1
                continue
            }
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true }
            else if character == "{" { depth += 1 }
            else if character == "}" {
                depth -= 1
                if depth == 0, let beginning = start {
                    let candidate = String(answer[beginning...index])
                    if let value = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)),
                       value is [String: Any] { return candidate }
                    // Skip balanced non-JSON prose and look for the actual answer.
                    start = nil
                    inString = false
                    escaped = false
                }
            }
        }
        return nil
    }
}
