import CoreText
import Foundation

/// Registers fonts bundled inside the app (e.g. the SHIFTBRAIN Norms timer
/// face) into *this process* so `NSFont(name:)` / `Font.timer` resolve them even
/// on Macs where the font isn't installed system-wide.
///
/// Scope is `.process`: nothing is installed into the user's font library, and
/// the registration disappears when the app quits. Registering a font that also
/// happens to be installed is harmless (CoreText just reports it's already
/// registered), so this is safe to call unconditionally at launch.
enum AppFonts {
    private static let extensions = ["ttf", "otf", "ttc"]

    static func registerBundled() {
        var urls: [URL] = []
        for ext in extensions {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
