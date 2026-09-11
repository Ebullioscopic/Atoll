import AppKit
import SwiftUI

/// A plain text composer that treats pasted/dropped images as attachments.
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var fontSize: CGFloat = 14
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = AttachmentTextView()
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: fontSize)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 2, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.string = text
        editor.onSend = onSend
        editor.registerForDraggedTypes([.fileURL, .png, .tiff])
        editor.setAccessibilityLabel(String(localized: "Message"))
        scroll.documentView = editor
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? AttachmentTextView else { return }
        editor.onSend = onSend
        if editor.font?.pointSize != fontSize { editor.font = .systemFont(ofSize: fontSize) }
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        context.coordinator.measure(editor)
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextEditor
        init(_ parent: ChatTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            measure(view)
        }
        func measure(_ view: NSTextView) {
            guard let container = view.textContainer, let layout = view.layoutManager else { return }
            layout.ensureLayout(for: container)
            let next = min(156, max(76, layout.usedRect(for: container).height + 18))
            if abs(parent.height - next) > 1 {
                DispatchQueue.main.async { [weak self] in self?.parent.height = next }
            }
        }
    }
}

final class AttachmentTextView: NSTextView {
    var onSend: (() -> Void)?
    override func paste(_ sender: Any?) {
        if !ScreenAssistantManager.shared.acceptPasteboard(.general) { super.paste(sender) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !hasMarkedText() {
            ScreenAssistantManager.shared.closePanels()
            return
        }
        // Let the input method commit Chinese/Japanese composition normally.
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .option]).isEmpty {
            onSend?()
        } else { super.keyDown(with: event) }
    }
    private func containsAttachment(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL, .png, .tiff]) != nil
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        containsAttachment(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        containsAttachment(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if ScreenAssistantManager.shared.acceptPasteboard(sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }
}
