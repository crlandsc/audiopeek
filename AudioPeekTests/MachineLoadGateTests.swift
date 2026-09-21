import XCTest
@testable import AudioPeek

final class MachineLoadGateTests: XCTestCase {
    func testSeriousOrBusyDoesNotAllowUntilTheWindowClears() {
        let gate = MachineLoadGate()
        gate.setInjected(thermal: .serious, cpu: 0.1)
        XCTAssertFalse(gate.allowsPlayback(gate.sample()))
        gate.setInjected(thermal: .nominal, cpu: 0.9)
        XCTAssertFalse(gate.allowsPlayback(gate.sample()))
        gate.setInjected(thermal: .fair, cpu: 0.75)
        XCTAssertFalse(gate.allowsPlayback(gate.sample()))
        gate.setInjected(thermal: .nominal, cpu: 0.7)
        XCTAssertTrue(gate.allowsPlayback(gate.sample()))
    }

    func testCriticalBlocksAndFairClears() {
        let gate = MachineLoadGate()
        gate.setInjected(thermal: .critical, cpu: 0.1)
        XCTAssertFalse(gate.allowsPlayback(gate.sample()))
        gate.setInjected(thermal: .fair, cpu: 0.2)
        XCTAssertTrue(gate.allowsPlayback(gate.sample()))
    }

    func testACoolWindowCanStart() {
        let gate = MachineLoadGate()
        gate.setInjected(thermal: .nominal, cpu: 0.2)
        XCTAssertTrue(gate.allowsPlayback(gate.sample()))
    }

    func testSystemSamplerReadsOneCPUWindow() {
        var sampler = SystemLoadSampler()
        let first = sampler.sample()
        XCTAssertNil(first.cpuBusy)
        Thread.sleep(forTimeInterval: 1.1)
        let second = sampler.sample()
        XCTAssertNotNil(second.cpuBusy)
        XCTAssertTrue((0...1).contains(second.cpuBusy ?? -1))
    }
}
