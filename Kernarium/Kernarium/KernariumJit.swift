// SPDX-License-Identifier: GPL-2.0-or-later

import Combine
import Foundation

/// One preparation per process, started before the guest view is created so
/// a servicing debugger does not time out while waiting for its request.
@MainActor
final class KernariumJit: ObservableObject {
    static let defaultsKey = "kernarium.jit"
    static let shared = KernariumJit()

    typealias Prepare = @Sendable (Bool, UInt32, UInt32, UInt32) -> Int32

    let wanted: Bool
    @Published private(set) var status = "Gadgets"
    private var preparation: Task<Int32, Never>?
    private var preparedFor: [UInt32]?
    private let prepareRuntime: Prepare

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        prepareRuntime: @escaping Prepare = KernariumJit.prepareRuntime
    ) {
        // Automation states its engine explicitly instead of inheriting a
        // person's saved JIT preference.
        if let stated = environment["KERNARIUM_JIT"] {
            wanted = stated == "1"
        } else if environment["KERNARIUM_EXECUTION_ENGINE"] != nil {
            wanted = false
        } else {
            wanted = defaults.bool(forKey: Self.defaultsKey)
        }
        self.prepareRuntime = prepareRuntime
    }

    func prepareAtLaunch(flavor: UInt32, memoryMiB: UInt32, processors: UInt32) {
        guard preparation == nil else { return }
        let wanted = wanted
        let prepare = prepareRuntime
        preparedFor = [flavor, memoryMiB, processors]
        status = wanted ? "Preparing JIT…" : "Gadgets"
        preparation = Task { [weak self] in
            let answer = await Task.detached(priority: .userInitiated) {
                prepare(wanted, flavor, memoryMiB, processors)
            }.value
            self?.show(answer)
            return answer
        }
    }

    /// Boot waits for the launch's request instead of issuing a second one.
    func useJitForBoot(flavor: UInt32, memoryMiB: UInt32, processors: UInt32) async -> Bool {
        prepareAtLaunch(flavor: flavor, memoryMiB: memoryMiB, processors: processors)
        guard let preparation else { return false }
        let answer = await preparation.value
        guard preparedFor == [flavor, memoryMiB, processors] else {
            if wanted { show(4) }
            return false
        }
        return wanted && answer == 0
    }

    private func show(_ answer: Int32) {
        guard wanted else { status = "Gadgets"; return }
        switch answer {
        case 0: status = "JIT prepared for this guest"
        case 1: status = "Gadgets — this runtime does not support JIT."
        case 2: status = "Gadgets — open Kernarium from StikDebug to prepare JIT."
        case 4: status = "Gadgets — CPU or RAM changed; relaunch from StikDebug."
        default: status = "Gadgets — the debugger could not prepare JIT."
        }
        print("Kernarium: \(status)")
    }

    private nonisolated static func prepareRuntime(
        wanted: Bool, flavor: UInt32, memoryMiB: UInt32, processors: UInt32
    ) -> Int32 {
        #if DEBUG
        // An ordinary Xcode debugger stops at the request instead of serving
        // it. Match Andarium's explicit opt-in for a servicing test debugger.
        guard ProcessInfo.processInfo.environment["KERNARIUM_JIT_DEBUGGER"] == "1" else {
            return wanted ? 2 : 5
        }
        #endif
        if !wanted && kernarium_runtime_loader_debugger_attached() == 0 { return 5 }
        guard kernarium_runtime_loader_select(flavor) == 0 else { return 1 }
        return kernarium_runtime_loader_prepare_jit(wanted ? 1 : 0, memoryMiB, processors)
    }
}
