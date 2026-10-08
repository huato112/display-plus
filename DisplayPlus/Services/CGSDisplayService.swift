import Foundation
import CoreGraphics
import OSLog

/// Low-level wrapper over the private CoreGraphics Services (CGS / SkyLight) display-mode API.
///
/// macOS generates HiDPI ("Retina") scaled modes — a backing resolution larger than the panel's
/// native pixels — for every display, but the **public** `CGDisplayCopyAllDisplayModes` hides any
/// mode whose backing exceeds native. Those modes still live in the private CGS table and can be
/// activated directly. This is exactly how BetterDisplay drives HiDPI on a plain display (no virtual
/// display, no mirroring, no plist override, no admin rights).
///
/// Verified on macOS 27 / Apple Silicon: with BetterDisplay quit, the `2560×1440 @ backing 5120×2880`
/// mode is still present in this table and can be set via `setMode`. Byte-offset probes:
/// `tools/cgs_modedump.swift` / `tools/cgs_probe.swift`.
///
/// Per the project hard rule, every private symbol is resolved with `dlopen` + `dlsym` (never
/// `@_silgen_name` or a link-time `extern`) — the CGS mode-enumeration symbols live in SkyLight,
/// which the app does not link against.
enum CGSDisplayService {
    private static let recoveryLogger = Logger(subsystem: "com.displayplus.app", category: "DisplayRecovery")

    /// One entry in the private CGS display-mode table.
    struct Mode: Equatable, Sendable {
        let number: Int32        // CGS modeNum (shares numbering with the public ioDisplayModeID)
        let width: Int           // logical ("looks like") width in points
        let height: Int          // logical ("looks like") height in points
        let refresh: Int         // refresh rate in Hz
        let density: Float       // 2.0 == HiDPI (backing pixels = logical × density)
        let flags: UInt32

        /// A Retina mode: renders larger then downscales → crisp text.
        var isHiDPI: Bool { density >= 1.5 }
        /// macOS tags "stretched"/non-desktop scaled modes with this high bit; skip them.
        var isStretched: Bool { (flags & 0x40000000) != 0 }
    }

    // MARK: - Symbol resolution (dlopen + dlsym)

