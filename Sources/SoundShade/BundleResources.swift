import Foundation

extension Bundle {
    /// Resource bundle for shipped resources (m1ddc, SVG icons, audio driver).
    ///
    /// In the packaged .app, `build_app.sh` copies `SoundShade_SoundShade.bundle`
    /// into `Contents/Resources`, so we resolve it from `Bundle.main.resourceURL`.
    ///
    /// We deliberately avoid SwiftPM's `Bundle.module`: its generated accessor
    /// hardcodes an absolute build path (on whatever volume the package was built,
    /// e.g. an external drive) as a fallback. In the shipped app that fallback
    /// makes resource lookups reach for the build volume at runtime, triggering
    /// macOS "removable volume" access prompts. Loading from Contents/Resources
    /// keeps everything self-contained and properly code-signed.
    ///
    /// Falls back to `.module` only for `swift run` / unit tests, where no .app
    /// wrapper exists.
    static let appResources: Bundle = {
        if let resURL = Bundle.main.resourceURL?
            .appendingPathComponent("SoundShade_SoundShade.bundle"),
           let bundle = Bundle(url: resURL) {
            return bundle
        }
        return .module
    }()
}
