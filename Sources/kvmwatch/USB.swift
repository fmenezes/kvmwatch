import Foundation
import IOKit

struct USBDevice {
    let vendorId: Int
    let productId: Int
    let name: String
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
            let name = (property(service, "USB Product Name") as? String) ?? "?"
            devices.append(USBDevice(vendorId: vid, productId: pid, name: name))
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
