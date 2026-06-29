// cgs_modedump — dump raw CGS display-mode descriptors for external displays.
//
// Purpose: reverse-engineer how BetterDisplay injects HiDPI modes (backing > native).
// Run with BetterDisplay HiDPI OFF, then ON, and diff the output — the injected
// "looks like 2560x1440 @ backing 5120x2880" mode will appear as a new descriptor.
//
// Uses private CGS/SkyLight symbols resolved at runtime via dlopen+dlsym (no SIP needed).
//   CGSGetNumberOfDisplayModes(display, *count)
//   CGSGetDisplayModeDescriptionOfLength(display, index, *desc, length)
//
// Build:  swiftc tools/cgs_modedump.swift -o tools/cgs_modedump
// Run:    tools/cgs_modedump > /tmp/modes_off.txt   (then toggle BD, run again)

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

typealias NumModesFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
typealias ModeDescFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32

guard let nmPtr = resolve("CGSGetNumberOfDisplayModes"),
      let mdPtr = resolve("CGSGetDisplayModeDescriptionOfLength") else {
    FileHandle.standardError.write(Data("ERROR: cannot resolve CGS symbols\n".utf8))
    exit(1)
}
let getNumModes = unsafeBitCast(nmPtr, to: NumModesFn.self)
let getModeDesc = unsafeBitCast(mdPtr, to: ModeDescFn.self)

var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)

// Known community layout of CGSDisplayMode (~212 bytes); probe a few sizes for safety.
let candidateLengths: [Int32] = [212, 224, 232, 256, 0xD4]
let BUF = 1024

for id in ids {
    if CGDisplayIsBuiltin(id) != 0 { continue }
    var n: Int32 = 0
    let rc = getNumModes(id, &n)
    print("=== display \(id)  vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id))  modes=\(n) (rc=\(rc)) ===")

    var buf = [UInt8](repeating: 0, count: BUF)
    var workLen: Int32 = 0
    for L in candidateLengths {
        let r = buf.withUnsafeMutableBytes { getModeDesc(id, 0, $0.baseAddress!, L) }
        if r == 0 { workLen = L; break }
    }
    guard workLen > 0 else { print("  (no working struct length found)"); continue }
    print("  struct length = \(workLen)")

    for i in 0..<n {
        for k in buf.indices { buf[k] = 0 }
        let r = buf.withUnsafeMutableBytes { getModeDesc(id, i, $0.baseAddress!, workLen) }
        if r != 0 { continue }
        func u32(_ o: Int) -> UInt32 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
        func u16(_ o: Int) -> UInt16 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
        func f32(_ o: Int) -> Float  { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
        // Field offsets per community CGSDisplayMode layout.
        let modeNum = u32(0), flags = u32(4), w = u32(8), h = u32(12), depth = u32(16)
        let freq = u16(190)
        let density = f32(208)
        print(String(format: "  idx=%-3d mode=%-5u %5ux%-5u depth=%u freq=%u density=%.3f flags=0x%08x",
                     i, modeNum, w, h, depth, freq, density, flags))
        let hex = (0..<Int(workLen)).map { String(format: "%02x", buf[$0]) }.joined()
        print("    hex=\(hex)")
    }
}
