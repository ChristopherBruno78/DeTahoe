//
//  IconUnboxer.swift
//  Detahoe
//
//  Finds apps whose icon macOS Tahoe would drop into a gray "box" and gives them
//  an unboxed custom icon instead — a compiled port of unbox-app-icons.swift.
//
//  Tahoe masks every app icon to the system squircle. Full-bleed icons render
//  fine; free-form/legacy icons (art with transparent margins) get composited
//  onto a gray rounded background — the "gray box". Installing the app's own
//  icon as a *custom Finder icon* skips that boxing (the programmatic version of
//  dragging an icon into Get Info). NSWorkspace.setIcon must run in the user's
//  GUI session, which it does here since this runs inside the app process.
//

import AppKit
import Foundation

// Result of an unbox pass, for reporting. Top-level @objc class (not nested) so
// it appears in the ObjC runtime under the explicit name `UnboxSummary`.
@objc(UnboxSummary) final class UnboxSummary: NSObject {
    @objc let unboxed: [String]          // app names that got their icon installed
    @objc let appStoreSkipped: [String]  // skipped: Mac App Store / OS-protected
    init(unboxed: [String], appStoreSkipped: [String]) {
        self.unboxed = unboxed
        self.appStoreSkipped = appStoreSkipped
    }
}

// Explicit @objc name so the ObjC class symbol is exactly `IconUnboxer`, letting
// AppDelegate call it via a hand-written IconUnboxer.h instead of the generated
// Detahoe-Swift.h (which importing SwiftUI anywhere in the module would empty).
@objc(IconUnboxer) final class IconUnboxer: NSObject {

    /// Detect boxed-prone icons and install each app's own icon as a custom icon.
    /// Returns a summary of what was unboxed and what was skipped.
    @objc(unboxInDirectories:)
    @discardableResult
    static func unbox(inDirectories dirs: [String]) -> UnboxSummary {
        return run(undo: false, searchDirs: dirs)
    }

    /// Remove the custom Finder icons this tool installed, restoring defaults.
    /// Returns a summary; `unboxed` holds the apps that were restored.
    @objc(undoInDirectories:)
    @discardableResult
    static func undo(inDirectories dirs: [String]) -> UnboxSummary {
        return run(undo: true, searchDirs: dirs)
    }

    // MARK: - Icon loading

    /// Locates the app's primary .icns file inside its bundle Resources, if any.
    private static func icnsURL(for app: Bundle) -> URL? {
        guard let resources = app.resourceURL else { return nil }
        // Try CFBundleIconFile (may be missing its extension), then any .icns.
        if let name = app.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let base = (name as NSString).lastPathComponent
            let withExt = base.hasSuffix(".icns") ? base : base + ".icns"
            let candidate = resources.appendingPathComponent(withExt)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let icns = (try? FileManager.default.contentsOfDirectory(at: resources,
                        includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "icns" }
        // Prefer the largest .icns (usually the app icon vs. document icons).
        return icns?.max { (a, b) in
            let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sa < sb
        }
    }

    /// Returns the largest bitmap representation of an NSImage as CGImage.
    private static func largestBitmap(_ image: NSImage) -> CGImage? {
        var best: NSBitmapImageRep?
        for rep in image.representations {
            guard let bmp = rep as? NSBitmapImageRep else { continue }
            if best == nil || bmp.pixelsWide > best!.pixelsWide { best = bmp }
        }
        if let cg = best?.cgImage { return cg }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - Boxing heuristic

    /// How "rounded-square" the icon's opaque shape is. All macOS .icns have
    /// transparent gutters, so we first crop to the opaque bounding box, then ask
    /// what fraction of that box the art fills:
    ///   * A full-bleed rounded-square (squircle) fills ~0.90+  → NOT boxed.
    ///   * A circle fills ~0.79, a free-form/irregular shape less → BOXED.
    /// We also require the bounding box to be near-square and to cover most of the
    /// canvas; tiny or lopsided art is boxed too. Returns the fill fraction, or
    /// 1.0 (treat as fine) if it can't be measured.
    private static func shapeFill(_ cg: CGImage) -> Double {
        let w = cg.width, h = cg.height
        guard w > 16, h > 16, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return 1 }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func a(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }

        // Opaque bounding box.
        var minX = w, minY = h, maxX = -1, maxY = -1, opaque = 0
        for y in 0..<h { for x in 0..<w where a(x, y) > 128 {
            opaque += 1
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        } }
        guard maxX >= minX, maxY >= minY else { return 0 }        // fully transparent
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let fill = Double(opaque) / Double(bw * bh)
        let coverage = Double(bw * bh) / Double(w * h)            // art vs canvas
        let aspect = Double(min(bw, bh)) / Double(max(bw, bh))    // 1.0 == square

        // Non-square or small art gets boxed regardless of fill.
        if aspect < 0.88 || coverage < 0.55 { return 0 }
        return fill
    }

    /// Icons filling < 92% of a square bounding box are free-form/round → Tahoe
    /// boxes them. Measured on real apps, genuine full-bleed squircles pack their
    /// bounding box at 0.95–0.96, while boxed shapes land ≤0.89 — so 0.92 sits in
    /// the clean gap between the two clusters.
    private static let boxThreshold = 0.92

    // MARK: - Writability / SIP guards

    private static func isProtected(_ path: String) -> Bool {
        // System apps live under /System and are SIP-sealed; never touch them.
        return path.hasPrefix("/System/")
    }

    private static func isWritable(_ path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: path)
    }

