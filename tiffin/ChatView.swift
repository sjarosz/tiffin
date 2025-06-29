import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var aiManager = AIManager()
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader
            
            // Messages
            messagesView
            
            // Input
            inputView
        }
        .navigationTitle("Tiffin AI")
        .background(Color(.controlBackgroundColor))
    }
    
    private var chatHeader: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Close")
                
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Tiffin AI")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear Chat") {
                    aiManager.clearChat()
                }
                .foregroundColor(.secondary)
            }
            .padding()
            
            Text("Ask questions about your recorded conversations")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if aiManager.chatMessages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(aiManager.chatMessages) { message in
                            ChatMessageView(message: message)
                        }
                        
                        // Show streaming response
                        if aiManager.isProcessing && !aiManager.currentResponse.isEmpty {
                            ChatMessageView(message: ChatMessage(
                                role: .assistant,
                                content: aiManager.currentResponse,
                                timestamp: Date()
                            ), isStreaming: true)
                        }
                        
                        // Typing indicator
                        if aiManager.isProcessing && aiManager.currentResponse.isEmpty {
                            TypingIndicatorView()
                        }
                    }
                }
                .padding()
            }
            .onChange(of: aiManager.chatMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: aiManager.currentResponse) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .overlay(
                // Invisible anchor for scrolling
                HStack {
                    Spacer()
                }
                .id("bottom"),
                alignment: .bottom
            )
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Ask about your recordings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("I can help you find information from your transcribed audio recordings. Try asking:")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                ExampleQuestionView(text: "What did I discuss about bananas last week?")
                ExampleQuestionView(text: "When did I mention the project deadline?")
                ExampleQuestionView(text: "Find conversations about machine learning")
                ExampleQuestionView(text: "What meetings did I have yesterday?")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var inputView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separatorColor))
            
            HStack(spacing: 12) {
                TextField("Ask about your recordings...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiManager.isProcessing ? .secondary : .blue)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiManager.isProcessing)
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
    }
    
    private func sendMessage() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !aiManager.isProcessing else { return }
        
        messageText = ""
        isTextFieldFocused = false
        
        Task {
            await aiManager.sendMessage(message, context: modelContext)
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.role == .assistant {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Text(message.role == .user ? "You" : "Tiffin AI")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separatorColor), lineWidth: 0.5)
                    )
                    .overlay(
                        // Streaming cursor
                        Group {
                            if isStreaming {
                                Text("|")
                                    .foregroundColor(.blue)
                                    .opacity(0.7)
                                    .animation(.easeInOut(duration: 1).repeatForever(), value: isStreaming)
                            }
                        },
                        alignment: .trailing
                    )
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ExampleQuestionView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct TypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("Tiffin AI")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Spacer(minLength: 60)
        }
        .overlay(
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(animationPhase == index ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever(), value: animationPhase)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            ),
            alignment: .leading
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

#Preview {
    ChatView()
        .modelContainer(for: AudioRecording.self, inMemory: true)
} 