// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

// The policy test links no runtime and can never ask a real debugger for memory.
nonisolated func kernarium_runtime_loader_debugger_attached() -> Int32 { 0 }
nonisolated func kernarium_runtime_loader_select(_ flavor: UInt32) -> Int32 { 1 }
nonisolated func kernarium_runtime_loader_prepare_jit(
    _ enabled: Int32, _ memory: UInt32, _ processors: UInt32
) -> Int32 { 1 }

nonisolated final class JitCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [Bool] = []

    func add(_ wanted: Bool) {
        precondition(!Thread.isMainThread, "JIT preparation blocked the main thread")
        lock.lock()
        defer { lock.unlock() }
        requests.append(wanted)
    }

    var all: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

@main
struct JitPreparationHarness {
    @MainActor static func main() async {
        let suite = "kernarium-jit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let offCalls = JitCalls()
        let off = KernariumJit(defaults: defaults, environment: [:]) { wanted, _, _, _ in
            offCalls.add(wanted)
            return 0
        }
        precondition(!off.wanted)
        let offResult = await off.useJitForBoot(flavor: 0, memoryMiB: 2048, processors: 2)
        precondition(!offResult && off.status == "Gadgets")
        precondition(offCalls.all == [false])

        defaults.set(true, forKey: KernariumJit.defaultsKey)
        let calls = JitCalls()
        let ready = KernariumJit(defaults: defaults, environment: [:]) { wanted, flavor, memory, cpus in
            calls.add(wanted)
            precondition(flavor == 0 && memory == 2048 && cpus == 2)
            return 0
        }
        ready.prepareAtLaunch(flavor: 0, memoryMiB: 2048, processors: 2)
        ready.prepareAtLaunch(flavor: 0, memoryMiB: 2048, processors: 2)
        let first = await ready.useJitForBoot(flavor: 0, memoryMiB: 2048, processors: 2)
        let second = await ready.useJitForBoot(flavor: 0, memoryMiB: 2048, processors: 2)
        precondition(first && second && calls.all == [true])
        let changed = await ready.useJitForBoot(flavor: 0, memoryMiB: 4096, processors: 2)
        precondition(!changed && ready.status.contains("CPU or RAM changed"))

        for answer: Int32 in [1, 2, 3, 4, 5, 99] {
            let fallback = KernariumJit(defaults: defaults, environment: [:]) { _, _, _, _ in answer }
            let usesJit = await fallback.useJitForBoot(flavor: 0, memoryMiB: 2048, processors: 2)
            precondition(!usesJit && fallback.status.hasPrefix("Gadgets"))
        }
        let explicitOff = KernariumJit(defaults: defaults, environment: ["KERNARIUM_JIT": "0"])
        let automation = KernariumJit(defaults: defaults, environment: ["KERNARIUM_EXECUTION_ENGINE": "gadgets"])
        precondition(!explicitOff.wanted && !automation.wanted)
        print("Kernarium JIT preparation policy passed")
    }
}
