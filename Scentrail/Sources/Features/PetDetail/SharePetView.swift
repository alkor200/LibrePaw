import SwiftUI
import ScentrailKit

/// Grants another Traccar account access to this pet — the in-app
/// equivalent of an admin doing it via Settings > Users in Traccar's own
/// web UI. Only reachable from an admin account (see `PetDetailView`):
/// `POST /api/permissions {userId, deviceId}` requires one server-side,
/// confirmed against a live server — see ADR-0018.
struct SharePetView: View {
    @State private var viewModel: SharePetViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEmailFieldFocused: Bool

    init(viewModel: SharePetViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEmailFieldFocused)
            } footer: {
                Text("The Traccar account with this email will be able to see \(viewModel.pet.name) in their own copy of Scentrail, the same as you.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task {
                        await viewModel.share()
                        if viewModel.didShare { dismiss() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSharing {
                            ProgressView()
                        } else {
                            Text("Share \(viewModel.pet.name)")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSharing)
            }
        }
        .navigationTitle("Share \(viewModel.pet.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { isEmailFieldFocused = true }
    }
}

#Preview {
    NavigationStack {
        SharePetView(viewModel: SharePetViewModel(pet: .previewOnline, petRepository: PreviewPetRepository()))
    }
}
