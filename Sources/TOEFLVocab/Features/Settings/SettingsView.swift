import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var speech: PronunciationService
    @Environment(\.strings) private var strings

    @State private var showResetConfirmation = false

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: ProgressBackupDocument?
    @State private var pendingBackup: ProgressBackup?
    @State private var showRestoreConfirmation = false
    @State private var showResultAlert = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""

    var body: some View {
        Form {
            appearanceSection
            pronunciationSection
            feedbackSection
            dataSection
            privacySection
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
        .alert(strings[.backupRestoreTitle], isPresented: $showRestoreConfirmation) {
            Button(strings[.backupRestoreAction], role: .destructive) {
                applyPendingBackup()
            }
            Button(strings[.commonCancel], role: .cancel) { pendingBackup = nil }
        } message: {
            Text("\(strings[.backupRestoreMessage])\n\n\(pendingBackup?.summary ?? "")")
        }
        .alert(resultTitle, isPresented: $showResultAlert) {
            Button(strings[.commonOK], role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                present(title: strings[.backupExportFailed], message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
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
            Button {
                beginExport()
            } label: {
                Label(strings[.settingsExportProgress], systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label(strings[.settingsImportProgress], systemImage: "square.and.arrow.down")
            }

            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label(strings[.settingsResetProgress], systemImage: "trash")
            }
        } header: {
            Text(strings[.settingsData])
        } footer: {
            Text(strings[.settingsBackupHint])
        }
    }

    private var privacySection: some View {
        Section {
            Text(strings[.settingsPrivacyBody])
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
        } header: {
            Text(strings[.settingsPrivacy])
        }
    }

    // MARK: Backup

    /// Encodes first, then presents. Building the document up front means an
    /// encoding failure surfaces as an error here rather than as an empty file
    /// the user only discovers is broken when they try to restore it.
    private func beginExport() {
        do {
            exportDocument = ProgressBackupDocument(data: try progress.exportBackup())
            showExporter = true
        } catch {
            present(title: strings[.backupExportFailed], message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            present(title: strings[.backupImportFailed], message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                // Decode before prompting, so an unusable file is rejected
                // without the user first agreeing to overwrite their history.
                let data = try ProgressStore.readBackupFile(at: url)
                pendingBackup = try ProgressBackup.decode(from: data)
                showRestoreConfirmation = true
            } catch {
                present(title: strings[.backupImportFailed], message: error.localizedDescription)
            }
        }
    }

    private func applyPendingBackup() {
        guard let backup = pendingBackup else { return }
        progress.replaceState(with: backup.progress)
        pendingBackup = nil
        present(title: strings[.backupRestoredTitle], message: backup.summary)
    }

    private func present(title: String, message: String) {
        resultTitle = title
        resultMessage = message
        showResultAlert = true
    }

    /// Dated so successive backups do not overwrite each other in Files.
    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "toefl-vocab-progress-\(formatter.string(from: Date()))"
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
