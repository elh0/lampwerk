import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The space a plot happens in: its size, and optionally the location's floor plan underneath.
struct SpaceSheet: View {
    @Binding var plot: Plot
    var done: () -> Void

    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Caps("Space")
                Spacer()
                Button("Done", action: done).buttonStyle(ActionButtonStyle(primary: true))
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            Divider().overlay(Palette.rule)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Caps("Size").padding(.top, 14)
                    SizeRow(label: "Width", value: $plot.roomWidth)
                    SizeRow(label: "Depth", value: $plot.roomDepth)
                    Text("Camera end at the bottom of the plan. Lamps stay where they are.")
                        .font(.lwChip).foregroundStyle(Palette.quiet)

                    Caps("Floor plan").padding(.top, 18)
                    if let img = FloorPlans.image(plot.floorPlan) {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 180)
                            .frame(maxWidth: .infinity)
                            .background(Palette.paper)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        Text("Stretched to the room. Set the width to the plan's real width and the depth follows its shape.")
                            .font(.lwChip).foregroundStyle(Palette.quiet)
                        HStack(spacing: 6) {
                            Button("Match depth to plan") { matchDepth(img) }.buttonStyle(ActionButtonStyle())
                            Spacer()
                            Button("Remove") {
                                FloorPlans.delete(plot.floorPlan)
                                plot.floorPlan = nil
                            }
                            .buttonStyle(ActionButtonStyle())
                        }
                    } else {
                        Text("Add the plan from the location, a photo of it, or a PDF. It sits faintly under your lamps.")
                            .font(.lwChip).foregroundStyle(Palette.quiet)
                    }
                    HStack(spacing: 6) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Text(plot.floorPlan == nil ? "From Photos" : "Replace from Photos")
                        }
                        .buttonStyle(ActionButtonStyle())
                        Button(plot.floorPlan == nil ? "From Files" : "Replace from Files") { importingFile = true }
                            .buttonStyle(ActionButtonStyle())
                    }
                    if let problem {
                        Text(problem).font(.lwChip).foregroundStyle(Palette.text)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .background(Palette.p1)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let name = FloorPlans.save(imageData: data) {
                    use(name)
                } else {
                    problem = "Couldn't read that photo. Try another."
                }
                photo = nil
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image, .pdf]) { result in
            if case .success(let url) = result, let name = FloorPlans.save(fileAt: url) {
                use(name)
            } else {
                problem = "Couldn't read that file. Images and PDFs work."
            }
        }
    }

    private func use(_ name: String) {
        FloorPlans.delete(plot.floorPlan)
        plot.floorPlan = name
        problem = nil
        if let img = FloorPlans.image(name) { matchDepth(img) }
    }

    /// Keeps the plan's proportions: depth = width × the image's height / width.
    private func matchDepth(_ img: UIImage) {
        guard img.size.width > 0 else { return }
        plot.roomDepth = ((plot.roomWidth * img.size.height / img.size.width) * 10).rounded() / 10
    }
}

/// Metres with − and + in half-metre steps, or type an exact figure.
struct SizeRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.lwBody).foregroundStyle(Palette.text).frame(width: 56, alignment: .leading)
            Button { value = max(1, ((value - 0.5) * 2).rounded() / 2) } label: { Image(systemName: "minus") }
                .buttonStyle(ActionButtonStyle())
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.lwValue).foregroundStyle(Palette.text)
                .frame(width: 64, height: 34)
                .background(Palette.p0, in: RoundedRectangle(cornerRadius: Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Palette.rule))
            Button { value = min(60, ((value + 0.5) * 2).rounded() / 2) } label: { Image(systemName: "plus") }
                .buttonStyle(ActionButtonStyle())
            Text("m").font(.lwData).foregroundStyle(Palette.quiet)
            Spacer()
        }
    }
}
