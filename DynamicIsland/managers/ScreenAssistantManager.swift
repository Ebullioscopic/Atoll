/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI
import AVFoundation
import Defaults
import Foundation
import UniformTypeIdentifiers

// Chat message model
struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    var content: String
    var reasoning: String = ""
    var tools: [String] = []
    var notice: String?
    var includeInContext = true
    let isFromUser: Bool
    let timestamp: Date
    let attachedFiles: [ScreenAssistantFile]?
    
    init(content: String, isFromUser: Bool, attachedFiles: [ScreenAssistantFile]? = nil) {
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()
        self.attachedFiles = attachedFiles
    }
}

// Screen Assistant item data structure
struct ScreenAssistantFile: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: FileType
    let timestamp: Date
    let fileURL: String? // For local files
    let audioFileName: String? // For audio recordings
    
    enum FileType: String, CaseIterable, Codable {
        case document = "document"
        case image = "image"
        case audio = "audio"
        case video = "video"
        case other = "other"
        
        var iconName: String {
            switch self {
            case .document: return "doc.text"
            case .image: return "photo"
            case .audio: return "waveform"
            case .video: return "video"
            case .other: return "doc"
            }
        }
        
        var displayName: String {
            switch self {
            case .document: return String(localized: "Document")
            case .image: return String(localized: "Image")
            case .audio: return String(localized: "Audio")
            case .video: return String(localized: "Video")
            case .other: return String(localized: "File")
            }
        }
    }
    
    init(fileURL: URL) {
        // Defensive initialization with nil coalescing
        self.name = fileURL.lastPathComponent.isEmpty ? "Unknown File" : fileURL.lastPathComponent
        self.fileURL = fileURL.absoluteString
        self.audioFileName = nil
        self.timestamp = Date()
        
        // Safe file extension extraction
        let fileExtension = fileURL.pathExtension.lowercased()
        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif":
            self.type = .image
        case "mp3", "wav", "m4a", "aac", "flac":
            self.type = .audio
        case "mp4", "mov", "avi", "mkv":
            self.type = .video
        case "txt", "md", "pdf", "doc", "docx", "rtf":
            self.type = .document
        default:
            self.type = .other
        }
        
        print("✅ ScreenAssistantFile: Created file entry - name: \(self.name), type: \(self.type), url: \(self.fileURL ?? "nil")")
    }
    
    init(audioFileName: String, name: String) {
        self.name = name
        self.type = .audio
        self.fileURL = nil
        self.audioFileName = audioFileName
        self.timestamp = Date()
    }
}

class ScreenAssistantManager: NSObject, ObservableObject {
    static let shared = ScreenAssistantManager()
    
    @Published var attachedFiles: [ScreenAssistantFile] = []
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    
    @Published var responseStatus = ""
    @Published var actualModelName: String?
    @Published var isBridge = false
    @Published var isControlling = false
    @Published var controlError: String?
    private var chatTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var requestGeneration = UUID()
    private var bridgeSessionID = UUID().uuidString
    private var activeBridge: (base: URL, session: String, job: String)?
    private var bridgeBase: URL?
    private var pendingControl: (base: URL, session: String, job: String, reset: Bool)?
    private var streamedMessageID: UUID?
    private var modelSelectionPanel: ModelSelectionPanel?

    @Published var draftMessage = ""
    @Published var attachmentError: String?
    @Published private(set) var pendingAttachments = 0
    private let attachmentQueue = DispatchQueue(label: "Atoll.chat-attachments", qos: .userInitiated)
    private var attachmentGeneration = UUID()

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var activeRequest: URLSessionTask?
    
    // Panel management
    private var chatInputPanel: ChatInputPanel?
    
