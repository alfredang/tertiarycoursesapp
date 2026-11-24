import SwiftUI
import UserNotifications

/// Class reminders as local notifications, scheduled on this device from the
/// class list — no push service. For every current or upcoming class, teaching
/// or attending:
///   • 3 days before the first day, 09:00
///   • the evening before each class day, 18:00
///   • the morning of each class day, 08:00 (an hour before the start when it is earlier)
/// The whole schedule is rebuilt each time the classes refresh.
enum Reminders {
    static let enabledKey = "reminders.enabled"
    private static let askedKey = "reminders.asked"
    /// iOS keeps at most 64 pending local notifications per app.
    private static let cap = 60

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    struct Planned {
        let id: String
        let fire: DateComponents
        let date: Date
        let title: String
        let body: String
    }

    /// Rebuilds the schedule. Asks for permission the first time classes load.
    @MainActor
    static func sync(with store: LearnerStore) async {
        let center = UNUserNotificationCenter.current()
        guard enabled, store.isSignedIn else {
            center.removeAllPendingNotificationRequests()
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["DUMP_REMINDERS"] == "1" {
            let f = ISO8601DateFormatter()
            f.timeZone = TimeZone(identifier: Site.timeZone)
            for p in plan(store.allClasses, showRole: store.isTrainer) {
                NSLog("REMINDER %@ | %@ | %@ | %@", f.string(from: p.date), p.id, p.title, p.body)
            }
        }
        #endif
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, !UserDefaults.standard.bool(forKey: askedKey), !skipPrompt {
            UserDefaults.standard.set(true, forKey: askedKey)
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let planned = plan(store.allClasses, showRole: store.isTrainer)
        center.removeAllPendingNotificationRequests()
        for p in planned {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: p.fire, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Asks for permission from the Account toggle. Returns the resulting status.
    static func requestPermission() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await center.notificationSettings().authorizationStatus
    }

    /// The next reminders, soonest first, capped. Pure, so it can be checked on its own.
    static func plan(_ classes: [ClassItem], showRole: Bool, now: Date = Date()) -> [Planned] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: Site.timeZone) ?? .current
        var out: [Planned] = []

        func add(_ item: ClassItem, kind: String, day: Date, hour: Int, minute: Int, lead: String) {
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = hour
            c.minute = minute
            c.timeZone = cal.timeZone
            c.calendar = cal
            guard let date = cal.date(from: c), date > now else { return }
            let verb = showRole ? (item.isTeaching ? "Teaching" : "Attending") : "Class"
            let time = Fmt.times(item.startTime, item.endTime)
            let place = item.mode == "Live Online"
                ? "Live online"
                : [item.room, item.venue].filter { !$0.isEmpty }.joined(separator: ", ")
            let detail = [time, place].filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(Planned(
                id: "class-\(item.runId)-\(item.role ?? "learner")-\(kind)-\(Fmt.ymd(day))",
                fire: c, date: date,
                title: "\(verb) \(lead): \(item.title)",
                body: detail.isEmpty ? Site.siteName : detail
            ))
        }

        for item in classes where item.runId > 0 && item.bucket != "past" && !item.isPendingPayment {
            let days = item.classDays.compactMap { ymd -> Date? in
                let p = ymd.split(separator: "-").compactMap { Int($0) }
                guard p.count == 3 else { return nil }
                return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
            }
            guard let first = days.first else { continue }
            if let early = cal.date(byAdding: .day, value: -3, to: first) {
                add(item, kind: "3d", day: early, hour: 9, minute: 0, lead: "in 3 days")
            }
            let hm = item.startTime.split(separator: ":").compactMap { Int($0) }
            for day in days {
                if let eve = cal.date(byAdding: .day, value: -1, to: day) {
                    add(item, kind: "eve", day: eve, hour: 18, minute: 0, lead: "tomorrow")
                }
                if hm.count == 2, hm[0] >= 1, hm[0] * 60 + hm[1] <= 8 * 60 + 30 {
                    add(item, kind: "day", day: day, hour: hm[0] - 1, minute: hm[1], lead: "in 1 hour")
                } else {
                    add(item, kind: "day", day: day, hour: 8, minute: 0, lead: "today")
                }
            }
        }
        return Array(out.sorted { $0.date < $1.date }.prefix(cap))
    }

    /// Screenshot automation signs in on launch; don't cover the screen with the prompt.
    private static var skipPrompt: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        return env["UITEST_SIGNIN"] != nil && env["REMINDER_PROMPT"] != "1"
        #else
        return false
        #endif
    }
}

/// Shows a reminder as a banner even while the app is open.
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Account → Class reminders: the switch, and what to do when iOS has them turned off.
struct ReminderSettingsRow: View {
    @EnvironmentObject private var store: LearnerStore
    @AppStorage(Reminders.enabledKey) private var enabled = true
    @State private var status: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            Toggle(isOn: $enabled) {
                Label("Class reminders", systemImage: "bell.badge.fill")
            }
            .tint(Theme.brand)
            .accessibilityIdentifier("reminderToggle")
            if enabled && status == .denied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for \(Site.appName) in Settings, so reminders can't be shown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        .onChange(of: enabled) { _, on in
            Task {
                if on, status == .notDetermined { status = await Reminders.requestPermission() }
                await Reminders.sync(with: store)
                await refreshStatus()
            }
        }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
