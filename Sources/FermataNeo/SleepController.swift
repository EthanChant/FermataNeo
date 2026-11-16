import Foundation
import IOKit.pwr_mgt

/// Owns the "prevent sleep" state and the safety rules that end it. Main thread only.
final class SleepController {
    static let batteryFloorKey = "BatteryFloorPercent"
    static let keepDisplayAwakeKey = "KeepDisplayAwake"
    static let thermalProtectionKey = "ThermalProtection"

    private(set) var isActive = false
    /// nil while active means "until turned off".
    private(set) var endDate: Date?
    /// The length of the running timed session; nil when off or indefinite.
    private(set) var duration: TimeInterval?
    /// Why the last session ended or failed to start, for the menu.
    private(set) var notice: String?

    var onChange: (() -> Void)?

    private let helper: HelperClient
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var displayAssertion: IOPMAssertionID = 0

    init(helper: HelperClient) {
        self.helper = helper

        helper.onInterrupted = { [weak self] in self?.reassert() }
        helper.onInvalidated = { [weak self] in
            guard let self, self.isActive else { return }
            self.stop(notice: "Stopped: lost contact with the helper", tellHelper: false)
        }

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() }
    }

    /// Battery percentage at which prevention stops while unplugged. 0 means never.
    var batteryFloor: Int {
        get { UserDefaults.standard.integer(forKey: Self.batteryFloorKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.batteryFloorKey)
            check()
            onChange?()
        }
    }

    /// Stop when macOS reports a serious or critical thermal state.
    var thermalProtection: Bool {
        get { UserDefaults.standard.bool(forKey: Self.thermalProtectionKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.thermalProtectionKey)
            check()
            onChange?()
        }
    }

    var keepDisplayAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Self.keepDisplayAwakeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.keepDisplayAwakeKey)
            updateDisplayAssertion()
            onChange?()
        }
    }

    // MARK: - Start / stop

    func activate(duration: TimeInterval?, completion: @escaping (HelperError?) -> Void) {
        if let reason = safetyStopReason() {
            notice = "Not started: \(reason)"
            onChange?()
            completion(nil)
            return
        }

        helper.setSleepDisabled(true) { [weak self] error in
            guard let self else { return }
            if let error {
                if case .rejected = error {
                    self.notice = "Not started: \(error.message)"
                    self.onChange?()
                }
                completion(error)
                return
            }

            self.isActive = true
            self.duration = duration
            self.endDate = duration.map { Date().addingTimeInterval($0) }
            self.notice = nil
            self.startMonitoring()
            self.onChange?()
            completion(nil)
        }
    }

    /// Changes the timer of a running session (nil = until turned off) without
    /// letting go of sleep prevention in between.
    func reschedule(duration: TimeInterval?) {
        guard isActive else { return }
        self.duration = duration
        endDate = duration.map { Date().addingTimeInterval($0) }
        onChange?()
    }

    func deactivate(completion: (() -> Void)? = nil) {
        stop(notice: nil, tellHelper: true, completion: completion)
    }

    private func stop(notice: String?, tellHelper: Bool, completion: (() -> Void)? = nil) {
        isActive = false
        endDate = nil
        duration = nil
        self.notice = notice
        stopMonitoring()
        onChange?()

        guard tellHelper else {
            completion?()
            return
        }
        helper.setSleepDisabled(false) { error in
            if let error { NSLog("Could not restore sleep: %@", error.message) }
            completion?()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Keeps timers firing on schedule (no App Nap) and blocks idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated], reason: "FermataNeo is preventing sleep")
        updateDisplayAssertion()

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        updateDisplayAssertion()
    }

    private func check() {
        guard isActive else { return }

        if let endDate, Date() >= endDate {
            stop(notice: "Stopped: timer finished", tellHelper: true)
            return
        }
        if let reason = safetyStopReason() {
            NSLog("Stopping sleep prevention: %@", reason)
            stop(notice: "Stopped: \(reason)", tellHelper: true)
            return
        }
        // Something else (e.g. `pmset disablesleep 0`) switched it off under us.
        if !PowerStatus.sleepDisabled {
            reassert()
        }
    }

    private func reassert() {
        guard isActive else { return }
        helper.setSleepDisabled(true) { [weak self] error in
            guard let self, self.isActive, let error else { return }
            self.stop(notice: "Stopped: \(error.message)", tellHelper: false)
        }
    }

    private func safetyStopReason() -> String? {
        let floor = batteryFloor
        if floor > 0, let battery = PowerStatus.battery(), battery.onBattery, battery.percent <= floor {
            return "battery reached \(floor)%"
        }
        guard thermalProtection else { return nil }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return "the Mac is running too hot"
        default:
            return nil
        }
    }

    private func updateDisplayAssertion() {
        let wanted = isActive && keepDisplayAwake
        if wanted && displayAssertion == 0 {
            IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "FermataNeo is keeping the display awake" as CFString,
                &displayAssertion)
        } else if !wanted && displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
    }
}
