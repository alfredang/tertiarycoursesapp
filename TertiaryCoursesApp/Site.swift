import Foundation

/// The country site this build of TC LMS serves. This file is the ONLY source
/// difference between TC LMS SG, MY and GH — every other Swift file is shared
/// (see scripts/sync_variant.sh). Each app talks only to its own site's LMS.
enum Site {
    static let code = "SG"
    static let appName = "TIA LMS SG"
    static let countryName = "Singapore"
    static let siteName = "Tertiary Courses Singapore"
    static let baseURL = URL(string: "https://www.tertiarycourses.com.sg")!
    static let websiteLabel = "tertiarycourses.com.sg"
    static let email = "enquiry@tertiaryinfotech.com"
    static let phone = "+65 6100 0613"
    static let whatsApp = "6588666375"
    static let whatsAppLabel = "+65 8866 6375"
    static let currency = "SGD"
    /// Class times from the site are local to it.
    static let timeZone = "Asia/Singapore"
    static let academy = "Tertiary Infotech Academy Pte. Ltd."
    static let developerURL = URL(string: "https://www.tertiaryinfotech.com/")!
    static let privacyURL = URL(string: "https://www.tertiaryinfotech.com/privacy")!
    /// Shown beside course fees: SG lists fees before GST.
    static let priceNote = "before 9% GST"
    static let keychainService = "com.tertiaryinfotech.tertiarycoursesapp"
}
