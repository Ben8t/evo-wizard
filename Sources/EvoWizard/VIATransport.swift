import Foundation
import IOKit.hid

/// VIA raw-HID command ids (QMK `via.h`).
enum VIACommand: UInt8 {
    case protocolVersion = 0x01
    case setKeycode = 0x05
    case customSetValue = 0x07
    case customGetValue = 0x08
    case customSave = 0x09
    case layerCount = 0x11
    case keymapGetBuffer = 0x12
}

/// Raw-HID transport to a VIA-enabled QMK keyboard (usage page 0xFF60, usage 0x61).
///
/// HID callbacks run on a private thread's run loop; requests are serialized on a
/// dispatch queue and block until the keyboard echoes a 32-byte response.
final class VIATransport: @unchecked Sendable {
    static let reportSize = 32

    /// Called on the HID thread with (connected, product name).
    var onConnectionChange: ((Bool, String?) -> Void)?

    private let manager: IOHIDManager
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
    private let commands = DispatchQueue(label: "evo.via.commands")
    private let condition = NSCondition()
    private var device: IOHIDDevice?
    private var response: [UInt8]?

    init(vendorID: Int, productID: Int) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDPrimaryUsagePageKey: 0xFF60,
            kIOHIDPrimaryUsageKey: 0x61,
        ] as CFDictionary)
    }

    func start() {
        let thread = Thread { [self] in
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
                Unmanaged<VIATransport>.fromOpaque(context!).takeUnretainedValue().attach(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
                Unmanaged<VIATransport>.fromOpaque(context!).takeUnretainedValue().detach(device)
            }, context)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopRun()
        }
        thread.name = "evo.via.hid"
        thread.start()
    }

    /// Sends a VIA command and returns the keyboard's response, or nil on timeout / no device.
    func request(_ bytes: [UInt8]) async -> [UInt8]? {
        await withCheckedContinuation { continuation in
            commands.async { continuation.resume(returning: self.transact(bytes)) }
        }
    }

    // MARK: - HID thread

    private func attach(_ device: IOHIDDevice) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, Self.reportSize, { context, _, _, _, _, report, length in
            let transport = Unmanaged<VIATransport>.fromOpaque(context!).takeUnretainedValue()
            transport.receive(Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        condition.lock()
        self.device = device
        condition.unlock()
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        onConnectionChange?(true, name)
    }

    private func detach(_ device: IOHIDDevice) {
        condition.lock()
        guard self.device == device else { condition.unlock(); return }
        self.device = nil
        condition.broadcast()
        condition.unlock()
        onConnectionChange?(false, nil)
    }

    private func receive(_ bytes: [UInt8]) {
        condition.lock()
        response = bytes
        condition.broadcast()
        condition.unlock()
    }

    // MARK: - Command queue

    private func transact(_ bytes: [UInt8]) -> [UInt8]? {
        condition.lock()
        defer { condition.unlock() }
        guard let device else { return nil }
        response = nil

        var report = Array(bytes.prefix(Self.reportSize))
        report += Array(repeating: 0, count: Self.reportSize - report.count)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, report, report.count)
        guard result == kIOReturnSuccess else { return nil }

        let deadline = Date().addingTimeInterval(0.5)
        while response == nil, self.device != nil {
            if !condition.wait(until: deadline) { break }
        }
        return response
    }
}
