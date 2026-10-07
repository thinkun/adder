import Foundation
import Contacts
import EventKit

/// An interpreted proposal. Nothing is written until the user presses Save.
struct ActionDraft: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: String
    var givenName: String?
    var familyName: String?
    var phone: String?
    var phoneCountry: String?
    var email: String?
    var meetingContext: String?
    var title: String?
    var body: String?
    var summary: String?
    var urls: [String]?
    var personName: String?
    var location: String?
    /// Local wall-clock date: yyyy-MM-dd'T'HH:mm. Resolve relative dates at interpretation time.
    var startLocal: String?
    var timeZone: String?
    var durationMinutes: Int?
    var reminderTitle: String?
    var reminderDaysBefore: Int?
    var questions: [String] = []

    init(kind: String, givenName: String? = nil, familyName: String? = nil,
         phone: String? = nil, phoneCountry: String? = nil, email: String? = nil,
         meetingContext: String? = nil, title: String? = nil, personName: String? = nil,
         location: String? = nil, startLocal: String? = nil, timeZone: String? = nil,
         durationMinutes: Int? = nil, reminderTitle: String? = nil,
         reminderDaysBefore: Int? = nil, questions: [String] = [],
         body: String? = nil, summary: String? = nil, urls: [String]? = nil) {
        self.kind = kind; self.givenName = givenName; self.familyName = familyName
        self.phone = phone; self.phoneCountry = phoneCountry; self.email = email
        self.meetingContext = meetingContext; self.title = title; self.personName = personName
        self.location = location; self.startLocal = startLocal; self.timeZone = timeZone
        self.durationMinutes = durationMinutes; self.reminderTitle = reminderTitle
        self.reminderDaysBefore = reminderDaysBefore; self.questions = questions
        self.body = body; self.summary = summary; self.urls = urls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        givenName = try c.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        phoneCountry = try c.decodeIfPresent(String.self, forKey: .phoneCountry)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        meetingContext = try c.decodeIfPresent(String.self, forKey: .meetingContext)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        urls = try c.decodeIfPresent([String].self, forKey: .urls)
        personName = try c.decodeIfPresent(String.self, forKey: .personName)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        startLocal = try c.decodeIfPresent(String.self, forKey: .startLocal)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        reminderTitle = try c.decodeIfPresent(String.self, forKey: .reminderTitle)
        reminderDaysBefore = try c.decodeIfPresent(Int.self, forKey: .reminderDaysBefore)
        questions = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case kind, givenName, familyName, phone, phoneCountry, email, meetingContext
        case title, personName, location, startLocal, timeZone, durationMinutes
        case reminderTitle, reminderDaysBefore, questions, body, summary, urls
    }

    var displayName: String {
        [givenName, familyName].compactMap { $0 }.joined(separator: " ")
    }

    var normalizedPhone: String? {
        guard let phone, !phone.isEmpty else { return nil }
        let digits = phone.filter { $0.isNumber }
        if phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return "+" + digits }
        if ["au", "australia", "+61", "61"].contains(phoneCountry?.lowercased() ?? ""), digits.hasPrefix("0") {
            return "+61" + digits.dropFirst()
        }
        return digits
    }

    func eventDate() throws -> Date {
        guard let startLocal, let zoneName = timeZone, let zone = TimeZone(identifier: zoneName) else {
            throw PhoneActionError.invalid("Choose an event date, time, and timezone.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.isLenient = false
        guard let date = formatter.date(from: startLocal), formatter.string(from: date) == startLocal else {
            throw PhoneActionError.invalid("The event date or time is invalid.")
        }
        return date
    }
}

struct SavedPerson: Codable, Identifiable {
    var id: String
    var name: String
    var phone: String?
    var email: String?
    var notes: String
}

struct SaveOutcome {
    var message: String
    var contactIdentifier: String?
    var eventIdentifier: String?
    var reminderIdentifier: String?
}

enum PhoneActionError: LocalizedError {
    case invalid(String)
    case denied(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .denied(let message): return message
        }
    }
}

