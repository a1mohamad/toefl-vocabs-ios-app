import SwiftUI

// MARK: - Language

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case system
    case english
    case persian

    var id: String { rawValue }

    /// Always shown in the language's own script, never translated.
    var nativeName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .persian: return "فارسی"
        }
    }

    var isRightToLeft: Bool { resolved == .persian }

    /// `.system` resolved against the device's preferred languages.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fa") ? .persian : .english
    }

    var layoutDirection: LayoutDirection {
        isRightToLeft ? .rightToLeft : .leftToRight
    }
}

// MARK: - Keys

/// Every piece of UI copy in the app.
///
/// Deliberately a Swift table rather than `.strings` files in `.lproj` folders:
/// localized resource bundles are one of the easier things to misconfigure in a
/// generated Xcode project, and a misconfiguration here would only show up as
/// raw keys on screen after a full CI round trip. A plain dictionary cannot
/// fail to build, is unit-testable (see `StringsTests`), and moves to a String
/// Catalog later without touching a single call site.
enum StringKey: String, CaseIterable {
    // Common
    case commonCancel, commonDone, commonClose, commonNext, commonStart
    case commonContinue, commonBack, commonReset, commonQuit, commonKeepGoing

    // Tabs
    case tabStudy, tabReports, tabSettings

    // Library
    case libraryTitle, librarySubtitle, libraryContinue, libraryEmpty, libraryEmptyHint

    // Book
    case bookSectionsCount, bookWordsCount, bookStart, bookAbout, bookProgress

    // Section
    case sectionChooseList, sectionBegin, sectionAbout
    case categoryMain, categoryExtra, categoryMainSubtitle, categoryExtraSubtitle
    case sectionNeedWork, sectionNotStarted, sectionComplete, sectionNoExtras

    // Practice
    case practiceKnewIt, practiceDidntKnow, practiceMeaning, practiceNextWord
    case practiceFinish, practiceProgress, practiceLastFive, practiceThisCycle
    case practiceCycleComplete, practiceQuitTitle, practiceQuitMessage
    case practiceTapToHear, practiceNewWord, practiceCorrectTally, practiceWrongTally
    case practiceSpeakLabel, practiceChecklistLabel

    // Summary
    case summaryTitle, summaryAccuracy, summaryAnswered, summaryNextSection
    case summaryPracticeAgain, summaryBackToMenu, summaryBookComplete, summaryHeadline

    // Reports
    case reportsTitle, reportsOverall, reportsMastered, reportsSeen, reportsAccuracy
    case reportsByBook, reportsWeakest, reportsRecent, reportsExtraPractice
    case reportsExtraSubtitle, reportsStartDrill, reportsEmpty, reportsEmptyHint
    case reportsMainVsExtra, reportsScope, reportsRun, reportsWordsTotal, statWords
    case scopeWeakest25, scopeWeakest50, scopeEverything

    // Restart / loop
    case restartTitle, restartMessage, restartAction, restartLater
    case extraLoopTitle, extraLoopMessage

    // Settings
    case settingsTitle, settingsAppearance, settingsTheme
    case themeSystem, themeLight, themeDark
    case settingsLanguage, settingsPronunciation, settingsAccent
    case accentAmerican, accentBritish, accentAustralian
    case settingsSpeed, speedSlow, speedNormal, speedFast
    case settingsAutoSpeak, settingsAutoSpeakHint, settingsHaptics
    case settingsData, settingsResetProgress, settingsResetMessage
    case settingsExportProgress, settingsImportProgress, settingsBackupHint
    case backupRestoreTitle, backupRestoreMessage, backupRestoreAction
    case backupRestoredTitle, backupExportFailed, backupImportFailed, commonOK
    case settingsPrivacy, settingsPrivacyBody, settingsAbout, settingsVersion
    case aboutTitle, aboutBody, aboutContentTitle, aboutContentBody
}

// MARK: - Table

