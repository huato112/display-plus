import Foundation
import CoreGraphics

// Compile this harness with the production DisplayConnectionService.swift only.
// These module-local stand-ins shadow CoreGraphics queries and CGS writes so the
// regression scenarios never change the computer's actual display configuration.
@MainActor
enum DisplaySystem {
    struct Panel {
        let builtin: Bool
        var active: Bool
        var online: Bool
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
    }

    static var panels: [CGDirectDisplayID: Panel] = [:]
    static var fullListAvailable = true
    static var toggleAvailable = true
    static var failReconnect = false
    static var deferReconnect = false
    static var invalidPublicIDs: Set<CGDirectDisplayID> = []
    static var writes: [(CGDirectDisplayID, Bool)] = []

    static var onlineIDs: [CGDirectDisplayID] {
        panels.filter { $0.value.online }.map { $0.key }
    }

    static func reset() {
        panels = [
            1: Panel(builtin: true, active: true, online: true, vendor: 1, model: 1, serial: 1),
            2: Panel(builtin: false, active: true, online: true, vendor: 2, model: 2, serial: 2)
        ]
        fullListAvailable = true
        toggleAvailable = true
        failReconnect = false
        deferReconnect = false
        invalidPublicIDs = []
        writes = []
    }
}

@MainActor
func CGDisplayIsActive(_ id: CGDirectDisplayID) -> Int32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? -1 : (DisplaySystem.panels[id]?.active == true ? 1 : 0)
}
@MainActor
func CGDisplayIsBuiltin(_ id: CGDirectDisplayID) -> Int32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? -1 : (DisplaySystem.panels[id]?.builtin == true ? 1 : 0)
}
@MainActor
func CGDisplayIsOnline(_ id: CGDirectDisplayID) -> Int32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? -1 : (DisplaySystem.panels[id]?.online == true ? 1 : 0)
}
@MainActor
func CGDisplayVendorNumber(_ id: CGDirectDisplayID) -> UInt32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? UInt32.max : (DisplaySystem.panels[id]?.vendor ?? 0)
}
@MainActor
func CGDisplayModelNumber(_ id: CGDirectDisplayID) -> UInt32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? UInt32.max : (DisplaySystem.panels[id]?.model ?? 0)
}
@MainActor
func CGDisplaySerialNumber(_ id: CGDirectDisplayID) -> UInt32 {
    DisplaySystem.invalidPublicIDs.contains(id) ? UInt32.max : (DisplaySystem.panels[id]?.serial ?? 0)
}
@MainActor
@discardableResult
func CGGetActiveDisplayList(_ maxDisplays: UInt32, _ ids: UnsafeMutablePointer<CGDirectDisplayID>?,
                            _ count: UnsafeMutablePointer<UInt32>?) -> CGError {
    let active = DisplaySystem.panels.filter { $0.value.active }.map { $0.key }
    if let ids {
        for (index, id) in active.prefix(Int(maxDisplays)).enumerated() { ids[index] = id }
        count?.pointee = UInt32(min(Int(maxDisplays), active.count))
    } else {
        count?.pointee = UInt32(active.count)
    }
    return .success
}

@MainActor
final class DisplayInfo {
    let displayID: CGDirectDisplayID
    let isBuiltin: Bool
    let hardwareID: String

    init(_ id: CGDirectDisplayID) {
        displayID = id
        isBuiltin = CGDisplayIsBuiltin(id) != 0
        hardwareID = "v\(CGDisplayVendorNumber(id))-m\(CGDisplayModelNumber(id))-s\(CGDisplaySerialNumber(id))"
    }
}

@MainActor
enum CGSDisplayService {
    static var canToggleDisplayEnabled: Bool { DisplaySystem.toggleAvailable }
    static func allKnownDisplayIDs() -> [CGDirectDisplayID] {
        DisplaySystem.fullListAvailable ? Array(DisplaySystem.panels.keys) : []
    }
    static func setDisplayEnabled(_ enabled: Bool, for id: CGDirectDisplayID) -> Bool {
        DisplaySystem.writes.append((id, enabled))
        guard DisplaySystem.panels[id] != nil, !(enabled && DisplaySystem.failReconnect) else { return false }
        if enabled && DisplaySystem.deferReconnect { return true }
        DisplaySystem.invalidPublicIDs.remove(id)
        DisplaySystem.panels[id]?.active = enabled
        DisplaySystem.panels[id]?.online = enabled
        return true
    }
}

