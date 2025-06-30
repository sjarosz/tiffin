# AI Chat Setup Guide for Tiffin

This guide explains how to complete the AI chat integration in your Tiffin app using **Kuzco** for local LLM functionality.

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
4. **AudioRecording model** - Enhanced with transcript paths for AI search

## ✅ Current Status

- ✅ Kuzco package integrated
- ✅ Chat interface working with simulated responses
- ✅ Transcript search and RAG system ready
- ✅ Close button added to chat interface

## 📋 Next Steps: Model Setup

### Step 1: Download the Model

You need to download a GGUF format model. **Recommended**: Phi-3-Mini-4K-Instruct

**Download this model:**
- **Model**: `phi-3-mini-4k-instruct-q4_0.gguf`
- **Size**: ~2.4GB
- **Quality**: Good balance of performance and accuracy for Apple Silicon

**Download Sources:**
1. **Hugging Face** (recommended): https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4_0.gguf
2. **Alternative**: https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_0.gguf

### Step 2: Model Placement

Create a models directory in your project and place the downloaded file:

```bash
# Create models directory
mkdir -p ~/Documents/Tiffin/models

# Place your downloaded model here:
~/Documents/Tiffin/models/phi-3-mini-4k-instruct-q4_0.gguf
```

### Step 3: Verify Download

The model file should be approximately **2.4GB**. You can verify with:

```bash
ls -lh ~/Documents/Tiffin/models/
```

## 🚀 What Happens Next

Once you've downloaded the model and confirmed it's in the correct location, I'll:

1. **Update AIManager.swift** to use the real Kuzco LLM instead of simulation
2. **Configure the model path** to point to your downloaded file
3. **Enable real AI responses** that search and reference your transcripts
4. **Test the integration** to ensure everything works smoothly

## 📁 Directory Structure

After setup, your structure should look like:
```
~/Documents/Tiffin/
└── models/
    └── phi-3-mini-4k-instruct-q4_0.gguf  (2.4GB)
```

## 🔧 Technical Details

- **Framework**: Kuzco (Swift wrapper for llama.cpp)
- **GPU Acceleration**: Automatic via Metal on Apple Silicon
- **Memory Usage**: ~4GB RAM during inference
- **Privacy**: 100% local processing, no cloud calls

---

**Ready?** Download the model file to the specified path and let me know when it's complete!

 