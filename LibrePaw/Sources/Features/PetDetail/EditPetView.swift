import SwiftUI
import PhotosUI
import UIKit
import LibrePawKit

/// A combined pet editor: change the name and/or photo in one place, save.
/// Persisting each change is still the caller's responsibility (via
/// `onSaveName`/`onSavePhoto`), and so is only presenting this to accounts
/// permitted to (see `PetDetailView`'s `canManageDevice` gate, ADR-0023,
/// this view has no permission check of its own). `petRepository` is used
/// for exactly one read, fetching the pet's current photo to show before
/// anyone picks a new one, the same call `PetAnnotationView` already makes
/// elsewhere for the same photo.
struct EditPetView: View {
    let pet: Pet
    let petRepository: PetRepository
    let onSaveName: (String) async throws -> Void
    let onSavePhoto: (Data) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var currentPhoto: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    private let cropDiameter: CGFloat = 220
    private let outputDiameter: CGFloat = 512
    /// Traccar rejects uploads over 500KB; staying comfortably under that.
    private let maxUploadBytes = 480_000

    init(
        pet: Pet,
        petRepository: PetRepository,
        onSaveName: @escaping (String) async throws -> Void,
        onSavePhoto: @escaping (Data) async throws -> Void
    ) {
        self.pet = pet
        self.petRepository = petRepository
        self.onSaveName = onSaveName
        self.onSavePhoto = onSavePhoto
        _name = State(initialValue: pet.name)
    }

    private var currentName: String { pet.name }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedName != currentName || selectedImage != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let selectedImage {
                    cropView(for: selectedImage)
                } else if let currentPhoto {
                    currentPhotoView(currentPhoto)
                } else {
                    photoPickerButton(label: "Choose a Photo", prominent: true)
                        .padding(.vertical, 24)
                }

                TextField("Name", text: $name)
                    .focused($isNameFieldFocused)
                    .padding(12)
                    .background(.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.appBackground)
            .navigationTitle("Edit \(currentName)")
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
                    .disabled(trimmedName.isEmpty || !hasChanges || isSaving)
                }
            }
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadPickedPhoto(newValue) }
            }
            .task {
                guard let data = try? await petRepository.fetchPhoto(for: pet) else { return }
                currentPhoto = UIImage(data: data)
            }
        }
    }

    private func currentPhotoView(_ photo: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: cropDiameter, height: cropDiameter)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(radius: 4)

            photoPickerButton(label: "Choose a Different Photo", prominent: false)
        }
    }

    private func photoPickerButton(label: LocalizedStringKey, prominent: Bool) -> some View {
        // `Text(label)` built here, outside `PhotosPicker`'s content
        // closure, rather than passing the raw `LocalizedStringKey`
        // straight in: that closure is `@Sendable`/isolated in newer SDKs,
        // and `LocalizedStringKey` itself isn't `Sendable` (it can hold
        // arbitrary interpolated values), triggering a Swift 6 strict
        // concurrency error. `Text`, already resolved, captures cleanly.
        let title = Text(label)
        return PhotosPicker(selection: $pickerItem, matching: .images) {
            if prominent {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    title
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            } else {
                Label {
                    title
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            }
        }
    }

    private func cropView(for image: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropDiameter, height: cropDiameter)
                .scaleEffect(scale)
                .offset(offset)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(radius: 4)
                .contentShape(Circle())
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                offset = clampedOffset(offset, scale: scale, imageSize: image.size)
                                lastOffset = offset
                            },
                        DragGesture()
                            .onChanged { value in
                                let candidate = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = clampedOffset(candidate, scale: scale, imageSize: image.size)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )

            photoPickerButton(label: "Choose a Different Photo", prominent: false)
        }
    }

    /// Keeps the crop circle filled with image content, without this, a
    /// large pan or a zoom-out-then-pan could reveal blank space.
    private func clampedOffset(_ offset: CGSize, scale: CGFloat, imageSize: CGSize) -> CGSize {
        let fillScale = max(cropDiameter / imageSize.width, cropDiameter / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * fillScale * scale, height: imageSize.height * fillScale * scale)
        let maxOffsetX = max(0, (scaledSize.width - cropDiameter) / 2)
        let maxOffsetY = max(0, (scaledSize.height - cropDiameter) / 2)
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            return
        }
        selectedImage = image
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    /// Saves only what actually changed, name and photo are independent
    /// writes against two different Traccar endpoints (see
    /// `TraccarClient.updateDeviceName`/`updateDeviceImage`), no reason to
    /// resend an unchanged name, or upload nothing, every time either one
    /// is edited. If one save succeeds and the other then throws, the sheet
    /// stays open with the error shown rather than dismissing, re-tapping
    /// Save simply retries the one that failed, resending an already-saved
    /// name is a harmless no-op.
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if trimmedName != currentName {
                try await onSaveName(trimmedName)
            }
            if let selectedImage {
                guard let jpegData = renderCircularCrop(image: selectedImage) else {
                    errorMessage = localized("Couldn't process that photo, try a different one.")
                    return
                }
                try await onSavePhoto(jpegData)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renders exactly what's visible inside the on-screen crop circle to a
    /// fixed-size square JPEG, reproducing the same `scaledToFill` +
    /// pinch/pan transform at `outputDiameter` resolution, then compresses
    /// it under Traccar's upload size limit.
    private func renderCircularCrop(image: UIImage) -> Data? {
        let renderScale = outputDiameter / cropDiameter
        let fillScale = max(outputDiameter / image.size.width, outputDiameter / image.size.height)
        let fittedSize = CGSize(width: image.size.width * fillScale, height: image.size.height * fillScale)
        let scaledSize = CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
        let origin = CGPoint(
            x: outputDiameter / 2 - scaledSize.width / 2 + offset.width * renderScale,
            y: outputDiameter / 2 - scaledSize.height / 2 + offset.height * renderScale
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputDiameter, height: outputDiameter))
        let rendered = renderer.image { context in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: outputDiameter, height: outputDiameter)).addClip()
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        var quality: CGFloat = 0.85
        var data = rendered.jpegData(compressionQuality: quality)
        while let currentData = data, currentData.count > maxUploadBytes, quality > 0.3 {
            quality -= 0.1
            data = rendered.jpegData(compressionQuality: quality)
        }
        return data
    }
}

#if DEBUG
#Preview {
    EditPetView(pet: .previewOnline, petRepository: PreviewPetRepository(), onSaveName: { _ in }, onSavePhoto: { _ in })
}
#endif