    // Directory for storing audio recordings
    static let audioDataDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDir = documentsPath.appendingPathComponent("ScreenAssistantAudio")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        
        return audioDir
    }()
    
    // Directory for storing screenshots
    static let screenshotDataDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotDir = documentsPath.appendingPathComponent("ScreenAssistantScreenshots")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        
        return screenshotDir
    }()
    
    private override init() {
        super.init()
        loadFilesFromDefaults()
    }
    
    deinit {
        stopRecording()
        closePanels()
    }
    
    // MARK: - Panel Management
    
    func showPanels() {
        // Close existing panels first
        closePanels()
        
        // Conversation and composer share one resizable native window.
        chatInputPanel = ChatInputPanel()
        chatInputPanel?.positionInCenter()
        NSApp.activate(ignoringOtherApps: true)
        chatInputPanel?.makeKeyAndOrderFront(nil)
        
        // Focus on input panel for immediate typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.chatInputPanel?.makeKey()
        }
    }
    
    func showModelSelection() {
        guard !isLoading, !isControlling, !isRecording else { return }
        // Recreate so cancelling unsaved edits cannot leak into the next visit.
        modelSelectionPanel?.close()
        modelSelectionPanel = ModelSelectionPanel()
        modelSelectionPanel?.positionInCenter()
        modelSelectionPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var imagesOnly: Bool { [.deepseek, .local].contains(Defaults[.selectedAIProvider]) }
    var canRetry: Bool { !isLoading && !isControlling && controlError == nil && chatMessages.last?.notice != nil }

    func toggleWindowZoom() { chatInputPanel?.zoom(nil) }

    func closePanels() {
        chatInputPanel?.close()
        chatInputPanel = nil
    }
    
    func arePanelsVisible() -> Bool {
        return chatInputPanel?.isVisible == true
    }
    
    // MARK: - File Management
    
    func addFiles(_ urls: [URL]) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.addFiles(urls) }
            return
        }
        for url in urls { importAttachment { try ChatAttachmentImport.prepare(file: url) } }
    }

    func addImageData(_ data: Data) {
        importAttachment { try ChatAttachmentImport.prepare(data: data) }
    }

    private func importAttachment(_ prepare: @escaping () throws -> URL) {
        pendingAttachments += 1
        attachmentError = nil
        let generation = attachmentGeneration
        attachmentQueue.async {
            let result = Result { try prepare() }
            DispatchQueue.main.async {
                self.pendingAttachments -= 1
                guard generation == self.attachmentGeneration else {
                    if case .success(let url) = result { ChatAttachmentImport.removeOwnedFile(url) }
                    return
                }
                switch result {
                case .success(let url):
                    let file = ScreenAssistantFile(fileURL: url)
                    if self.imagesOnly && file.type != .image {
                        ChatAttachmentImport.removeOwnedFile(url)
                        self.attachmentError = String(localized: "This model accepts images only. Documents and audio cannot be attached.")
                        return
                    }
                    if file.type == .image && self.attachedFiles.filter({ $0.type == .image }).count >= ChatAttachmentImport.maximumImages {
                        ChatAttachmentImport.removeOwnedFile(url)
                        self.attachmentError = String(localized: "Attach up to 8 images per message.")
                        return
                    }
                    guard !self.attachedFiles.contains(where: { $0.fileURL == url.absoluteString }) else { return }
                    self.attachedFiles.append(file)
                    self.saveFilesToDefaults()
                case .failure(let error): self.attachmentError = error.localizedDescription
                }
            }
        }
    }

    /// Handles Finder files and actual image data from browsers or other apps.
    @discardableResult
    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        for provider in supported {
            pendingAttachments += 1
            let generation = attachmentGeneration
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    DispatchQueue.main.async {
                        self.pendingAttachments -= 1
                        guard generation == self.attachmentGeneration else { return }
                        if let data, let url = URL(dataRepresentation: data, relativeTo: nil) { self.addFiles([url]) }
                        else { self.attachmentError = error?.localizedDescription ?? "This file could not be imported." }
                    }
                }
            } else {
                let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    DispatchQueue.main.async {
                        self.pendingAttachments -= 1
                        guard generation == self.attachmentGeneration else { return }
                        if let data { self.addImageData(data) }
                        else { self.attachmentError = error?.localizedDescription ?? "This image could not be imported." }
                    }
                }
            }
        }
        return !supported.isEmpty
    }

    @discardableResult
    func acceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addFiles(urls)
            return true
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { addImageData(data); return true }
        }
        return false
    }

    func removeFile(_ file: ScreenAssistantFile) {
        attachedFiles.removeAll { $0.id == file.id }
        if let path = file.fileURL, let url = URL(string: path) { ChatAttachmentImport.removeOwnedFile(url) }
        
        // Clean up audio file if it exists
        if let audioFileName = file.audioFileName {
            let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(audioFileName)
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        saveFilesToDefaults()
    }
    
    func clearAllFiles() {
        // Clean up all audio files
        for file in attachedFiles {
            if let path = file.fileURL, let url = URL(string: path) { ChatAttachmentImport.removeOwnedFile(url) }
            if let audioFileName = file.audioFileName {
                let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        
        attachedFiles.removeAll()
        saveFilesToDefaults()
    }
    
    // MARK: - Audio Recording
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let audioURL = ScreenAssistantManager.audioDataDirectory.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isRecording = true
            recordingDuration = 0
            
            // Start timer for recording duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateRecordingDuration()
            }
            
            print("Started recording: \(fileName)")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        
        print("Stopped recording")
    }
    
    private func updateRecordingDuration() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recordingDuration = recorder.currentTime
    }
    
    // MARK: - Persistence
    
    private func saveFilesToDefaults() {
        do {
            let encoded = try JSONEncoder().encode(attachedFiles)
            UserDefaults.standard.set(encoded, forKey: "ScreenAssistantFiles")
            print("✅ ScreenAssistant: Saved \(attachedFiles.count) files to UserDefaults")
        } catch {
            print("❌ ScreenAssistant: Failed to save files to UserDefaults - \(error)")
            // Don't throw - this is a non-critical operation
        }
    }
    
    private func loadFilesFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "ScreenAssistantFiles"),
              let decoded = try? JSONDecoder().decode([ScreenAssistantFile].self, from: data) else {
            return
        }
        
        attachedFiles = decoded
    }
    
    // MARK: - Chat Management
    
    @discardableResult
    func sendMessage(_ message: String) -> Bool {
        guard !isLoading, !isControlling, controlError == nil, pendingAttachments == 0,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty else { return false }
        guard validateDraft() else { return false }
        print("📤 ScreenAssistant: Sending message")
        print("📁 ScreenAssistant: Attached files count: \(attachedFiles.count)")
        
        // Add user message to chat
        let userMessage = ChatMessage(content: message, isFromUser: true, attachedFiles: attachedFiles.isEmpty ? nil : attachedFiles)
        chatMessages.append(userMessage)
        
        // Print attached files details
        for (index, file) in attachedFiles.enumerated() {
            print("📎 ScreenAssistant: File \(index + 1): \(file.name) (\(file.type.displayName))")
        }
        
        // Clear input and files after sending
        let currentFiles = attachedFiles
        // Keep files referenced by sent messages available to the API and previews.
        attachedFiles.removeAll()
        attachmentError = nil
        saveFilesToDefaults()
        
        // Send to appropriate AI API based on selected provider
        let provider = Defaults[.selectedAIProvider]
        sendToAI(message: message, files: currentFiles, provider: provider)
        return true
    }

    private func validateDraft() -> Bool {
        let provider = Defaults[.selectedAIProvider]
        if imagesOnly, attachedFiles.contains(where: { $0.type != .image }) {
            attachmentError = String(localized: "This model accepts images only. Remove unsupported attachments before sending.")
            return false
        }
        if provider == .deepseek && !DeepSeekConfiguration.isValid(endpoint: Defaults[.deepseekEndpoint], model: Defaults[.deepseekModel], apiKey: AICredentialStore.shared.key(for: .deepseek)) {
            attachmentError = String(localized: "Configure the DeepSeek endpoint, model and API key before sending.")
            return false
        }
        if provider == .local && ChatRequestBuilder.localBase(Defaults[.localModelEndpoint]) == nil {
            attachmentError = String(localized: "Configure a valid local model endpoint before sending.")
            return false
        }
        return true
    }
    
    private func sendToAI(message: String, files: [ScreenAssistantFile], provider: AIModelProvider) {
        print("🚀 ScreenAssistant: Making API request to \(provider.displayName)")
        requestGeneration = UUID()
        responseStatus = String(localized: "Connecting…")
        actualModelName = nil
        isLoading = true
        
        switch provider {
        case .gemini:
            sendToGeminiAPI(message: message, files: files)
        case .openai:
            sendToOpenAIAPI(message: message, files: files)
        case .claude:
            sendToClaudeAPI(message: message, files: files)
        case .local:
            sendToLocalAPI(message: message, files: files)
        case .deepseek:
            sendToDeepSeekAPI(message: message, files: files)
        case .groq:
            sendToGroqAPI(message: message, files: files)
        }
    }
    
    private func sendToGeminiAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = AICredentialStore.shared.key(for: .gemini)
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No Gemini API key configured")
            addAssistantMessage("Error: No Gemini API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to gemini-2.5-flash
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", supportsThinking: true)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent?key=\(apiKey)") else {
            print("❌ ScreenAssistant: Invalid Gemini API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performAPIRequest(url: url, requestBody: buildGeminiRequestBody(message: message, files: files), provider: .gemini)
    }
    
    private func sendToOpenAIAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = AICredentialStore.shared.key(for: .openai)
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No OpenAI API key configured")
            addAssistantMessage("Error: No OpenAI API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to gpt-4o
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "gpt-4o", name: "GPT-4o", supportsThinking: false)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            print("❌ ScreenAssistant: Invalid OpenAI API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performOpenAIRequest(url: url, requestBody: buildOpenAIRequestBody(message: message, files: files, model: modelId), apiKey: apiKey)
    }

    private func sendToDeepSeekAPI(message: String, files: [ScreenAssistantFile]) {
        startModernChat(provider: .deepseek)
    }

    private func sendToGroqAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = AICredentialStore.shared.key(for: .groq)
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No Groq API key configured")
            addAssistantMessage("Error: No Groq API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to llama-3.3-70b-versatile
        let selectedModel = Defaults[.selectedAIModel]
        let modelId: String
        if let selectedId = selectedModel?.id,
           AIModelProvider.groq.supportedModels.contains(where: { $0.id == selectedId }) {
            modelId = selectedId
        } else {
            modelId = "llama-3.3-70b-versatile"
        }
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            print("❌ ScreenAssistant: Invalid Groq API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performOpenAIRequest(
            url: url,
            requestBody: buildOpenAIRequestBody(message: message, files: files, model: modelId),
            apiKey: apiKey,
            provider: .groq
        )
    }
    
    private func sendToClaudeAPI(message: String, files: [ScreenAssistantFile]) {
        let apiKey = AICredentialStore.shared.key(for: .claude)
        guard !apiKey.isEmpty else {
            print("❌ ScreenAssistant: No Claude API key configured")
            addAssistantMessage("Error: No Claude API key configured. Please set your API key in model settings.")
            isLoading = false
            return
        }
        
        // Get selected model or default to claude-3-5-sonnet
        let selectedModel = Defaults[.selectedAIModel] ?? AIModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", supportsThinking: false)
        let modelId = selectedModel.id
        
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            print("❌ ScreenAssistant: Invalid Claude API URL")
            addAssistantMessage("Error: Invalid API URL")
            isLoading = false
            return
        }
        
        performClaudeRequest(url: url, requestBody: buildClaudeRequestBody(message: message, files: files, model: modelId), apiKey: apiKey)
    }
    
    private func sendToLocalAPI(message: String, files: [ScreenAssistantFile]) {
        startModernChat(provider: .local)
    }

    // MARK: - API Request Builders
    
    private func buildGeminiRequestBody(message: String, files: [ScreenAssistantFile]) -> [String: Any] {
        var contents: [[String: Any]] = []
        
        // Add previous conversation messages (last 10 for context)
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id { // Don't include the message we just added
                let role = chatMessage.isFromUser ? "user" : "model"
                contents.append([
                    "role": role,
                    "parts": [["text": chatMessage.content]]
                ])
            }
        }
        
        // Build current message parts
        var parts: [[String: Any]] = []
        
        // Add text part
        let contextualMessage = buildContextualMessage(message: message, files: files)
        parts.append(["text": contextualMessage])
        
        // Add file content for supported types using proper Gemini 2.5 APIs
        for file in files {
            if let filePart = createGeminiFilePart(for: file) {
                parts.append(filePart)
                print("📎 ScreenAssistant: Added file part for \(file.name)")
            }
        }
        
        // Add current message
        contents.append([
            "role": "user",
            "parts": parts
        ])
        
        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "topP": 0.8,
                "topK": 40,
                "maxOutputTokens": 2048,
                "responseMimeType": "text/plain"
            ],
            "safetySettings": [
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH", 
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                ]
            ]
        ]
        
        // Add thinking configuration if enabled and model supports it
        let selectedModel = Defaults[.selectedAIModel]
        if selectedModel?.supportsThinking == true && Defaults[.enableThinkingMode] {
            requestBody["generationConfig"] = (requestBody["generationConfig"] as! [String: Any]).merging([
                "thinkingConfig": [
                    "thinkingBudget": 0 // 0 means unlimited thinking
                ]
            ]) { (_, new) in new }
        }
        
        return requestBody
    }
    
    private func buildOpenAIRequestBody(message: String, files: [ScreenAssistantFile], model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        
        // Add previous conversation messages (last 10 for context)
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id {
                let role = chatMessage.isFromUser ? "user" : "assistant"
                messages.append([
                    "role": role,
                    "content": chatMessage.content
                ])
            }
        }
        
        // Add current message
        let contextualMessage = buildContextualMessage(message: message, files: files)
        messages.append([
            "role": "user",
            "content": contextualMessage
        ])
        
        return [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 2048
        ]
    }
    
    private func buildClaudeRequestBody(message: String, files: [ScreenAssistantFile], model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        
        // Add previous conversation messages (last 10 for context)
        let recentMessages = Array(chatMessages.suffix(10))
        for chatMessage in recentMessages {
            if chatMessage.id != chatMessages.last?.id {
                let role = chatMessage.isFromUser ? "user" : "assistant"
                messages.append([
                    "role": role,
                    "content": chatMessage.content
                ])
            }
        }
        
        // Add current message
        let contextualMessage = buildContextualMessage(message: message, files: files)
        messages.append([
            "role": "user",
            "content": contextualMessage
        ])
        
        return [
            "model": model,
            "max_tokens": 2048,
            "messages": messages
        ]
    }
    
    private func imageAttachments(_ files: [ScreenAssistantFile]) throws -> [ImageAttachment] {
        guard files.count <= 8 else {
            throw NSError(domain: "Attachments", code: 1, userInfo: [NSLocalizedDescriptionKey: "Send at most 8 images."])
        }
        return try files.map { file in
            guard file.type == .image, let path = file.fileURL, let url = URL(string: path), url.isFileURL else {
                throw NSError(domain: "Attachments", code: 2, userInfo: [NSLocalizedDescriptionKey: "This integration supports image attachments only."])
            }
            return try ImageAttachment(data: Data(contentsOf: url))
        }
    }

    // MARK: - API Request Performers
    
    private func performAPIRequest(url: URL, requestBody: [String: Any], provider: AIModelProvider) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
            
            print("📋 ScreenAssistant: Request body size: \(jsonData.count) bytes")
        } catch {
            print("❌ ScreenAssistant: Failed to encode request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: provider)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    private func performOpenAIRequest(url: URL, requestBody: [String: Any], apiKey: String, provider: AIModelProvider = .openai) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
        } catch {
            print("❌ ScreenAssistant: Failed to encode OpenAI request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        performChatRequest(request, provider: provider)
    }

    private func performChatRequest(_ request: URLRequest, provider: AIModelProvider) {
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: provider)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    private func performClaudeRequest(url: URL, requestBody: [String: Any], apiKey: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
            request.httpBody = jsonData
        } catch {
            print("❌ ScreenAssistant: Failed to encode Claude request - \(error)")
            addAssistantMessage("Error: Failed to encode request - \(error.localizedDescription)")
            isLoading = false
            return
        }
        
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTask = task else { return }
                
                // Ensure this callback belongs to the current in-flight request
                guard self.activeRequest === currentTask else { return }
                
                self.isLoading = false
                self.activeRequest = nil
                
                self.handleResponse(data: data, response: response, error: error, provider: .claude)
            }
        }
        
        activeRequest = task
        task?.resume()
    }
    
    // MARK: - Response Handlers
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, provider: AIModelProvider) {
        // Check if the request was cancelled (e.g., by resetConversationContext)
        if let error = error as? NSError, error.code == NSURLErrorCancelled {
            print("ℹ️ ScreenAssistant: Request was cancelled")
            return
        }
        
        if let error = error {
            print("❌ ScreenAssistant: Network error - \(error)")
            addAssistantMessage("Error: \(error.localizedDescription)")
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 ScreenAssistant: HTTP Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                handleAPIError(statusCode: httpResponse.statusCode, provider: provider)
                return
            }
        }
        
        guard let data = data else {
            print("❌ ScreenAssistant: No response data")
            addAssistantMessage("Error: No response data")
            return
        }
        
        print("📨 ScreenAssistant: Response data size: \(data.count) bytes")
        
        // Parse response based on provider
        switch provider {
        case .gemini:
            parseGeminiResponse(data: data)
        case .openai, .groq, .deepseek:
            parseOpenAIResponse(data: data)
        case .claude:
            parseClaudeResponse(data: data)
        case .local:
            parseOllamaResponse(data: data)
        }
    }
    
    private func parseGeminiResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed Gemini JSON response")
                
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    
                    print("✅ ScreenAssistant: Got Gemini response text: \(text.prefix(100))...")
                    addAssistantMessage(text)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleAPIError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected Gemini response format")
                        addAssistantMessage("Error: Unexpected response format from Gemini")
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: Gemini JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func parseOpenAIResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed OpenAI JSON response")
                
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    print("✅ ScreenAssistant: Got OpenAI response text: \(content.prefix(100))...")
                    addAssistantMessage(content)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleOpenAIError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected OpenAI response format")
                        addAssistantMessage("Error: Unexpected response format from OpenAI")
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: OpenAI JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func parseClaudeResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed Claude JSON response")
                
                if let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    
                    print("✅ ScreenAssistant: Got Claude response text: \(text.prefix(100))...")
                    addAssistantMessage(text)
                } else {
                    if let error = json["error"] as? [String: Any] {
                        handleClaudeError(error: error)
                    } else {
                        print("❌ ScreenAssistant: Unexpected Claude response format")
                        addAssistantMessage("Error: Unexpected response format from Claude")
                    }
                }
            }
        } catch {
            print("❌ ScreenAssistant: Claude JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func parseOllamaResponse(data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ ScreenAssistant: Successfully parsed Ollama JSON response")
                
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    print("✅ ScreenAssistant: Got Ollama response text: \(content.prefix(100))...")
                    addAssistantMessage(content)
                } else {
                    print("❌ ScreenAssistant: Unexpected Ollama response format")
                    addAssistantMessage("Error: Unexpected response format from local model")
                }
            }
        } catch {
            print("❌ ScreenAssistant: Ollama JSON parsing error - \(error)")
            addAssistantMessage("Error: Failed to parse response - \(error.localizedDescription)")
        }
    }
    
    private func buildContextualMessage(message: String, files: [ScreenAssistantFile]) -> String {
        var contextualMessage = message
        
        // Add file context with specific instructions for different types
        if !files.isEmpty {
            contextualMessage += "\n\nI have attached the following files for your analysis:"
            
            var hasImages = false
            var hasDocuments = false
            var hasAudio = false
            var hasVideo = false
            
            for file in files {
                contextualMessage += "\n- \(file.name) (\(file.type.displayName))"
                
                switch file.type {
                case .image: hasImages = true
                case .document: hasDocuments = true
                case .audio: hasAudio = true
                case .video: hasVideo = true
                case .other: break
                }
            }
            
            // Add specific instructions based on file types
            contextualMessage += "\n\nPlease analyze these files in the context of my question. Specifically:"
            
            if hasImages {
                contextualMessage += "\n- For images: Describe what you see, identify objects, text, or patterns, and relate them to my question."
            }
            
            if hasDocuments {
                contextualMessage += "\n- For documents: Read and understand the content, extract key information, and provide insights relevant to my question."
            }
            
            if hasAudio {
                contextualMessage += "\n- For audio: Listen to and transcribe the audio content, identify speakers, topics, or sounds as relevant."
            }
            
            if hasVideo {
                contextualMessage += "\n- For video: Analyze both visual and audio content, describe actions, scenes, or dialogue as applicable."
            }
            
            contextualMessage += "\n\nProvide comprehensive insights that combine information from all attached files with your response to my question."
        }
        
        return contextualMessage
    }
    
    private func createGeminiFilePart(for file: ScreenAssistantFile) -> [String: Any]? {
        print("📎 ScreenAssistant: Processing file for Gemini 2.5: \(file.name) (\(file.type.displayName))")
        
        guard let fileURL = file.fileURL, let url = URL(string: fileURL) else {
            print("❌ ScreenAssistant: No valid URL for file \(file.name)")
            return ["text": "File: \(file.name) (no valid URL)"]
        }
        
        switch file.type {
        case .image:
            return createGeminiImagePart(for: url, fileName: file.name)
        case .document:
            return createGeminiDocumentPart(for: url, fileName: file.name)
        case .audio:
            return createGeminiAudioPart(for: url, fileName: file.name)
        case .video:
            return createGeminiVideoPart(for: url, fileName: file.name)
        case .other:
            return createGeminiTextPart(for: url, fileName: file.name)
        }
    }
    
    private func createGeminiImagePart(for url: URL, fileName: String) -> [String: Any]? {
        print("🖼️ ScreenAssistant: Processing image file: \(fileName)")
        
        do {
            let imageData = try Data(contentsOf: url)
            let base64String = imageData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "webp":
                mimeType = "image/webp"
            case "heic":
                mimeType = "image/heic"
            default:
                mimeType = "image/jpeg"
            }
            
            print("📎 ScreenAssistant: Image encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode image \(fileName): \(error)")
            return ["text": "Image file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiDocumentPart(for url: URL, fileName: String) -> [String: Any]? {
        print("📄 ScreenAssistant: Processing document file: \(fileName)")
        
        let pathExtension = url.pathExtension.lowercased()
        
        if pathExtension == "pdf" {
            // Handle PDF files using base64 encoding for Gemini 2.5
            do {
                let pdfData = try Data(contentsOf: url)
                let base64String = pdfData.base64EncodedString()
                
                print("📎 ScreenAssistant: PDF encoded - \(base64String.count) bytes")
                
                return [
                    "inline_data": [
                        "mime_type": "application/pdf",
                        "data": base64String
                    ]
                ]
            } catch {
                print("❌ ScreenAssistant: Failed to encode PDF \(fileName): \(error)")
                return ["text": "PDF file: \(fileName) (failed to encode: \(error.localizedDescription))"]
            }
        } else {
            // Handle text-based documents
            do {
                let content = try String(contentsOf: url)
                print("📄 ScreenAssistant: Read document content (\(content.count) characters)")
                return ["text": "File content of \(fileName):\n\(content)"]
            } catch {
                print("❌ ScreenAssistant: Failed to read document \(fileName): \(error)")
                return ["text": "Document file: \(fileName) (could not read content: \(error.localizedDescription))"]
            }
        }
    }
    
    private func createGeminiAudioPart(for url: URL, fileName: String) -> [String: Any]? {
        print("🎵 ScreenAssistant: Processing audio file: \(fileName)")
        
        do {
            let audioData = try Data(contentsOf: url)
            let base64String = audioData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "mp3":
                mimeType = "audio/mpeg"
            case "wav":
                mimeType = "audio/wav"
            case "m4a":
                mimeType = "audio/mp4"
            case "aac":
                mimeType = "audio/aac"
            case "flac":
                mimeType = "audio/flac"
            default:
                mimeType = "audio/mpeg"
            }
            
            print("� ScreenAssistant: Audio encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode audio \(fileName): \(error)")
            return ["text": "Audio file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiVideoPart(for url: URL, fileName: String) -> [String: Any]? {
        print("� ScreenAssistant: Processing video file: \(fileName)")
        
        do {
            let videoData = try Data(contentsOf: url)
            let base64String = videoData.base64EncodedString()
            
            // Determine MIME type
            let mimeType: String
            let pathExtension = url.pathExtension.lowercased()
            switch pathExtension {
            case "mp4":
                mimeType = "video/mp4"
            case "mov":
                mimeType = "video/quicktime"
            case "avi":
                mimeType = "video/x-msvideo"
            case "mkv":
                mimeType = "video/x-matroska"
            default:
                mimeType = "video/mp4"
            }
            
            print("📎 ScreenAssistant: Video encoded - \(base64String.count) bytes, MIME: \(mimeType)")
            
            return [
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ]
        } catch {
            print("❌ ScreenAssistant: Failed to encode video \(fileName): \(error)")
            return ["text": "Video file: \(fileName) (failed to encode: \(error.localizedDescription))"]
        }
    }
    
    private func createGeminiTextPart(for url: URL, fileName: String) -> [String: Any]? {
        print("📝 ScreenAssistant: Processing text file: \(fileName)")
        
        do {
            let content = try String(contentsOf: url)
            print("📄 ScreenAssistant: Read text content (\(content.count) characters)")
            return ["text": "File content of \(fileName):\n\(content)"]
        } catch {
            print("❌ ScreenAssistant: Failed to read text file \(fileName): \(error)")
            return ["text": "File: \(fileName) (could not read content: \(error.localizedDescription))"]
        }
    }
    
    // MARK: - Conversation transport and task controls

    private static func requestTurns(_ messages: [ChatMessage]) throws -> [ChatRequestTurn] {
        try messages.filter(\.includeInContext).map { message in
            let images = try (message.attachedFiles ?? []).map { file -> ImageAttachment in
                guard file.type == .image, let path = file.fileURL, let url = URL(string: path), url.isFileURL else {
                    throw ChatStreamChunk.failure(String(localized: "This model accepts images only. Start a new chat to switch from document or audio conversations."))
                }
                return try ImageAttachment(data: Data(contentsOf: url))
            }
            return ChatRequestTurn(role: message.isFromUser ? "user" : "assistant", text: message.content, images: images, reasoning: message.reasoning)
        }
    }

    private func startModernChat(provider: AIModelProvider) {
        let generation = requestGeneration
        let snapshot = chatMessages
        let endpoint = provider == .deepseek ? Defaults[.deepseekEndpoint] : Defaults[.localModelEndpoint]
        let selected = provider == .deepseek ? Defaults[.deepseekModel] : (Defaults[.selectedAIModel]?.id ?? "llama3.2")
        let key = AICredentialStore.shared.key(for: .deepseek)
        let vision = Defaults[.deepseekVisionModel]
        let thinking = Defaults[.enableThinkingMode]
        let toolsEnabled = Defaults[.chatToolsEnabled]
        let session = bridgeSessionID
        chatTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let turns = try await Task.detached(priority: .userInitiated) { try Self.requestTurns(snapshot) }.value
                try Task.checkCancellation()
                guard self.requestGeneration == generation else { return }
                var placeholder = ChatMessage(content: "", isFromUser: false)
                placeholder.includeInContext = false
                self.chatMessages.append(placeholder)
                self.streamedMessageID = placeholder.id
                if provider == .deepseek {
                    self.isBridge = false
                    let model = ChatRequestBuilder.model(endpoint: endpoint, selected: selected, vision: vision, hasImages: turns.contains { !$0.images.isEmpty })
                    self.actualModelName = model
                    let request = try DeepSeekConfiguration.request(endpoint: endpoint, model: model, apiKey: key,
                        messages: ChatRequestBuilder.openAIMessages(turns), stream: true,
                        thinking: ChatRequestBuilder.isOfficial(endpoint) ? thinking : nil)
                    try await ChatTransport.stream(request, ollama: false) { chunk in
                        guard self.requestGeneration == generation else { return }
                        self.receiveChunk(chunk)
                    }
                } else {
                    guard let base = ChatRequestBuilder.localBase(endpoint) else { throw ChatStreamChunk.failure(String(localized: "Invalid local model endpoint.")) }
                    let info = try await ChatTransport.bridgeInfo(base)
                    try Task.checkCancellation()
                    guard self.requestGeneration == generation else { return }
                    if let info {
                        self.isBridge = true
                        guard (info["protocol_version"] as? Int ?? 0) >= 2 else {
                            throw ChatStreamChunk.failure(String(localized: "Update the Atoll DeepSeek bridge to enable isolated chats and task controls."))
                        }
                        self.bridgeBase = base
                        let job = generation.uuidString
                        self.activeBridge = (base, session, job)
                        self.actualModelName = info["model"] as? String
                        let admission = try await ChatTransport.json(base.appendingPathComponent("atoll/chat"), body: [
                            "session_id": session, "request_id": job, "messages": ChatRequestBuilder.ollamaMessages(turns),
                            "thinking": thinking, "tools": toolsEnabled
                        ], timeout: 30)
                        guard (admission["job_id"] as? String)?.lowercased() == job.lowercased(),
                              ["pending", "completed", "failed"].contains(admission["status"] as? String ?? "") else {
                            throw ChatStreamChunk.failure(String(localized: "Invalid bridge task status."))
                        }
                        let deadline = Date().addingTimeInterval(330)
                        while true {
                            try Task.checkCancellation()
                            guard Date() < deadline else { throw ChatStreamChunk.failure(String(localized: "The task timed out. Stop it before retrying.")) }
                            let result = try await ChatTransport.json(base.appendingPathComponent("atoll/sessions/\(session)/jobs/\(job)"))
                            guard self.requestGeneration == generation else { return }
                            guard (result["job_id"] as? String)?.lowercased() == job.lowercased() else {
                                throw ChatStreamChunk.failure(String(localized: "Invalid bridge task status."))
                            }
                            self.actualModelName = result["model"] as? String ?? self.actualModelName
                            let toolNames = result["tools"] as? [String] ?? []
                            let phase = result["phase"] as? String ?? ""
                            if phase == "tool_execution" {
                                self.responseStatus = String(localized: "Using tools:") + " " + toolNames.map(Self.toolDisplayName).joined(separator: ", ")
                            } else {
                                self.responseStatus = phase == "thinking" ? String(localized: "Thinking…") : (phase == "starting" ? String(localized: "Connecting…") : String(localized: "Replying…"))
                            }
                            if let index = self.chatMessages.firstIndex(where: { $0.id == self.streamedMessageID }) { self.chatMessages[index].tools = toolNames }
                            if let content = result["content"] as? String { self.setStreamedContent(content) }
                            switch result["status"] as? String {
                            case "completed": break
                            case "failed": throw ChatStreamChunk.failure(result["content"] as? String ?? String(localized: "The model request failed."))
                            case "cancelled": throw CancellationError()
                            case "pending":
                                try await Task.sleep(for: .milliseconds(350))
                                continue
                            default: throw ChatStreamChunk.failure(String(localized: "Invalid bridge task status."))
                            }
                            break
                        }
                    } else {
                        self.isBridge = false
                        self.actualModelName = selected
                        var request = URLRequest(url: base.appendingPathComponent("api/chat"))
                        request.httpMethod = "POST"
                        request.timeoutInterval = 180
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": selected, "messages": ChatRequestBuilder.ollamaMessages(turns), "stream": true])
                        try await ChatTransport.stream(request, ollama: true) { chunk in
                            guard self.requestGeneration == generation else { return }
                            self.receiveChunk(chunk)
                        }
                    }
                }
                guard self.requestGeneration == generation else { return }
                guard let index = self.chatMessages.firstIndex(where: { $0.id == self.streamedMessageID }), !self.chatMessages[index].content.isEmpty else {
                    throw ChatStreamChunk.failure(String(localized: "The model returned no answer. Please retry."))
                }
                self.chatMessages[index].includeInContext = true
                self.finishModernRequest()
            } catch {
                guard self.requestGeneration == generation else { return }
                let interrupted = error is CancellationError || (error as NSError).code == NSURLErrorCancelled
                self.markInterrupted(interrupted ? String(localized: "Stopped") : error.localizedDescription)
                let outstanding = self.activeBridge
                self.finishModernRequest()
                // Polling failures must not leave a tool task running invisibly.
                if let outstanding { self.beginControl(base: outstanding.base, session: outstanding.session, job: outstanding.job, reset: false) }
            }
        }
    }

    private func receiveChunk(_ chunk: ChatStreamChunk) {
        guard let index = chatMessages.firstIndex(where: { $0.id == streamedMessageID }) else { return }
        chatMessages[index].content += chunk.text
        chatMessages[index].reasoning += chunk.reasoning
        if let model = chunk.model { actualModelName = model }
        responseStatus = chunk.text.isEmpty && !chunk.reasoning.isEmpty ? String(localized: "Thinking…") : String(localized: "Replying…")
        if chunk.truncated { chatMessages[index].notice = String(localized: "The reply reached the model's length limit.") }
    }

    private func setStreamedContent(_ content: String) {
        if let index = chatMessages.firstIndex(where: { $0.id == streamedMessageID }) { chatMessages[index].content = content }
    }

    private func markInterrupted(_ reason: String) {
        if let index = chatMessages.firstIndex(where: { $0.id == streamedMessageID }) {
            chatMessages[index].notice = reason
            chatMessages[index].includeInContext = false
        } else {
            var message = ChatMessage(content: "", isFromUser: false)
            message.notice = reason; message.includeInContext = false
            chatMessages.append(message)
        }
    }

    private func finishModernRequest() {
        isLoading = false; responseStatus = ""; activeBridge = nil; streamedMessageID = nil; chatTask = nil
    }

    private func cancelLocalRequest() {
        requestGeneration = UUID()
        chatTask?.cancel(); chatTask = nil
        activeRequest?.cancel(); activeRequest = nil
        finishModernRequest()
    }

    func stopResponse() {
        guard isLoading else { return }
        let bridge = activeBridge
        markInterrupted(String(localized: "Stopped"))
        cancelLocalRequest()
        if let bridge { beginControl(base: bridge.base, session: bridge.session, job: bridge.job, reset: false) }
    }

    func retryLastMessage() {
        guard canRetry, let index = chatMessages.lastIndex(where: \.isFromUser) else { return }
        let message = chatMessages[index]
        chatMessages.removeSubrange((index + 1)..<chatMessages.count)
        sendToAI(message: message.content, files: message.attachedFiles ?? [], provider: Defaults[.selectedAIProvider])
    }

    private func beginControl(base: URL, session: String, job: String, reset: Bool) {
        pendingControl = (base, session, job, reset)
        controlError = nil; isControlling = true
        controlTask = Task { @MainActor [weak self] in
            do {
                let acknowledgment = try await ChatTransport.json(base.appendingPathComponent("atoll/sessions/\(session)/\(reset ? "reset" : "stop")"), body: reset ? [:] : ["job_id": job], timeout: 30)
                let expectedStatus = reset ? "reset" : "cancelled"
                let acknowledgedID = acknowledgment[reset ? "session_id" : "job_id"] as? String
                guard acknowledgment["status"] as? String == expectedStatus,
                      acknowledgedID?.lowercased() == (reset ? session : job).lowercased() else {
                    throw ChatStreamChunk.failure(String(localized: "Invalid bridge task status."))
                }
                self?.pendingControl = nil
            } catch {
                self?.controlError = String(localized: "Could not confirm that the backend stopped. Retry before sending another message.")
            }
            self?.isControlling = false
        }
    }

    func retryBackendControl() {
        guard !isControlling, let pendingControl else { return }
        beginControl(base: pendingControl.base, session: pendingControl.session, job: pendingControl.job, reset: pendingControl.reset)
    }

    func refreshModelStatus() {
        guard !isLoading else { return }
        actualModelName = nil; isBridge = false
        guard Defaults[.selectedAIProvider] == .local, let base = ChatRequestBuilder.localBase(Defaults[.localModelEndpoint]) else { return }
        let generation = requestGeneration
        Task { @MainActor [weak self] in
            let info = try? await ChatTransport.bridgeInfo(base)
            guard let self, !self.isLoading, self.requestGeneration == generation else { return }
            guard Defaults[.selectedAIProvider] == .local, ChatRequestBuilder.localBase(Defaults[.localModelEndpoint]) == base else { return }
            self.isBridge = info != nil
            self.actualModelName = info?["model"] as? String
        }
    }

    static func toolDisplayName(_ name: String) -> String {
        switch name {
        case "web_search": return String(localized: "Web search")
        case "read_webpage": return String(localized: "Read webpage")
        case "list_files": return String(localized: "List files")
        case "read_file": return String(localized: "Read file")
        default: return name
        }
    }

    func clearChat() {
        resetConversationContext()
    }

    func resetConversationContext() {
        guard !isControlling, controlError == nil else { return }
        let prior = activeBridge ?? bridgeBase.map { (base: $0, session: bridgeSessionID, job: "") }
        bridgeBase = nil
        cancelLocalRequest()
        bridgeSessionID = UUID().uuidString
        attachmentGeneration = UUID()
        for file in attachedFiles + chatMessages.flatMap({ $0.attachedFiles ?? [] }) {
            if let path = file.fileURL, let url = URL(string: path) { ChatAttachmentImport.removeOwnedFile(url) }
        }
        if isRecording { stopRecording() }
        chatMessages.removeAll()
        clearAllFiles()
        draftMessage = ""
        attachmentError = nil
        actualModelName = nil
        if let prior { beginControl(base: prior.base, session: prior.session, job: prior.job, reset: true) }
    }

    private func addAssistantMessage(_ content: String) {
        print("💬 ScreenAssistant: Adding assistant message: \(content.prefix(100))...")
        let assistantMessage = ChatMessage(content: content, isFromUser: false)
        chatMessages.append(assistantMessage)
    }
    
    private func handleAPIError(statusCode: Int, provider: AIModelProvider) {
        let userFriendlyMessage: String
        
        switch statusCode {
        case 429:
            userFriendlyMessage = "🚫 **Rate Limited**\n\n\(provider.displayName) is currently rate limiting requests. Please wait a moment and try again."
        case 400:
            userFriendlyMessage = "❌ **Invalid Request**\n\nThere was an issue with your request to \(provider.displayName). Please check your message and attached files."
        case 401:
            userFriendlyMessage = "🔑 **Authentication Error**\n\nYour \(provider.displayName) API key appears to be invalid. Please check your API key in model settings."
        case 403:
            userFriendlyMessage = "🚫 **Access Denied**\n\nYour \(provider.displayName) API key doesn't have permission for this request."
        case 404:
            userFriendlyMessage = "🔍 **Model Not Found**\n\nThe requested model is not available on \(provider.displayName)."
        case 500, 502, 503:
            userFriendlyMessage = "⚠️ **Server Error**\n\n\(provider.displayName) servers are experiencing issues. Please try again in a few minutes."
        default:
            userFriendlyMessage = "❌ **API Error (\(statusCode))**\n\n\(provider.displayName) returned an error. Please try again."
        }
        
        addAssistantMessage(userFriendlyMessage)
    }
    
    private func handleAPIError(error: [String: Any]) {
        guard let code = error["code"] as? Int,
              let message = error["message"] as? String else {
            print("❌ ScreenAssistant: Unknown API Error")
            addAssistantMessage("An unknown error occurred. Please try again.")
            return
        }
        
        print("❌ ScreenAssistant: API Error \(code) - \(message)")
        
        let userFriendlyMessage: String
        
        switch code {
        case 429:
            // Quota exceeded
            if message.contains("quota") || message.contains("exceeded") {
                userFriendlyMessage = "🚫 **API Quota Exceeded**\n\nYou've reached your API usage limit. This usually happens when:\n\n• Too many requests in a short time\n• Daily/monthly quota exceeded\n• Free tier limits reached\n\n**What you can do:**\n• Wait a few minutes and try again\n• Check your API billing\n• Consider upgrading your plan\n\n*The system will work again once the quota resets.*"
            } else {
                userFriendlyMessage = "⏰ **Rate Limited**\n\nToo many requests. Please wait a moment and try again."
            }
            
        case 400:
            userFriendlyMessage = "❌ **Invalid Request**\n\nThere was an issue with your request. Please check your message and attached files."
            
        case 401:
            userFriendlyMessage = "🔑 **Authentication Error**\n\nYour API key appears to be invalid. Please check your API key in settings."
            
        case 403:
            userFriendlyMessage = "🚫 **Access Denied**\n\nYour API key doesn't have permission for this request. Please check your API key settings."
            
        case 404:
            userFriendlyMessage = "🔍 **Model Not Found**\n\nThe requested AI model is not available. Please try again later."
            
        case 500, 502, 503:
            userFriendlyMessage = "⚠️ **Server Error**\n\nThe AI service is experiencing issues. Please try again in a few minutes."
            
        default:
            userFriendlyMessage = "❌ **API Error (\(code))**\n\n\(message.components(separatedBy: ".").first ?? message)"
        }
        
        addAssistantMessage(userFriendlyMessage)
    }
    
    private func handleOpenAIError(error: [String: Any]) {
        if let message = error["message"] as? String {
            let userFriendlyMessage = "❌ **OpenAI Error**\n\n\(message)"
            addAssistantMessage(userFriendlyMessage)
        } else {
            addAssistantMessage("❌ **OpenAI Error**\n\nAn unknown error occurred with OpenAI.")
        }
    }
    
    private func handleClaudeError(error: [String: Any]) {
        if let message = error["message"] as? String {
            let userFriendlyMessage = "❌ **Claude Error**\n\n\(message)"
            addAssistantMessage(userFriendlyMessage)
        } else {
            addAssistantMessage("❌ **Claude Error**\n\nAn unknown error occurred with Claude.")
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension ScreenAssistantManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if flag {
            let fileName = recorder.url.lastPathComponent
            let displayName = "Recording \(DateFormatter.shortTime.string(from: Date()))"
            let audioFile = ScreenAssistantFile(audioFileName: fileName, name: displayName)
            attachedFiles.append(audioFile)
            saveFilesToDefaults()
            print("Recording saved: \(fileName)")
        } else {
            print("Recording failed")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Recording encode error: \(error?.localizedDescription ?? "Unknown error")")
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
