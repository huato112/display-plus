import Foundation
import CoreGraphics

// Probe: which display-enumeration list still includes a CGS-DISABLED display?
//
// A display disabled via CGSConfigureDisplayEnabled(false) drops off
// CGGetOnlineDisplayList entirely (it even vanishes from system_profiler).
// To implement BetterDisplay-style "connect to all displays" we need a list
// that STILL contains the disabled display so we can grab its
// CGDirectDisplayID and call setDisplayEnabled(true).
//
// This run is SELF-RESTORING: it disconnects the first external display,
// dumps every candidate list while it is disabled, then re-enables it. Your
// screen blinks off for ~2 s and comes back. (BetterDisplay's "connect to
// all displays" is the safety net if anything goes wrong.)
//
// Build & run:
//   swiftc tools/display_list_probe.swift -o /tmp/dlprobe && /tmp/dlprobe

let RTLD_NOW: Int32 = 2
let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)

func sym(_ n: String) -> UnsafeMutableRawPointer? {
    if let s = sl, let p = dlsym(s, n) { return p }
    if let c = cg, let p = dlsym(c, n) { return p }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), n)
}

typealias ListFn  = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> Int32
typealias BeginFn = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
typealias EnFn    = @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, Bool) -> Int32
typealias DoneFn  = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32

let beginCfg = sym("CGBeginDisplayConfiguration").map { unsafeBitCast($0, to: BeginFn.self) }
let setEn    = sym("CGSConfigureDisplayEnabled").map { unsafeBitCast($0, to: EnFn.self) }
let doneCfg  = sym("CGCompleteDisplayConfiguration").map { unsafeBitCast($0, to: DoneFn.self) }

func setEnabled(_ on: Bool, _ id: CGDirectDisplayID) -> Bool {
    guard let beginCfg, let setEn, let doneCfg else { return false }
    var cfg: UnsafeMutableRawPointer? = nil
    guard beginCfg(&cfg) == 0 else { return false }
    guard setEn(cfg, id, on) == 0 else { return false }
    return doneCfg(cfg, 2) == 0   // kCGConfigurePermanently
}

func call(_ name: String) -> (err: Int32, ids: [CGDirectDisplayID])? {
    guard let p = sym(name) else { return nil }
    let fn = unsafeBitCast(p, to: ListFn.self)
    var count: UInt32 = 0
    guard fn(0, nil, &count) == 0 else { return (-1, []) }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    var got: UInt32 = 0
    guard fn(count, &ids, &got) == 0 else { return (-2, []) }
    return (0, Array(ids.prefix(Int(got))))
}

func describe(_ id: CGDirectDisplayID) -> String {
    let v = CGDisplayVendorNumber(id), m = CGDisplayModelNumber(id), s = CGDisplaySerialNumber(id)
    let active = CGDisplayIsActive(id) != 0 ? "active" : "INACTIVE"
    let online = CGDisplayIsOnline(id) != 0 ? "online" : "OFFLINE"
    let builtin = CGDisplayIsBuiltin(id) != 0 ? " builtin" : ""
    return "id=\(id) v\(v)-m\(m)-s\(s) [\(active),\(online)\(builtin)]"
}

let LISTS = ["SLSGetDisplayList", "SLSGetPotentiallyActiveDisplayList",
             "SLSGetOnlineDisplayList", "SLSGetActiveDisplayList"]

func dumpAll(_ title: String) {
    print("\n========== \(title) ==========")
    var c: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &c)
    var pub = [CGDirectDisplayID](repeating: 0, count: Int(c))
    CGGetOnlineDisplayList(c, &pub, &c)
    print("CGGetOnlineDisplayList:")
    for id in pub.prefix(Int(c)) { print("  " + describe(id)) }
    if let r = call("SLSGetDisplayList"), r.err == 0 {
        print("SLSGetDisplayList (full, with identity):")
        for id in r.ids { print("  " + describe(id)) }
    }
    for name in LISTS where name != "SLSGetDisplayList" {
        guard let r = call(name), r.err == 0 else { print("\(name): (err)"); continue }
        print("\(name): \(r.ids.map { "\($0)" }.joined(separator: ","))")
    }
}

func spin(_ secs: Double) { RunLoop.current.run(until: Date().addingTimeInterval(secs)) }

// Pick the external display to toggle: not builtin, active, online, real vendor.
var c: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &c)
var online = [CGDirectDisplayID](repeating: 0, count: Int(c))
CGGetOnlineDisplayList(c, &online, &c)
let target = online.prefix(Int(c)).first {
    CGDisplayIsBuiltin($0) == 0 && CGDisplayIsActive($0) != 0 && CGDisplayVendorNumber($0) != 0
}

dumpAll("BASELINE (all connected)")

guard let target else {
    print("\n⚠️ No external display found to toggle. Connect one and rerun.")
    exit(0)
}
print("\n>>> disabling external display \(describe(target)) ...")
guard setEnabled(false, target) else { print("disable failed"); exit(1) }
spin(2.0)
dumpAll("DISABLED (target \(target) off)  <-- which list still shows id=\(target)?")

print("\n>>> re-enabling display \(target) ...")
_ = setEnabled(true, target)
spin(2.0)
dumpAll("RESTORED")
print("\n✅ done — your display should be back. (If not, use BetterDisplay → connect to all displays.)")
