import SwiftUI
import AppKit
import RealityKit
import SceneKit
import UniformTypeIdentifiers

@main
struct MeshTreeApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            FolderPickerView()
                .frame(minWidth: 450, minHeight: 520)
        }
    }
}

struct FolderPickerView: View {
    @State private var selectedFolderURL: URL?
    @State private var outputModelURL: URL?
    @State private var statusText: String = "No folder selected"
    @State private var isProcessing: Bool = false
    @State private var inputImageURLs: [URL] = []
    @State private var progress: Double = 0.0
    @State private var selectedDetail: PhotogrammetrySession.Request.Detail = .medium
    @State private var session: PhotogrammetrySession?
    @State private var currentWorkingDir: URL?

    private let columns = [GridItem(.adaptive(minimum: 75), spacing: 8)]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(Color.black.opacity(0.10))

                if let modelURL = outputModelURL {
                    ModelPreviewView(url: modelURL)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else if !inputImageURLs.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(inputImageURLs, id: \.self) { imageURL in
                                AsyncImage(url: imageURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 75, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        removeImage(imageURL)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(Color.black.opacity(0.75)))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(5)
                                    .zIndex(1)
                                }
                            }
                        }
                        .padding(10)
                    }
                } else {
                    Text(statusText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }

            HStack {
                if outputModelURL != nil {
                    Button("Save 3D Model") {
                        saveModel()
                    }
                }

                if isProcessing {
                    ProgressView(value: progress)
                        .frame(width: 130)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                }

                Spacer()

                Picker("Quality", selection: $selectedDetail) {
                    Text("Low").tag(PhotogrammetrySession.Request.Detail.preview)
                    Text("Medium").tag(PhotogrammetrySession.Request.Detail.reduced)
                    Text("High").tag(PhotogrammetrySession.Request.Detail.medium)
                    Text("Max").tag(PhotogrammetrySession.Request.Detail.full)
                    Text("Ultra").tag(PhotogrammetrySession.Request.Detail.raw)
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .disabled(isProcessing)

                Button("Select Folder") {
                    openFolderPicker()
                }
                .disabled(isProcessing)

                if isProcessing {
                    Button("Cancel") {
                        cancelReconstruction()
                    }
                    .tint(.red)
                } else {
                    Button("Start Reconstruction") {
                        reconstruct()
                    }
                    .disabled(selectedFolderURL == nil || isProcessing)
                }
            }
        }
        .padding(20)
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() != .OK {
            return
        }
        guard let url = panel.url else { return }
        applySelectedFolder(url)
    }

    private func applySelectedFolder(_ url: URL) {
        selectedFolderURL = url
        outputModelURL = nil
        inputImageURLs = []

        let validExtensions = ["jpg", "jpeg", "png", "heic"]
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
            .filter { validExtensions.contains($0.pathExtension.lowercased()) } ?? []

        // print("found \(files.count) valid images in folder")

        inputImageURLs = files
        statusText = "Selected: \(url.lastPathComponent) (\(files.count) images)"
    }
    
    private func removeImage(_ url: URL) {
        inputImageURLs.removeAll { $0 == url }  //remove picture
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                applySelectedFolder(url)
            }
        }
        return true
    }

    private func saveModel() {
        guard let sourceURL = outputModelURL else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.usdz]
        panel.nameFieldStringValue = "Model.usdz"
        panel.canCreateDirectories = true
        panel.title = "Export 3D Model"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            statusText = "Exported to: \(destinationURL.lastPathComponent)"
        } catch {
            statusText = "Export failed"
        }
    }

    private func cancelReconstruction() {
        session?.cancel()
        session = nil
        isProcessing = false
        statusText = "Reconstruction cancelled"
        if let dir = currentWorkingDir {
            try? FileManager.default.removeItem(at: dir)
            currentWorkingDir = nil
        }
    }

    private func reconstruct() {
        guard let inputFolder = selectedFolderURL else { return }

        guard PhotogrammetrySession.isSupported else {
            statusText = "Photogrammetry is not supported on this Mac."
            return
        }

        if let previousDir = currentWorkingDir {
            try? FileManager.default.removeItem(at: previousDir)
            currentWorkingDir = nil
        }

        progress = 0.0
        isProcessing = true
        statusText = "Preparing images"

        Task {
            let fileManager = FileManager.default

            let hasAccess = inputFolder.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    inputFolder.stopAccessingSecurityScopedResource()
                }
            }

            let workingDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let tempInputDir = workingDir.appendingPathComponent("input")
            let outputDir = workingDir.appendingPathComponent("output")
            let outputURL = outputDir.appendingPathComponent("model.usdz")

            await MainActor.run {
                self.currentWorkingDir = workingDir
            }

            do {
                try fileManager.createDirectory(at: tempInputDir, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
                
                let currentImageURLs = await MainActor.run { inputImageURLs }
                var imageCount = 0

                for fileURL in currentImageURLs {
                    let targetURL = tempInputDir.appendingPathComponent(fileURL.lastPathComponent)
                    try fileManager.copyItem(at: fileURL, to: targetURL)
                    imageCount += 1
                }
                
                guard imageCount >= 3 else {
                    await MainActor.run {
                        statusText = "Folder must contain at least 3 images."
                        isProcessing = false
                    }
                    return
                }

                await MainActor.run {
                    statusText = "Processing \(imageCount) images..."
                }

                let newSession = try PhotogrammetrySession(input: tempInputDir)
                await MainActor.run {
                    self.session = newSession
                }
                
                Task {
                    for try await output in newSession.outputs {
                        switch output {
                        case .processingComplete:
                            await MainActor.run {
                                statusText = "Reconstruction complete"
                                outputModelURL = outputURL
                                isProcessing = false
                                inputImageURLs = []
                                self.session = nil
                            }
                            try? fileManager.removeItem(at: tempInputDir)
                        case .requestProgress(_, let fraction):
                            // print("progress: \(fraction)")
                            await MainActor.run {
                                progress = fraction
                            }
                        case .requestError(_, let error):
                            await MainActor.run {
                                statusText = "Error: \(error.localizedDescription)"
                                isProcessing = false
                                self.session = nil
                            }
                        default:
                            break
                        }
                    }
                }

                try newSession.process(requests: [.modelFile(url: outputURL, detail: selectedDetail)])

            } catch {
                await MainActor.run {
                    statusText = "Failed: \(error.localizedDescription)"
                    isProcessing = false
                    self.session = nil
                }
            }
        }
    }
}

#Preview {
    FolderPickerView()
}

struct ModelPreviewView: View {
    let url: URL
 
    var body: some View {
        Group {
            if let scene = try? SCNScene(url: url, options: nil) {
                SceneView(
                    scene: scene,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
            } else {
                Text("Unable to load 3D model")
            }
        }
    }
}
