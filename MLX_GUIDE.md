# Building Your Own LLM/VLM App with MLX Swift

This guide walks through the process of creating your own macOS applications for language and vision-language models using the MLX Swift framework, similar to the LLMEval and VLMEval examples.

## Prerequisites

### Required Tools & Versions
- **macOS**: Sonoma (macOS 14) or newer
- **Xcode**: Latest version from Mac App Store
- **Swift**: 5.9 or newer (comes with Xcode)
- **Command Line Tools**: Install via Xcode or with `xcode-select --install`
- **Homebrew**: Package manager for macOS

## Step 1: Install Required Tools

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install swift-format for code formatting
brew install swift-format
```

## Step 2: Set Up Your Development Environment

```bash
# Clone the example repo for reference
git clone https://github.com/ml-explore/mlx-swift-examples.git
cd mlx-swift-examples

# Explore the example apps
open -a Xcode .
```

## Step 3: Create Your Own Project

1. Open Xcode
2. Select "Create a new Xcode project"
3. Choose "App" under macOS
4. Configure your project:
   - Product Name: "MyLLMApp" (or your preferred name)
   - Interface: SwiftUI
   - Language: Swift
5. Choose a location to save your project

## Step 4: Add Dependencies to Your Project

1. In Xcode, select your project in the navigator
2. Go to "Package Dependencies" tab
3. Click "+" to add packages
4. Add these packages:
   - https://github.com/ml-explore/mlx-swift (MLX Swift)
   - https://github.com/huggingface/swift-transformers (Swift Transformers)
   - https://github.com/apple/swift-async-algorithms (Swift Async Algorithms)
   - https://github.com/ml-explore/mlx-swift-examples (to use their libraries)
5. Select the appropriate version for each (usually latest released version)

## Step 5: Create Your App Structure

Add the necessary imports to your main app file:

```swift
import SwiftUI
import MLX
import MLXNN
import MLXRandom
import MLXLMCommon
import MLXLLM  // For LLM app
import MLXVLM  // For VLM app
```

## Step 6: Create Basic UI Components

Create a basic UI in your ContentView.swift:

```swift
import SwiftUI
import MLXLMCommon
import MLXLLM

struct ContentView: View {
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isGenerating = false
    @State private var selectedModel = "Qwen2-1.5B-Instruct-4bit" // Default model
    
    let availableModels = [
        "Qwen2-1.5B-Instruct-4bit",
        "phi3-mini-4k-instruct-4bit"
    ]
    
    var body: some View {
        VStack {
            Text("MLX Model Demo")
                .font(.largeTitle)
            
            Picker("Model", selection: $selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    Text(model)
                }
            }
            .pickerStyle(.menu)
            
            TextEditor(text: $inputText)
                .frame(height: 100)
                .border(Color.gray)
                .padding()
            
            Button("Generate") {
                // Generate text functionality will go here
                isGenerating = true
                outputText = "Generation will be implemented in next steps..."
                isGenerating = false
            }
            .disabled(isGenerating || inputText.isEmpty)
            
            TextEditor(text: $outputText)
                .frame(height: 200)
                .border(Color.gray)
                .padding()
                .disabled(true)
        }
        .padding()
    }
}
```

## Step 7: Implement Model Loading

Create a ViewModel to handle model operations:

```swift
import Foundation
import MLX
import MLXLMCommon
import MLXLLM

class ModelViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var loadingMessage = ""
    @Published var isReady = false
    @Published var modelInfo = ""
    
    private var modelContainer: ModelContainer<LLMModel>?
    
    func loadModel(name: String) async {
        isLoading = true
        loadingProgress = 0
        loadingMessage = "Preparing to download model..."
        isReady = false
        
        // Set memory cache limit
        MLX.GPU.set(cacheLimit: 2 * 1024 * 1024 * 1024) // 2GB
        
        do {
            let factory = LLMModelFactory.shared
            
            // Configure progress tracking
            let progress = Progress()
            progress.totalUnitCount = 100
            
            Task { [weak self] in
                for await progressValue in progress.observe() {
                    await MainActor.run {
                        self?.loadingProgress = progressValue
                    }
                }
            }
            
            // Load the model
            modelContainer = try await ModelContainer<LLMModel>(
                modelName: name,
                factory: factory,
                progress: progress,
                progressHandler: { message in
                    Task { @MainActor in
                        self.loadingMessage = message
                    }
                }
            )
            
            await MainActor.run {
                self.isLoading = false
                self.isReady = true
                if let model = self.modelContainer?.model {
                    self.modelInfo = "Model: \(name)\nParameters: \(model.parameterCount / 1_000_000)M"
                }
            }
        } catch {
            await MainActor.run {
                self.loadingMessage = "Error loading model: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func generateText(prompt: String) async -> String {
        guard let model = modelContainer?.model else {
            return "Model not loaded"
        }
        
        do {
            // Generate configuration
            let configuration = GenerateConfiguration(
                maxTokens: 512,
                temperature: 0.7,
                topP: 0.9
            )
            
            // Process the prompt for the model
            let processor = modelContainer?.inputProcessor
            let formattedPrompt = processor?.processPrompt(prompt) ?? prompt
            
            // Generate tokens
            var result = ""
            for try await token in model.generate(formattedPrompt, configuration: configuration) {
                result += token
            }
            
            return result
        } catch {
            return "Error generating text: \(error.localizedDescription)"
        }
    }
}
```

## Step 8: Connect ViewModel to UI

Update your ContentView to use the ViewModel:

```swift
struct ContentView: View {
    @StateObject private var viewModel = ModelViewModel()
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isGenerating = false
    @State private var selectedModel = "Qwen2-1.5B-Instruct-4bit"
    
    let availableModels = [
        "Qwen2-1.5B-Instruct-4bit",
        "phi3-mini-4k-instruct-4bit"
    ]
    
    var body: some View {
        VStack {
            Text("MLX Model Demo")
                .font(.largeTitle)
            
            if viewModel.isLoading {
                ProgressView(value: viewModel.loadingProgress, total: 1.0) {
                    Text(viewModel.loadingMessage)
                }
                .padding()
            } else if !viewModel.isReady {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                
                Button("Load Model") {
                    Task {
                        await viewModel.loadModel(name: selectedModel)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(viewModel.modelInfo)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                
                TextEditor(text: $inputText)
                    .frame(height: 100)
                    .border(Color.gray)
                    .padding(.horizontal)
                
                Button("Generate") {
                    isGenerating = true
                    Task {
                        let result = await viewModel.generateText(prompt: inputText)
                        await MainActor.run {
                            outputText = result
                            isGenerating = false
                        }
                    }
                }
                .disabled(isGenerating || inputText.isEmpty)
                .buttonStyle(.borderedProminent)
                
                if isGenerating {
                    ProgressView("Generating...")
                }
                
                TextEditor(text: $outputText)
                    .frame(height: 200)
                    .border(Color.gray)
                    .padding()
                    .disabled(true)
            }
        }
        .padding()
    }
}
```

## Step 9: Building a VLM App

For a Vision Language Model app, follow similar steps but with these modifications:

1. Import the MLXVLM library instead of MLXLLM
2. Add UI components for image selection
3. Use VLMModel instead of LLMModel
4. Process images for model input

Basic image selection UI example:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ImagePickerView: View {
    @Binding var selectedImage: NSImage?
    @State private var isPresented = false
    
    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(Text("No image selected"))
            }
            
            Button("Select Image") {
                isPresented = true
            }
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else { return }
                
                if selectedFile.startAccessingSecurityScopedResource() {
                    let image = NSImage(contentsOf: selectedFile)
                    selectedImage = image
                    selectedFile.stopAccessingSecurityScopedResource()
                }
            } catch {
                print("Error selecting file: \(error.localizedDescription)")
            }
        }
    }
}
```

## Step 10: Build and Test

1. Build your app in Xcode (⌘B)
2. Run your app (⌘R)
3. Test with different models and prompts

## Common Issues and Solutions

### Memory-Related Crashes
- Set proper GPU cache limits with `MLX.GPU.set(cacheLimit:)`
- Build in Release mode for better performance with large models

### Model Download Issues
- Check your internet connection
- Verify the model name is correct on Hugging Face
- Ensure you have sufficient disk space

### Slow Performance
- Use quantized models (4-bit or 8-bit) for better performance
- Set reasonable generation parameters (lower max tokens)
- Build in Release mode

## Learning Path for Beginners

1. **Start by modifying** the existing LLMEval instead of building from scratch
   - Copy the example project and modify it gradually
   - Run the original app to understand its behavior

2. **Make incremental changes**
   - Start with UI modifications
   - Then modify model loading
   - Finally customize token generation

3. **Reference the key files**
   - `Applications/LLMEval/ContentView.swift` - Main UI
   - `Applications/LLMEval/LLMEvalApp.swift` - App setup
   - `Libraries/MLXLMCommon/ModelContainer.swift` - Model loading
   - `Libraries/MLXLLM/LLMModelFactory.swift` - Model factory pattern

## Resources for Further Learning

- [MLX Swift Documentation](https://ml-explore.github.io/mlx-swift/documentation/mlx/)
- [Swift Transformers Documentation](https://github.com/huggingface/swift-transformers)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [Hugging Face Models](https://huggingface.co/models)