// Copyright 2024 Apple Inc.

// Note on AX Lookup errors seen in logs:
// The "AX Lookup problem - errorCode:1100 error:Permission denied portName:'com.apple.iphone.axserver'" errors
// are related to Accessibility services. These errors do not affect core functionality and are related to
// UIKit's interaction with the accessibility subsystem. These are common in development builds or when
// running without certain accessibility permissions. They can be safely ignored for this application.

import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import MLX
import MLXLMCommon
import MLXRandom
import MLXVLM
import PhotosUI
import SwiftUI

#if os(iOS)
    typealias PlatformImage = UIImage
#else
    typealias PlatformImage = NSImage
#endif

struct ContentView: View {
    @State var prompt = ""
    @State var llm = VLMEvaluator()
    @Environment(DeviceStat.self) private var deviceStat

    @State private var selectedImage: PlatformImage? = nil {
        didSet {
            if selectedImage != nil {
                selectedVideoURL = nil
                player = nil
            }
        }
    }
    @State private var selectedVideoURL: URL? = nil {
        didSet {
            if let selectedVideoURL {
                player = AVPlayer(url: selectedVideoURL)
                selectedImage = nil
            }
        }
    }
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var player: AVPlayer? = nil

    private var currentImageURL: URL? {
        selectedImage == nil && selectedVideoURL == nil
            ? URL(
                string:
                    "https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/bee.jpg"
            ) : nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack {
                HStack {
                    Text(llm.modelInfo)
                        .textFieldStyle(.roundedBorder)

                    Spacer()

                    Text(llm.stat)
                }

                VStack {
                    if let selectedImage {
                        Group {
                            #if os(iOS) || os(visionOS)
                                Image(uiImage: selectedImage)
                                    .resizable()
                            #else
                                Image(nsImage: selectedImage)
                                    .resizable()
                            #endif
                        }
                        .scaledToFit()
                        .cornerRadius(12)
                        .frame(height: 300)
                    } else if let imageURL = currentImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .frame(height: 200)
                            case .failure:
                                Image(systemName: "photo.badge.exclamationmark")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if let player {
                        VideoPlayer(player: player)
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                    }

                    HStack {
                        #if os(iOS) || os(visionOS)
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: PHPickerFilter.any(of: [
                                    PHPickerFilter.images, PHPickerFilter.videos,
                                ])
                            ) {
                                Label("Select Image/Video", systemImage: "photo.badge.plus")
                            }
                            .onChange(of: selectedItem) {
                                Task {
                                    print("PhotosPicker selection changed")
                                    if let video = try? await selectedItem?.loadTransferable(
                                        type: TransferableVideo.self)
                                    {
                                        print("Loaded video transferable")
                                        selectedVideoURL = video.url
                                    } else if let data = try? await selectedItem?.loadTransferable(
                                        type: Data.self)
                                    {
                                        print("Loaded image data: \(data.count) bytes")
                                        
                                        // Check image format based on data headers
                                        let imageFormat = detectImageFormat(data: data)
                                        print("Detected image format: \(imageFormat)")
                                        
                                        if let image = PlatformImage(data: data) {
                                            print("Successfully created image with size: \(image.size.width) x \(image.size.height)")
                                            
                                            // Detect if image is likely a screenshot (common for PNG files with specific aspect ratios)
                                            let isLikelyScreenshot = imageFormat == "PNG" && (
                                                // Portrait screenshots often have very tall aspect ratios
                                                image.size.height > image.size.width * 1.8 ||
                                                // Check for common screenshot dimensions
                                                (image.size.width == 1179 && image.size.height == 2556) ||
                                                (image.size.width == 1170 && image.size.height == 2532) ||
                                                (image.size.width == 1290 && image.size.height == 2796)
                                            )
                                            
                                            if isLikelyScreenshot {
                                                print("Detected likely screenshot - applying special processing")
                                            }
                                            
                                            // Process all images to a standard, safe format regardless of source
                                            #if os(iOS)
                                            // Create square canvas image at 448x448 dimensions
                                            print("Creating standardized 448x448 image for model compatibility")
                                            let targetSize = CGSize(width: 448, height: 448)
                                            let format = UIGraphicsImageRendererFormat()
                                            format.scale = 1.0
                                            
                                            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
                                            let squareImage = renderer.image { context in
                                                // White background for transparency
                                                UIColor.white.setFill()
                                                context.fill(CGRect(origin: .zero, size: targetSize))
                                                
                                                // Calculate dimensions to maintain aspect ratio within square
                                                let originalSize = image.size
                                                let widthRatio = targetSize.width / originalSize.width
                                                let heightRatio = targetSize.height / originalSize.height
                                                let scale = min(widthRatio, heightRatio)
                                                
                                                let scaledWidth = originalSize.width * scale
                                                let scaledHeight = originalSize.height * scale
                                                
                                                // Center the image in the square
                                                let xOffset = (targetSize.width - scaledWidth) / 2
                                                let yOffset = (targetSize.height - scaledHeight) / 2
                                                
                                                // Draw the image centered in the square canvas
                                                image.draw(in: CGRect(
                                                    x: xOffset,
                                                    y: yOffset,
                                                    width: scaledWidth,
                                                    height: scaledHeight
                                                ))
                                            }
                                            
                                            print("Created standardized image with size: \(squareImage.size.width) x \(squareImage.size.height)")
                                            selectedImage = squareImage
                                            #endif
                                        } else {
                                            print("ERROR: Failed to create image from data. Data size: \(data.count) bytes")
                                            print("First 16 bytes: \(data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
                                        }
                                    } else {
                                        print("ERROR: Failed to load transferable content")
                                    }
                                }
                            }
                        #else
                            Button("Select Image/Video") {
                                showingImagePicker = true
                            }
                            .fileImporter(
                                isPresented: $showingImagePicker,
                                allowedContentTypes: [.image, .movie]
                            ) { result in
                                switch result {
                                case .success(let file):
                                    Task { @MainActor in
                                        do {
                                            let data = try loadData(from: file)
                                            print("macOS: Loaded file data: \(data.count) bytes")
                                            
                                            if let image = PlatformImage(data: data) {
                                                print("macOS: Successfully created image with size: \(image.size.width) x \(image.size.height)")
                                                
                                                // Create a safer version of the image for very large images
                                                if image.size.width > 2000 || image.size.height > 2000 {
                                                    print("macOS: Image is very large, resizing...")
                                                    let scale = 1000.0 / max(image.size.width, image.size.height)
                                                    
                                                    let newSize = NSSize(
                                                        width: image.size.width * scale,
                                                        height: image.size.height * scale
                                                    )
                                                    
                                                    let resizedImage = NSImage(size: newSize)
                                                    resizedImage.lockFocus()
                                                    image.draw(in: NSRect(origin: .zero, size: newSize),
                                                              from: NSRect(origin: .zero, size: image.size),
                                                              operation: .copy,
                                                              fraction: 1.0)
                                                    resizedImage.unlockFocus()
                                                    
                                                    selectedImage = resizedImage
                                                } else {
                                                    selectedImage = image
                                                }
                                            } else if let fileType = UTType(
                                                filenameExtension: file.pathExtension),
                                                fileType.conforms(to: .movie)
                                            {
                                                print("macOS: Processing video file")
                                                if let sandboxURL = try? loadVideoToSandbox(
                                                    from: file)
                                                {
                                                    selectedVideoURL = sandboxURL
                                                }
                                            } else {
                                                print("macOS: Failed to create image from data - unsupported format")
                                            }
                                        } catch {
                                            print(
                                                "macOS: Failed to load file: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                case .failure(let error):
                                    print(error.localizedDescription)
                                }
                            }
                        #endif

                        if selectedImage != nil {
                            Button("Clear", role: .destructive) {
                                selectedImage = nil
                                selectedItem = nil
                            }
                        }
                    }
                }
                .padding()

                HStack {
                    Spacer()
                    if llm.running {
                        ProgressView()
                            .frame(maxHeight: 20)
                        Spacer()
                    }
                }
            }

            ScrollView(.vertical) {
                ScrollViewReader { sp in
                    Text(llm.output)
                        .textSelection(.enabled)
                        .onChange(of: llm.output) { _, _ in
                            sp.scrollTo("bottom")
                        }

                    Spacer()
                        .frame(width: 1, height: 1)
                        .id("bottom")
                }
            }

            HStack {
                TextField("prompt", text: $prompt)
                    .onSubmit(generate)
                    .disabled(llm.running)
                    #if os(visionOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                Button("generate", action: generate)
                    .disabled(llm.running)
            }
        }
        #if os(visionOS)
            .padding(40)
        #else
            .padding()
        #endif
        .toolbar {
            ToolbarItem {
                Label(
                    "Memory Usage: \(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))",
                    systemImage: "info.circle.fill"
                )
                .labelStyle(.titleAndIcon)
                .padding(.horizontal)
                .help(
                    Text(
                        """
                        Active Memory: \(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))/\(GPU.memoryLimit.formatted(.byteCount(style: .memory)))
                        Cache Memory: \(deviceStat.gpuUsage.cacheMemory.formatted(.byteCount(style: .memory)))/\(GPU.cacheLimit.formatted(.byteCount(style: .memory)))
                        Peak Memory: \(deviceStat.gpuUsage.peakMemory.formatted(.byteCount(style: .memory)))
                        """
                    )
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        copyToClipboard(llm.output)
                    }
                } label: {
                    Label("Copy Output", systemImage: "doc.on.doc.fill")
                }
                .disabled(llm.output == "")
                .labelStyle(.titleAndIcon)
            }
        }
        .task {
            self.prompt = llm.modelConfiguration.defaultPrompt
            _ = try? await llm.load()
        }
    }

    #if os(iOS)
    // iOS-specific image preprocessing function
    private func preprocessImage(_ image: UIImage) -> CIImage? {
        print("iOS: Preprocessing image of size: \(image.size.width) x \(image.size.height)")
        
        // Target size for the VLM model - must be exactly 448x448
        let targetSize = CGSize(width: 448, height: 448)
        
        // Create a square canvas with white background
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        let squareImage = renderer.image { context in
            // Fill with white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            
            // Calculate dimensions that maintain aspect ratio but fit within target size
            let originalSize = image.size
            let widthRatio = targetSize.width / originalSize.width
            let heightRatio = targetSize.height / originalSize.height
            let scale = min(widthRatio, heightRatio)
            
            let newWidth = originalSize.width * scale
            let newHeight = originalSize.height * scale
            
            // Center the image
            let xOffset = (targetSize.width - newWidth) / 2
            let yOffset = (targetSize.height - newHeight) / 2
            
            image.draw(in: CGRect(
                x: xOffset,
                y: yOffset,
                width: newWidth,
                height: newHeight
            ))
        }
        
        print("iOS: Created square image: \(targetSize.width) x \(targetSize.height)")
        
        // Convert to CIImage with sRGB color space
        guard let ciImage = CIImage(image: squareImage) else {
            print("iOS: Failed to convert square UIImage to CIImage")
            return nil
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciContext = CIContext()
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("iOS: Failed to create CGImage with sRGB color space")
            return nil
        }
        
        let finalCIImage = CIImage(cgImage: cgImage)
        print("iOS: Final CIImage size: \(finalCIImage.extent.width) x \(finalCIImage.extent.height)")
        
        return finalCIImage
    }
    #else
    // macOS-specific image preprocessing function
    private func preprocessImage(_ image: NSImage) -> CIImage? {
        print("macOS: Preprocessing image of size: \(image.size.width) x \(image.size.height)")
        
        // Target size for the VLM model
        let targetSize = CGSize(width: 448, height: 448)
        
        // Step 1: Get CGImage from NSImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("macOS: Failed to get CGImage from NSImage")
            return nil
        }
        
        // Step 2: Create CIImage from CGImage
        let ciImage = CIImage(cgImage: cgImage)
        print("macOS: Original CIImage extent: \(ciImage.extent.width) x \(ciImage.extent.height)")
        
        // Step 3: Create a square canvas with the image centered
        let squareContext = CIContext()
        let squareImage = NSImage(size: targetSize)
        squareImage.lockFocus()
        
        // Fill with white background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        
        // Calculate scale to fit within target size while preserving aspect ratio
        let widthRatio = targetSize.width / ciImage.extent.width
        let heightRatio = targetSize.height / ciImage.extent.height
        let scale = min(widthRatio, heightRatio)
        
        // Calculate dimensions that maintain aspect ratio
        let newWidth = ciImage.extent.width * scale
        let newHeight = ciImage.extent.height * scale
        
        // Center the image
        let xOffset = (targetSize.width - newWidth) / 2
        let yOffset = (targetSize.height - newHeight) / 2
        
        print("macOS: Drawing image with scale factor: \(scale), new size: \(newWidth) x \(newHeight)")
        
        // Create a CGImage from the CIImage
        if let cgImageFromCI = squareContext.createCGImage(ciImage, from: ciImage.extent) {
            let tempNSImage = NSImage(cgImage: cgImageFromCI, size: ciImage.extent.size)
            tempNSImage.draw(in: NSRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight),
                       from: NSRect(origin: .zero, size: tempNSImage.size),
                       operation: .sourceOver,
                       fraction: 1.0)
        }
        
