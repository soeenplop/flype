import FlypeCore
import SwiftUI

struct DictionaryView: View {
    @State private var snapshot = DictionarySnapshot()
    @State private var search = ""
    @State private var editing: PersonalDictionaryEntry?
    @State private var errorMessage: String?
    private var entries: [PersonalDictionaryEntry] {
        snapshot.entries.filter { entry in
            search.isEmpty
                || ([entry.spelling] + entry.aliases).contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .sorted { $0.spelling.localizedStandardCompare($1.spelling) == .orderedAscending }
    }
    var body: some View {
        FlypePage {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading.fixedSize(horizontal: true, vertical: true)
                    Spacer(minLength: 20)
                    addButton
                }
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    addButton
                }
            }
            Text(L10n.text("Namen und Begriffe.\nGenauso geschrieben, wie du sie meinst."))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L10n.text("Begriff suchen"), text: $search).textFieldStyle(.plain).frame(minHeight: 44)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.text("Suche zurücksetzen"))
                }
            }.padding(.horizontal, 13).padding(.vertical, 2).background(
                FlypeDesign.soft, in: RoundedRectangle(cornerRadius: 12))
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(
                        L10n.text(search.isEmpty ? "Deine Wörter finden hier Platz." : "Keine passenden Begriffe"),
                        systemImage: search.isEmpty ? "book" : "magnifyingglass")
                } description: {
                    Text(
                        L10n.text(
                            search.isEmpty
                                ? "Füge Namen, Firmen und Begriffe hinzu, die Flype kennen soll."
                                : "Versuche einen anderen Suchbegriff."))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            HStack {
                                Text(verbatim: entry.spelling).foregroundStyle(.primary)
                                Spacer()
                                if entry.learnedFromCorrection == true {
                                    Text(L10n.text("Aus Korrektur")).font(.caption).foregroundStyle(.secondary)
                                }
                                if !entry.enabled { Text(L10n.text("Aus")).font(.caption).foregroundStyle(.secondary) }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.horizontal, 16).padding(.vertical, 18).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if entry.id != entries.last?.id { Divider().padding(.horizontal, 16) }
                    }
                }.background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            if let errorMessage { Text(L10n.text(errorMessage)).font(.footnote).foregroundStyle(.red) }
        }
        .navigationTitle(L10n.text("Wörter"))
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear(perform: reload)
        .task {
            while !Task.isCancelled {
                reload()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .sheet(item: $editing, onDismiss: reload) { entry in
            NavigationStack {
                DictionaryEntryEditor(entry: entry, isExisting: snapshot.entries.contains { $0.id == entry.id })
            }.tint(FlypeDesign.accent)
        }
    }
    private var heading: some View {
        Text(L10n.text("Deine Wörter")).font(.title.weight(.semibold).leading(.tight))
            .accessibilityAddTraits(.isHeader)
    }
    private var addButton: some View {
        Button {
            editing = PersonalDictionaryEntry(spelling: "")
        } label: {
            Label(L10n.text("Begriff hinzufügen"), systemImage: "plus")
        }.buttonStyle(FlypePrimaryButtonStyle()).fixedSize(horizontal: true, vertical: true)
    }
    private func reload() {
        do {
            snapshot = try PersonalDictionaryStore.shared().snapshot()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

struct DictionaryEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: PersonalDictionaryEntry
    let isExisting: Bool
    @State private var variants = ""
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    var body: some View {
        Form {
            Section {
                TextField(L10n.text("Zum Beispiel Flype"), text: $entry.spelling).autocorrectionDisabled()
            } header: {
                Text(L10n.text("Gewünschte Schreibweise"))
            } footer: {
                Text(L10n.text("Für Namen, Firmen und Begriffe, die Flype genauso schreiben soll."))
            }
            Section {
                Toggle(L10n.text("Eintrag aktiv"), isOn: $entry.enabled)
                DisclosureGroup(L10n.text("Weitere Optionen")) {
                    Toggle(L10n.text("Für Tastaturvorschläge"), isOn: $entry.useForTyping)
                    Toggle(L10n.text("Für Transkriptionen"), isOn: $entry.useForDictation)
                    TextField(L10n.text("Falsche Schreibweisen, eine pro Zeile"), text: $variants, axis: .vertical)
                        .lineLimit(2...5).autocorrectionDisabled()
                    Toggle(L10n.text("Automatisch korrigieren"), isOn: $entry.replaceAliases)
                }
            }
            if isExisting {
                Section {
                    Button(L10n.text("Begriff löschen"), role: .destructive) { confirmingDelete = true }
                }
            }
            if let errorMessage { Text(L10n.text(errorMessage)).foregroundStyle(.red) }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden).background(FlypeDesign.paper)
        .navigationTitle(L10n.text(isExisting ? "Begriff bearbeiten" : "Begriff hinzufügen"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Abbrechen")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("Speichern"), action: save).disabled(
                    entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { variants = entry.aliases.joined(separator: "\n") }
        .confirmationDialog(
            L10n.text("Begriff löschen?"), isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button(L10n.text("Begriff löschen"), role: .destructive, action: remove)
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        }
    }
    private func save() {
        entry.aliases = variants.split(separator: "\n").map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        do {
            try PersonalDictionaryStore.shared().upsert(entry)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    private func remove() {
        do {
            try PersonalDictionaryStore.shared().delete(id: entry.id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
