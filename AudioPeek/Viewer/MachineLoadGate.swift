import Darwin
import Foundation

struct LoadSample: Equatable {
    var thermal: ProcessInfo.ThermalState
    var cpuBusy: Double?
}

final class MachineLoadGate {
    private var sampler = SystemLoadSampler()
    private var injectedThermal: ProcessInfo.ThermalState?
    private var injectedCPU: Double?
    private var blocked = false

    func setInjected(thermal: ProcessInfo.ThermalState, cpu: Double) {
        injectedThermal = thermal
        injectedCPU = cpu
    }

    func clearInjection() {
        injectedThermal = nil
        injectedCPU = nil
    }

    func sample() -> LoadSample {
        if let injectedThermal, let injectedCPU {
            return LoadSample(thermal: injectedThermal, cpuBusy: injectedCPU)
        }
        return sampler.sample()
    }

    func allowsPlayback(_ sample: LoadSample) -> Bool {
        let thermalOK = sample.thermal == .nominal || sample.thermal == .fair
        guard thermalOK else {
            blocked = true
            return false
        }
        guard let cpu = sample.cpuBusy else {
            if blocked { return false }
            return true
        }
        if cpu >= 0.85 {
            blocked = true
            return false
        }
        if blocked {
            guard cpu <= 0.70 else { return false }
            blocked = false
        }
        return true
    }
}

struct SystemLoadSampler {
    private var previous: host_cpu_load_info_data_t?

    mutating func sample() -> LoadSample {
        let thermal = ProcessInfo.processInfo.thermalState
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            return LoadSample(thermal: thermal, cpuBusy: nil)
        }
        let prior = previous
        previous = info
        guard let prior else {
            return LoadSample(thermal: thermal, cpuBusy: nil)
        }
        let user = delta(info.cpu_ticks.0, prior.cpu_ticks.0)
        let system = delta(info.cpu_ticks.1, prior.cpu_ticks.1)
        let idle = delta(info.cpu_ticks.2, prior.cpu_ticks.2)
        let nice = delta(info.cpu_ticks.3, prior.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else {
            return LoadSample(thermal: thermal, cpuBusy: nil)
        }
        let busy = Double(user + system + nice) / Double(total)
        return LoadSample(thermal: thermal, cpuBusy: busy)
    }

    private func delta(_ now: natural_t, _ then: natural_t) -> UInt64 {
        UInt64(now &- then)
    }
}
