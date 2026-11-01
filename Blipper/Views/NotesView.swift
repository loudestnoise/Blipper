//
//  NotesView.swift
//  Blipper
//
//  Notes as in Tidepool Mobile: a list of notes, newest first. Tapping one opens its glucose,
//  insulin, and carb graph around the note's time; only one note is open at a time.
//

import SwiftUI

struct NotesView: View {
    let provider: any NoteProvider
    let glucoseProvider: any GlucoseDataProvider
    let therapyProvider: any TherapyDataProvider

    @State private var notes: [Note] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expanded: Note.ID?
    @State private var isComposing = Self.opensComposer

    init(
        provider: any NoteProvider = MockNoteProvider(),
        glucoseProvider: any GlucoseDataProvider = MockGlucoseProvider(),
        therapyProvider: any TherapyDataProvider = MockTherapyProvider()
    ) {
        self.provider = provider
        self.glucoseProvider = glucoseProvider
        self.therapyProvider = therapyProvider
    }

    /// `-openNewNote` starts with the new note form open (Debug builds only).
    private static var opensComposer: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openNewNote")
        #else
        false
        #endif
    }

    /// `-openFirstNote` opens the newest note's graph once notes load (Debug builds only).
    private static var opensFirstNote: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openFirstNote")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        isExpanded: expanded == note.id,
                        glucoseProvider: glucoseProvider,
                        therapyProvider: therapyProvider
                    ) {
                        withAnimation { expanded = expanded == note.id ? nil : note.id }
                    }
                }
            }
            .overlay {
                if notes.isEmpty {
                    if isLoading {
                        ProgressView()
                    } else if errorMessage == nil {
                        ContentUnavailableView(
                            "No Notes",
                            systemImage: "note.text",
                            description: Text("Tap + to note a meal, exercise, or anything else, and see it on your glucose graph.")
                        )
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isComposing = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New note")
                }
            }
            .sheet(isPresented: $isComposing) {
                NoteEditorView { text, timestamp in
                    try await add(text: text, timestamp: timestamp)
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await provider.notes()
            errorMessage = nil
            if Self.opensFirstNote, expanded == nil { expanded = notes.first?.id }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the note, then lists it and opens its graph.
    private func add(text: String, timestamp: Date) async throws {
        let note = try await provider.addNote(text: text, timestamp: timestamp)
        withAnimation {
            notes.append(note)
            notes.sort { $0.timestamp > $1.timestamp }
            expanded = note.id
        }
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: Note
    let isExpanded: Bool
    let glucoseProvider: any GlucoseDataProvider
    let therapyProvider: any TherapyDataProvider
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only the text toggles, so scrolling the graph never closes it.
            Button(action: onToggle) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the graph" : "Shows the graph around this note")

            if isExpanded {
                NoteGraphView(note: note, glucoseProvider: glucoseProvider, therapyProvider: therapyProvider)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let time = note.timestamp.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        guard let author = note.authorName else { return time }
        return "\(time) · \(author)"
    }
}

// MARK: - Graph

/// Glucose, insulin, and carbs around a note, scrollable back to `lookback` before it.
private struct NoteGraphView: View {
    static let lookback: TimeInterval = 7 * 3600
    static let lookahead: TimeInterval = 2 * 3600
    static let visibleLength: TimeInterval = 3 * 3600

    let note: Note
    let glucoseProvider: any GlucoseDataProvider
    let therapyProvider: any TherapyDataProvider
    private let span: DateInterval

    @State private var readings: [GlucoseReading] = []
    @State private var therapy: TherapyData = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scrollPosition: Date

    init(note: Note, glucoseProvider: any GlucoseDataProvider, therapyProvider: any TherapyDataProvider) {
        self.note = note
        self.glucoseProvider = glucoseProvider
        self.therapyProvider = therapyProvider
        let span = Self.span(around: note.timestamp)
        self.span = span
        // Open with the note about two-thirds across, so the lead-up shows and the graph scrolls back for more.
        let start = note.timestamp.addingTimeInterval(-Self.visibleLength * 2 / 3)
        let latestStart = span.end.addingTimeInterval(-Self.visibleLength)
        _scrollPosition = State(initialValue: min(max(start, span.start), latestStart))
    }

    /// From `lookback` before the note to `lookahead` after it, stopping at now
    /// but leaving a little room after a note made just now.
    private static func span(around time: Date) -> DateInterval {
        let end = max(min(time.addingTimeInterval(lookahead), Date()), time.addingTimeInterval(30 * 60))
        return DateInterval(start: time.addingTimeInterval(-lookback), end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                let scroll = ChartScroll(visibleLength: Self.visibleLength, position: $scrollPosition)
                GlucoseChartView(
                    readings: readings,
                    fingersticks: therapy.fingersticks,
                    interval: span,
                    selectedReading: nil,
                    selectedTime: .constant(nil),
                    marker: note.timestamp,
                    scroll: scroll,
                    height: 200
                )
                TherapyChartView(
                    therapy: therapy,
                    interval: span,
                    selectedTime: .constant(nil),
                    marker: note.timestamp,
                    scroll: scroll
                )
                Text("Swipe the graph to see up to \(Int(Self.lookback / 3600)) hours before the note.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: note.id) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let glucose = glucoseProvider.readings(in: span)
            async let doses = therapyProvider.therapy(in: span)
            (readings, therapy) = try await (glucose, doses)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Editor

/// The new note form: free text plus the date and time the note is about.
private struct NoteEditorView: View {
    let onSave: (String, Date) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var timestamp = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($isTextFocused)
                } header: {
                    Text("Note")
                }

                Section {
                    DatePicker("Date", selection: $timestamp, in: ...Date(), displayedComponents: .date)
                    DatePicker("Time", selection: $timestamp, in: ...Date(), displayedComponents: .hourAndMinute)
                } footer: {
                    Text("The note appears on your glucose graph at this time.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(trimmed.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || !trimmed.isEmpty)
            .onAppear { isTextFocused = true }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(trimmed, min(timestamp, Date()))
            dismiss()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NotesView()
}
