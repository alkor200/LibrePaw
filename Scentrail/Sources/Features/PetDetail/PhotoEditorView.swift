import SwiftUI
import PhotosUI
import UIKit

/// A minimal in-app photo editor: pick a photo from the library, pinch/drag
/// to position it inside a circular crop, save. Renders exactly what's
/// visible inside the circle to a fixed-size JPEG and hands it to `onSave`,
/// callers are responsible for actually uploading it.
struct PhotoEditorView: View {
    let petName: String
    let onSave: (Data) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let cropDiameter: CGFloat = 280
    private let outputDiameter: CGFloat = 512
    /// Traccar rejects uploads over 500KB; staying comfortably under that.
    private let maxUploadBytes = 480_000

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let selectedImage {
                    cropView(for: selectedImage)
                } else {
                    photoPickerButton(label: "Choose a Photo", prominent: true)
                        .padding(.vertical, 40)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle("\(petName)'s Photo")
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
                    .disabled(selectedImage == nil || isSaving)
                }
            }
            .onChange(of: pickerItem) { _, newValue in
                Task { await loadPickedPhoto(newValue) }
            }
        }
    }

    private func photoPickerButton(label: LocalizedStringKey, prominent: Bool) -> some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            if prominent {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text(label)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            } else {
                Label(label, systemImage: "photo.on.rectangle")
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

            Text("Pinch to zoom, drag to reposition")
                .font(.caption)
                .foregroundStyle(.appSecondaryText)
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

    private func save() async {
        guard let selectedImage else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        guard let jpegData = renderCircularCrop(image: selectedImage) else {
            errorMessage = localized("Couldn't process that photo, try a different one.")
            return
        }

        do {
            try await onSave(jpegData)
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

#Preview {
    PhotoEditorView(petName: "Buddy", onSave: { _ in })
}
