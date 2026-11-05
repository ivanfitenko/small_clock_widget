import Cocoa
import CoreGraphics

// MARK: - Config persistence

let configDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SmallClockWidget")
let configFile = configDir.appendingPathComponent("config.json")

func loadTimezone() -> TimeZone {
    if let data = try? Data(contentsOf: configFile),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
       let id = obj["timezone"], let tz = TimeZone(identifier: id) {
        return tz
    }
    return TimeZone(identifier: "UTC")!
}

func saveTimezone(_ id: String) {
    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    let obj = ["timezone": id]
    if let data = try? JSONSerialization.data(withJSONObject: obj) {
        try? data.write(to: configFile)
    }
}

func timezoneShortLabel(_ tz: TimeZone) -> String {
    let id = tz.identifier
    if let city = id.split(separator: "/").last {
        return city.replacingOccurrences(of: "_", with: " ")
    }
    return id
}

// MARK: - Widget view

final class WidgetView: NSView {
    let timeLabel = NSTextField(labelWithString: "")
    let tzLabel = NSTextField(labelWithString: "")
    var timezone: TimeZone

    init(frame: NSRect, timezone: TimeZone) {
        self.timezone = timezone
        super.init(frame: frame)
        setupLabels()
        updateTime()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setupLabels() {
        for label in [timeLabel, tzLabel] {
            label.alignment = .center
            label.isBordered = false
            label.isEditable = false
            label.drawsBackground = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        timeLabel.textColor = .labelColor
        tzLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        tzLabel.textColor = .secondaryLabelColor

        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            tzLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            tzLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 2),
        ])
    }

    func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timezone
        timeLabel.stringValue = formatter.string(from: Date())
        tzLabel.stringValue = timezoneShortLabel(timezone)
    }
}

// MARK: - Glass container

/// Wraps `content` in the real Liquid Glass material (macOS 26+): desaturated,
/// translucent, with specular highlights — falls back to a blurred
/// NSVisualEffectView on older systems.
func makeGlassContainer(frame: NSRect, cornerRadius: CGFloat, content: NSView) -> NSView {
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = cornerRadius
        glass.style = .clear
        glass.contentView = content
        return glass
    } else {
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var widgetView: WidgetView!
    var glassContainer: NSView!
    var timer: Timer?

    let commonZones = [
        "UTC", "America/New_York", "America/Chicago", "America/Los_Angeles",
        "Europe/London", "Europe/Berlin", "Europe/Paris",
        "Asia/Tokyo", "Asia/Shanghai", "Asia/Kolkata", "Asia/Dubai",
        "Australia/Sydney",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let tz = loadTimezone()
        setupWindow(timezone: tz)

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.widgetView.updateTime()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func screenParamsChanged() {
        repositionWindow()
    }

    private func computeFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 150, height: 60)
        }
        let full = screen.frame
        let visible = screen.visibleFrame

        var dockHeight = visible.origin.y - full.origin.y
        if dockHeight < 30 { dockHeight = 50 } // Dock hidden/auto-hide fallback
        if dockHeight > 110 { dockHeight = 110 }

        let width: CGFloat = 150
        let margin: CGFloat = 4
        let x = full.maxX - width - margin
        let y: CGFloat = 0
        return NSRect(x: x, y: y, width: width, height: dockHeight)
    }

    private func setupWindow(timezone: TimeZone) {
        let frame = computeFrame()
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Desktop icon level: the same layer Finder desktop icons and native
        // desktop widgets (Calendar, Weather) live on — directly above the
        // wallpaper, below all normal app windows. This is what lets their
        // glass/blur sample the real wallpaper instead of whatever window
        // happens to be on screen.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        widgetView = WidgetView(frame: NSRect(origin: .zero, size: frame.size), timezone: timezone)
        widgetView.autoresizingMask = [.width, .height]

        glassContainer = makeGlassContainer(
            frame: NSRect(origin: .zero, size: frame.size), cornerRadius: 14, content: widgetView)
        glassContainer.autoresizingMask = [.width, .height]

        let menu = buildMenu()
        widgetView.menu = menu
        glassContainer.menu = menu
        window.contentView = glassContainer

        window.orderFrontRegardless()
    }

    private func repositionWindow() {
        window.setFrame(computeFrame(), display: true)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        for id in commonZones {
            let item = NSMenuItem(title: id, action: #selector(selectTimezone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom…", action: #selector(chooseCustomTimezone), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc func selectTimezone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let tz = TimeZone(identifier: id) else { return }
        applyTimezone(tz, id: id)
    }

    @objc func chooseCustomTimezone() {
        let alert = NSAlert()
        alert.messageText = "Enter IANA timezone identifier"
        alert.informativeText = "Example: America/New_York"
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let id = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tz = TimeZone(identifier: id) {
                applyTimezone(tz, id: id)
            } else {
                let err = NSAlert()
                err.messageText = "Unknown timezone identifier: \(id)"
                err.runModal()
            }
        }
    }

    private func applyTimezone(_ tz: TimeZone, id: String) {
        widgetView.timezone = tz
        widgetView.updateTime()
        saveTimezone(id)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