@MainActor
final class PhoneActions {
    private let contacts = CNContactStore()
    private let events = EKEventStore()
    private let historyKey = "recentSavedPeople.v1"
    private(set) var recentPeople: [SavedPerson] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let people = try? JSONDecoder().decode([SavedPerson].self, from: data) {
            recentPeople = people
        }
    }

    /// Supply this context to Liquid so a subsequent request can refer to Jack Black.
    var recentContactContext: String {
        recentPeople.prefix(10).map { "\($0.name); phone: \($0.phone ?? ""); email: \($0.email ?? "")" }
            .joined(separator: "\n")
    }

    func save(_ draft: ActionDraft, photoData: Data? = nil, captureContext: String? = nil) async throws -> SaveOutcome {
        if !draft.questions.isEmpty {
            throw PhoneActionError.invalid(draft.questions.joined(separator: "\n"))
        }
        let context = captureContext ?? "Captured: \(ISO8601DateFormatter().string(from: Date())) (\(TimeZone.current.identifier)). Location unavailable."
        switch draft.kind.lowercased() {
        case "contact": return try await saveContact(draft, photoData: photoData, captureContext: context)
        case "event", "calendar": return try await saveEvent(draft, captureContext: context)
        case "note", "bookmark": throw PhoneActionError.invalid("Save this item to the app's local library or share it to Notes.")
        default: throw PhoneActionError.invalid("Choose a contact or calendar event to save.")
        }
    }

    private func saveContact(_ draft: ActionDraft, photoData: Data?, captureContext: String?) async throws -> SaveOutcome {
        guard !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PhoneActionError.invalid("Add the person's name first.")
        }
        guard try await contacts.requestAccess(for: .contacts) else {
            throw PhoneActionError.denied("Allow Contacts access in Settings to save this person.")
        }
        let contact = CNMutableContact()
        contact.givenName = draft.givenName ?? ""
        contact.familyName = draft.familyName ?? ""
        contact.imageData = photoData
        if let phone = draft.normalizedPhone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        if let email = draft.email, !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        let stamp = DateFormatter()
        stamp.dateStyle = .long
        stamp.timeStyle = .short
        let notes = [draft.meetingContext ?? "", captureContext ?? "", "Saved: \(stamp.string(from: Date())) (\(TimeZone.current.identifier))"]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Apple's notes entitlement governs fetching CNContactNoteKey. We never fetch it.
        contact.note = notes
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try contacts.execute(request)
        let person = SavedPerson(id: contact.identifier, name: draft.displayName, phone: draft.normalizedPhone, email: draft.email, notes: notes)
        recentPeople.insert(person, at: 0)
        recentPeople = Array(recentPeople.prefix(30))
        if let data = try? JSONEncoder().encode(recentPeople) { UserDefaults.standard.set(data, forKey: historyKey) }
        return SaveOutcome(message: "Saved \(draft.displayName) to Contacts with meeting context.", contactIdentifier: contact.identifier)
    }

    private func saveEvent(_ draft: ActionDraft, captureContext: String?) async throws -> SaveOutcome {
        let start = try draft.eventDate()
        guard let duration = draft.durationMinutes, duration > 0, duration <= 24 * 60 else {
            throw PhoneActionError.invalid("Choose the meeting duration before saving.")
        }
        guard let title = draft.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PhoneActionError.invalid("Add an event title first.")
        }
        guard try await events.requestWriteOnlyAccessToEvents() else {
            throw PhoneActionError.denied("Allow Calendar access in Settings to save this event.")
        }
        var reminder: EKReminder?
        if let reminderTitle = draft.reminderTitle, !reminderTitle.isEmpty {
            guard let days = draft.reminderDaysBefore, days >= 0, days <= 365 else {
                throw PhoneActionError.invalid("Choose when to remind you before the meeting.")
            }
            guard try await events.requestFullAccessToReminders() else {
                throw PhoneActionError.denied("Allow Reminders access in Settings to save the preparation reminder.")
            }
            guard let reminderCalendar = events.defaultCalendarForNewReminders() else {
                throw PhoneActionError.invalid("Create a Reminders list on this phone first.")
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: draft.timeZone ?? "") ?? .current
            guard let due = calendar.date(byAdding: .day, value: -days, to: start) else {
                throw PhoneActionError.invalid("Unable to calculate the reminder date.")
            }
            let item = EKReminder(eventStore: events)
            item.title = reminderTitle
            item.notes = ["Prepare for: \(title)", draft.location, draft.meetingContext, captureContext]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            item.calendar = reminderCalendar
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            item.startDateComponents = components
            item.dueDateComponents = components
            item.addAlarm(EKAlarm(absoluteDate: due))
            reminder = item
        }
        guard let eventCalendar = events.defaultCalendarForNewEvents else {
            throw PhoneActionError.invalid("Set up a Calendar account on this phone first.")
        }
        let event = EKEvent(eventStore: events)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(duration * 60))
        event.timeZone = TimeZone(identifier: draft.timeZone ?? "")
        event.location = draft.location
        event.calendar = eventCalendar
        if let name = draft.personName {
            let person = recentPeople.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            event.notes = ["Meeting with \(name)", person?.phone, person?.email].compactMap { $0 }.joined(separator: "\n")
        }
        event.notes = [event.notes, draft.meetingContext, captureContext]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        do {
            try events.save(event, span: .thisEvent, commit: false)
            if let reminder { try events.save(reminder, commit: false) }
        } catch {
            events.reset()
            throw error
        }
        do {
            try events.commit()
        } catch {
            events.reset()
            // A failed cross-store commit must never trigger an automatic retry.
            throw PhoneActionError.invalid("Could not confirm the save. Check Calendar and Reminders before retrying to avoid duplicates. \(error.localizedDescription)")
        }
        return SaveOutcome(message: reminder == nil ? "Saved event to Calendar." : "Saved event to Calendar and preparation task to Reminders.", eventIdentifier: event.eventIdentifier, reminderIdentifier: reminder?.calendarItemIdentifier)
    }
}
