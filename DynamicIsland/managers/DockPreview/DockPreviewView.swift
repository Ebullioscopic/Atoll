/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import SwiftUI

struct DockPreviewView: View {
    @ObservedObject var manager: DockPreviewManager
    var body: some View {
        if let session = manager.session {
            DockPreviewContent(session: session, thumbnails: manager.thumbnails, isLoading: manager.isLoading,
                actionError: manager.actionError, hasScreenRecording: manager.hasScreenRecording,
                cardWidth: manager.cardWidth, refresh: { manager.refresh() }, dismiss: { manager.dismiss() },
                activateApplication: { manager.activateApplication() }, perform: { manager.perform($0, window: $1) })
        }
    }
}
