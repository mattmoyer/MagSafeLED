// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import os
import CSMC
import Shared
import SMCKit

let log = Logger(subsystem: "com.moyer.magsafeledd", category: "led")

// MARK: - Debug CLI: magsafeledd --read KEY | --write KEY HEX

let args = CommandLine.arguments
if args.count >= 3, args[1] == "--read" || args[1] == "--write" {
    do {
        let smc = try SMC()
        if args[1] == "--read" {
            let bytes = try smc.read(args[2])
            print(bytes.map { String(format: "%02x", $0) }.joined())
        } else {
            guard args.count == 4, args[3].count % 2 == 0 else {
                FileHandle.standardError.write("usage: --write KEY HEXBYTES\n".data(using: .utf8)!)
                exit(2)
            }
            let hex = Array(args[3])
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
            try smc.write(args[2], bytes)
            print("ok")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - Enforcer

final class Enforcer {
    static let stateDir = URL(fileURLWithPath: "/Library/Application Support/MagSafeLED")
    static let stateFile = stateDir.appendingPathComponent("led-off")

    private let smc: SMC
    private let queue = DispatchQueue.main
    private var fallbackTimer: Timer?
    private(set) var ledOff: Bool

    init() throws {
        smc = try SMC()
        ledOff = FileManager.default.fileExists(atPath: Enforcer.stateFile.path)
    }

    func setLEDOff(_ off: Bool) throws {
        ledOff = off
        if off {
            try FileManager.default.createDirectory(at: Enforcer.stateDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: Enforcer.stateFile.path, contents: nil)
            try write(MagSafeLED.off)
        } else {
            try? FileManager.default.removeItem(at: Enforcer.stateFile)
            try write(MagSafeLED.system)
        }
        log.info("LED off = \(off)")
    }

    private func write(_ value: UInt8) throws {
        try smc.write(MagSafeLED.key, [value])
    }

    /// Rewrite only if firmware changed it.
    func enforce(reason: String) {
        guard ledOff else { return }
        do {
            let current = try smc.read(MagSafeLED.key).first
            if current != MagSafeLED.off {
                try write(MagSafeLED.off)
                log.info("re-applied LED off (\(reason, privacy: .public); was \(current.map { String($0) } ?? "nil", privacy: .public))")
            }
        } catch {
            log.error("enforce failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Firmware resets the LED shortly after power events, so hit it a few times.
    func burst(reason: String) {
        for delay in [0.0, 0.1, 0.3, 0.6, 1.0, 2.0, 3.0] {
            queue.asyncAfter(deadline: .now() + delay) { self.enforce(reason: reason) }
        }
    }

    func start() {
        if ledOff { burst(reason: "startup") }

        // Power source / adapter changes.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<Enforcer>.fromOpaque(ctx!).takeUnretainedValue().burst(reason: "power source change")
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        // Wake from sleep.
        var notifier: io_object_t = 0
        var port: IONotificationPortRef?
        let root = IORegisterForSystemPower(ctx, &port, { ctx, _, messageType, argument in
            let enforcer = Unmanaged<Enforcer>.fromOpaque(ctx!).takeUnretainedValue()
            switch messageType {
            case CSMCMessageSystemHasPoweredOn:
                enforcer.burst(reason: "wake")
            case CSMCMessageCanSystemSleep, CSMCMessageSystemWillSleep:
                IOAllowPowerChange(enforcer.rootPort, Int(bitPattern: argument))
            default: break
            }
        }, &notifier)
        rootPort = root
        if root != 0, let port {
            CFRunLoopAddSource(CFRunLoopGetMain(),
                               IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        }

        // Fallback for resets that don't produce a notification (e.g. charge state changes).
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.enforce(reason: "periodic check")
        }
    }

    fileprivate var rootPort: io_connect_t = 0
}

// MARK: - XPC

final class HelperService: NSObject, MagSafeLEDHelperProtocol {
    let enforcer: Enforcer
    init(enforcer: Enforcer) { self.enforcer = enforcer }

    func setLEDOff(_ off: Bool, reply: @escaping (Bool, String?) -> Void) {
        DispatchQueue.main.async {
            do {
                try self.enforcer.setLEDOff(off)
                reply(true, nil)
            } catch {
                reply(false, String(describing: error))
            }
        }
    }

    func getLEDOff(reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { reply(self.enforcer.ledOff) }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: HelperService
    init(service: HelperService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // Light guard: only root or the user currently logged in at the console.
        var st = stat()
        let consoleUID = stat("/dev/console", &st) == 0 ? st.st_uid : 0
        let uid = conn.effectiveUserIdentifier
        guard uid == 0 || uid == consoleUID else {
            log.error("rejected XPC connection from uid \(uid)")
            return false
        }
        conn.exportedInterface = NSXPCInterface(with: MagSafeLEDHelperProtocol.self)
        conn.exportedObject = service
        conn.resume()
        return true
    }
}

guard getuid() == 0 else {
    FileHandle.standardError.write("magsafeledd must run as root (it is meant to be started by launchd)\n".data(using: .utf8)!)
    exit(1)
}

let enforcer: Enforcer
do { enforcer = try Enforcer() } catch {
    log.fault("cannot open SMC: \(String(describing: error), privacy: .public)")
    exit(1)
}
enforcer.start()

let delegate = ListenerDelegate(service: HelperService(enforcer: enforcer))
let listener = NSXPCListener(machServiceName: helperMachServiceName)
listener.delegate = delegate
listener.resume()
log.info("magsafeledd started, LED off = \(enforcer.ledOff)")
RunLoop.main.run()
