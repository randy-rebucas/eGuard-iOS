import Foundation
import Observation

/// Polls a configuration batch every 1–2 seconds until every item finishes, giving up after a minute
/// with a "waiting for the device" state the parent can come back to later.
@Observable
final class BatchPoller {
    enum Phase: Equatable {
        case idle
        case polling
        case done
        case waitingForDevice
        case failed(String)
    }

    private(set) var batch: Batch?
    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Faster under UI tests so flows finish quickly.
    static var interval: Duration {
        ProcessInfo.processInfo.arguments.contains("-uiTesting") ? .milliseconds(250) : .seconds(1.5)
    }

    var isBusy: Bool { phase == .polling }

    func start(batchId: String, api: EGuardAPIService, initial: Batch? = nil, timeout: TimeInterval = 60) {
        if let initial { batch = initial }
        phase = .polling
        task?.cancel()
        task = Task { [weak self] in
            let started = Date.now
            while !Task.isCancelled {
                do {
                    let latest = try await api.batch(id: batchId)
                    guard let self, !Task.isCancelled else { return }
                    batch = latest
                    if latest.done {
                        phase = .done
                        return
                    }
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    phase = .failed(error.localizedDescription)
                    return
                }
                if Date.now.timeIntervalSince(started) > timeout {
                    self?.phase = .waitingForDevice
                    return
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Guided setup: the parent finished the steps on the device, so ask the server to verify.
    func confirm(api: EGuardAPIService) async throws {
        guard let id = batch?.batchId else { return }
        batch = try await api.confirmBatch(id: id)
        start(batchId: id, api: api)
    }

    func cancel(api: EGuardAPIService) async throws {
        guard let id = batch?.batchId else { return }
        stop()
        _ = try await api.cancelBatch(id: id)
        batch = try await api.batch(id: id)
        phase = .done
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .polling { phase = .idle }
    }
}