    /// True if the bundle carries a custom Finder icon (an "Icon\r" resource
    /// file), i.e. something this tool (or a manual Get Info drag) installed.
    private static func hasCustomIcon(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Icon\r"))
    }

    // MARK: - Main

    @discardableResult
    private static func run(undo: Bool, searchDirs: [String]) -> UnboxSummary {
        let dirs = searchDirs.isEmpty ? ["/Applications"] : searchDirs
        var checked = 0, boxed = 0, fixed = 0, skipped = 0
        var unboxedNames: [String] = []
        var appStoreSkipped: [String] = []

        for dir in dirs {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for entry in entries.sorted() where entry.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(entry)
                guard let bundle = Bundle(path: path) else { continue }
                checked += 1

                // --undo: strip any custom Finder icon, restoring the OS-drawn
                // (boxed) one. setIcon(nil,…) is the inverse of the install below.
                if undo {
                    guard hasCustomIcon(path) else { continue }
                    boxed += 1                                   // reuse = "had custom icon"
                    let name = (entry as NSString).deletingPathExtension
                    if isProtected(path) || !isWritable(path) {
                        NSLog("Detahoe: ▣ %@: has custom icon — SKIP (protected/read-only)", entry)
                        appStoreSkipped.append(isAppStore(path) ? name : "\(name) (system app)")
                        skipped += 1
                        continue
                    }
                    if NSWorkspace.shared.setIcon(nil, forFile: path, options: []) {
                        NSLog("Detahoe: ↩ %@: custom icon removed (back to default)", entry)
                        unboxedNames.append(name)
                        fixed += 1
                    } else {
                        NSLog("Detahoe: ✗ %@: setIcon(nil) failed — skipped", entry)
                        skipped += 1
                    }
                    continue
                }

                guard let icns = icnsURL(for: bundle), let img = NSImage(contentsOf: icns),
                      let cg = largestBitmap(img) else {
                    NSLog("Detahoe: • %@: no readable .icns (asset catalog?) — skipped", entry)
                    skipped += 1
                    continue
                }

                let fill = shapeFill(cg)
                guard fill < boxThreshold else { continue }
                boxed += 1

                if isProtected(path) || !isWritable(path) {
                    // macOS protects app bundles you don't own (SIP for /System,
                    // App Management for App Store / root-owned apps) so that even
                    // root can't modify them without a private Apple entitlement.
                    // These can't be unboxed programmatically, so skip them.
                    NSLog("Detahoe: ▣ %@: would be boxed (fill %d%%) — SKIP (protected by macOS)",
                          entry, Int(fill * 100))
                    let name = (entry as NSString).deletingPathExtension
                    appStoreSkipped.append(isAppStore(path) ? name : "\(name) (system app)")
                    skipped += 1
                    continue
                }

                // Install the app's own icon as a custom Finder icon → unboxed.
                if NSWorkspace.shared.setIcon(img, forFile: path, options: []) {
                    NSLog("Detahoe: ✔ %@: unboxed (custom icon installed)", entry)
                    unboxedNames.append((entry as NSString).deletingPathExtension)
                    fixed += 1
                } else {
                    NSLog("Detahoe: ✗ %@: setIcon failed — skipped", entry)
                    skipped += 1
                }
            }
        }

        NSLog("Detahoe: unbox %@ — %d checked, %d boxed, %d %@, %d skipped",
              undo ? "undo" : "apply", checked, boxed, fixed,
              undo ? "restored" : "unboxed", skipped)
        return UnboxSummary(unboxed: unboxedNames, appStoreSkipped: appStoreSkipped)
    }

    /// True if the bundle was installed from the Mac App Store (has a _MASReceipt).
    private static func isAppStore(_ path: String) -> Bool {
        let receipt = (path as NSString).appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receipt)
    }
}
