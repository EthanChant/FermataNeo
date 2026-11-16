import AppKit
import FermataNeoShared
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum HelperState {
        case unknown, ready, missing, outdated
    }

    private static let durations: [(title: String, seconds: TimeInterval)] = [
        ("30 Minutes", 30 * 60),
        ("1 Hour", 60 * 60),
        ("2 Hours", 2 * 60 * 60),
        ("4 Hours", 4 * 60 * 60),
    ]

    private static let batteryFloors = [0, 5, 10, 15, 20, 30]

    private let helper = HelperClient()
    private lazy var controller = SleepController(helper: helper)
    private var statusItem: NSStatusItem!
    private let statusDot = StatusDotView()
    private var helperState = HelperState.unknown

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            SleepController.batteryFloorKey: 5,
            SleepController.keepDisplayAwakeKey: false,
            SleepController.thermalProtectionKey: true,
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        // Items are enabled or greyed out explicitly in menuNeedsUpdate.
        menu.autoenablesItems = false
        statusItem.menu = menu

        if let button = statusItem.button {
            statusDot.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(statusDot)
            NSLayoutConstraint.activate([
                statusDot.widthAnchor.constraint(equalToConstant: StatusIcon.size.width),
                statusDot.heightAnchor.constraint(equalToConstant: StatusIcon.size.height),
                statusDot.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                statusDot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }

        controller.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()

        refreshHelperState {
            // `FermataNeo -StartActive YES` turns prevention on at launch.
            if UserDefaults.standard.bool(forKey: "StartActive") {
                self.start(duration: nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.isActive else { return .terminateNow }

        // Restore sleep before quitting. The helper would do it anyway when the
        // connection drops, so do not wait long.
        var replied = false
        let reply = {
            if !replied {
                replied = true
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        controller.deactivate(completion: reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reply)
        return .terminateLater
    }

    // MARK: - Status item

    private func updateIcon() {
        let label = controller.isActive ? "FermataNeo: preventing sleep" : "FermataNeo: sleep allowed"
        let image = StatusIcon.image(active: controller.isActive)
        image.accessibilityDescription = label
        statusItem.button?.image = image
        statusDot.isHidden = !controller.isActive
        statusItem.button?.toolTip = label
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(infoItem(statusText()))
        if let notice = controller.notice {
            menu.addItem(infoItem(notice))
        }
        menu.addItem(.separator())

        let toggle = item("Prevent Sleep", #selector(togglePrevent))
        toggle.state = controller.isActive ? .on : .off
        menu.addItem(toggle)

        // Ticked together with the chosen duration while a timed session runs.
        // "Prevent Sleep" ticked on its own means until turned off.
        let timed = NSMenuItem(title: "Prevent Sleep For", action: nil, keyEquivalent: "")
        timed.state = controller.duration != nil ? .on : .off
        let submenu = NSMenu()
        for (index, duration) in Self.durations.enumerated() {
            let entry = item(duration.title, #selector(preventForDuration(_:)))
            entry.tag = index
            entry.state = controller.duration == duration.seconds ? .on : .off
            submenu.addItem(entry)
        }
        timed.submenu = submenu
        menu.addItem(timed)
        menu.addItem(.separator())

        let display = item("Keep Display Awake", #selector(toggleKeepDisplayAwake))
        display.state = controller.keepDisplayAwake ? .on : .off
        // These three only apply while sleep is being prevented.
        display.isEnabled = controller.isActive
        menu.addItem(display)

        let floor = controller.batteryFloor
        let floorItem = NSMenuItem(
            title: floor > 0 ? "Stop at \(floor)% Battery" : "Stop at Low Battery: Off",
            action: nil, keyEquivalent: "")
        let floorMenu = NSMenu()
        // Include a custom value set with `defaults write`, so it shows as selected.
        for level in Set(Self.batteryFloors + [floor]).sorted() {
            let entry = item(level > 0 ? "\(level)%" : "Off", #selector(setBatteryFloor(_:)))
            entry.tag = level
            entry.state = level == floor ? .on : .off
            floorMenu.addItem(entry)
        }
        floorItem.submenu = floorMenu
        floorItem.isEnabled = controller.isActive
        menu.addItem(floorItem)

        let thermal = item("Overheating Protection", #selector(toggleThermalProtection))
        thermal.state = controller.thermalProtection ? .on : .off
        thermal.isEnabled = controller.isActive
        menu.addItem(thermal)
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        switch helperState {
        case .ready:
            menu.addItem(item("Uninstall Helper…", #selector(uninstallHelper)))
        case .outdated:
            menu.addItem(item("Update Helper…", #selector(installHelper)))
        case .missing, .unknown:
            menu.addItem(item("Install Helper…", #selector(installHelper)))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FermataNeo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func statusText() -> String {
        guard controller.isActive else { return "Sleep is allowed" }
        guard let endDate = controller.endDate else { return "Preventing sleep until turned off" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Preventing sleep until \(formatter.string(from: endDate))"
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func togglePrevent() {
        if controller.isActive {
            controller.deactivate()
        } else {
            start(duration: nil)
        }
    }

    @objc private func preventForDuration(_ sender: NSMenuItem) {
        let duration = Self.durations[sender.tag].seconds
        if !controller.isActive {
            start(duration: duration)
        } else if controller.duration == duration {
            // Clicking the ticked duration removes the timer: prevent until turned off.
            controller.reschedule(duration: nil)
        } else {
            controller.reschedule(duration: duration)
        }
    }

    @objc private func toggleKeepDisplayAwake() {
        controller.keepDisplayAwake.toggle()
    }

    @objc private func setBatteryFloor(_ sender: NSMenuItem) {
        controller.batteryFloor = sender.tag
    }

    @objc private func toggleThermalProtection() {
        controller.thermalProtection.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Could not change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func installHelper() {
        runInstaller(then: nil)
    }

    @objc private func uninstallHelper() {
        let finish = {
            self.helper.disconnect()
            if let error = HelperInstaller.uninstall(), !error.isEmpty {
                self.showAlert("Could not uninstall the helper", error)
            }
            self.refreshHelperState(then: nil)
        }
        if controller.isActive {
            controller.deactivate(completion: finish)
        } else {
            finish()
        }
    }

    // MARK: - Helper

    private func start(duration: TimeInterval?, allowInstall: Bool = true) {
        controller.activate(duration: duration) { [weak self] error in
            guard let self, case .unavailable(let detail)? = error else { return }
            NSLog("Helper unavailable: %@", detail)
            self.helperState = .missing
            guard allowInstall, self.confirmInstall() else { return }
            self.runInstaller { self.start(duration: duration, allowInstall: false) }
        }
    }

    private func confirmInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install the FermataNeo helper?"
        alert.informativeText = "Preventing sleep with the lid closed needs a small background helper "
            + "that runs with administrator rights. macOS will ask for your password once."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runInstaller(then next: (() -> Void)?) {
        helper.disconnect()
        if let error = HelperInstaller.install() {
            if !error.isEmpty { showAlert("Could not install the helper", error) }
            refreshHelperState(then: nil)
            return
        }
        refreshHelperState {
            if self.helperState == .ready {
                next?()
            } else {
                self.showAlert("The helper did not start",
                               "It was installed but is not responding. Check Console for local.FermataNeo.Helper.")
            }
        }
    }

    private func refreshHelperState(then next: (() -> Void)?) {
        helper.getVersion { [weak self] version in
            guard let self else { return }
            switch version {
            case nil: self.helperState = .missing
            case helperVersion?: self.helperState = .ready
            default: self.helperState = .outdated
            }
            next?()
        }
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
