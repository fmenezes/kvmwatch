import Foundation
import IOKit

struct USBDevice {
    let vendorId: Int
    let productId: Int
    let locationId: Int
    let name: String

    /// Stable identity across polls (locationID is unique per port/device).
    var key: String {
        let ids = String(format: "%04X:%04X", vendorId, productId)
        return locationId != 0 ? "\(locationId)-\(ids)-\(name)" : "\(ids)-\(name)"
    }

    var label: String { String(format: "0x%04X:0x%04X  %@", vendorId, productId, name) }
}

/// Native IOKit USB inspection — no `ioreg` subprocess, no polling of the shell.
enum USB {
    static func present(vid: Int, pid: Int) -> Bool {
        for cls in ["IOUSBHostDevice", "IOUSBDevice"] {
            let service = matching(cls: cls, vid: vid, pid: pid)
            if service != 0 {
                IOObjectRelease(service)
                return true
            }
        }
        return false
    }

    static func all() -> [USBDevice] {
        // IOUSBHostDevice is the modern class; fall back to legacy IOUSBDevice
        // only if the modern class yields nothing (avoids double-listing).
        let modern = devices(of: "IOUSBHostDevice")
        return modern.isEmpty ? devices(of: "IOUSBDevice") : modern
    }

    private static func devices(of cls: String) -> [USBDevice] {
        guard let matchingDict = IOServiceMatching(cls) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [USBDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let vid = (property(service, "idVendor") as? NSNumber)?.intValue ?? 0
            let pid = (property(service, "idProduct") as? NSNumber)?.intValue ?? 0
            let location = (property(service, "locationID") as? NSNumber)?.intValue ?? 0
            let name = (property(service, "USB Product Name") as? String) ?? "?"
            devices.append(USBDevice(vendorId: vid, productId: pid, locationId: location, name: name))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices
    }

    private static func matching(cls: String, vid: Int, pid: Int) -> io_service_t {
        guard let matchingDict = IOServiceMatching(cls) else { return 0 }
        let dict = matchingDict as NSMutableDictionary
        dict["idVendor"] = vid
        dict["idProduct"] = pid
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        return IOIteratorNext(iterator)
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue()
    }
}
