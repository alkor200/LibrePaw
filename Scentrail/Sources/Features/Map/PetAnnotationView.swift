import SwiftUI
import UIKit
import ScentrailKit

/// A circular avatar for a pet: the photo set on its Traccar device (the
/// `deviceImage` attribute, see ADR-0011) when available, otherwise a paw
/// icon tinted by the pet's online/offline status. Used both as a map
/// annotation and as the pet detail screen's larger profile picture.
///
/// Traccar's device media endpoint requires the same Basic Auth as every
/// other request, so this loads the photo through `PetRepository` rather
/// than a plain `AsyncImage(url:)` (which can't attach auth headers).
struct PetAnnotationView: View {
    let pet: Pet
    let petRepository: PetRepository
    var size: CGFloat = 44
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
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(pet.status.tintColor, lineWidth: max(2, size * 0.07)))
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
                .font(.system(size: size * 0.4, weight: .semibold))
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        PetAnnotationView(pet: .previewOnline, petRepository: PreviewPetRepository())
        PetAnnotationView(pet: .previewOffline, petRepository: PreviewPetRepository(), size: 96)
    }
    .padding()
}
