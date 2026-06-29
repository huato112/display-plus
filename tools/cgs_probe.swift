// cgs_probe — compare what the PUBLIC CoreGraphics API exposes vs the PRIVATE CGS table,
// and report the current active mode. Answers: does DisplayPlus need to INJECT the HiDPI
// mode, or is it already in CGS and just hidden from the public API (so it only needs to
// ACTIVATE it)?
//
// Run with BetterDisplay HiDPI on, then fully QUIT BetterDisplay and run again, then diff.
//   - If the 2560x1440 density=2.0 (backing 5120x2880) row vanishes from CGS after quit -> BD injects it.
//   - If it stays -> it is a native CGS mode merely filtered out of the public API -> activate via CGS.
//
// Build:  swiftc tools/cgs_probe.swift -o tools/cgs_probe
// Run:    tools/cgs_probe > /tmp/probe_bdon.txt   (then quit BD, run again -> /tmp/probe_bdquit.txt)

import Foundation
import CoreGraphics

let RTLD_NOW_FLAG: Int32 = 2
let slHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW_FLAG)
let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW_FLAG)

func resolve(_ name: String) -> UnsafeMutableRawPointer? {
    if let s = slHandle, let p = dlsym(s, name) { return p }
    if let c = cgHandle, let p = dlsym(c, name) { return p }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
}

typealias NumModesFn   = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
typealias ModeDescFn   = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32
typealias CurModeFn    = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32

let getNumModes = resolve("CGSGetNumberOfDisplayModes").map { unsafeBitCast($0, to: NumModesFn.self) }
let getModeDesc = resolve("CGSGetDisplayModeDescriptionOfLength").map { unsafeBitCast($0, to: ModeDescFn.self) }
let getCurMode  = resolve("CGSGetCurrentDisplayMode").map { unsafeBitCast($0, to: CurModeFn.self) }

var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)

let workLen: Int32 = 212
let BUF = 1024

for id in ids {
    if CGDisplayIsBuiltin(id) != 0 { continue }
    print("=== display \(id)  vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id)) ===")

    // ---- current active mode (CGS) ----
    if let cur = getCurMode {
        var m: Int32 = -1
        let rc = cur(id, &m)
        print("CURRENT CGS mode = \(m) (rc=\(rc))")
    }

    // ---- private CGS table: only the density>=2.0 ("HiDPI") rows, compact ----
    if let nm = getNumModes, let md = getModeDesc {
        var n: Int32 = 0
        _ = nm(id, &n)
        print("--- CGS HiDPI rows (density>=2.0) of \(n) total ---")
        var buf = [UInt8](repeating: 0, count: BUF)
        for i in 0..<n {
            for k in buf.indices { buf[k] = 0 }
            if buf.withUnsafeMutableBytes({ md(id, i, $0.baseAddress!, workLen) }) != 0 { continue }
            func u32(_ o: Int) -> UInt32 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
            func u16(_ o: Int) -> UInt16 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
            func f32(_ o: Int) -> Float  { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
            let modeNum = u32(0), flags = u32(4), w = u32(8), h = u32(12)
            let freq = u16(190), density = f32(208)
            if density < 1.5 { continue }
            print(String(format: "  CGS mode=%-4u %5ux%-5u (backing %ux%u) freq=%u density=%.2f flags=0x%08x",
                         modeNum, w, h, UInt32(Float(w)*density), UInt32(Float(h)*density), freq, density, flags))
        }
    }

    // ---- public CoreGraphics API: what System Settings / DisplayPlus can see ----
    print("--- PUBLIC CGDisplayCopyAllDisplayModes (showDuplicateLowRes) ---")
    let opts = ["kCGDisplayShowDuplicateLowResolutionModes": kCFBooleanTrue as Any] as CFDictionary
    if let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] {
        print("  public mode count = \(modes.count)")
        for m in modes {
            let hidpi = m.pixelWidth > m.width   // Retina iff backing pixels > logical points
            print(String(format: "  PUB %5dx%-5d (backing %dx%d) refresh=%.0f usableGUI=%@ %@ id=%d",
                         m.width, m.height, m.pixelWidth, m.pixelHeight, m.refreshRate,
                         m.isUsableForDesktopGUI() ? "Y" : "N", hidpi ? "[HiDPI]" : "", m.ioDisplayModeID))
        }
    } else {
        print("  (CGDisplayCopyAllDisplayModes returned nil)")
    }
    print("")
}
