import Foundation

enum FileCoordinator {
    // filePresenter is nil because the owning TextDocument (a UIDocument) is already
    // registered as presenter for its own file and receives coordination callbacks directly.
    nonisolated static func coordinateRead<T: Sendable>(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        _ body: @Sendable @escaping (URL) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var result: Result<T, Error>?
                coordinator.coordinate(readingItemAt: url, options: options, error: &coordError) { coordinatedURL in
                    result = Result { try body(coordinatedURL) }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    nonisolated static func coordinateWrite(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: @Sendable @escaping (URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var thrown: Error?
                coordinator.coordinate(writingItemAt: url, options: options, error: &coordError) { coordinatedURL in
                    do { try body(coordinatedURL) } catch { thrown = error }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let thrown {
                    continuation.resume(throwing: thrown)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    nonisolated static func coordinateMove(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var thrown: Error?
                coordinator.coordinate(
                    writingItemAt: source, options: .forMoving,
                    writingItemAt: destination, options: .forReplacing,
                    error: &coordError
                ) { src, dst in
                    do {
                        try FileManager.default.moveItem(at: src, to: dst)
                        coordinator.item(at: src, didMoveTo: dst)
                    } catch {
                        thrown = error
                    }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let thrown {
                    continuation.resume(throwing: thrown)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
