import SwiftUI

/// A minimal rename sheet: edit the pet's name, save. Mirrors
/// `PhotoEditorView`'s shape (`NavigationStack` sheet, Cancel/Save toolbar,
/// best-effort error message), callers are responsible for actually
/// persisting it.
struct RenamePetView: View {
    let currentName: String
    let onSave: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    init(currentName: String, onSave: @escaping (String) async throws -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFieldFocused)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Rename \(currentName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(trimmedName.isEmpty || isSaving)
                }
            }
            .task {
                isNameFieldFocused = true
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await onSave(trimmedName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RenamePetView(currentName: "Buddy", onSave: { _ in })
}
