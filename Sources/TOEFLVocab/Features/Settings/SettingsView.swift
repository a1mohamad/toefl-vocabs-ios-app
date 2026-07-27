import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var speech: PronunciationService
    @Environment(\.strings) private var strings

    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            appearanceSection
            pronunciationSection
            feedbackSection
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(strings[.settingsTitle])
        .alert(strings[.settingsResetProgress], isPresented: $showResetConfirmation) {
            Button(strings[.commonReset], role: .destructive) {
                progress.eraseAll()
            }
            Button(strings[.commonCancel], role: .cancel) {}
        } message: {
            Text(strings[.settingsResetMessage])
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker(strings[.settingsTheme], selection: $settings.settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Label(strings[theme.titleKey], systemImage: theme.symbolName).tag(theme)
                }
            }
            .pickerStyle(.menu)

            Picker(strings[.settingsLanguage], selection: $settings.settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language == .system ? strings[.themeSystem] : language.nativeName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text(strings[.settingsAppearance])
        }
    }

    // MARK: Pronunciation

    private var pronunciationSection: some View {
        Section {
            Picker(strings[.settingsAccent], selection: $settings.settings.accent) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(strings[accent.titleKey]).tag(accent)
                }
            }
            .pickerStyle(.segmented)

            speedRow
            previewRow

            Toggle(strings[.settingsAutoSpeak], isOn: $settings.settings.autoSpeak)
        } header: {
            Text(strings[.settingsPronunciation])
        } footer: {
            Text(strings[.settingsAutoSpeakHint])
        }
    }

    private var speedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings[.settingsSpeed])
                Spacer()
                Text(strings[settings.settings.speedLabelKey])
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Slider(
                value: $settings.settings.speechRate,
                in: AppSettings.minimumSpeechRate...AppSettings.maximumSpeechRate
            ) {
                Text(strings[.settingsSpeed])
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").foregroundStyle(Palette.textTertiary)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").foregroundStyle(Palette.textTertiary)
            }
            .accessibilityValue(strings[settings.settings.speedLabelKey])
        }
    }

    /// Hearing the change is the only way to judge a speech-rate slider.
    private var previewRow: some View {
        Button {
            speech.speak(
                "vocabulary",
                accent: settings.settings.accent,
                rate: settings.settings.speechRate
            )
        } label: {
            Label(strings[.practiceTapToHear], systemImage: "speaker.wave.2.fill")
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        Section {
            Toggle(strings[.settingsHaptics], isOn: $settings.settings.haptics)
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(strings[.settingsResetProgress], systemImage: "trash")
            }
        } header: {
            Text(strings[.settingsData])
        } footer: {
            Text(strings[.settingsPrivacyBody])
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            NavigationLink(value: Route.about) {
                Label(strings[.settingsAbout], systemImage: "info.circle")
            }
            LabeledContent(strings[.settingsVersion], value: Self.versionString)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