        squareImage.unlockFocus()
        
        // Convert back to CIImage
        guard let squareCGImage = squareImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("macOS: Failed to get CGImage from square NSImage")
            return nil
        }
        
        let squareCIImage = CIImage(cgImage: squareCGImage)
        
        // Ensure we're using sRGB color space
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        
        guard let finalCGImage = squareContext.createCGImage(squareCIImage, from: squareCIImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
            print("macOS: Failed to create final CGImage")
            return nil
        }
        
        let finalCIImage = CIImage(cgImage: finalCGImage)
        print("macOS: Final CIImage size: \(finalCIImage.extent.width) x \(finalCIImage.extent.height)")
        
        return finalCIImage
    }
    #endif
    
    private func generate() {
        Task {
            if let selectedImage = selectedImage {
                #if os(iOS)
                    print("iOS: Processing image of size: \(selectedImage.size.width) x \(selectedImage.size.height)")
                    if let processedImage = preprocessImage(selectedImage) {
                        print("iOS: Successfully preprocessed image")
                        await llm.generate(prompt: prompt, image: processedImage, videoURL: nil)
                    } else {
                        print("iOS: Failed to preprocess image, using fallback")
                        // Fall back to a 1x1 transparent image
                        let fallbackImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
                        await llm.generate(prompt: prompt, image: fallbackImage, videoURL: nil)
                    }
                #else
                    print("macOS: Processing image of size: \(selectedImage.size.width) x \(selectedImage.size.height)")
                    if let processedImage = preprocessImage(selectedImage) {
                        print("macOS: Successfully preprocessed image")
                        await llm.generate(prompt: prompt, image: processedImage, videoURL: nil)
                    } else {
                        print("macOS: Failed to preprocess image")
                    }
                #endif
            } else if let imageURL = currentImageURL {
                do {
                    print("Loading image from URL: \(imageURL)")
                    let (data, _) = try await URLSession.shared.data(from: imageURL)
                    print("Downloaded image data size: \(data.count) bytes")
                    
                    // Create a platform image first, then preprocess it
                    #if os(iOS)
                    if let uiImage = UIImage(data: data), let processedImage = preprocessImage(uiImage) {
                        print("Successfully preprocessed image from URL")
                        await llm.generate(prompt: prompt, image: processedImage, videoURL: nil)
                    } else {
                        print("ERROR: Failed to process image from URL data")
                    }
                    #else
                    if let nsImage = NSImage(data: data), let processedImage = preprocessImage(nsImage) {
                        print("Successfully preprocessed image from URL")
                        await llm.generate(prompt: prompt, image: processedImage, videoURL: nil)
                    } else {
                        print("ERROR: Failed to process image from URL data")
                    }
                    #endif
                } catch {
                    print("Failed to load image from URL: \(error.localizedDescription)")
                }
            } else {
                if let videoURL = selectedVideoURL {
                    print("Processing video from URL: \(videoURL)")
                    await llm.generate(prompt: prompt, image: nil, videoURL: videoURL)
                }
            }
        }
    }

    #if os(macOS)
        private func loadData(from url: URL) throws -> Data {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return try Data(contentsOf: url)
        }

        private func loadVideoToSandbox(from url: URL) throws -> URL {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: url)
            return sandboxURL
        }
    #endif

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }

    private func detectImageFormat(data: Data) -> String {
        guard data.count >= 12 else { return "Unknown (too small)" }
        
        // Check PNG signature (89 50 4E 47 0D 0A 1A 0A)
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "PNG"
        }
        
        // Check JPEG signature (FF D8)
        if data.starts(with: [0xFF, 0xD8]) {
            return "JPEG"
        }
        
        // Check HEIF/HEIC signature
        if data.count >= 12 {
            let heicSignature = data[4..<12]
            if heicSignature.elementsEqual([0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]) ||
               heicSignature.elementsEqual([0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x78]) {
                return "HEIC"
            }
        }
        
        // Check GIF signature (47 49 46)
        if data.starts(with: [0x47, 0x49, 0x46]) {
            return "GIF"
        }
        
        // Check TIFF signature (49 49 or 4D 4D)
        if (data.starts(with: [0x49, 0x49]) || data.starts(with: [0x4D, 0x4D])) {
            return "TIFF"
        }
        
        // Check WebP signature (52 49 46 46 ... 57 45 42 50)
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 {
            let webpSignature = data[8..<12]
            if webpSignature.elementsEqual([0x57, 0x45, 0x42, 0x50]) {
                return "WebP"
            }
        }
        
        // Check BMP signature (42 4D)
        if data.starts(with: [0x42, 0x4D]) {
            return "BMP"
        }
        
        // Unknown format - return hex signature for debugging
        if data.count >= 8 {
            let hexSignature = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Unknown (\(hexSignature))"
        }
        
        return "Unknown"
    }
}

