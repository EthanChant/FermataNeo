import Foundation
import IOKit.ps
import PowerSPI

enum PowerStatus {
    struct Battery {
        let percent: Int
        let onBattery: Bool
    }

    /// The system-wide setting the helper changes; readable without privileges.
    static var sleepDisabled: Bool {
        guard let settings = IOPMCopySystemPowerSettings() as NSDictionary? else { return false }
        return (settings["SleepDisabled"] as? Bool) ?? false
    }

    /// The internal battery, or nil on a Mac without one.
    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            let state = info[kIOPSPowerSourceStateKey] as? String
            return Battery(percent: current * 100 / max, onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
