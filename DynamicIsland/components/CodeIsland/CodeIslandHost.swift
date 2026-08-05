/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandCore
import CodeIslandRuntime
import CodeIslandUI
import Combine

/// Atoll's lifecycle state for the embedded feature host, not provider state.
enum CodeIslandHostLifecycleState: Equatable {
    case stopped
    case running
}

/// Owns the inert Code Island feature lifecycle inside the Atoll process.
///
/// Phase 3 starts only this host shell. The contained runtime remains disabled,
/// and this type performs no discovery, listener startup, persistence, or tool
/// configuration writes.
final class CodeIslandHost: ObservableObject {
    static let shared = CodeIslandHost()

    @Published private(set) var lifecycleState: CodeIslandHostLifecycleState = .stopped
    @Published private(set) var dashboardState: CodeIslandDashboardState = .setupRequired(provider: .codex)
    @Published private(set) var pendingActivityIntent: CodeIslandActivityIntent?

    private let runtime: CodeIslandRuntime
    private let activityIntentAdapter: CodeIslandActivityIntentAdapter

    private init(
        runtime: CodeIslandRuntime = CodeIslandRuntime(),
        activityIntentAdapter: CodeIslandActivityIntentAdapter = CodeIslandActivityIntentAdapter()
    ) {
        self.runtime = runtime
        self.activityIntentAdapter = activityIntentAdapter
    }

    /// Starts the Atoll-owned shell without activating the provider runtime.
    func start() {
        guard lifecycleState == .stopped else { return }
        lifecycleState = .running
        dashboardState = runtime.isRunning
            ? .idle(provider: .codex)
            : .setupRequired(provider: .codex)
    }

    /// Clears transient host state during Atoll shutdown.
    func stop() {
        pendingActivityIntent = nil
        lifecycleState = .stopped
    }

    /// Accepts only the sanitized projection seam reserved for later providers.
    /// No Phase 3 component invokes this method because all providers are inert.
    func consumeSanitizedSession(
        _ current: SessionMetadata,
        previous: SessionMetadata?
    ) {
        guard lifecycleState == .running else { return }
        guard let intent = activityIntentAdapter.intent(
            for: current,
            previous: previous
        ) else { return }
        pendingActivityIntent = intent
    }
}
