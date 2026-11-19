// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ServiceManagement
import Shared
import SMCKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "Turn MagSafe LED Off", action: #selector(toggleLED), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private var connection: NSXPCConnection?
    private var ledOff = false
    private var helperReachable = false
    private let smc = try? SMC()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Stable identity so macOS remembers its position (and can list it in Menu Bar settings).
        statusItem.autosaveName = "MagSafeLEDStatusItem"
        statusItem.behavior = .removalAllowed
        toggleItem.target = self
        loginItem.target = self
        statusLine.isEnabled = false
        menu.addItem(toggleItem)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    /// Opening the app again (Spotlight, Finder, `open`) pops the menu up at the mouse pointer.
    /// This matters on notched Macs, where a crowded menubar hides new icons behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            self.menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        return false
    }

    // MARK: XPC

    private func helper(onError: @escaping (Error) -> Void) -> MagSafeLEDHelperProtocol? {
        if connection == nil {
            let c = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: MagSafeLEDHelperProtocol.self)
            c.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async { onError(error) }
        } as? MagSafeLEDHelperProtocol
    }

    private func refresh() {
        helper { [weak self] _ in
            self?.helperReachable = false
            self?.updateUI()
        }?.getLEDOff { [weak self] off in
            DispatchQueue.main.async {
                self?.helperReachable = true
                self?.ledOff = off
                self?.updateUI()
            }
        }
        updateUI()
    }

    @objc private func toggleLED() {
        let want = !ledOff
        helper { [weak self] error in
            self?.helperReachable = false
            self?.updateUI()
            self?.alert("Helper not reachable", "Install it with scripts/install.sh.\n\n\(error.localizedDescription)")
        }?.setLEDOff(want) { [weak self] ok, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.helperReachable = true
                if ok { self.ledOff = want } else { self.alert("Couldn't change LED", message ?? "Unknown error") }
                self.updateUI()
            }
        }
    }

    // MARK: Login item

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change login item", error.localizedDescription)
        }
        updateUI()
    }

    // MARK: UI

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func updateUI() {
        let symbol = ledOff ? "bolt.slash" : "bolt"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MagSafe LED")
        toggleItem.state = ledOff ? .on : .off
        toggleItem.isEnabled = helperReachable

        let raw = (try? smc?.read(MagSafeLED.key).first).flatMap { $0 }
        let led: String
        switch raw {
        case MagSafeLED.system: led = "system"
        case MagSafeLED.off: led = "off"
        case MagSafeLED.green: led = "green"
        case MagSafeLED.orange: led = "orange"
        case let v?: led = String(format: "0x%02x", v)
        case nil: led = "unknown"
        }
        statusLine.title = helperReachable ? "LED: \(led)" : "Helper not installed (run scripts/install.sh)"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