    private static let RTLD_NOW: Int32 = 2
    nonisolated(unsafe) private static let slHandle =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    nonisolated(unsafe) private static let cgHandle =
        dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)

    private static func sym(_ name: String) -> UnsafeMutableRawPointer? {
        if let s = slHandle, let p = dlsym(s, name) { return p }
        if let c = cgHandle, let p = dlsym(c, name) { return p }
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
    }

    private typealias NumModesFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ModeDescFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32
    private typealias CurModeFn  = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias BeginFn    = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    private typealias SetModeFn  = @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, Int32) -> Int32
    private typealias CompleteFn = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
    private typealias CancelFn   = @convention(c) (UnsafeMutableRawPointer?) -> Int32

    private static let getNumModes = sym("CGSGetNumberOfDisplayModes").map { unsafeBitCast($0, to: NumModesFn.self) }
    private static let getModeDesc = sym("CGSGetDisplayModeDescriptionOfLength").map { unsafeBitCast($0, to: ModeDescFn.self) }
    private static let getCurMode  = sym("CGSGetCurrentDisplayMode").map { unsafeBitCast($0, to: CurModeFn.self) }
    private static let beginCfg    = sym("CGBeginDisplayConfiguration").map { unsafeBitCast($0, to: BeginFn.self) }
    private static let setModeCfg  = sym("CGSConfigureDisplayMode").map { unsafeBitCast($0, to: SetModeFn.self) }
    private static let completeCfg = sym("CGCompleteDisplayConfiguration").map { unsafeBitCast($0, to: CompleteFn.self) }
    private static let cancelCfg   = sym("CGCancelDisplayConfiguration").map { unsafeBitCast($0, to: CancelFn.self) }

    /// `CGSDisplayMode` binary layout (212 bytes). Field byte-offsets reverse-engineered on
    /// macOS 27 / Apple Silicon — see `tools/cgs_modedump.swift`.
    private enum Layout {
        static let length: Int32 = 212
        static let modeNum = 0     // u32
        static let flags   = 4     // u32
        static let width   = 8     // u32  (logical)
        static let height  = 12    // u32  (logical)
        static let freq    = 190   // u16  (Hz)
        static let density = 208   // f32  (2.0 == HiDPI)
    }

    /// Whether the private CGS mode-enumeration API resolved. If false, HiDPI activation is unsupported.
    static var isAvailable: Bool { getNumModes != nil && getModeDesc != nil }

    // MARK: - Query

    /// All modes in the private CGS table for `display`, **including** the HiDPI modes the public API hides.
    static func modes(for display: CGDirectDisplayID) -> [Mode] {
        guard let getNumModes, let getModeDesc else { return [] }
        var count: Int32 = 0
        guard getNumModes(display, &count) == 0, count > 0 else { return [] }

        var buf = [UInt8](repeating: 0, count: 1024)
        var result: [Mode] = []
        result.reserveCapacity(Int(count))
        for i in 0..<count {
            for k in buf.indices { buf[k] = 0 }
            guard buf.withUnsafeMutableBytes({ getModeDesc(display, i, $0.baseAddress!, Layout.length) }) == 0 else { continue }
            func u32(_ o: Int) -> UInt32 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
            func u16(_ o: Int) -> UInt16 { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
            func f32(_ o: Int) -> Float  { buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
            let density = f32(Layout.density)
            // Sanity check: a real density is a small positive scale. Anything else means the struct
            // layout shifted on this OS version — drop the row rather than emit garbage.
            guard density > 0.4, density < 4.0 else { continue }
            result.append(Mode(number: Int32(bitPattern: u32(Layout.modeNum)),
                               width: Int(u32(Layout.width)),
                               height: Int(u32(Layout.height)),
                               refresh: Int(u16(Layout.freq)),
                               density: density,
                               flags: u32(Layout.flags)))
        }
        return result
    }

    /// The currently active CGS mode number for `display`, or nil.
    static func currentModeNumber(for display: CGDirectDisplayID) -> Int32? {
        guard let getCurMode else { return nil }
        var m: Int32 = -1
        guard getCurMode(display, &m) == 0 else { return nil }
        return m
    }

    // MARK: - Apply

    /// Activates a CGS mode by its `number`, bracketed by `CGBeginDisplayConfiguration` /
    /// `CGCompleteDisplayConfiguration(permanently)`. Returns true if the change actually took effect
    /// (verified by reading the current mode back), not merely if the API returned success.
    ///
    /// ⚠️ **Call on the main thread.** The CGS display-configuration transaction needs main-runloop
    /// servicing; off a background queue `CGCompleteDisplayConfiguration` can stall for many seconds
    /// even though it applies eventually. The change is fast (~instant) on the main thread.
    static func setMode(_ number: Int32, for display: CGDirectDisplayID) -> Bool {
        guard let beginCfg, let setModeCfg, let completeCfg else { return false }
        var cfg: UnsafeMutableRawPointer? = nil
        guard beginCfg(&cfg) == 0 else { return false }
        guard setModeCfg(cfg, display, number) == 0 else {
            _ = cancelCfg?(cfg)
            return false
        }
        let kCGConfigurePermanently: UInt32 = 2
        guard completeCfg(cfg, kCGConfigurePermanently) == 0 else { return false }
        return currentModeNumber(for: display) == number
    }

    // MARK: - Display enable/disable (disconnect / reconnect)

    // CGSConfigureDisplayEnabled's FIRST argument is a CGDisplayConfigRef (the same opaque pointer
    // produced by CGBeginDisplayConfiguration), NOT a connection id. It must be called *inside* a
    // begin/complete transaction, exactly like CGSConfigureDisplayMode. Passing anything else (e.g.
    // a connection-id integer) makes the function dereference garbage and crashes the process.
    //   CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef config, CGDirectDisplayID display, bool enabled)
    private typealias SetEnabledFn = @convention(c) (UnsafeMutableRawPointer?, CGDirectDisplayID, Bool) -> Int32
    private static let setEnabled = sym("CGSConfigureDisplayEnabled").map { unsafeBitCast($0, to: SetEnabledFn.self) }

    /// Whether the private display enable/disable API resolved on this OS. When false, the
    /// disconnect/reconnect feature is unavailable and the UI hides its controls.
    static var canToggleDisplayEnabled: Bool { beginCfg != nil && setEnabled != nil && completeCfg != nil }

    // MARK: - Full display enumeration (includes CGS-disabled displays)

    // `SLSGetDisplayList` returns the WindowServer's full display table — a superset of
    // CGGetOnlineDisplayList that still contains displays we disabled via CGSConfigureDisplayEnabled
    // (those drop off the public online list entirely). This is how "connect to all displays"
    // recovers a display that was turned off in a previous session: enumerate here, re-enable the
    // inactive ones. Signature matches CGGetOnlineDisplayList: (maxCount, list, outCount).
    private typealias ListFn = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private static let getFullList = sym("SLSGetDisplayList").map { unsafeBitCast($0, to: ListFn.self) }

    /// Every display ID the WindowServer knows about, including ones disabled (disconnected) by us.
    /// Empty if the private symbol is unavailable. Note: the list can include placeholder/virtual
    /// slots (vendor 0), so callers that act on these IDs should filter by what they intend to touch.
    static func allKnownDisplayIDs() -> [CGDirectDisplayID] {
        guard let getFullList else { return [] }
        var count: UInt32 = 0
        guard getFullList(0, nil, &count) == 0, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var got: UInt32 = 0
        guard getFullList(count, &ids, &got) == 0 else { return [] }
        return Array(ids.prefix(Int(got)))
    }

    /// Connects (`enabled = true`) or disconnects (`enabled = false`) a display from the desktop
    /// arrangement — the mechanism behind BetterDisplay's per-display on/off. A disconnected display
    /// goes black, leaves the active arrangement (windows reflow to remaining displays), and the
    /// cursor can no longer enter its region.
    ///
    /// Bracketed by `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration(permanently)`,
    /// identical to `setMode` — `CGSConfigureDisplayEnabled` only works inside such a transaction.
    ///
    /// ⚠️ **Call on the main thread** — the CGS display-configuration path needs main-runloop
    /// servicing, the same constraint as `setMode`.
    ///
    /// Returns true if the transaction completed successfully. Verified on macOS 27 / Apple Silicon.
    static func setDisplayEnabled(_ enabled: Bool, for display: CGDirectDisplayID) -> Bool {
        guard let beginCfg, let setEnabled, let completeCfg else { return false }
        var cfg: UnsafeMutableRawPointer? = nil
        let beginResult = beginCfg(&cfg)
        guard beginResult == 0 else {
            recoveryLogger.error("Begin display transaction failed id=\(display, privacy: .public), error=\(beginResult, privacy: .public)")
            return false
        }
        let setResult = setEnabled(cfg, display, enabled)
        guard setResult == 0 else {
            recoveryLogger.error("Set display enabled failed id=\(display, privacy: .public), enabled=\(enabled, privacy: .public), error=\(setResult, privacy: .public)")
            _ = cancelCfg?(cfg)
            return false
        }
        let kCGConfigurePermanently: UInt32 = 2
        let completeResult = completeCfg(cfg, kCGConfigurePermanently)
        if completeResult != 0 {
            recoveryLogger.error("Complete display transaction failed id=\(display, privacy: .public), error=\(completeResult, privacy: .public)")
        }
        return completeResult == 0
    }
}
