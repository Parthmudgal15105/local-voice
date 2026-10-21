import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
enum VoiceStyle {
    static let ink = Color(hex: 0x1b1b19)
    static let muted = Color(hex: 0x787873)
    static let canvas = Color(hex: 0xf6f5f1)
    static let paper = Color(hex: 0xfdfdfb)
    static let selected = Color(hex: 0xeeeae1)
    static let line = Color(hex: 0xe8e5dd)
    static let teal = Color(hex: 0x1b6060)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Figtree", size: size).weight(weight) }
    static func serif(_ size: CGFloat) -> Font { .custom("EBGaramond-Regular", size: size) }
}
struct VoiceButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(VoiceStyle.font(15, .semibold)).padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(primary ? .white : VoiceStyle.ink)
            .background(primary ? VoiceStyle.ink.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(configuration.isPressed ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(primary ? .clear : VoiceStyle.line, lineWidth: 1))
    }
}
extension View {
    func voiceCard() -> some View { self.padding(22).background(VoiceStyle.canvas, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(VoiceStyle.line)) }
    func voiceField() -> some View { self.textFieldStyle(.plain).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(VoiceStyle.line)) }
}
struct Dashboard: View {
    @ObservedObject var model = VoiceModel.shared
    let navigation = [("Dictation", "mic"), ("Insights", "chart.bar.xaxis"), ("Dictionary", "character.book.closed"), ("Snippets", "scissors"), ("Scratchpad", "note.text")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) { Image(systemName: "waveform").font(.system(size: 25, weight: .semibold)); Text("Local Voice").font(VoiceStyle.font(24, .bold)) }.padding(.bottom, 28).padding(.top, 20).padding(.leading, 10)
                ForEach(navigation, id: \.0) { item in nav(item.0, item.1) }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.usesHomeServerForSpeech ? "HP home server" : "On your Mac", systemImage: model.usesHomeServerForSpeech ? "network" : "lock.shield").font(VoiceStyle.font(14, .semibold))
                    Text((model.preferences.translates ? "English output." : "Hinglish output.") + "\nNo monthly limits.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).lineSpacing(4)
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(VoiceStyle.selected.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                Rectangle().fill(VoiceStyle.line).frame(height: 1).padding(.vertical, 13)
                nav("Settings", "gearshape")
                Button { NSApp.terminate(nil) } label: { Label("Quit Local Voice", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain).font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted)
            }.padding(.horizontal, 14).padding(.bottom, 20).frame(width: 208).background(VoiceStyle.canvas)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    switch model.tab {
                    case "Insights": Insights(model: model)
                    case "Dictionary": DictionaryScreen(model: model)
                    case "Snippets": SnippetsScreen(model: model)
                    case "Scratchpad": ScratchpadScreen(model: model)
                    case "Settings": SettingsScreen(model: model)
                    default: DictationScreen(model: model)
                    }
                }.padding(38).frame(maxWidth: .infinity, alignment: .leading)
            }.background(VoiceStyle.paper, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(VoiceStyle.line))
                .padding(.trailing, 8).padding(.top, 12).padding(.bottom, 8)
        }.background(VoiceStyle.canvas).foregroundStyle(VoiceStyle.ink).font(VoiceStyle.font(16)).tint(VoiceStyle.teal).preferredColorScheme(.light).frame(minWidth: 1000, minHeight: 680)
    }
    func nav(_ title: String, _ icon: String) -> some View {
        Button { model.tab = title; model.search = "" } label: {
            HStack(spacing: 13) { Image(systemName: icon).font(.system(size: 19)).frame(width: 22); Text(title).font(VoiceStyle.font(16, model.tab == title ? .semibold : .medium)); Spacer() }.padding(.horizontal, 12).padding(.vertical, 12).background(model.tab == title ? VoiceStyle.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}
struct PageHeader: View {
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { Text(title).font(VoiceStyle.font(30, .semibold)); if !subtitle.isEmpty { Text(subtitle).font(VoiceStyle.font(15)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true) } }
    }
}
struct DictationScreen: View {
    @ObservedObject var model: VoiceModel
    var body: some View {
        PageHeader(title: "Dictation")
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.preferences.translates ? "Your words. In English." : "Your words. As spoken.").font(VoiceStyle.serif(36))
                Text("Speak in English, Hindi, or Hinglish.\nLet your voice do the typing.").font(VoiceStyle.font(17)).lineSpacing(5).foregroundStyle(VoiceStyle.muted)
                HStack(spacing: 10) {
                    Text("fn").font(VoiceStyle.font(17, .medium)).padding(.horizontal, 12).padding(.vertical, 7).background(.white, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(VoiceStyle.line))
                    Text("Tap or hold to talk · double-tap for continuous listening").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted)
                }
                HStack {
                    Button { model.toggleRecording() } label: { Label(model.recording ? "Finish dictation" : "Try dictation", systemImage: model.recording ? "stop.fill" : "mic") }.buttonStyle(VoiceButton(primary: true)).disabled(model.busy)
                    if model.recording || model.busy { Button("Cancel") { model.cancelCurrent() }.buttonStyle(VoiceButton()) }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if model.recording { ProgressView(value: model.inputLevel).tint(VoiceStyle.teal).accessibilityLabel("Microphone level") }
                Label(model.status, systemImage: model.recording ? "record.circle" : model.busy ? "hourglass" : "waveform").font(VoiceStyle.font(13)).foregroundStyle(model.recording ? .red : VoiceStyle.teal).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).voiceCard()
            VStack(alignment: .leading, spacing: 14) {
                stat((model.totalWords + (model.imported?.words ?? 0)).formatted(), "total words")
                stat("\(model.wpm)", "local WPM")
                stat("\(model.streak)", "day local streak")
                Divider().overlay(VoiceStyle.line)
                Label(model.usesHomeServerForSpeech ? "HP preferred · Mac fallback" : "Fully local", systemImage: model.usesHomeServerForSpeech ? "network" : "lock").font(VoiceStyle.font(14, .semibold)).foregroundStyle(VoiceStyle.teal)
                Button {
                    model.preferences.homeServerForSpeech = !model.usesHomeServerForSpeech
                } label: {
                    Label(model.usesHomeServerForSpeech ? "Switch to Mac" : "Switch to HP", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(VoiceButton())
                .disabled(model.recording || model.busy || model.trainingVoice || (!model.usesHomeServerForSpeech && !model.homeServerConfigured))
                .help(model.recording || model.busy ? "Finish or cancel the current dictation before switching." : (model.homeServerConfigured ? "Choose where new dictations are transcribed. Your choice is saved." : "A private home server must be configured before switching to HP."))
                Text(model.modelName + (model.preferences.translates ? "\nEnglish translation" : "\nHinglish transcription")).font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).lineSpacing(4)
            }.frame(width: 165, alignment: .leading).voiceCard()
        }
        if !model.shortcutReady || !model.microphoneReady {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "keyboard").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 5) { Text("Finish setting up your shortcut").font(VoiceStyle.font(15, .semibold)); Text("Microphone: \(model.microphoneReady ? "allowed" : "needed") · Fn listener: \(model.shortcutReady ? "connected" : "not connected")").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted) }
                Spacer()
                Button("Check setup") { model.tab = "Settings" }.buttonStyle(VoiceButton())
            }.voiceCard()
        }
        if (model.recording || model.busy) && !model.liveTranscript.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recognized so far", systemImage: "waveform").font(VoiceStyle.font(16, .semibold))
                Text(model.liveTranscript).font(VoiceStyle.font(15)).textSelection(.enabled).lineLimit(10)
                Text("Preview only. Your complete transcript is inserted after you finish speaking.").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
            }.voiceCard()
        }
        if !model.recoveryText.isEmpty && !model.busy {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovered speech transcript").font(VoiceStyle.font(18, .semibold))
                Text("Processing did not finish. These recognized words are available here.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted)
                Text(model.recoveryText).textSelection(.enabled).font(VoiceStyle.font(16))
                Button("Copy recovered text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.recoveryText, forType: .string) }.buttonStyle(VoiceButton())
            }.voiceCard()
        }
        if !model.recoveryRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recordings to recover").font(VoiceStyle.font(18, .semibold))
                Text("Retry uses the recording’s original language and model, with your current dictionary and corrections. You can also try local Whisper or use your current settings. Results are copied for manual paste.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
                ForEach(model.recoveryRecordings, id: \.path) { url in
                    HStack {
                        Text(model.recordingLabel(url)).font(VoiceStyle.font(12)).lineLimit(1).textSelection(.enabled)
                        Spacer()
                        Button("Show in Finder") { model.revealRecording(url) }.buttonStyle(VoiceButton())
                        Button("Retry") { model.retryRecording(url) }.buttonStyle(VoiceButton(primary: true)).disabled(model.recording || model.busy)
                        Menu {
                            Button("Retry with local Whisper") { model.retryRecording(url, usingWhisper: true) }
                            Button("Retry with current settings") { model.retryRecording(url, usingCurrentSettings: true) }
                        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Other recovery options") }
                        .menuStyle(.borderlessButton).frame(width: 28).disabled(model.recording || model.busy)
                    }
                }
            }.voiceCard()
        }
        HStack { Text("Dictation history").font(VoiceStyle.font(20, .semibold)); Spacer(); Image(systemName: "magnifyingglass").foregroundStyle(VoiceStyle.muted); TextField("Search transcripts", text: $model.search).textFieldStyle(.plain).frame(width: 180).font(VoiceStyle.font(14)) }
        if model.history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("A little less typing. A little more flow.").font(VoiceStyle.serif(27))
                Text("Your transcripts appear here after you speak. History stays in memory unless you choose to save it in Settings.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 28)
        } else {
            ForEach(model.history.filter { model.search.isEmpty || $0.text.localizedCaseInsensitiveContains(model.search) || $0.app.localizedCaseInsensitiveContains(model.search) }) { entry in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(entry.app).font(VoiceStyle.font(13, .semibold)); Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted); Spacer(); Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.text, forType: .string) }.buttonStyle(.plain).foregroundStyle(VoiceStyle.teal) }
                    HistoryTranscriptEditor(model:model, entryID:entry.id)
                    if let original=entry.originalText, original != entry.text {
                        DisclosureGroup("Before your correction") {Text(original).textSelection(.enabled).font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted)}
                    }
                    if let original = entry.sourceText, original != entry.text {
                        DisclosureGroup("Original recognized words") {
                            Text(original).textSelection(.enabled).font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
                    }
                    Button("Add to scratchpad") { model.preferences.scratchpad += (model.preferences.scratchpad.isEmpty ? "" : "\n\n") + entry.text; model.tab = "Scratchpad" }.buttonStyle(.plain).font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
                }.voiceCard()
            }
        }
        if !model.transcript.isEmpty && model.history.isEmpty { Text(model.transcript).textSelection(.enabled).voiceCard(); Button("Copy latest output") { model.copy() }.buttonStyle(VoiceButton()) }
    }
    func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) { Text(value).font(VoiceStyle.serif(30)); Text(label).font(VoiceStyle.font(13)) }
    }
}
struct DictionaryScreen: View {
    @ObservedObject var model: VoiceModel
    var body: some View {
        PageHeader(title: "Dictionary", subtitle: "Names, jargon, and spellings that sound like you.")
        VStack(alignment: .leading, spacing: 16) {
            Text("Spell it your way.").font(VoiceStyle.serif(34))
            Text("Add vocabulary to guide the speech model. Add a correction when you want a specific spelling replaced every time.").font(VoiceStyle.font(15)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).voiceCard()
        Text("Personal vocabulary").font(VoiceStyle.font(19, .semibold))
        HStack { TextField("A name or technical term", text: $model.newTerm).voiceField(); Button("Add word") { let term = model.newTerm.trimmingCharacters(in: .whitespacesAndNewlines); guard !term.isEmpty else { return }; if !model.preferences.vocabulary.contains(term) { model.preferences.vocabulary.append(term) }; model.newTerm = "" }.buttonStyle(VoiceButton(primary: true)).disabled(model.newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        VStack(spacing: 0) {
            ForEach(model.preferences.vocabulary, id: \.self) { term in HStack { Text(term); Spacer(); Button { model.preferences.vocabulary.removeAll { $0 == term } } label: { Image(systemName: "trash").foregroundStyle(VoiceStyle.muted) }.buttonStyle(.plain).accessibilityLabel("Remove " + term) }.padding(16); Divider().overlay(VoiceStyle.line) }
        }.background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(VoiceStyle.line))
        Text("Always replace").font(VoiceStyle.font(19, .semibold))
        HStack { TextField("When it writes…", text: $model.ruleSpoken).voiceField(); Image(systemName: "arrow.right").foregroundStyle(VoiceStyle.muted); TextField("Use this spelling…", text: $model.ruleWritten).voiceField(); Button("Add") { model.preferences.corrections.append(TextRule(spoken: model.ruleSpoken.trimmingCharacters(in: .whitespacesAndNewlines), written: model.ruleWritten.trimmingCharacters(in: .whitespacesAndNewlines))); model.ruleSpoken = ""; model.ruleWritten = "" }.buttonStyle(VoiceButton(primary: true)).disabled(model.ruleSpoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.ruleWritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        ForEach(model.preferences.corrections) { rule in HStack { Text(rule.spoken); Image(systemName: "arrow.right").foregroundStyle(VoiceStyle.muted); Text(rule.written); Spacer(); Button("Remove") { model.preferences.corrections.removeAll { $0.id == rule.id } }.buttonStyle(.plain).foregroundStyle(VoiceStyle.muted) }.voiceCard() }
        Text("Vocabulary is a hint, not a guarantee. Corrections apply to matching whole words after transcription.").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
    }
}
struct SnippetsScreen: View {
    @ObservedObject var model: VoiceModel
    var body: some View {
        PageHeader(title: "Snippets", subtitle: "Say a short phrase. Write the whole thing.")
        VStack(alignment: .leading, spacing: 15) {
            Text("A shortcut for things you say often.").font(VoiceStyle.serif(32))
            Text("For example, say ‘my sign off’ to insert your full email signature. The entire dictation must match the trigger phrase.").font(VoiceStyle.font(15)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
        TextField("Spoken trigger, e.g. my sign off", text: $model.snippetSpoken).voiceField()
        TextEditor(text: $model.snippetWritten).scrollContentBackground(.hidden).font(VoiceStyle.font(16)).padding(12).frame(height: 150).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(VoiceStyle.line)).accessibilityLabel("Snippet text")
        HStack { Spacer(); Button("Add snippet") { model.preferences.snippets.append(TextRule(spoken: model.snippetSpoken.trimmingCharacters(in: .whitespacesAndNewlines), written: model.snippetWritten.trimmingCharacters(in: .whitespacesAndNewlines))); model.snippetSpoken = ""; model.snippetWritten = "" }.buttonStyle(VoiceButton(primary: true)).disabled(model.snippetSpoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.snippetWritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        ForEach(model.preferences.snippets) { rule in VStack(alignment: .leading, spacing: 12) { HStack { Text(rule.spoken).font(VoiceStyle.font(17, .semibold)); Spacer(); Button("Remove") { model.preferences.snippets.removeAll { $0.id == rule.id } }.buttonStyle(.plain).foregroundStyle(VoiceStyle.muted) }; Text(rule.written).textSelection(.enabled).font(VoiceStyle.font(15)).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading).voiceCard() }
    }
}
struct ScratchpadScreen: View {
    @ObservedObject var model: VoiceModel
    var body: some View {
        PageHeader(title: "Scratchpad", subtitle: "A quiet place for your words. Saved only on this Mac.")
        HStack {
            Button(model.recording ? "Finish dictation" : "Dictate into scratchpad") { model.toggleRecording() }.buttonStyle(VoiceButton(primary: true)).disabled(model.busy)
            Spacer()
            Button("Copy all") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.preferences.scratchpad, forType: .string) }.buttonStyle(VoiceButton()).disabled(model.preferences.scratchpad.isEmpty)
        }
        TextEditor(text: $model.preferences.scratchpad).scrollContentBackground(.hidden).font(VoiceStyle.font(18)).padding(20).frame(minHeight: 400).background(.white, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(VoiceStyle.line)).accessibilityLabel("Scratchpad")
        Label(model.status, systemImage: "waveform").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.teal)
    }
}
struct SettingsScreen: View {
    @ObservedObject var model: VoiceModel
    var body: some View {
        PageHeader(title: "Settings", subtitle: "Make Local Voice work the way you do.").onAppear {model.loadLearning()}
        VStack(alignment: .leading, spacing: 12) {
            Text("Output language").font(VoiceStyle.font(22, .semibold))
            Picker("Mode", selection: Binding(get: { model.preferences.translates }, set: { model.preferences.translateToEnglish = $0 })) {
                Text("English translation").tag(true)
                Text("Hinglish · as spoken").tag(false)
            }.pickerStyle(.segmented)
            Text("Hinglish keeps your spoken language. Hindi words use everyday Latin spellings; unfamiliar words use a small, dedicated local spelling model. English translation can change phrasing.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
        VStack(alignment: .leading, spacing: 20) {
            Text("Dictation shortcut").font(VoiceStyle.font(22, .semibold))
            Toggle("Transcribe while I speak", isOn: Binding(get: { model.preferences.transcribeWhileRecording ?? true }, set: { model.preferences.transcribeWhileRecording = $0 })).toggleStyle(.switch).disabled(model.recording || model.busy)
            Text("Long dictations start processing in roughly 20–30 second parts while you keep speaking. The full audio stays available for recovery. Text is inserted once, after you finish. Turn this off to process everything after recording.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
            Toggle("Enable Fn shortcut", isOn: $model.enabled).toggleStyle(.switch)
            Text("Tap Fn to start, tap again to finish. Or hold Fn while speaking and release to finish. Double-tap Fn to listen continuously until you press Fn again. Escape cancels recording or processing. Regular recordings stop after 2 minutes.").foregroundStyle(VoiceStyle.muted).font(VoiceStyle.font(14)).fixedSize(horizontal: false, vertical: true)
            Label(model.lastShortcutEvent, systemImage: "keyboard").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.teal)
            Divider()
            Text("macOS permissions").font(VoiceStyle.font(22, .semibold))
            permission("Microphone", model.microphoneReady)
            permission("Device Control / Accessibility", model.accessibilityReady)
            permission("Keyboard listener", model.shortcutReady)
            Text("If access is on in System Settings but unavailable here, switch Local Voice off and on in Device Control and Data Access (called Accessibility on older macOS), then reopen the app. Input Monitoring is needed only if the keyboard listener still cannot connect.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Request permissions") { model.permissions() }.buttonStyle(VoiceButton(primary: true))
                Button("Open macOS settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }.buttonStyle(VoiceButton())
                Button("Reconnect shortcut") { model.reconnectShortcut() }.buttonStyle(VoiceButton())
            }
            Text("Quit Wispr Flow before dictating. In Keyboard settings, set ‘Press Globe key to’ to ‘Do Nothing’.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal voice learning").font(VoiceStyle.font(22, .semibold))
            Toggle("Keep recordings for personal training", isOn: Binding(get:{model.preferences.voiceLearning ?? false},set:{model.preferences.voiceLearning=$0})).toggleStyle(.switch)
            Text("In Hinglish mode, keeps clips up to 30 seconds locally, capped at 500 MB / 2,000 clips. Review the exact words before training. Turning this off stops collection; saved examples remain available. Training uses a small adapter, pauses dictation, and stops after 10 minutes. Candidates require review and are never activated automatically.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal:false,vertical:true)
            Toggle("Train automatically after 10 new corrected recordings",isOn:Binding(get:{model.preferences.automaticTraining ?? true},set:{model.preferences.automaticTraining=$0})).toggleStyle(.switch)
            Text("New corrected recordings: \(model.newCorrectedRecordings) / 10. Training starts when dictation is idle. Each recording counts once, even if edited repeatedly. Candidates still need your review.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted)
            Text("Verified examples: \(model.learningSamples.filter{$0.confirmed}.count) / \(model.learningSamples.count)").font(VoiceStyle.font(13))
            Text(model.learningStatus).font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.teal)
            HStack {
                Button("Open evaluation") { NSWorkspace.shared.open(model.learningDirectory.appendingPathComponent("candidate/evaluation.json")) }
                Button("Use reviewed candidate") {model.setPersonalAdapter(true)}.disabled(model.trainingVoice || model.busy || model.recording)
                Button("Restore original") {model.setPersonalAdapter(false)}.disabled(model.trainingVoice || model.busy || model.recording)
                Button("Train candidate") {model.trainVoice()}.disabled(model.trainingVoice || model.busy || model.recording || model.learningSamples.filter{$0.confirmed}.count<10)
                if model.trainingVoice {Button("Cancel training") {model.learningJob?.cancel()}}
            }
            ForEach(model.learningSamples.filter{!$0.confirmed}.prefix(20)) { sample in
                VStack(alignment:.leading) {
                    HStack {Text(sample.confirmed ? "Verified example" : "Review exact spoken words");Spacer();Button("Listen") {NSWorkspace.shared.open(model.learningDirectory.appendingPathComponent(sample.id.uuidString+".wav"))}}
                    TextField("Correct transcript",text:Binding(get:{model.learningSamples.first(where:{$0.id==sample.id})?.corrected ?? ""},set:{text in if let i=model.learningSamples.firstIndex(where:{$0.id==sample.id}) {model.learningSamples[i].corrected=text;model.learningSamples[i].confirmed=false}}),axis:.vertical)
                    HStack {Button("Confirm for training") {model.confirmLearning(sample.id)}; Button("Discard") {model.discardLearning(sample.id)}}.disabled(model.trainingVoice)
                }.font(VoiceStyle.font(13)).padding(.vertical,8)
            }
            Divider()
            Text("Privacy & history").font(VoiceStyle.font(22, .semibold))
            Toggle("Save my last 50 transcripts on this Mac", isOn: $model.preferences.saveHistory).toggleStyle(.switch)
            Text("Off by default. Turning it off removes saved transcript history from disk; the current session stays visible until you quit. Dictionary, snippets, scratchpad, and usage counts are saved locally. Audio is deleted after processing unless personal voice learning is enabled.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
        VStack(alignment: .leading, spacing: 12) {
            Text("Speech model").font(VoiceStyle.font(22, .semibold))
            Picker("Hinglish recognition", selection: Binding(get: { model.preferences.speechModel ?? "qwen-0.6" }, set: { model.preferences.speechModel = $0 })) {
                Text("Qwen3 0.6B · faster").tag("qwen-0.6")
                Text("Qwen3 1.7B · stronger Hindi recognition").tag("qwen-1.7")
                Text("Whisper Large-v3 · translation").tag("whisper")
            }.disabled(model.busy || model.recording)
            Toggle("Prefer HP home server", isOn: Binding(
                get: { model.usesHomeServerForSpeech },
                set: { model.preferences.homeServerForSpeech = $0 }
            )).toggleStyle(.switch).disabled(model.busy || model.recording || (!model.usesHomeServerForSpeech && !model.homeServerConfigured))
            Label(model.modelName + (model.modelReady ? (model.usesHomeServerForSpeech ? " · configured" : " · installed") : " · missing"), systemImage: "internaldrive")
            Text(model.usesHomeServerForSpeech
                ? "Each dictation checks the HP before sending audio and vocabulary over encrypted Tailscale. If the HP is unavailable or processing fails, this Mac automatically uses the selected installed Qwen model, or local Whisper. Hinglish spelling also falls back to the Mac and keeps your cached spellings. The next dictation tries the HP again. Turn this off to keep all speech processing on this Mac. Your personal Qwen adapter stays on the Mac."
                : "Qwen3 0.6B favors speed; the larger 1.7B model uses more memory. English translation uses Whisper. Processing speed depends on the model and your Mac. With this switch off, speech processing stays on this Mac.")
                .font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).voiceCard()
    }
    func permission(_ title: String, _ ready: Bool) -> some View {
        HStack { Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(ready ? VoiceStyle.teal : .orange); Text(title); Spacer(); Text(ready ? "Connected" : "Unavailable").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted) }
    }
}

struct HistoryTranscriptEditor: View {
    @ObservedObject var model: VoiceModel
    let entryID: UUID
    @FocusState private var focused: Bool
    var entry: TranscriptEntry? {model.history.first{$0.id==entryID}}
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            TextField("Transcript",text:Binding(get:{entry?.text ?? ""},set:{model.editHistory(entryID,text:$0)}),axis:.vertical)
                .textFieldStyle(.plain).font(VoiceStyle.font(16)).lineLimit(2...30).focused($focused)
                .disabled(model.trainingVoice)
                .onChange(of:focused) { _, editing in if !editing {model.saveHistoryCorrection(entryID)}}
                .onDisappear {model.saveHistoryCorrection(entryID)}
            if let entry {
                if let id=model.learningSampleID(for:entry), let sample=model.learningSamples.first(where:{$0.id==id}) {
                    Text(sample.confirmed ? "Correction saved for training" : "Edit to correct · changes save for training automatically")
                        .font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.teal)
                } else {
                    Text("Editable · audio unavailable for training. Enable personal learning in Settings for future recordings.")
                        .font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted)
                }
            }
        }
    }
}