@main
struct DisplayConnectionRecoveryTests {
    @MainActor
    static func main() {
        var passed = 0
        func scenario(_ name: String, _ body: (DisplayConnectionService, UserDefaults) -> Void) {
            DisplaySystem.reset()
            let suite = "DisplayPlus.RecoveryTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            body(DisplayConnectionService(defaults: defaults), defaults)
            passed += 1
            print("PASS: \(name)")
        }
        func recover(_ service: DisplayConnectionService, _ known: [DisplayInfo] = []) -> Bool {
            service.recoverBuiltinIfNeeded(onlineDisplayIDs: DisplaySystem.onlineIDs, knownDisplays: known)
        }
        func unplug(_ id: CGDirectDisplayID = 2) { DisplaySystem.panels[id] = nil }

        scenario("unplug last external recovers disabled built-in and clears off state") { service, _ in
            let builtin = DisplayInfo(1)
            let external = DisplayInfo(2)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            precondition(recover(service, [builtin, external]))
            precondition(CGDisplayIsActive(1) != 0)
            precondition(!service.isDisconnected(displayID: 1))
            precondition(!service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
            let writes = DisplaySystem.writes.count
            precondition(!recover(service, [builtin]))
            precondition(DisplaySystem.writes.count == writes, "recovery must be idempotent")
        }
        scenario("keep built-in off while another active external remains") { service, _ in
            DisplaySystem.panels[3] = DisplaySystem.panels[2]
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            precondition(!recover(service, [builtin]))
            precondition(CGDisplayIsActive(1) == 0)
            precondition(service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
        }
        scenario("recover after relaunch when built-in is absent from public list") { service, defaults in
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            DisplaySystem.panels[1]?.active = false
            DisplaySystem.panels[1]?.online = false
            unplug()
            precondition(recover(service))
            precondition(CGDisplayIsActive(1) != 0)
            precondition(!service.isMarkedDisconnected(hardwareID: "v1-m1-s1"))
        }
        scenario("clear preference when macOS already restored built-in") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            DisplaySystem.panels[1]?.active = true
            DisplaySystem.panels[1]?.online = true
            let writes = DisplaySystem.writes.count
            precondition(!recover(service, [builtin]))
            precondition(DisplaySystem.writes.count == writes)
            precondition(!service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
            precondition(!service.isDisconnected(displayID: 1))
            DisplaySystem.panels[2] = DisplaySystem.Panel(builtin: false, active: true, online: true,
                                                         vendor: 2, model: 2, serial: 2)
            service.restoreAll(displays: [builtin, DisplayInfo(2)])
            precondition(CGDisplayIsActive(1) != 0, "wake restore must not turn recovered panel off again")
        }
        scenario("failed reconnect keeps state and succeeds on retry") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            DisplaySystem.failReconnect = true
            precondition(!recover(service, [builtin]))
            precondition(service.isDisconnected(displayID: 1))
            precondition(service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
            DisplaySystem.failReconnect = false
            precondition(recover(service, [builtin]))
            precondition(!service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
        }
        scenario("recovery uses reassigned live ID and removes stale tracking") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            DisplaySystem.panels[10] = DisplaySystem.panels.removeValue(forKey: 1)
            unplug()
            let writes = DisplaySystem.writes.count
            precondition(recover(service, [builtin]))
            precondition(CGDisplayIsActive(10) != 0)
            precondition(!service.isDisconnected(displayID: 1))
            precondition(DisplaySystem.writes.count == writes + 1)
            precondition(DisplaySystem.writes.last?.0 == 10)
        }
        scenario("cached built-in remains recoverable without private full list") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            DisplaySystem.fullListAvailable = false
            precondition(recover(service, [builtin]))
        }
        scenario("inactive external cannot prevent built-in recovery") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            DisplaySystem.panels[2]?.active = false
            precondition(recover(service, [builtin]))
        }
        scenario("do not enable unmarked panels or disabled external displays") { service, defaults in
            DisplaySystem.panels[1]?.active = false
            DisplaySystem.panels[1]?.online = false
            DisplaySystem.panels[2]?.active = false
            defaults.set(true, forKey: "fd.display.disconnected.v2-m2-s2")
            precondition(!recover(service))
            precondition(DisplaySystem.writes.isEmpty)
        }
        scenario("built-in recovery preserves a disabled external's off preference") { service, defaults in
            DisplaySystem.panels[1]?.active = false
            DisplaySystem.panels[1]?.online = false
            DisplaySystem.panels[2]?.active = false
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            defaults.set(true, forKey: "fd.display.disconnected.v2-m2-s2")
            precondition(recover(service))
            precondition(CGDisplayIsActive(1) != 0)
            precondition(CGDisplayIsActive(2) == 0)
            precondition(service.isMarkedDisconnected(hardwareID: "v2-m2-s2"))
            precondition(DisplaySystem.writes.count == 1 && DisplaySystem.writes[0].0 == 1)
        }
        scenario("unsupported toggle API leaves preference intact") { service, defaults in
            DisplaySystem.toggleAvailable = false
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            unplug()
            precondition(!recover(service))
            precondition(service.isMarkedDisconnected(hardwareID: "v1-m1-s1"))
            precondition(DisplaySystem.writes.isEmpty)
        }
        scenario("accepted transaction keeps monitor armed until activation is verified") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            DisplaySystem.deferReconnect = true
            precondition(recover(service, [builtin]))
            precondition(service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
            precondition(service.isDisconnected(displayID: 1))
            precondition(service.needsBuiltinRecoveryMonitoring(knownDisplays: [builtin]))
            DisplaySystem.panels[1]?.active = true
            DisplaySystem.panels[1]?.online = true
            precondition(!recover(service, [builtin]))
            precondition(!service.needsBuiltinRecoveryMonitoring(knownDisplays: [builtin]))
        }
        scenario("monitor remains armed beyond initial retries without any callback") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            for _ in 0..<10 {
                precondition(service.needsBuiltinRecoveryMonitoring(knownDisplays: [builtin]))
                precondition(!recover(service, [builtin]))
            }
            unplug()
            precondition(recover(service, [builtin]))
            precondition(!service.needsBuiltinRecoveryMonitoring(knownDisplays: [builtin]))
        }
        scenario("monitor discovers off built-in after relaunch with no cached rows") { service, defaults in
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            DisplaySystem.panels[1]?.active = false
            DisplaySystem.panels[1]?.online = false
            precondition(service.needsBuiltinRecoveryMonitoring(knownDisplays: []))
        }
        scenario("headless virtual fallback must not block built-in recovery") { service, _ in
            let builtin = DisplayInfo(1)
            precondition(service.disconnect(builtin) == nil)
            unplug()
            DisplaySystem.panels[6] = DisplaySystem.Panel(builtin: false, active: true, online: true,
                                                         vendor: 0x756e6b6e, model: 0x76697274, serial: 0)
            // The actual unplug logs also showed -1 public query results for the off panel.
            DisplaySystem.invalidPublicIDs.insert(1)
            precondition(recover(service, [builtin]))
            precondition(CGDisplayIsActive(1) > 0)
            precondition(!service.isMarkedDisconnected(hardwareID: builtin.hardwareID))
        }
        scenario("virtual fallback cannot bypass the last-physical-screen guard") { service, _ in
            unplug()
            DisplaySystem.panels[6] = DisplaySystem.Panel(builtin: false, active: true, online: true,
                                                         vendor: 0, model: 0, serial: 0)
            precondition(service.disconnect(DisplayInfo(1)) != nil)
            precondition(CGDisplayIsActive(1) > 0)
            precondition(DisplaySystem.writes.isEmpty)
        }
        scenario("wake restore cannot turn built-in off beside a virtual fallback") { service, defaults in
            unplug()
            DisplaySystem.panels[6] = DisplaySystem.Panel(builtin: false, active: true, online: true,
                                                         vendor: 0x756e6b6e, model: 0x76697274, serial: 0)
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            service.restoreAll(displays: [DisplayInfo(1), DisplayInfo(6)])
            precondition(CGDisplayIsActive(1) > 0)
            precondition(DisplaySystem.writes.isEmpty)
        }
        scenario("relaunch caches off panel before headless queries become unavailable") { service, defaults in
            defaults.set(true, forKey: "fd.display.disconnected.v1-m1-s1")
            DisplaySystem.panels[1]?.active = false
            DisplaySystem.panels[1]?.online = false
            precondition(service.needsBuiltinRecoveryMonitoring(knownDisplays: []))
            unplug()
            DisplaySystem.invalidPublicIDs.insert(1)
            DisplaySystem.panels[6] = DisplaySystem.Panel(builtin: false, active: true, online: true,
                                                         vendor: 0x756e6b6e, model: 0x76697274, serial: 0)
            precondition(service.needsBuiltinRecoveryMonitoring(knownDisplays: []))
            precondition(recover(service))
            precondition(CGDisplayIsActive(1) > 0)
            precondition(!service.needsBuiltinRecoveryMonitoring(knownDisplays: []))
        }
        print("\(passed) display recovery scenarios passed")
    }
}
