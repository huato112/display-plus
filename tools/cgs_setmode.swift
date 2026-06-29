// cgs_setmode — activate a CGS display mode by its CGS modeNum, via the private
// CGSConfigureDisplayMode path that BetterDisplay uses. This is the core of Method 2:
// the HiDPI mode (backing > native) is already in the CGS table; we just select it.
//
// Public CGBeginDisplayConfiguration / CGCompleteDisplayConfiguration bracket the change;
// CGSConfigureDisplayMode (private, SkyLight) sets the mode index inside the bracket.
//
// Build:  swiftc tools/cgs_setmode.swift -o tools/cgs_setmode
// Usage:  tools/cgs_setmode <displayID> <cgsModeNum>
//   e.g.  tools/cgs_setmode 3 86   -> looks like 2560x1440, backing 5120x2880 (HiDPI)
//         tools/cgs_setmode 3 61   -> 2560x1440 @ 60Hz native 1x (revert / fuzzy)

import Foundation
import CoreGraphics

let RTLD_NOW_FLAG: Int32 = 2
let slHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW_FLAG)
let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW_FLAG)
func resolve(_ n: String) -> UnsafeMutableRawPointer? {
    if let s = slHandle, let p = dlsym(s, n) { return p }
    if let c = cgHandle, let p = dlsym(c, n) { return p }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), n)
}

// CGError CGBeginDisplayConfiguration(CGDisplayConfigRef *pConfigRef)
typealias BeginFn    = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
// CGError CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display, int modeNum)
typealias SetModeFn  = @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, Int32) -> Int32
// CGError CGCompleteDisplayConfiguration(CGDisplayConfigRef config, CGConfigureOption option)
typealias CompleteFn = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
// CGError CGCancelDisplayConfiguration(CGDisplayConfigRef config)
typealias CancelFn   = @convention(c) (UnsafeMutableRawPointer?) -> Int32

guard let bPtr = resolve("CGBeginDisplayConfiguration"),
      let sPtr = resolve("CGSConfigureDisplayMode"),
      let cPtr = resolve("CGCompleteDisplayConfiguration") else {
    FileHandle.standardError.write(Data("ERROR: cannot resolve config symbols\n".utf8)); exit(1)
}
let beginCfg    = unsafeBitCast(bPtr, to: BeginFn.self)
let setMode     = unsafeBitCast(sPtr, to: SetModeFn.self)
let completeCfg = unsafeBitCast(cPtr, to: CompleteFn.self)
let cancelCfg   = resolve("CGCancelDisplayConfiguration").map { unsafeBitCast($0, to: CancelFn.self) }

let args = CommandLine.arguments
guard args.count == 3, let did = UInt32(args[1]), let mode = Int32(args[2]) else {
    FileHandle.standardError.write(Data("usage: cgs_setmode <displayID> <cgsModeNum>\n".utf8)); exit(2)
}

var cfg: UnsafeMutableRawPointer? = nil
let rb = beginCfg(&cfg)
guard rb == 0 else { print("CGBeginDisplayConfiguration failed rc=\(rb)"); exit(1) }
let rs = setMode(cfg, did, mode)
if rs != 0 {
    print("CGSConfigureDisplayMode failed rc=\(rs) — cancelling")
    _ = cancelCfg?(cfg); exit(1)
}
let kCGConfigurePermanently: UInt32 = 2
let rc = completeCfg(cfg, kCGConfigurePermanently)
print("set display \(did) -> CGS mode \(mode): begin=\(rb) setmode=\(rs) complete=\(rc)")
exit(rc == 0 ? 0 : 1)