@Observable
@MainActor
class VLMEvaluator {

    var running = false

    var output = ""
    var modelInfo = ""
    var stat = ""

    /// This controls which model loads. `qwen2VL2BInstruct4Bit` is one of the smaller ones, so this will fit on
    /// more devices.
    let modelConfiguration = ModelRegistry.qwen2VL2BInstruct4Bit

    /// parameters controlling the output
    let generateParameters = MLXLMCommon.GenerateParameters(temperature: 0.6)
    let maxTokens = 800

    /// update the display every N tokens -- 4 looks like it updates continuously
    /// and is low overhead.  observed ~15% reduction in tokens/s when updating
    /// on every token
    let displayEveryNTokens = 4

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            // limit the buffer cache
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) { [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo =
                        "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                }
            }

            let numParams = await modelContainer.perform { context in
                context.model.numParameters()
            }

            self.modelInfo = "Loaded \(modelConfiguration.id). Weights: \(numParams / (1024*1024))M"
            loadState = .loaded(modelContainer)
            return modelContainer

        case .loaded(let modelContainer):
            return modelContainer
        }
    }

    func generate(prompt: String, image: CIImage?, videoURL: URL?) async {
        guard !running else { return }

        running = true
        self.output = ""

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            print("Starting model inference with \(image != nil ? "image" : "no image") and \(videoURL != nil ? "video" : "no video")")
            if let image = image {
                // Verify image dimensions are exactly 448x448
                if image.extent.width != 448 || image.extent.height != 448 {
                    print("WARNING: Image dimensions \(image.extent.width)x\(image.extent.height) are not exactly 448x448")
                    print("This may cause reshape errors in the MLX model")
                }
                
                // Verify pixel format and properties
                let properties = image.properties
                print("Image properties: \(properties)")
            }
            
            let result = try await modelContainer.perform { context in
                let images: [UserInput.Image] = {
                    if let image = image {
                        print("Processing image with extent: \(image.extent.size.width) x \(image.extent.size.height)")
                        return [UserInput.Image.ciImage(image)]
                    } else {
                        print("No image to process")
                        return []
                    }
                }()
                let videos: [UserInput.Video] = {
                    if let videoURL = videoURL {
                        print("Processing video from URL: \(videoURL)")
                        return [UserInput.Video.url(videoURL)]
                    } else {
                        return []
                    }
                }()
                let messages: [[String: Any]] = {
                    if !images.isEmpty || !videos.isEmpty {
                        print("Creating messages with media content")
                        return [
                            [
                                "role": "user",
                                "content": [
                                    ["type": "text", "text": prompt]
                                ]
                                    // Messages format for Qwen 2 VL, Qwen 2.5 VL. May need to be adapted for other models.
                                    + images.map { _ in
                                        ["type": "image"]
                                    }
                                    + videos.map { _ in
                                        ["type": "video"]
                                    },
                            ]
                        ]
                    } else {
                        print("Creating text-only messages")
                        return [
                            [
                                "role": "user",
                                "content": prompt,
                            ]
                        ]
                    }
                }()
                
                var userInput = UserInput(messages: messages, images: images, videos: videos)
                
                // This is where the image resizing happens - note the 448x448 target size
                print("Setting image processing resize to 448x448")
                userInput.processing.resize = .init(width: 448, height: 448)
                
                do {
                    print("Preparing input through processor")
                    let input = try await context.processor.prepare(input: userInput)
                    print("Input preparation complete, starting token generation")
                    
                    return try MLXLMCommon.generate(
                        input: input,
                        parameters: generateParameters,
                        context: context
                    ) { tokens in
                        // update the output -- this will make the view show the text as it generates
                        if tokens.count % displayEveryNTokens == 0 {
                            let text = context.tokenizer.decode(tokens: tokens)
                            Task { @MainActor in
                                self.output = text
                            }
                        }

                        if tokens.count >= maxTokens {
                            return .stop
                        } else {
                            return .more
                        }
                    }
                } catch {
                    print("ERROR in processor.prepare: \(error)")
                    print("Error details: \(String(describing: error))")
                    
                    // Check if the error contains information about reshape issues
                    let errorDescription = String(describing: error)
                    if errorDescription.contains("reshape") {
                        print("DETECTED reshape error in MLX processing")
                    }
                    
                    throw error
                }
            }

            // update the text if needed, e.g. we haven't displayed because of displayEveryNTokens
            if result.output != self.output {
                self.output = result.output
            }
            self.stat = " Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"

        } catch {
            print("ERROR in VLM processing: \(error)")
            print("Error details: \(String(describing: error))")
            
            // Provide more detailed error diagnostics
            let nsError = error as NSError
            print("NSError domain: \(nsError.domain), code: \(nsError.code)")
            print("Error user info: \(nsError.userInfo)")
            
            // Handle specific errors based on error description
            let errorDescription = String(describing: error)
            if errorDescription.contains("reshape") {
                output = "Failed: Image processing error - The image format caused a reshape error in the model. Try a different image or format."
            } else {
                output = "Failed: \(error)"
            }
        }

        running = false
    }
}

#if os(iOS) || os(visionOS)
    struct TransferableVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: received.file)
                return .init(url: sandboxURL)
            }
        }
    }
#endif

struct SandboxFileTransfer {
    static func transferFileToTemp(from sourceURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sandboxURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: sandboxURL.path()) {
            try FileManager.default.removeItem(at: sandboxURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: sandboxURL)
        return sandboxURL
    }
}
