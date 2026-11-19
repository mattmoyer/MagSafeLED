// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public let helperMachServiceName = "com.moyer.magsafeledd"

/// XPC interface exposed by the root helper. `ledOff` true = keep LED off, false = firmware controls it.
@objc public protocol MagSafeLEDHelperProtocol {
    func setLEDOff(_ off: Bool, reply: @escaping (Bool, String?) -> Void)
    func getLEDOff(reply: @escaping (Bool) -> Void)
}
