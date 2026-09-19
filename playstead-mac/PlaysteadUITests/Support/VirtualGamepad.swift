import Foundation
import IOKit.hid

/// Finite virtual HID producer used only by the non-distributed UI-test runner.
final class VirtualGamepad {
    enum Failure: Error, LocalizedError {
        case invalidDescriptor, createFailed(IOReturn), notConnected, reportFailed(IOReturn)
        var errorDescription: String? {
            switch self {
            case .invalidDescriptor: "PLAYSTEAD_FAILURE_STAGE[invalid-hid-descriptor]"
            case .createFailed(let code): "PLAYSTEAD_FAILURE_STAGE[hid-create]: \(code)"
            case .notConnected: "PLAYSTEAD_FAILURE_STAGE[hid-not-connected]"
            case .reportFailed(let code): "PLAYSTEAD_FAILURE_STAGE[hid-report]: \(code)"
            }
        }
    }

    static let controllerName = "Playstead Virtual Gamepad"
    // Conventional desktop-gamepad collection: face buttons, d-pad, shoulders,
    // Menu and Options. It is compiled in; environment data is never accepted.
    private static let descriptor = Data([
        0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01,
        0x05, 0x09, 0x19, 0x01, 0x29, 0x08, 0x15, 0x00, 0x25, 0x01, 0x95, 0x08, 0x75, 0x01, 0x81, 0x02,
        0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x08, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
        0x75, 0x04, 0x95, 0x01, 0x81, 0x03, 0xC0
    ])
    private var device: IOHIDUserDevice?

    func connect() throws { try connect(using: Self.descriptor) }
    func connect(using candidate: Data) throws {
        guard candidate == Self.descriptor else { throw Failure.invalidDescriptor }
        disconnect()
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: Self.descriptor,
            kIOHIDVendorIDKey as String: 0x5053,
            kIOHIDProductIDKey as String: 0x0317,
            kIOHIDProductKey as String: Self.controllerName,
            kIOHIDManufacturerKey as String: "Playstead Tests",
            kIOHIDPrimaryUsagePageKey as String: 0x01,
            kIOHIDPrimaryUsageKey as String: 0x05
        ]
        guard let created = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties as CFDictionary, 0) else {
            throw Failure.createFailed(kIOReturnError)
        }
        device = created
    }
    func disconnect() { device = nil }
    func press(_ button: UInt8) throws { try send(buttons: button, hat: 8) }
    func release() throws { try send(buttons: 0, hat: 8) }
    func direction(_ hat: UInt8) throws {
        guard hat <= 8 else { throw Failure.reportFailed(kIOReturnBadArgument) }
        try send(buttons: 0, hat: hat)
    }
    private func send(buttons: UInt8, hat: UInt8) throws {
        guard let device else { throw Failure.notConnected }
        var report = [UInt8(1), buttons, hat]
        let result = IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(), &report, report.count)
        guard result == kIOReturnSuccess else { throw Failure.reportFailed(result) }
    }
}
