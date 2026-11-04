import Foundation
import IOKit.ps

/// Reads the internal battery through IOKit's public power-source API and updates when it changes.
/// `status` is nil on Macs without a battery (desktops), so the indicator hides itself there.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    struct Status: Equatable {
        var percent: Int
        var isCharging: Bool
        var onACPower: Bool
        /// Low and not plugged in: worth drawing attention to.
        var isLow: Bool { percent <= 20 && !onACPower }
    }

    @Published private(set) var status: Status?

    private var source: CFRunLoopSource?

    private init() {
        status = Self.read()
        // The system calls this on the main run loop whenever the charge, charger or power source changes.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        if let created = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
        }
    }

    private func refresh() {
        let new = Self.read()
        if new != status { status = new }
    }

    private static func read() -> Status? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let desc = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = desc[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
            return Status(percent: percent,
                          isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                          onACPower: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}
