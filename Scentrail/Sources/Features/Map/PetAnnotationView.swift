import SwiftUI
import UIKit
import ScentrailKit

/// A circular map annotation for a pet: the photo set on its Traccar device
/// (the `deviceImage` attribute, see ADR-0011) when available, otherwise a
/// paw icon tinted by the pet's online/offline status.
///
/// Traccar's device media endpoint requires the same Basic Auth as every
/// other request, so this loads the photo through `PetRepository` rather
/// than a plain `AsyncImage(url:)` (which can't attach auth headers).
struct PetAnnotationView: View {
    let pet: Pet
    let petRepository: PetRepository
    @State private var photo: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(.background)
                .shadow(radius: 2)

            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    pawIcon
                }
            }
            .clipShape(Circle())
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(pet.status.tintColor, lineWidth: 3))
        .task(id: pet.photoURL) {
            photo = nil
            guard let data = try? await petRepository.fetchPhoto(for: pet) else { return }
            photo = UIImage(data: data)
        }
    }

    private var pawIcon: some View {
        ZStack {
            Circle().fill(pet.status.tintColor.opacity(0.2))
            Image(systemName: "pawprint.fill")
                .foregroundStyle(pet.status.tintColor)
                .font(.system(size: 18, weight: .semibold))
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        PetAnnotationView(pet: .previewOnline, petRepository: PreviewPetRepository())
        PetAnnotationView(pet: .previewOffline, petRepository: PreviewPetRepository())
    }
    .padding()
}
