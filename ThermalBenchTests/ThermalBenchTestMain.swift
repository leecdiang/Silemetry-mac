// ThermalBenchTests — standalone test runner entry point.
// Exit code 0 = pass, 1 = fail. (XCTest integration lives in the
// Package.swift test target; this binary is what Scripts/run_tests.sh runs.)
import Foundation

@main
struct TestMain {
    static func main() {
        print("ThermalBench Tests")
        print("==================")
        let result = MainActor.assumeIsolated { runAllTests() }
        print("")
        print("=== Results: \(result.passed)/\(result.total) passed, \(result.failed) failed ===")
        Darwin.exit(result.failed > 0 ? 1 : 0)
    }
}
