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

    func testNilCPUOnNominalDoesNotLatch() {
        let nominal = MachineLoadGate()
        XCTAssertTrue(nominal.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: nil)))
        XCTAssertTrue(nominal.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: 0.75)))

        let fair = MachineLoadGate()
        XCTAssertTrue(fair.allowsPlayback(LoadSample(thermal: .fair, cpuBusy: nil)))
        XCTAssertTrue(fair.allowsPlayback(LoadSample(thermal: .fair, cpuBusy: 0.75)))
    }

    func testNilCPUOnSeriousBlocks() {
        let serious = MachineLoadGate()
        XCTAssertFalse(serious.allowsPlayback(LoadSample(thermal: .serious, cpuBusy: nil)))
        XCTAssertFalse(serious.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: 0.75)))

        let critical = MachineLoadGate()
        XCTAssertFalse(critical.allowsPlayback(LoadSample(thermal: .critical, cpuBusy: nil)))
        XCTAssertFalse(critical.allowsPlayback(LoadSample(thermal: .fair, cpuBusy: 0.75)))
    }

    func testNilCPUWhileAlreadyBlockedDoesNotClear() {
        let gate = MachineLoadGate()
        XCTAssertFalse(gate.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: 0.9)))
        XCTAssertFalse(gate.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: nil)))
        XCTAssertFalse(gate.allowsPlayback(LoadSample(thermal: .fair, cpuBusy: 0.75)))
        XCTAssertTrue(gate.allowsPlayback(LoadSample(thermal: .nominal, cpuBusy: 0.7)))
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
