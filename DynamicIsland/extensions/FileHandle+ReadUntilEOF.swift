import Foundation

extension FileHandle {
    /// Sets a `readabilityHandler` that hands each chunk to `onData` and detaches itself at EOF.
    ///
    /// Once the writing process exits, `availableData` returns empty data and the dispatch source
    /// keeps firing. A handler that only returns on empty data then spins a core until Atoll quits.
    func readUntilEOF(onEOF: (@Sendable () -> Void)? = nil, onData: @escaping @Sendable (Data) -> Void) {
        readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                onEOF?()
                return
            }
            onData(data)
        }
    }
}
