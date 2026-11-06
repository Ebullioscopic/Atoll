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

import SwiftUI
import Defaults

struct NotchNotesView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    @FocusState private var isFocused: Bool
    @Default(.savedNotes) var savedNotes
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableAppleNotesSync) var enableAppleNotesSync
    
    @State private var selectedNoteId: UUID?
    @State private var isEditingNewNote = false
    
    // Editor State
    @State private var editorTitle: String = ""
    @State private var editorContent: String = ""
    @State private var editorImageData: Data? = nil
    @State private var editorColorIndex: Int = 0
    @State private var editorNoteId: UUID?
    @State private var autoSaveTask: Task<Void, Never>?

    @Default(.enableNotes) var enableNotes
    
    var showSplitView: Bool {
        return enableClipboardManager && clipboardDisplayMode == .separateTab
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSplitView {
                NotchClipboardView(fixedColumns: 2)
                    .frame(maxWidth: .infinity)
                
                if enableNotes {
                    Divider()
                        .background(Color.white.opacity(0.15))
                }
            }
            
            if enableNotes {
                ZStack {
                    if isEditingNewNote || selectedNoteId != nil {
                        NoteEditorView(
                            title: $editorTitle,
                            content: $editorContent,
                            imageData: $editorImageData,
                            colorIndex: $editorColorIndex,
                            onSave: saveNote,
                            onCancel: cancelEdit,
                            isNew: isEditingNewNote
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                    } else {
                        NoteListView(
                            notes: savedNotes,
                            onSelect: selectNote,
                            onCreate: createNote,
                            onDelete: deleteNote,
                            onDeleteItem: deleteNoteItem,
                            onClearAll: clearAllNotes,
                            onTogglePin: togglePin,
                            onCreateFromClipboard: createNoteFromClipboard,
                            onSync: syncWithAppleNotes
                        )
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped() // Prevent overflow during transition
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditingNewNote)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedNoteId)
                .overlay {
                    // Hidden button for Cmd+V paste listener
                    Button("") {
                        handlePaste()
                    }
                    .keyboardShortcut("v", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            updateLayoutState()
            syncWithAppleNotes()
        }
        .onChange(of: enableAppleNotesSync) { _, isEnabled in
            if isEnabled {
                syncWithAppleNotes()
            }
        }
        .onDisappear {
            if isEditingNewNote || selectedNoteId != nil {
                persistNote()
            }
            coordinator.notesLayoutState = .list
        }
        .onChange(of: isEditingNewNote) { _, _ in
            updateLayoutState()
        }
        .onChange(of: selectedNoteId) { _, _ in
            updateLayoutState()
        }
        .onChange(of: enableClipboardManager) { _, _ in
            updateLayoutState()
        }
        .onChange(of: clipboardDisplayMode) { _, _ in
            updateLayoutState()
        }
        .onChange(of: enableNotes) { _, _ in
            updateLayoutState()
        }
        .onChange(of: editorContent) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: editorTitle) { _, _ in
            scheduleAutoSave()
        }
        .onChange(of: editorColorIndex) { _, _ in
            scheduleAutoSave()
        }
    }
    
    // MARK: - Actions
    
    private func handlePaste() {
        let pasteboard = NSPasteboard.general
        
        // Check for file URLs first (higher quality source than icons)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
            if let firstImageURL = fileURLs.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
               let imageData = try? Data(contentsOf: firstImageURL) {
                updateImageData(imageData)
                return
            }
        }
        
        // Then direct image data
        if let tiffData = pasteboard.data(forType: .tiff) {
            updateImageData(tiffData)
            return
        } else if let pngData = pasteboard.data(forType: .png) {
            updateImageData(pngData)
            return
        }
        
        // Handle text paste
        if let text = pasteboard.string(forType: .string) {
            if isEditingNewNote || selectedNoteId != nil {
                // In editor: insert text at the end of content since we intercepted the shortcut
                editorContent.append(text)
            } else {
                // Not in editor: create a new note with the pasted text
                createNoteWithContent(text)
            }
        }
    }

    private func updateImageData(_ data: Data) {
        withAnimation {
            if isEditingNewNote || selectedNoteId != nil {
                editorImageData = data
            } else {
                // If not editing, create a new note with this image
                editorTitle = ""
                editorContent = ""
                editorImageData = data
                editorColorIndex = 0
                editorNoteId = UUID()
                isEditingNewNote = true
            }
        }
    }

    private func createNoteWithContent(_ content: String) {
        editorTitle = ""
        editorContent = content
        editorImageData = nil
        editorColorIndex = 0
        editorNoteId = UUID()
        isEditingNewNote = true
    }
    
    private func createNote() {
        editorTitle = ""
        editorContent = ""
        editorImageData = nil
        editorColorIndex = 0 // Default Yellow
        editorNoteId = UUID()
        isEditingNewNote = true
    }
    
    private func selectNote(_ note: NoteItem) {
        editorTitle = note.title
        editorContent = note.content
        editorImageData = note.getImageData() // Load from disk
        editorColorIndex = note.colorIndex
        editorNoteId = note.id
        selectedNoteId = note.id
        isEditingNewNote = false
    }
    
    private func persistNote() {
        guard let id = editorNoteId else { return }

        let isExistingNote = savedNotes.contains(where: { $0.id == id })
        if !isExistingNote && editorTitle.isEmpty && editorContent.isEmpty && editorImageData == nil {
            return
        }

        var notes = savedNotes
        let now = Date()

        var fileName: String? = nil
        if let data = editorImageData {
            let name = "note_image_\(id.uuidString).png"
            let fileURL = NoteItem.noteImageDataDirectory.appendingPathComponent(name)
            try? data.write(to: fileURL)
            fileName = name
        }

        if let index = notes.firstIndex(where: { $0.id == id }) {
            // Update
            if let oldFileName = notes[index].imageFileName, oldFileName != fileName {
                let oldFileURL = NoteItem.noteImageDataDirectory.appendingPathComponent(oldFileName)
                try? FileManager.default.removeItem(at: oldFileURL)
            }

            notes[index].title = editorTitle
            notes[index].content = editorContent
            notes[index].imageFileName = fileName
            notes[index].colorIndex = editorColorIndex
            notes[index].modificationDate = now
        } else {
            // Create
            let newNote = NoteItem(
                id: id,
                title: editorTitle.isEmpty ? "Untitled Note" : editorTitle,
                content: editorContent,
                creationDate: now,
                modificationDate: now,
                colorIndex: editorColorIndex,
                isPinned: false,
                imageFileName: fileName
            )
            notes.insert(newNote, at: 0)
        }

        savedNotes = notes
        pushNoteToAppleNotes(noteId: id)
    }

    private func scheduleAutoSave() {
        guard isEditingNewNote || selectedNoteId != nil else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistNote()
            }
        }
    }

    private func saveNote() {
        persistNote()
        closeEditor()
    }
    
    private func createNoteFromClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Priority 1: Check for real image files (highest quality)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
            if let firstImageURL = fileURLs.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
               let imageData = try? Data(contentsOf: firstImageURL) {
                createNoteWithContent("")
                editorImageData = imageData
                return
            }
        }
        
        // Priority 2: Direct image data
        if let tiffData = pasteboard.data(forType: .tiff) {
            createNoteWithContent("")
            editorImageData = tiffData
            return
        } else if let pngData = pasteboard.data(forType: .png) {
            createNoteWithContent("")
            editorImageData = pngData
            return
        }
        
        if let text = pasteboard.string(forType: .string) {
            createNoteWithContent(text)
        }
    }
    
    private func deleteNote(_ indexSet: IndexSet) {
        var notes = savedNotes
        for index in indexSet {
            if index < notes.count {
                deleteRemoteNoteIfNeeded(notes[index])
                if let fileName = notes[index].imageFileName {
                    let fileURL = NoteItem.noteImageDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        notes.remove(atOffsets: indexSet)
        savedNotes = notes
    }
    
    private func deleteNoteItem(_ note: NoteItem) {
        var notes = savedNotes
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            deleteRemoteNoteIfNeeded(notes[index])
            // Clean up image file
            if let fileName = notes[index].imageFileName {
                let fileURL = NoteItem.noteImageDataDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
            notes.remove(at: index)
            savedNotes = notes
        }
    }
    
    private func clearAllNotes() {
        // Clean up all image files
        for note in savedNotes {
            deleteRemoteNoteIfNeeded(note)
            if let fileName = note.imageFileName {
                let fileURL = NoteItem.noteImageDataDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        savedNotes.removeAll()
    }

    private func syncWithAppleNotes() {
        guard enableAppleNotesSync else { return }
        Task {
            if let merged = await appleNotesSync.sync(localNotes: savedNotes) {
                savedNotes = merged
            }
        }
    }

    private func pushNoteToAppleNotes(noteId: UUID) {
        guard enableAppleNotesSync,
              let note = savedNotes.first(where: { $0.id == noteId }) else { return }

        Task {
            if let updated = await appleNotesSync.pushNote(note),
               let appleNotesId = updated.appleNotesId {
                var notes = savedNotes
                if let index = notes.firstIndex(where: { $0.id == noteId }) {
                    notes[index].appleNotesId = appleNotesId
                    savedNotes = notes
                }
            }
        }
    }

    private func deleteRemoteNoteIfNeeded(_ note: NoteItem) {
        guard enableAppleNotesSync, let appleNotesId = note.appleNotesId else { return }
        Task {
            await appleNotesSync.deleteRemoteNote(appleNotesId: appleNotesId)
        }
    }

    private func cancelEdit() {
        persistNote()
        closeEditor()
    }
    
    private func togglePin(_ note: NoteItem) {
        var notes = savedNotes
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isPinned.toggle()
            savedNotes = notes
        }
    }

    private func scaleDownEditor() {
        closeEditor()
    }
    
    private func closeEditor() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        isEditingNewNote = false
        selectedNoteId = nil
        // Tiny delay to clear state after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            editorTitle = ""
            editorContent = ""
        }
        updateLayoutState()
    }

    private func updateLayoutState() {
        let newState: NotesLayoutState
        if enableNotes && (isEditingNewNote || selectedNoteId != nil) {
            newState = .editor
        } else if showSplitView {
            newState = .split
        } else {
            newState = .list
        }

        if coordinator.notesLayoutState != newState {
            coordinator.notesLayoutState = newState
        }
    }
}

// MARK: - Subviews

struct NoteListView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    let notes: [NoteItem]
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void
    let onDelete: (IndexSet) -> Void
    let onDeleteItem: (NoteItem) -> Void
    let onClearAll: () -> Void
    let onTogglePin: (NoteItem) -> Void
    let onCreateFromClipboard: () -> Void
    let onSync: () -> Void

    @Default(.enableNoteSearch) var enableNoteSearch
    @Default(.enableNoteColorFiltering) var enableNoteColorFiltering
    @Default(.enableCreateFromClipboard) var enableCreateFromClipboard
    @Default(.enableAppleNotesSync) var enableAppleNotesSync
    
    @State private var searchText = ""
    @State private var selectedColorFilter: Int? = nil
    @State private var isSearchExpanded = false
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    @State private var showClearNotesAlert = false
    @State private var autoCloseToken = UUID()

    var sortedNotes: [NoteItem] {
        var filtered = searchText.isEmpty ? notes : notes.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText) || 
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
        
        if let colorIndex = selectedColorFilter {
            filtered = filtered.filter { $0.colorIndex == colorIndex }
        }
        
        return filtered.sorted { 
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.modificationDate > $1.modificationDate
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notes")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if enableAppleNotesSync {
                    Image(systemName: appleNotesSync.isSyncing ? "arrow.triangle.2.circlepath" : "apple.logo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appleNotesSync.isSyncing ? .yellow : .white.opacity(0.45))
                        .rotationEffect(.degrees(appleNotesSync.isSyncing ? 360 : 0))
                        .animation(
                            appleNotesSync.isSyncing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: appleNotesSync.isSyncing
                        )
                }
                
                Spacer()
                
                if enableAppleNotesSync {
                    Button(action: onSync) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(appleNotesSync.isSyncing ? .yellow : .white.opacity(0.6))
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(appleNotesSync.isSyncing)
                    .help(String(localized: "Sync with Apple Notes"))
                }

                if enableNoteSearch || enableNoteColorFiltering {
                    Button(action: { 
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isSearchExpanded.toggle()
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: isSearchExpanded ? .bold : .medium))
                            .symbolVariant(isSearchExpanded ? .circle.fill : .none)
                            .frame(width: 16, height: 16) // Fixed frame to stabilize
                            .foregroundStyle(isSearchExpanded ? .blue : .white.opacity(0.6))
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if enableCreateFromClipboard {
                    Button(action: onCreateFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Create from Clipboard")
                }
                
                if !notes.isEmpty {
                    Button(action: { showClearNotesAlert = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.red)
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16) // Reduced from 20
            .padding(.top, 8)
            .padding(.bottom, isSearchExpanded ? 4 : 2)

            if isSearchExpanded {
                VStack(spacing: 6) {
                    if enableNoteSearch && !notes.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextField("Search notes...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4) // Reduced from 6
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                    }
                    
                    if enableNoteColorFiltering && !notes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) { // Reduced from 8
                                Button(action: { selectedColorFilter = nil }) {
                                    Text("All")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(selectedColorFilter == nil ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(0..<NoteItem.colors.count, id: \.self) { index in
                                    Circle()
                                        .fill(NoteItem.colors[index])
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColorFilter == index ? 2 : 0)
                                                .padding(-2)
                                        )
                                        .onTapGesture {
                                            withAnimation {
                                                selectedColorFilter = (selectedColorFilter == index) ? nil : index
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.bottom, 10)
            }
            if sortedNotes.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? "note.text" : "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text(searchText.isEmpty ? "No notes yet" : "No results found")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .padding(.top, 10)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ScrollView {
                        let useGrid = sortedNotes.count > 3
                        let columns = useGrid ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)] : [GridItem(.flexible())]
                        
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(sortedNotes) { note in
                                NoteRow(
                                    note: note, 
                                    onDelete: { onDeleteItem(note) },
                                    onTogglePin: { onTogglePin(note) },
                                    isCompact: useGrid
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(note)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }

                    LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .top)

                    LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .alert("Delete All Notes?", isPresented: $showClearNotesAlert) {
            Button("Delete", role: .destructive) {
                onClearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved note and its attachments.")
        }
        .onChange(of: showClearNotesAlert) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

struct NoteRow: View {
    let note: NoteItem
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let isCompact: Bool
    @State private var isHovered = false
    @State private var isCopied = false
    @Default(.enableNotePinning) var enableNotePinning
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: isCompact ? 8 : 12) {
                // Color Indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(note.color)
                    .frame(width: isCompact ? 3 : 4)
                    .padding(.vertical, isCompact ? 4 : 2)
                
                VStack(alignment: .leading, spacing: isCompact ? 1 : 4) {
                    HStack(spacing: 4) {
                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: isCompact ? 7 : 8))
                                .foregroundStyle(note.color)
                        }
                        Text(note.title)
                            .font(.system(size: isCompact ? 12 : 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    Text(note.content.isEmpty ? "No content" : note.content)
                        .font(.system(size: isCompact ? 10 : 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(isCompact ? 1 : 2)
                        .multilineTextAlignment(.leading)
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                Spacer(minLength: 0)
            }
            .padding(.trailing, isCompact ? 50 : 130) // Standardized padding for alignment
            .padding(isCompact ? 8 : 12)
                
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(note.color.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12)) // Ensure everything stays inside the frame
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
                if isHovered {
                    HStack(spacing: isCompact ? 3 : 4) {
                        if enableNotePinning {
                            Button(action: onTogglePin) {
                                Image(systemName: note.isPinned ? "pin.slash.fill" : "pin.fill")
                                    .font(.system(size: isCompact ? 9 : 11))
                                    .foregroundStyle(.white)
                                    .padding(isCompact ? 5 : 6)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(note.content, forType: .string)
                            
                            // Also copy image data if present
                            if let imageData = note.getImageData(), let tiffData = NSImage(data: imageData)?.tiffRepresentation {
                                pasteboard.setData(tiffData, forType: .tiff)
                            }
                            
                            withAnimation {
                                isCopied = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    isCopied = false
                                }
                            }
                        }) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: isCompact ? 9 : 11))
                                .foregroundStyle(isCopied ? .green : .white)
                                .padding(isCompact ? 5 : 6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: isCompact ? 9 : 11))
                                .foregroundStyle(.red)
                                .padding(isCompact ? 5 : 6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, isCompact ? 6 : 8)
                    .padding(.vertical, isCompact ? 2 : 3)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.12)) // Softer dark gray, not solid black
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    )
                    .padding(.vertical, 4) // Ensure it stays within note borders
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                } else if !isCompact {
                    Text(timeAgoString(from: note.creationDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                
                if let imageData = note.getImageData(), let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: isCompact ? 32 : 50, height: isCompact ? 32 : 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .padding(.trailing, isCompact ? 4 : 8)
                }
            }
            .padding(.trailing, isCompact ? 2 : 4)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "Just now") }
        if interval < 3600 { return String(localized: "\(Int(interval/60))m") }
        if interval < 86400 { return String(localized: "\(Int(interval/3600))h") }
        return date.formatted(.dateTime.day().month())
    }
}

