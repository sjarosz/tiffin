# AI Chat Setup Guide for Tiffin

This guide explains how to complete the AI chat integration in your Tiffin app. The basic infrastructure has been added, but you need to add a local LLM package dependency and activate the real LLM functionality.

## Overview

The AI chat functionality allows users to query their transcribed recordings with natural language questions like:
- "What did I discuss about bananas last week?"
- "When did I mention the project deadline?"
- "Find conversations about machine learning"

## Architecture

The implementation consists of:

1. **AIManager.swift** - Handles LLM interactions and transcript search
2. **ChatView.swift** - SwiftUI chat interface  
3. **ContentView.swift** - Updated with AI Chat button and integration
4. **AudioRecording model** - Enhanced with transcript path storage

## Setup Options

### Option A: Kuzco (Recommended - More Stable)

**Kuzco** is a newer, more polished Swift wrapper around llama.cpp that's more stable than LocalLLMClient.

#### 1. Add Kuzco Package Dependency

In Xcode:
1. Go to **File > Add Package Dependencies**
2. Enter URL: `https://github.com/jaredcassoutt/Kuzco.git`
3. Select "Up to Next Major" with version 1.0.0+
4. Add the **Kuzco** target to your app

#### 2. Update AIManager.swift for Kuzco

Replace the imports and implementation:

```swift
import Kuzco

// In AIManager class
private var kuzco: Kuzco?

// Update loadModel() method:
private func loadModel() async {
    guard !isModelLoaded else { return }
    
    do {
        self.kuzco = Kuzco.shared
        
        // You'll need to download a model first
        // For now, we'll simulate loading
        self.isModelLoaded = true
        self.logger.info("Kuzco initialized successfully")
    } catch {
        self.logger.error("Failed to initialize Kuzco: \(error)")
    }
}

// Update generateResponse() method:
private func generateResponse(to userMessage: String, 
                            context: [TranscriptSearchResult]) async {
    guard let kuzco = self.kuzco else {
        await MainActor.run {
            currentResponse = "Model not loaded. Please try again."
        }
        return
    }
    
    let systemPrompt = buildSystemPrompt(with: context)
    let dialogue = [
        Turn(role: .system, text: systemPrompt),
        Turn(role: .user, text: userMessage)
    ]
    
    do {
        // You'll need to specify a model profile
        // This is a placeholder - you'll need to set up your model
        let stream = try await kuzco.predict(
            dialogue: dialogue,
            with: ModelProfile(sourcePath: "/path/to/model.gguf", architecture: .llama3),
            instanceSettings: .performanceFocused,
            predictionConfig: .creative
        )
        
        for try await token in stream {
            await MainActor.run {
                currentResponse += token
            }
        }
    } catch {
        logger.error("Kuzco generation error: \(error)")
        await MainActor.run {
            currentResponse = "Sorry, I encountered an error processing your request."
        }
    }
}
```

### Option B: LocalLLMClient (Fixed Version)

If you prefer to continue with LocalLLMClient, here's the corrected setup:

#### 1. Add LocalLLMClient Package (Fixed)

In Xcode:
1. Go to **File > Add Package Dependencies**
2. Enter URL: `https://github.com/tattn/LocalLLMClient.git`
3. **Important**: Select "Branch" and enter `main` (not version numbers)
4. Click "Add Anyway" when you see the unstable dependencies warning
5. You should see the **LocalLLMClient** package added (it contains multiple modules internally)

#### 2. Update AIManager.swift for LocalLLMClient

```swift
import LocalLLMClient
import LocalLLMClientLlama
import LocalLLMClientUtility

// In loadModel() method, replace simulation with:
do {
    // Download model if needed
    let modelName = "phi-3-mini-4k-instruct-q4_0.gguf"
    let downloader = FileDownloader(source: .huggingFace(
        id: "microsoft/Phi-3-mini-4k-instruct-gguf",
        globs: [modelName]
    ))
    
    try await downloader.download { progress in
        self.logger.info("Download progress: \(progress)")
    }
    
    // Initialize LLM client
    let modelURL = downloader.destination.appending(component: modelName)
    self.llmClient = try await LocalLLMClient.llama(url: modelURL, parameter: .init(
        context: 4096,
        temperature: 0.7,
        topK: 40,
        topP: 0.9
    ))
    
    self.isModelLoaded = true
    self.logger.info("LLM model loaded successfully")
} catch {
    self.logger.error("Failed to load LLM model: \(error)")
}

// In generateResponse() method:
let input = LLMInput.chat([
    .system(systemPrompt),
    .user(userMessage)
])

do {
    for try await token in try await llmClient?.textStream(from: input) ?? [] {
        await MainActor.run {
            currentResponse += token
        }
    }
} catch {
    logger.error("LLM generation error: \(error)")
    await MainActor.run {
        currentResponse = "Sorry, I encountered an error processing your request."
    }
}
```

## Why You're Seeing Only One Package

When you add LocalLLMClient, Xcode shows it as one package because it's structured as a single repository with multiple Swift modules (LocalLLMClient, LocalLLMClientLlama, LocalLLMClientUtility). These are automatically available once you add the main package.

## Recommended Approach

I recommend **Option A (Kuzco)** because:
- More stable and production-ready
- Better documentation and examples
- Cleaner API design
- Active development and support

## Next Steps

1. Choose either Option A or B above
2. Add the package dependency to your project
3. Update the AIManager.swift code accordingly
4. Test the integration

## Model Download and Setup

Both options will need you to:
1. Download an appropriate GGUF model file (2-4GB)
2. Place it in your app's documents directory
3. Update the model path in the code

**Recommended starter model**: Phi-3-Mini-4K-Instruct (Q4_0 quantized) - good balance of quality and performance.

Let me know which option you'd like to proceed with, and I can provide more specific setup instructions!

## Summary

This setup provides:
- ✅ Chat interface with streaming responses
- ✅ Transcript search and context building  
- ✅ Beautiful macOS-native UI
- ✅ Integration with existing recording/transcription workflow
- ✅ Local processing (privacy-focused)

## Usage

1. **Record and Transcribe**: Use the main app to record and transcribe conversations
2. **Open AI Chat**: Click the "AI Chat" button in the header  
3. **Ask Questions**: Type natural language questions about your recordings
4. **Get Answers**: The AI will search your transcripts and provide contextual answers

## Performance Notes

- **First Launch**: Model download may take several minutes (2-4GB)
- **Apple Silicon**: Optimized for M1/M2/M3 chips with Metal acceleration
- **Memory Usage**: Recommend 8GB+ RAM for best performance
- **Privacy**: All processing happens locally - no data sent to external services

## Troubleshooting

- If packages fail to resolve, clean build folder and try again
- Ensure adequate disk space (models require 2-4GB)
- Check internet connection for initial model download

---

This AI chat functionality provides powerful querying capabilities for your recorded content while maintaining complete privacy through local processing. 