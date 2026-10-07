import Foundation

/// Pure field/date checks. No PhoneActions instance or Apple stores are created.
@main
struct ExtractionChecks {
    static func main() throws {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-10-07T01:00:00Z")! // Oct 6, 6pm in San Francisco.

        let json = #"{"kind":"contact","givenName":"Jack","familyName":"Black","phone":"0411234759","phoneCountry":"Australia","email":"wrong@gmail.com"}"#
        let draft = try JSONDecoder().decode(ActionDraft.self, from: Data(json.utf8))
        precondition(draft.questions.isEmpty, "Missing questions should decode to an empty array")
        precondition(draft.normalizedPhone == "+61411234759", "AU national phone should use +61 and drop leading zero")
        precondition(ActionDraft(kind: "contact", phone: "+61 411 234 759").normalizedPhone == "+61411234759")
        precondition(ActionDraft(kind: "contact", phone: "0411234759").normalizedPhone == "0411234759", "Unknown country must not be guessed")

        precondition(explicitlySpelledEmail(in: "j-a-c-k-g-r-e-y at gmail.com") == "jackgrey@gmail.com")
        precondition(explicitlySpelledEmail(in: "J A C K G R E Y at gmail dot com") == "jackgrey@gmail.com")
        precondition(explicitlySpelledEmail(in: "j–a–c–k at icloud dot com") == "jack@icloud.com")
        precondition(explicitlySpelledEmail(in: "Jack Grey at gmail.com") == nil, "Ordinary words are not explicit spelling")
        precondition(explicitlySpelledEmail(in: "j-a-c-k at gmail.com; correction j-i-l-l at gmail.com") == "jill@gmail.com", "Last explicit correction wins")
        let corrected = enforce(draft, transcript: "I met him today at the Liquid event in SF. His email is j-a-c-k-g-r-e-y at gmail.com", now: now, timeZone: zone)
        precondition(corrected.email == "jackgrey@gmail.com")
        precondition(corrected.displayName == "Jack Black", "Spelling an email must not change the person's name")
        precondition(corrected.meetingContext?.contains("October 6, 2026") == true)
        precondition(corrected.meetingContext?.contains("18:00") != true, "Meeting date does not imply an exact meeting time")

        let original = ActionDraft(kind: "event", startLocal: "2026-10-07T15:00")
        let event = enforce(original, transcript: "Catch up with Jack next Wednesday at 3pm", now: now, timeZone: zone)
        precondition(event.startLocal == "2026-10-14T15:00")
        precondition(event.timeZone == zone.identifier)
        let eventDate = try event.eventDate()
        precondition(iso.string(from: eventDate) == "2026-10-14T22:00:00Z")
        let ambiguous = enforce(original, transcript: "Maybe next Wednesday or next Thursday", now: now, timeZone: zone)
        precondition(ambiguous.startLocal == original.startLocal, "Multiple weekday choices must not silently select one")

        let sample = "I'll make a catch up with Jack Black next Wednesday at 3:00 PM at Hexwizard Cafe. And remind me the day before to prepare for the meeting."
        let routed = enforce(ActionDraft(kind: "note", title: "Catch up with Jack Black", body: sample), transcript: sample, now: now, timeZone: zone)
        precondition(routed.kind == "event", "Explicit calendar request must override model note routing")
        precondition(routed.startLocal == "2026-10-14T15:00")
        precondition(routed.personName == "Jack Black")
        precondition(routed.location == "Hexwizard Cafe")
        precondition(routed.timeZone == zone.identifier)
        precondition(routed.reminderDaysBefore == 1)
        precondition(routed.reminderTitle == "Prepare for meeting with Jack Black")
        precondition(routed.durationMinutes == nil, "Meeting duration must remain a user choice")
        let past = enforce(draft, transcript: "I met Jack Black at the Liquid event today in San Francisco", now: now, timeZone: zone)
        precondition(past.kind == "contact", "Past contact context is not a calendar request")
        precondition(enforce(draft, transcript: "Add Jack Black as a contact. I met him at a meeting today.", now: now, timeZone: zone).kind == "contact")
        precondition(enforce(draft, transcript: "I met Jack today, author of a book", now: now, timeZone: zone).kind == "contact", "Book as a noun is not a scheduling command")
        let explicitNote = enforce(ActionDraft(kind: "note"), transcript: "Write a note about the meeting with Jack Black next Wednesday at 3pm", now: now, timeZone: zone)
        precondition(explicitNote.kind == "note", "Explicit note request must not become an event")
        let staleContact = ActionDraft(kind: "contact", givenName: "Jack", familyName: "Black", phone: "0411234759", phoneCountry: "Australia", email: "jackgrey@gmail.com", meetingContext: "Met Jack today", title: "Jack Black", personName: "Jack", location: "Cafe", startLocal: "2026-10-14T15:00", timeZone: zone.identifier, durationMinutes: 30, reminderTitle: "Prepare", reminderDaysBefore: 1, body: "Jack's old context", summary: "Jack Black")
        let imageNote = enforce(staleContact, transcript: "Extract the text from this image and add it as a new note in Notes", now: now, timeZone: zone)
        precondition(imageNote.kind == "note")
        precondition(imageNote.givenName == nil && imageNote.familyName == nil && imageNote.phone == nil && imageNote.email == nil)
        precondition(imageNote.meetingContext == nil && imageNote.personName == nil && imageNote.location == nil)
        precondition(imageNote.startLocal == nil && imageNote.timeZone == nil && imageNote.durationMinutes == nil)
        precondition(imageNote.reminderTitle == nil && imageNote.reminderDaysBefore == nil)
        precondition(imageNote.body == nil && imageNote.summary == nil && imageNote.title == "New note", "Stale model contact content must not populate the new note")
        precondition(enforce(draft, transcript: "Met Jack today while taking notes", now: now, timeZone: zone).kind == "contact")
        let tomorrow = enforce(ActionDraft(kind: "note"), transcript: "Schedule a meeting with Jack tomorrow at 12am", now: now, timeZone: zone)
        precondition(tomorrow.kind == "event" && tomorrow.startLocal == "2026-10-07T00:00")
        let noTime = enforce(ActionDraft(kind: "note"), transcript: "Schedule a meeting with Jack tomorrow", now: now, timeZone: zone)
        precondition(noTime.kind == "event" && noTime.startLocal == nil && !noTime.questions.isEmpty)
        precondition(enforce(ActionDraft(kind: "CALENDAR"), transcript: "", now: now, timeZone: zone).kind == "event")
        let physicalSummary = "Meet Jack tomorrow at 3pm at the illegal cafe on Main Street."
        let physicalBody = "remind you to prepare for tomorrow at 3pm to meet Jack."
        let physicalNote = ActionDraft(kind: "note", title: "Meeting reminder", body: physicalBody, summary: physicalSummary)
        let physicalRouted = enforce(physicalNote, transcript: physicalSummary, now: now, timeZone: zone)
        precondition(physicalRouted.kind == "event" && physicalRouted.startLocal == "2026-10-07T15:00")
        precondition(physicalRouted.personName == "Jack")
        precondition(physicalRouted.title == "Catch up with Jack")
        precondition(physicalRouted.location == "the illegal cafe on Main Street", "Preserve the user's spoken place rather than correcting its name")
        let repeated = enforce(physicalNote, transcript: physicalSummary + " " + physicalBody, now: now, timeZone: zone)
        precondition(repeated.kind == "event" && repeated.startLocal == "2026-10-07T15:00", "Repeated identical date/time evidence is not ambiguity")
        let differentTimes = enforce(ActionDraft(kind: "note"), transcript: "Schedule a meeting tomorrow at 3pm or 4pm", now: now, timeZone: zone)
        precondition(differentTimes.startLocal == nil && !differentTimes.questions.isEmpty)
        let differentDays = enforce(ActionDraft(kind: "note"), transcript: "Schedule a meeting today or tomorrow at 3pm", now: now, timeZone: zone)
        precondition(differentDays.startLocal == nil && !differentDays.questions.isEmpty)

        let beforeDST = iso.date(from: "2026-10-27T01:00:00Z")! // Monday, Oct 26, PDT.
        let afterDST = enforce(original, transcript: "next Sunday at 3pm", now: beforeDST, timeZone: zone)
        precondition(afterDST.startLocal == "2026-11-08T15:00", "Next weekday uses the following Monday-based week")
        let afterDSTDate = try afterDST.eventDate()
        precondition(iso.string(from: afterDSTDate) == "2026-11-08T23:00:00Z", "DST must preserve local meeting hour")

        for invalid in ["2026-02-30T15:00", "2026-03-08T02:30"] {
            var bad = event
            bad.startLocal = invalid
            var rejected = false
            do { _ = try bad.eventDate() } catch { rejected = true }
            precondition(rejected, "Invalid dates and nonexistent DST times must be rejected")
        }
        print("Passed: decoding, phone normalization, spelled email precedence, date context, relative weekdays, DST, invalid dates. No stores touched.")
    }
}