struct NoteEditorView: View {
    @Binding var title: String
    @Binding var content: String
    @Binding var imageData: Data?
    @Binding var colorIndex: Int
    let onSave: () -> Void
    let cancelAction: () -> Void
    let isNew: Bool
    
    init(title: Binding<String>, content: Binding<String>, imageData: Binding<Data?>, colorIndex: Binding<Int>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, isNew: Bool) {
        self._title = title
        self._content = content
        self._imageData = imageData
        self._colorIndex = colorIndex
        self.onSave = onSave
        self.cancelAction = onCancel
        self.isNew = isNew
    }

    @FocusState private var isContentFocused: Bool

    @EnvironmentObject var vm: DynamicIslandViewModel
    private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: cancelAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Notes")
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: onSave) {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(NoteItem.colors[colorIndex])
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            
            // Title & Color Picker Row
            HStack(alignment: .center, spacing: 12) {
                TextField("Title", text: $title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Color Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<NoteItem.colors.count, id: \.self) { index in
                            Circle()
                                .fill(NoteItem.colors[index])
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: colorIndex == index ? 2 : 0)
                                        .padding(-2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        colorIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 160)
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))


            
            // Content Input
            ZStack(alignment: .topLeading) {
                if content.isEmpty { // Placeholder
                    Text("Start typing...")
                        .font(.system(size: 13, design: .rounded)) // Reduced from 14
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 10)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $content)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .padding(.bottom, 20)
                    .padding(.trailing, imageData != nil ? 75 : 0) // Reduced from 100
                    .focused($isContentFocused)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.05))
                
                // Image Overlay in Bottom Right
                if let data = imageData, let nsImage = NSImage(data: data) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 55, height: 55) // Reduced from 80
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 2)
                                
                                Button(action: {
                                    withAnimation {
                                        imageData = nil
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.9), .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4) // Move out slightly for better accessibility
                            }
                            .padding(12)
                            .padding(.bottom, 20) // Moved higher as requested
                        }
                    }
                }
                
                if Defaults[.enableNoteCharCount] {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(content.count) chars")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(4)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack takes full space
        .background(Color.black) // Ensure solid background
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .onAppear {
            if isNew {
                isContentFocused = true
            }
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}
