import Foundation

/// Deterministic corrections applied after Liquid proposes fields, before user review.
func enforce(_ draft: ActionDraft, transcript: String, now: Date, timeZone: TimeZone) -> ActionDraft {
    var result = draft
    switch result.kind.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
    case "calendar", "calendar_event", "calendar event", "events": result.kind = "event"
    case "contacts", "person": result.kind = "contact"
    default: result.kind = result.kind.lowercased()
    }
    if let email = explicitlySpelledEmail(in: transcript) { result.email = email }

    let noteRequested = firstRuleMatch(#"\b(write|save|make|create|add)\s+(?:me\s+)?(?:(?:it|this|that)\s+(?:as\s+)?)?(?:(?:a|an)\s+)?(?:new\s+)?note\b|\b(send|put|add|save)\s+(?:it|this|that|the\s+text)\s+(?:to|in)\s+(?:the\s+)?(?:apple\s+)?notes\b|\b(extract|read|transcribe|copy)\s+(?:the\s+|all\s+)?text\b.{0,60}\b(image|photo|picture)\b"#, in: transcript) != nil
    if noteRequested {
        let wasOtherKind = result.kind != "note"
        result.kind = "note"
        result.givenName = nil; result.familyName = nil; result.phone = nil
        result.phoneCountry = nil; result.email = nil; result.meetingContext = nil
        result.personName = nil; result.location = nil; result.startLocal = nil
        result.timeZone = nil; result.durationMinutes = nil
        result.reminderTitle = nil; result.reminderDaysBefore = nil
        if wasOtherKind {
            result.title = "New note"
            result.body = nil; result.summary = nil; result.urls = nil
            result.questions = []
        }
    }
    let schedulingCommand = firstRuleMatch(#"\b(schedule|arrange)\b|\bbook\s+(?:(?:a|an|the|new)\s+)?(?:meeting|appointment|slot|catch[ -]?up)\b|\b(create|add|make)\s+(?:(?:a|an|the|new)\s+)?(?:calendar\s+event|appointment|catch[ -]?up|meeting)\b"#, in: transcript) != nil
    let meetingWords = firstRuleMatch(#"\b(catch[ -]?up|meeting|appointment|meet)\b"#, in: transcript) != nil
    let relativeDate = firstRuleMatch(#"\b(next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)|tomorrow|today)\b"#, in: transcript) != nil
    let pastMeeting = firstRuleMatch(#"\b(met|had|attended|went)\b"#, in: transcript) != nil
    let clock = explicitClock(in: transcript)
    let eventIntent = !noteRequested && (schedulingCommand || (meetingWords && relativeDate && clock != nil && !pastMeeting))
    if eventIntent {
        let wasNote = ["note", "bookmark"].contains(result.kind)
        result.kind = "event"
        if result.personName == nil,
           let match = firstRuleMatch(#"\bwith\s+([\p{L}][\p{L} '\-]*?)(?=\s+(?:next|tomorrow|today|on|at)\b|[,.]|$)"#, in: transcript),
           let range = Range(match.range(at: 1), in: transcript) {
            result.personName = String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.personName == nil,
           let match = firstRuleMatch(#"\bmeet\s+([\p{L}][\p{L} '\-]*?)(?=\s+(?:next|tomorrow|today|on|at)\b|[,.]|$)"#, in: transcript),
           let range = Range(match.range(at: 1), in: transcript) {
            result.personName = String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.location == nil,
           let match = firstRuleMatch(#"\bat\s+([\p{L}][\p{L}\d '\-]*?)(?=\s+and\s+remind\b|[,.]|$)"#, in: transcript),
           let range = Range(match.range(at: 1), in: transcript) {
            result.location = String(transcript[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if wasNote || result.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            result.title = "Catch up" + (result.personName.map { " with " + $0 } ?? "")
        }
        if result.timeZone == nil { result.timeZone = timeZone.identifier }
        if firstRuleMatch(#"\bremind\s+me\b.*\b(?:day\s+before|one\s+day\s+before)\b"#, in: transcript) != nil {
            result.reminderDaysBefore = 1
            result.reminderTitle = "Prepare for meeting" + (result.personName.map { " with " + $0 } ?? "")
        }
    }

    let weekdayMatches = (try? NSRegularExpression(pattern: #"\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: .caseInsensitive))?
        .matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) ?? []
    if !noteRequested, weekdayMatches.count == 1, let match = weekdayMatches.first,
       let weekdayRange = Range(match.range(at: 1), in: transcript),
       let time = clock ?? validClockSuffix(result.startLocal) {
        let weekdayName = String(transcript[weekdayRange]).lowercased()
        let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        if let index = weekdays.firstIndex(of: weekdayName),
           let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
           let date = calendar.date(byAdding: .day, value: 7 + index, to: thisWeek) {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.calendar = calendar
            format.timeZone = timeZone
            format.dateFormat = "yyyy-MM-dd"
            result.startLocal = format.string(from: date) + "T" + time
            result.timeZone = timeZone.identifier
        }
    }

    if eventIntent && weekdayMatches.isEmpty, let clock {
        let dayMatches = (try? NSRegularExpression(pattern: #"\b(today|tomorrow)\b"#, options: .caseInsensitive))?
            .matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) ?? []
        let uniqueDays = Set(dayMatches.compactMap { Range($0.range(at: 1), in: transcript).map { transcript[$0].lowercased() } })
        if uniqueDays.count == 1, let match = dayMatches.first, let range = Range(match.range(at: 1), in: transcript) {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let offset = transcript[range].lowercased() == "tomorrow" ? 1 : 0
            if let date = calendar.date(byAdding: .day, value: offset, to: now) {
                let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
                format.timeZone = timeZone; format.dateFormat = "yyyy-MM-dd"
                result.startLocal = format.string(from: date) + "T" + clock
                result.timeZone = timeZone.identifier
            }
        }
    }
    let temporalChoices = (try? NSRegularExpression(pattern: #"\b(today|tomorrow|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#, options: .caseInsensitive))?
        .matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) ?? []
    let uniqueTemporalChoices = Set(temporalChoices.compactMap { Range($0.range, in: transcript).map { transcript[$0].lowercased() } })
    if eventIntent && (uniqueTemporalChoices.count > 1 || explicitClocks(in: transcript).count > 1) {
        result.startLocal = nil
    }
    if eventIntent, result.startLocal == nil {
        var questions = result.questions
        let question = "What date and time should this meeting start?"
        if !questions.contains(question) { questions.append(question) }
        result.questions = questions
    }

    if result.kind == "contact",
       firstRuleMatch(#"\btoday\b"#, in: transcript) != nil,
       firstRuleMatch(#"\b(met|meeting|meet|event)\b"#, in: transcript) != nil {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "MMMM d, yyyy"
        let date = format.string(from: now)
        var context = result.meetingContext ?? ""
        context = context.replacingOccurrences(of: #"\btoday\b"#, with: date, options: [.regularExpression, .caseInsensitive])
        let dateLine = "Meeting date: \(date) (\(timeZone.identifier))."
        if !context.contains(dateLine) { context = [context, dateLine].filter { !$0.isEmpty }.joined(separator: "\n") }
        result.meetingContext = context
    }
    return result
}

private func validClockSuffix(_ value: String?) -> String? {
    guard let value, value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
    return String(value.suffix(5))
}

private func explicitClock(in input: String) -> String? {
    let clocks = explicitClocks(in: input)
    return clocks.count == 1 ? clocks.first : nil
}

private func explicitClocks(in input: String) -> Set<String> {
    guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(1[0-2]|[1-9])(?::([0-5]\d))?\s*([ap])\.?m\.?\b"#, options: .caseInsensitive) else { return [] }
    let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
    let clocks = Set(matches.compactMap { match -> String? in
        guard let hourRange = Range(match.range(at: 1), in: input),
              let periodRange = Range(match.range(at: 3), in: input), let hour = Int(input[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: input).flatMap { Int(input[$0]) } ?? 0
        let normalized = hour % 12 + (input[periodRange].lowercased() == "p" ? 12 : 0)
        return String(format: "%02d:%02d", normalized, minute)
    })
    return clocks
}

/// Requires at least three separately spoken letters; never treats ordinary words as spelling.
func explicitlySpelledEmail(in transcript: String) -> String? {
    let separator = #"(?:\s*[-–—]\s*|\s+)"#
    let letters = #"([a-z](?:"# + separator + #"[a-z]){2,})"#
    let domain = #"([a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\s*(?:\.|\bdot\b)\s*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+)"#
    let pattern = #"(?<![a-z0-9])"# + letters + #"\s*(?:\bat\b|@)\s*"# + domain + #"\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let matches = regex.matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript))
    // A later explicit spelling is a correction to an earlier one.
    guard let match = matches.last,
          let lettersRange = Range(match.range(at: 1), in: transcript),
          let domainRange = Range(match.range(at: 2), in: transcript) else { return nil }
    let local = transcript[lettersRange].lowercased().filter { $0.isLetter }
    let host = transcript[domainRange].lowercased()
        .replacingOccurrences(of: #"\s*\bdot\b\s*"#, with: ".", options: .regularExpression)
        .filter { !$0.isWhitespace }
    return local + "@" + host
}

private func firstRuleMatch(_ pattern: String, in input: String) -> NSTextCheckingResult? {
    (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
        .firstMatch(in: input, range: NSRange(input.startIndex..., in: input))
}
