// Build identity — version from Info.plist, commit injected by build script
import Foundation

enum BuildIdentity {
    /// App version from Info.plist (CFBundleShortVersionString + build).
    static let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build  = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (build \(build))"
    }()

    static let gitSHA = "ba0b000"
    static let buildTimestampUTC = "045600"
}