/// Resolves keys for the active language, falling back to English for any key a
/// translation is missing so a gap shows readable copy, never a raw key.
struct Strings {
    let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language.resolved
    }

    subscript(_ key: StringKey) -> String {
        if language == .persian, let value = Self.persian[key] { return value }
        return Self.english[key] ?? key.rawValue
    }

    /// For keys whose value contains `%d` / `%@` placeholders.
    func format(_ key: StringKey, _ arguments: CVarArg...) -> String {
        String(format: self[key], arguments: arguments)
    }

    static let english: [StringKey: String] = [
        .commonCancel: "Cancel",
        .commonDone: "Done",
        .commonClose: "Close",
        .commonNext: "Next",
        .commonStart: "Start",
        .commonContinue: "Continue",
        .commonBack: "Back",
        .commonReset: "Reset",
        .commonQuit: "Quit",
        .commonKeepGoing: "Keep going",

        .tabStudy: "Study",
        .tabReports: "Reports",
        .tabSettings: "Settings",

        .libraryTitle: "Library",
        .librarySubtitle: "%d words across two books",
        .libraryContinue: "Pick up where you left off",
        .libraryEmpty: "No vocabulary found",
        .libraryEmptyHint: "The bundled content files could not be read. This is a packaging problem, not something you did.",

        .bookSectionsCount: "%d sections",
        .bookWordsCount: "%d words",
        .bookStart: "Start studying",
        .bookAbout: "About this book",
        .bookProgress: "Progress",

        .sectionChooseList: "Choose a list",
        .sectionBegin: "Begin",
        .sectionAbout: "About this section",
        .categoryMain: "Main",
        .categoryExtra: "Extra",
        .categoryMainSubtitle: "The book's own word list",
        .categoryExtraSubtitle: "Extra words you collected",
        .sectionNeedWork: "%d need work",
        .sectionNotStarted: "Not started",
        .sectionComplete: "Complete",
        .sectionNoExtras: "No extra words in this section",

        .practiceKnewIt: "I knew it",
        .practiceDidntKnow: "Didn't know",
        .practiceMeaning: "Meaning",
        .practiceNextWord: "Next word",
        .practiceFinish: "Finish",
        .practiceProgress: "%d of %d",
        .practiceLastFive: "Last 5",
        .practiceThisCycle: "This cycle",
        .practiceCycleComplete: "Cycle complete",
        .practiceQuitTitle: "Quit this session?",
        .practiceQuitMessage: "Everything you have answered so far is already saved.",
        .practiceTapToHear: "Tap to hear it",
        .practiceNewWord: "First time",
        .practiceCorrectTally: "%d right",
        .practiceWrongTally: "%d wrong",
        .practiceSpeakLabel: "Pronounce %@",
        .practiceChecklistLabel: "%d of %d answered, %d correct",

        .summaryTitle: "Section complete",
        .summaryAccuracy: "Accuracy",
        .summaryAnswered: "Answered",
        .summaryNextSection: "Next section",
        .summaryPracticeAgain: "Practise again",
        .summaryBackToMenu: "Back to menu",
        .summaryBookComplete: "That was the last section in this book.",
        .summaryHeadline: "Nice work",

        .reportsTitle: "Reports",
        .reportsOverall: "Overall",
        .reportsMastered: "Mastered",
        .reportsSeen: "Seen",
        .reportsAccuracy: "Accuracy",
        .reportsByBook: "By book",
        .reportsWeakest: "Needs the most work",
        .reportsRecent: "Recent sessions",
        .reportsExtraPractice: "Extra practice",
        .reportsExtraSubtitle: "Drill your weakest words from anywhere in the library. Kept separate from main progress.",
        .reportsStartDrill: "Start drill",
        .reportsEmpty: "Nothing to report yet",
        .reportsEmptyHint: "Finish a section and your numbers will show up here.",
        .reportsMainVsExtra: "Main vs extra",
        .reportsScope: "How many words",
        .reportsRun: "Run %d",
        .reportsWordsTotal: "%d words",
        .statWords: "Words",
        .scopeWeakest25: "Weakest 25",
        .scopeWeakest50: "Weakest 50",
        .scopeEverything: "Everything",

        .restartTitle: "You've been through everything",
        .restartMessage: "Every word has finished a full five-answer cycle. Starting a new run clears the checklists so you can go again — your history and accuracy are kept.",
        .restartAction: "Start a new run",
        .restartLater: "Not yet",
        .extraLoopTitle: "Full pass complete",
        .extraLoopMessage: "You've drilled every word in this scope. The list starts again from the weakest.",

        .settingsTitle: "Settings",
        .settingsAppearance: "Appearance",
        .settingsTheme: "Theme",
        .themeSystem: "System",
        .themeLight: "Light",
        .themeDark: "Dark",
        .settingsLanguage: "Language",
        .settingsPronunciation: "Pronunciation",
        .settingsAccent: "Accent",
        .accentAmerican: "American",
        .accentBritish: "British",
        .accentAustralian: "Australian",
        .settingsSpeed: "Speed",
        .speedSlow: "Slow",
        .speedNormal: "Normal",
        .speedFast: "Fast",
        .settingsAutoSpeak: "Speak each new word",
        .settingsAutoSpeakHint: "Pronounces a word automatically as it appears.",
        .settingsHaptics: "Haptics",
        .settingsData: "Data",
        .settingsResetProgress: "Reset all progress",
        .settingsResetMessage: "This erases every checklist, counter and session record. It cannot be undone.",
        .settingsExportProgress: "Export progress",
        .settingsImportProgress: "Import progress",
        .settingsBackupHint: "Save your practice history to a file before reinstalling, and restore it afterwards.",
        .backupRestoreTitle: "Replace current progress?",
        .backupRestoreMessage: "Restoring overwrites everything currently saved on this device with the contents of the backup.",
        .backupRestoreAction: "Restore",
        .backupRestoredTitle: "Progress restored",
        .backupExportFailed: "Could not export progress",
        .backupImportFailed: "Could not import progress",
        .commonOK: "OK",
        .settingsPrivacy: "Privacy",
        .settingsPrivacyBody: "Everything stays on this device. There is no account, no analytics, no network access of any kind — the word lists are bundled inside the app and your progress is a single file in the app's own storage. Deleting the app deletes all of it.",
        .settingsAbout: "About",
        .settingsVersion: "Version",
        .aboutTitle: "About",
        .aboutBody: "An offline vocabulary trainer built around two classic TOEFL word lists. No account, no subscription, no connection required.",
        .aboutContentTitle: "Word lists",
        .aboutContentBody: "504 Absolutely Essential Words (Barron's) and 400 Must-Have Words for the TOEFL (McGraw-Hill). Definitions are study notes, not the publishers' text.",
    ]

    /// Second language slot. Any key missing here falls back to English, so this
    /// table can be filled in incrementally.
    static let persian: [StringKey: String] = [
        .commonCancel: "انصراف",
        .commonDone: "تمام",
        .commonClose: "بستن",
        .commonNext: "بعدی",
        .commonStart: "شروع",
        .commonContinue: "ادامه",
        .commonBack: "بازگشت",
        .commonReset: "بازنشانی",
        .commonQuit: "خروج",
        .commonKeepGoing: "ادامه می‌دهم",

        .tabStudy: "مطالعه",
        .tabReports: "گزارش‌ها",
        .tabSettings: "تنظیمات",

        .libraryTitle: "کتابخانه",
        .librarySubtitle: "%d واژه در دو کتاب",
        .libraryContinue: "ادامه از جایی که بودید",
        .libraryEmpty: "واژه‌ای پیدا نشد",
        .libraryEmptyHint: "فایل‌های محتوا خوانده نشدند. این یک مشکل بسته‌بندی برنامه است.",

        .bookSectionsCount: "%d بخش",
        .bookWordsCount: "%d واژه",
        .bookStart: "شروع مطالعه",
        .bookAbout: "درباره این کتاب",
        .bookProgress: "پیشرفت",

        .sectionChooseList: "یک فهرست انتخاب کنید",
        .sectionBegin: "شروع",
        .sectionAbout: "درباره این بخش",
        .categoryMain: "اصلی",
        .categoryExtra: "اضافه",
        .categoryMainSubtitle: "واژه‌های خود کتاب",
        .categoryExtraSubtitle: "واژه‌هایی که خودتان جمع کرده‌اید",
        .sectionNeedWork: "%d واژه نیاز به تمرین دارد",
        .sectionNotStarted: "شروع نشده",
        .sectionComplete: "کامل",
        .sectionNoExtras: "این بخش واژه اضافه ندارد",

        .practiceKnewIt: "بلد بودم",
        .practiceDidntKnow: "بلد نبودم",
        .practiceMeaning: "معنی",
        .practiceNextWord: "واژه بعدی",
        .practiceFinish: "پایان",
        .practiceProgress: "%d از %d",
        .practiceLastFive: "۵ تای قبلی",
        .practiceThisCycle: "این دور",
        .practiceCycleComplete: "دور کامل شد",
        .practiceQuitTitle: "از این تمرین خارج می‌شوید؟",
        .practiceQuitMessage: "هرچه تا اینجا پاسخ داده‌اید ذخیره شده است.",
        .practiceTapToHear: "برای شنیدن بزنید",
        .practiceNewWord: "بار اول",
        .practiceCorrectTally: "%d درست",
        .practiceWrongTally: "%d غلط",
        .practiceSpeakLabel: "تلفظ %@",
        .practiceChecklistLabel: "%d از %d پاسخ، %d درست",

        .summaryTitle: "بخش کامل شد",
        .summaryAccuracy: "دقت",
        .summaryAnswered: "پاسخ‌داده",
        .summaryNextSection: "بخش بعدی",
        .summaryPracticeAgain: "تمرین دوباره",
        .summaryBackToMenu: "بازگشت به منو",
        .summaryBookComplete: "این آخرین بخش این کتاب بود.",
        .summaryHeadline: "آفرین",

        .reportsTitle: "گزارش‌ها",
        .reportsOverall: "کلی",
        .reportsMastered: "مسلط",
        .reportsSeen: "دیده‌شده",
        .reportsAccuracy: "دقت",
        .reportsByBook: "به تفکیک کتاب",
        .reportsWeakest: "بیشترین نیاز به تمرین",
        .reportsRecent: "تمرین‌های اخیر",
        .reportsExtraPractice: "تمرین اضافه",
        .reportsExtraSubtitle: "ضعیف‌ترین واژه‌های کل کتابخانه را تمرین کنید. جدا از پیشرفت اصلی حساب می‌شود.",
        .reportsStartDrill: "شروع تمرین",
        .reportsEmpty: "هنوز گزارشی نیست",
        .reportsEmptyHint: "یک بخش را تمام کنید تا آمارتان اینجا بیاید.",
        .reportsMainVsExtra: "اصلی در برابر اضافه",
        .reportsScope: "چند واژه",
        .reportsRun: "دور %d",
        .reportsWordsTotal: "%d واژه",
        .statWords: "واژه‌ها",
        .scopeWeakest25: "۲۵ واژه ضعیف",
        .scopeWeakest50: "۵۰ واژه ضعیف",
        .scopeEverything: "همه",

        .restartTitle: "همه واژه‌ها را تمام کردید",
        .restartMessage: "هر واژه یک دور کامل پنج‌تایی را تمام کرده است. شروع دور تازه چک‌لیست‌ها را پاک می‌کند اما تاریخچه و دقت شما می‌ماند.",
        .restartAction: "شروع دور تازه",
        .restartLater: "فعلاً نه",
        .extraLoopTitle: "یک دور کامل تمام شد",
        .extraLoopMessage: "همه واژه‌های این محدوده را تمرین کردید. فهرست دوباره از ضعیف‌ترین شروع می‌شود.",

        .settingsTitle: "تنظیمات",
        .settingsAppearance: "ظاهر",
        .settingsTheme: "پوسته",
        .themeSystem: "سیستم",
        .themeLight: "روشن",
        .themeDark: "تیره",
        .settingsLanguage: "زبان",
        .settingsPronunciation: "تلفظ",
        .settingsAccent: "لهجه",
        .accentAmerican: "آمریکایی",
        .accentBritish: "بریتانیایی",
        .accentAustralian: "استرالیایی",
        .settingsSpeed: "سرعت",
        .speedSlow: "آهسته",
        .speedNormal: "معمولی",
        .speedFast: "تند",
        .settingsAutoSpeak: "تلفظ خودکار هر واژه",
        .settingsAutoSpeakHint: "هر واژه به‌محض نمایش خوانده می‌شود.",
        .settingsHaptics: "لرزش",
        .settingsData: "داده‌ها",
        .settingsResetProgress: "بازنشانی همه پیشرفت‌ها",
        .settingsResetMessage: "همه چک‌لیست‌ها، شمارنده‌ها و تاریخچه پاک می‌شود. قابل بازگشت نیست.",
        .settingsExportProgress: "خروجی گرفتن از پیشرفت",
        .settingsImportProgress: "بازیابی پیشرفت",
        .settingsBackupHint: "پیش از نصب دوباره برنامه، تاریخچه تمرین را در یک فایل ذخیره کنید و بعد آن را برگردانید.",
        .backupRestoreTitle: "پیشرفت فعلی جایگزین شود؟",
        .backupRestoreMessage: "بازیابی، همه چیزی که اکنون روی این دستگاه ذخیره شده را با محتوای فایل پشتیبان جایگزین می‌کند.",
        .backupRestoreAction: "بازیابی",
        .backupRestoredTitle: "پیشرفت بازیابی شد",
        .backupExportFailed: "خروجی گرفتن انجام نشد",
        .backupImportFailed: "بازیابی انجام نشد",
        .commonOK: "باشه",
        .settingsPrivacy: "حریم خصوصی",
        .settingsPrivacyBody: "همه چیز روی همین دستگاه می‌ماند. نه حسابی هست، نه آماری، نه هیچ ارتباط شبکه‌ای — واژه‌ها داخل خود برنامه هستند و پیشرفت شما یک فایل در حافظه اختصاصی برنامه است. با حذف برنامه همه‌اش پاک می‌شود.",
        .settingsAbout: "درباره",
        .settingsVersion: "نسخه",
        .aboutTitle: "درباره",
        .aboutBody: "یک تمرین‌کننده واژگان آفلاین بر پایه دو فهرست کلاسیک واژگان تافل. بدون حساب کاربری، بدون اشتراک، بدون نیاز به اینترنت.",
        .aboutContentTitle: "فهرست واژه‌ها",
        .aboutContentBody: "۵۰۴ واژه کاملاً ضروری (Barron's) و ۴۰۰ واژه ضروری تافل (McGraw-Hill). معنی‌ها یادداشت مطالعه‌اند، نه متن ناشر.",
    ]
}

// MARK: - Environment

private struct StringsKey: EnvironmentKey {
    static let defaultValue = Strings(language: .english)
}

extension EnvironmentValues {
    var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
}
