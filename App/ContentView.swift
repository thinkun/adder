import SwiftUI
import PhotosUI

struct CaptureRecord: Identifiable, Codable {
    var id = UUID()
    var title: String
    var detail: String
    var date = Date()
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showsSettings = false
    @State private var showsDemo = false
    @State private var showsReview = false
    @State private var showsNotesShare = false
    @State private var notesShareSnapshot = ""
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsError = false
    @FocusState private var transcriptFocused: Bool
    @FocusState private var reviewFocused: Bool

    private let ink = Color(red: 0.10, green: 0.17, blue: 0.19)
    private let accent = Color(red: 0.87, green: 0.32, blue: 0.16)
    private let canvas = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    captureCard
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                statusCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .background(canvas)
            }
            .background(canvas.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsDemo = true } label: { Image(systemName: "qrcode.viewfinder") }
                        .accessibilityLabel("Presentation screen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Model settings")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { transcriptFocused = false; reviewFocused = false }
                }
            }
            .sheet(isPresented: $showsSettings) { settingsSheet }
            .fullScreenCover(isPresented: $showsDemo) { DemoView() }
            .sheet(isPresented: $showsReview) {
                NavigationStack {
                    ScrollView { reviewCard.padding(16) }
                        .scrollDismissesKeyboard(.interactively)
                        .background(canvas.ignoresSafeArea())
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { Button("Done") { showsReview = false } }
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { reviewFocused = false }
                            }
                        }
                }
                .tint(accent)
                .foregroundStyle(ink)
                .preferredColorScheme(.light)
                .sheet(isPresented: $showsNotesShare) {
                    NotesShareSheet(text: notesShareSnapshot) { activityType, completed in
                        showsNotesShare = false
                        model.completeNoteShare(activityType: activityType, completed: completed)
                    }
                }
            }
            .onChange(of: model.draft?.id) { _, id in showsReview = id != nil }
            .task {
                if !model.apiKey.isEmpty && (!model.isModelReady || !model.isVoiceReady || !model.isVisionReady) { await model.loadModels() }
            }
            .task { await model.captureLocation() }
            .alert("Adder needs attention", isPresented: $showsError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.error ?? "Please check model setup and microphone access.")
            }
            .onChange(of: model.transcript) { _, _ in model.captureInputChanged() }
            .onChange(of: model.photoText) { _, _ in model.captureInputChanged() }
            .onChange(of: model.error) { _, error in
                if let error, !error.isEmpty { showsError = true }
            }
            .sheet(isPresented: $showsCamera) {
                CameraCapture(onCapture: { image in
                    showsCamera = false
                    Task { await model.addPhoto(image) }
                }, onCancel: { showsCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: pickedPhotos) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            await model.addPhoto(image)
                        }
                    }
                    pickedPhotos = []
                }
            }
        }
        .tint(accent)
    }

    private var header: some View {
        HStack {
            Text("Adder")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.7)
            Spacer()
            Button { model.clearCapture() } label: {
                Label("New capture", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }.disabled(!model.canEditInputs || model.isReadingPhotos)
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactBlock {
                HStack {
                    Label("Text", systemImage: "text.alignleft").font(.subheadline.bold())
                    Spacer()
                    Menu {
                        Button("Sample contact") {
                            insertSample("I have just emailed Jack Black. His number is 0411234759 in Australia. His email is Jack Gray, spelled j-a-c-k-g-r-e-y at gmail.com. I met him at the Liquid AI event today in San Francisco.")
                        }
                        Button("Sample event") {
                            insertSample("Make a catch up with Jack Black next Wednesday at 3:00 PM at Hexwizard Cafe. Remind me the day before to prepare for the meeting.")
                        }
                        if !model.transcript.isEmpty || !model.photos.isEmpty {
                            Button("Clear all", role: .destructive) { model.clearCapture() }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(!model.canEditInputs || model.isReadingPhotos)
                    .accessibilityLabel("Samples and clear capture")
                }
                ZStack(alignment: .topLeading) {
                    if model.transcript.isEmpty {
                        Text("Type here, or add images and audio below.")
                            .font(.callout).foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $model.transcript)
                        .font(.callout).frame(height: 82)
                        .scrollContentBackground(.hidden)
                        .focused($transcriptFocused)
                        .disabled(!model.canEditInputs)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            compactBlock { attachments }
            compactBlock {
                HStack(spacing: 12) {
                    Label("Audio", systemImage: "waveform").font(.subheadline.bold())
                    Spacer()
                    Button {
                        transcriptFocused = false
                        reviewFocused = false
                        if model.apiKey.isEmpty && !model.isRecording { showsSettings = true }
                        else {
                            Task {
                                if !model.isVoiceReady && !model.isRecording { await model.loadModels() }
                                if model.isVoiceReady || model.isRecording { await model.toggleRecording() }
                            }
                        }
                    } label: {
                        Label(model.isRecording ? "Stop" : "Record", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled((model.isBusy || model.isReadingPhotos) && !model.isRecording)
                }
                Text(model.isRecording ? "Tap Stop when finished · 30 seconds maximum" : (model.isVoiceReady ? "Local Whisper · transcript joins your text" : (model.isLoadingModels ? "Voice models loading…" : "Tap Record to set up local voice models")))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            captureContext
            Button {
                transcriptFocused = false
                reviewFocused = false
                if model.draft != nil { showsReview = true }
                else { Task { await model.interpret() } }
            } label: {
                Label(model.draft == nil ? "Preview" : "Review draft", systemImage: "arrow.right")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .disabled((model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.photos.isEmpty) || model.isBusy || model.isReadingPhotos || model.isRecording || !model.isModelReady)
        }
        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func compactBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.12), lineWidth: 1) }
    }

    private var statusIsActive: Bool { model.isBusy || model.isLoadingModels || model.isRecording || model.isReadingPhotos }

    private var activityTitle: String {
        if model.isRecording { return "Listening" }
        if model.isReadingPhotos { return "Reading your image" }
        if model.isBusy {
            let detail = model.status.lowercased()
            if detail.contains("transcrib") { return "Transcribing audio" }
            if detail.contains("vision") { return "Understanding your images" }
            if detail.contains("saving") { return "Adding your item" }
            return "Preparing your preview"
        }
        if model.isLoadingModels { return "Getting models ready" }
        if model.error != nil { return "Needs attention" }
        if model.draft != nil { return "Preview ready" }
        return model.isModelReady ? "Ready to capture" : "Preparing Adder"
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill((model.error != nil ? Color.red : accent).opacity(0.12))
                    if statusIsActive {
                        ProgressView().tint(accent)
                    } else {
                        Image(systemName: model.error != nil ? "exclamationmark.triangle.fill" : (model.draft != nil ? "doc.text.magnifyingglass" : "checkmark.circle.fill"))
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(model.error != nil ? Color.red : accent)
                    }
                }.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(activityTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text(model.status)
                        .font(.subheadline)
                        .foregroundStyle(ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !model.generationDetail.isEmpty {
                Text(model.generationDetail).font(.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.7))
            }
            if model.isLoadingModels && !model.isBusy && !model.isRecording {
                HStack(spacing: 6) {
                    ForEach(Array(["Text", "Audio", "Image"].enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption.weight(model.startupStage == index + 1 ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(model.startupStage == index + 1 ? accent.opacity(0.14) : canvas, in: Capsule())
                    }
                }
                if let progress = model.loadProgress, progress < 1 {
                    ProgressView(value: progress).tint(accent)
                        .accessibilityLabel("Model download progress")
                    Text("Downloading · \(Int(max(0, min(1, progress)) * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.7))
                } else {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small).tint(accent)
                        Text("Initializing local model…")
                            .font(.caption.weight(.medium))
                    }.foregroundStyle(ink.opacity(0.7))
                }
            }
            if model.error != nil {
                Button("View error details") { showsError = true }
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
            if !model.isModelReady || !model.isVoiceReady || !model.isVisionReady {
                Button {
                    if model.apiKey.isEmpty { showsSettings = true }
                    else { Task { await model.loadModels() } }
                } label: {
                    Label(model.apiKey.isEmpty ? "Set up local models" : "Retry model setup", systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                }.disabled(model.isBusy || model.isLoadingModels)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(statusIsActive ? 0.65 : 0.2), lineWidth: statusIsActive ? 2 : 1) }
        .accessibilityElement(children: .contain)
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label("Image", systemImage: "photo").font(.subheadline.bold())
                Spacer(minLength: 4)
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: max(1, 6 - model.photos.count), matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }.disabled(model.photos.count >= 6)
                if CameraCapture.isAvailable {
                    Button { showsCamera = true } label: { Image(systemName: "camera") }
                        .disabled(model.photos.count >= 6)
                        .accessibilityLabel("Take a photo")
                }
            }
            .font(.caption.weight(.semibold))
            .disabled(!model.canEditInputs || model.isReadingPhotos)
            if model.isReadingPhotos {
                Text("Reading photo text locally…").font(.caption2).foregroundStyle(.secondary)
            }
            if !model.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.photos.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 48, height: 48).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(alignment: .topTrailing) {
                                    Button { Task { await model.removePhoto(at: index) } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.7))
                                            .font(.system(size: 15))
                                    }
                                    .padding(2).disabled(!model.canEditInputs || model.isReadingPhotos)
                                    .accessibilityLabel("Remove photo \(index + 1)")
                                }
                        }
                    }
                }.frame(height: 48)
                DisclosureGroup("Photo details · \(model.photos.count)/6") {
                    Text("Liquid vision examines images at Preview. Local text recognition supplies supporting evidence. For a contact, the first photo becomes their picture.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: $model.photoText)
                        .frame(height: 120).font(.caption)
                        .scrollContentBackground(.hidden).focused($reviewFocused)
                        .disabled(!model.canEditInputs || model.isReadingPhotos)
                        .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8))
                }.font(.caption2)
            } else {
                Text("Attach photos or take one with the camera").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var captureContext: some View {
        DisclosureGroup("Location & capture context") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.locationStatus.isEmpty ? "Location has not been captured." : model.locationStatus)
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await model.captureLocation() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh capture location").disabled(!model.canEditInputs)
                }
                Text(model.captureContext).font(.caption).textSelection(.enabled)
            }
        }.font(.caption2)
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: draftIcon)
                    .foregroundStyle(accent)
                Text(draftTitle)
                    .font(.title3.bold())
                Spacer()
                Text(model.draft?.kind == "contact" ? "CONTACTS" : (model.draft?.kind == "note" ? "NOTES" : "CALENDAR")).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
            }
            if model.draft?.kind == "contact" {
                field("First name", path: \.givenName)
                field("Last name", path: \.familyName)
                field("Phone", path: \.phone, keyboard: .phonePad)
                field("Phone country", path: \.phoneCountry)
                if let phone = model.draft?.normalizedPhone {
                    Text("Saved phone: \(phone)").font(.caption).foregroundStyle(.secondary)
                }
                field("Email · explicit spelling wins", path: \.email, keyboard: .emailAddress)
                field("Meeting context", path: \.meetingContext, axis: .vertical)
                Text("The saved note includes the capture date, time, and timezone.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.draft?.kind == "note" {
                field("Title", path: \.title)
                field("Note", path: \.body, axis: .vertical)
                Text("Choose Notes in the share sheet and save as a new note.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.captureContext.isEmpty {
                    DisclosureGroup("Included capture context") {
                        Text(model.captureContext).font(.caption).textSelection(.enabled)
                    }.font(.caption)
                }
            } else {
                field("Event title", path: \.title)
                field("With", path: \.personName)
                field("Location", path: \.location)
                field("Starts · YYYY-MM-DDTHH:mm", path: \.startLocal)
                field("Timezone", path: \.timeZone)
                if let draft = model.draft, let date = try? draft.eventDate() {
                    Text("Meeting: \(formattedDate(date, zone: draft.timeZone))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                numberField("Duration in minutes", path: \.durationMinutes)
                HStack(spacing: 12) {
                    Text("Choose:").font(.caption).foregroundStyle(.secondary)
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes) min") { model.draft?.durationMinutes = minutes }
                            .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                    }
                }
                if model.draft?.durationMinutes == nil {
                    Text("Choose a duration to enable saving.")
                        .font(.caption).foregroundStyle(accent)
                }
                if model.draft?.reminderTitle != nil || model.draft?.reminderDaysBefore != nil {
                    Divider()
                    Label("Separate reminder", systemImage: "checklist").font(.subheadline.bold())
                    field("Reminder", path: \.reminderTitle)
                    numberField("Days before the event", path: \.reminderDaysBefore)
                    Text("The reminder is due at the meeting’s local time on that earlier day, with an alert.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let draft = model.draft, let date = try? draft.eventDate(), let days = draft.reminderDaysBefore {
                        let reminder = reminderDate(date, daysBefore: days, zone: draft.timeZone)
                        Text("Reminder: \(formattedDate(reminder, zone: draft.timeZone))")
                            .font(.caption.weight(.semibold)).foregroundStyle(accent)
                    }
                }
            }
            if let questions = model.draft?.questions, !questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Details to check", systemImage: "questionmark.circle").font(.subheadline.bold())
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                        Text(question).font(.caption)
                    }
                    Button("I’ve checked and corrected these details") { model.draft?.questions = [] }
                        .font(.caption.weight(.semibold))
                }
                .padding(12).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                transcriptFocused = false
                reviewFocused = false
                if model.draft?.kind == "note" {
                    notesShareSnapshot = model.noteShareText
                    showsNotesShare = true
                } else {
                    Task { await model.saveDraft() }
                }
            } label: {
                Label(saveTitle, systemImage: model.draft?.kind == "note" ? "square.and.arrow.up" : "plus")
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || !(model.draft?.questions.isEmpty ?? false) || ((model.draft?.kind == "event" || model.draft?.kind == "calendar") && (model.draft?.durationMinutes ?? 0) <= 0))
        }
        .foregroundStyle(ink)
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))
    }

    private var draftIcon: String {
        switch model.draft?.kind {
        case "contact": return "person.crop.rectangle"
        case "note": return "note.text"
        default: return "calendar"
        }
    }

    private var draftTitle: String {
        switch model.draft?.kind {
        case "contact": return "New contact"
        case "note": return "New note"
        default: return "New event"
        }
    }

    private var saveTitle: String {
        switch model.draft?.kind {
        case "contact": return "Add to Contacts"
        case "note": return "Share to Apple Notes"
        default: return model.draft?.reminderTitle == nil ? "Add to Calendar" : "Add to Calendar + Reminders"
        }
    }

    private func field(_ title: String, path: WritableKeyPath<ActionDraft, String?>, keyboard: UIKeyboardType = .default, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: Binding(get: { model.draft?[keyPath: path] ?? "" }, set: { model.draft?[keyPath: path] = $0.isEmpty ? nil : $0 }), axis: axis)
                .focused($reviewFocused)
                .foregroundStyle(ink)
                .font(.body).keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
                .padding(11).background(canvas, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func numberField(_ title: String, path: WritableKeyPath<ActionDraft, Int?>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("Enter a value", text: Binding(get: { model.draft?[keyPath: path].map(String.init) ?? "" }, set: { model.draft?[keyPath: path] = Int($0) }))
                .focused($reviewFocused)
                .keyboardType(.numberPad)
                .foregroundStyle(ink)
                .padding(11).background(canvas, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func formattedDate(_ date: Date, zone: String?) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date) + " · " + (zone ?? TimeZone.current.identifier)
    }

    private func insertSample(_ text: String) {
        model.transcript = text
        model.draft = nil
        model.error = nil
        transcriptFocused = false
    }

    private func reminderDate(_ date: Date, daysBefore: Int, zone: String?) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        return calendar.date(byAdding: .day, value: -daysBefore, to: date) ?? date
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Model access") {
                    Label(model.apiKey.isEmpty ? "Mac build setup required" : "Configured in this build", systemImage: model.apiKey.isEmpty ? "laptopcomputer" : "checkmark.circle")
                    Text(model.apiKey.isEmpty ? "On your Mac, run python3 scripts/configure-local-key.py, then rebuild and install Adder. No token entry is needed on the phone." : "Model access is included in this development build. Keep internet on for the first model download; interpretation and transcription run locally.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Models on this iPhone") {
                    Label("Liquid LFM2.5-1.2B-Instruct · action extraction", systemImage: "brain")
                    Label("Liquid VL-450M · photo understanding", systemImage: "photo")
                    Label("Whisper Tiny · speech to text", systemImage: "waveform")
                    Text("All models load at app startup. First downloads need internet; later launches reuse stored model files. Photos are analyzed one at a time; review all extracted details.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Load local models") {
                        showsSettings = false
                        Task { await model.loadModels() }
                    }
                    .disabled(model.apiKey.isEmpty || model.isBusy)
                }
            }
            .navigationTitle("Local models")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showsSettings = false } } }
        }
        .tint(accent)
    }
}
