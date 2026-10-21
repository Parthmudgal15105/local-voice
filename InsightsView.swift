import SwiftUI
import Charts

private final class InsightControls: ObservableObject {
    @Published var range = 30
    @Published var wordSort = "Frequency"
    @Published var hoveredDate: Date? = nil
    @Published var fingerprint = DictationFingerprint(texts: [])
}

struct Insights: View {
    @ObservedObject var model: VoiceModel
    @StateObject private var controls = InsightControls()
    private var activity: DictationActivity { DictationActivity(sessions: model.sessions, rangeDays: controls.range == 0 ? nil : controls.range) }
    private var corpus: [String] { DictationFingerprint.corpus(history: model.history, samples: model.learningSamples) }

    var body: some View {
        let stats = activity
        let voice = controls.fingerprint
        PageHeader(title: "Your voice, in perspective", subtitle: "The words you reach for. The rhythms you fall into.")
            .onChange(of: corpus, initial: true) { _, texts in controls.fingerprint = DictationFingerprint(texts: texts) }
        HStack {
            Label("ACTIVITY", systemImage: "waveform.path").font(VoiceStyle.font(12, .semibold)).tracking(1)
            Spacer()
            Label("\(model.streak)-day streak", systemImage: "flame").font(VoiceStyle.font(12, .medium)).foregroundStyle(VoiceStyle.teal)
            Picker("Activity period", selection: $controls.range) {
                Text("7 days").tag(7); Text("30 days").tag(30); Text("All time").tag(0)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 290)
        }
        HStack(alignment: .top, spacing: 14) {
            metric(stats.words.formatted(), "WORDS DICTATED", detail: "\(stats.sessions.count) dictations · \(stats.activeDays) active days")
            metric("\(stats.wpm)", "OUTPUT WORDS / MIN", detail: "\(Int(stats.seconds / 60)) minutes recorded")
            metric("\(stats.averageWords)", "WORDS PER DICTATION", detail: "\(duration(stats.averageSeconds)) average recording")
        }
        activityChart(stats)
        HStack(alignment: .top, spacing: 16) {
            observation("Your busiest hour", icon: "clock", value: peakHour(stats), detail: stats.peakHour == nil ? "Your rhythm will appear as you dictate." : "\(stats.peakHourCount) of \(stats.sessions.count) dictations completed in this hour. Times are local.")
            observation("Your longest thought", icon: "text.alignleft", value: stats.longest.map { duration(Int($0.seconds)) } ?? "—", detail: stats.longest.map { "\($0.words.formatted()) words in \($0.app) · \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "Your longest recording will appear here.")
            observation("A week in words", icon: "arrow.up.right", value: stats.currentWeekWords.formatted(), detail: weekComparison(stats))
        }
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your voice fingerprint").font(VoiceStyle.serif(32))
                Text("Based on \(voice.documents) retained dictations · \(voice.words.formatted()) words analyzed").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted)
            }
            Spacer()
            Image(systemName: "quote.bubble").font(.system(size: 30)).foregroundStyle(VoiceStyle.teal)
        }.padding(.top, 8)
        Text("Word insights use available transcript history and saved learning examples, including edits. Linked entries count once. This sample is separate from the activity period above; common English and Hinglish words are filtered from the word ranking.")
            .font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        if voice.words == 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your next dictation starts the story.").font(VoiceStyle.serif(28))
                Text("Dictate a few thoughts to see your words and phrases here. Current-session transcripts work immediately; saved history and learning examples stay available after restarting.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).voiceCard()
        } else {
            HStack(alignment: .top, spacing: 18) {
                wordsCard(voice)
                phrasesCard(voice)
            }
            expressionCard(voice)
        }
        appCard(stats)
        if let old = model.imported {
            DisclosureGroup {
                HStack(spacing: 30) {
                    metric(old.words.formatted(), "IMPORTED WORDS", detail: "\(old.wpm) WPM · \(old.appsUsed) apps")
                    metric("\(old.fixes)", "HISTORICAL FIXES", detail: "\(old.wordsCorrected) corrections · \(old.dictionaryFixes) dictionary fixes")
                }.padding(.top, 12)
                Text(old.source + ". Imported totals do not contribute to the charts or word analysis.").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).padding(.top, 8)
            } label: { Text("Your Wispr Flow history").font(VoiceStyle.font(17, .semibold)) }.voiceCard()
        }
        Label("Calculated on this Mac. Counts describe generated text; translation and corrections can change your words. No additional transcript storage is enabled.", systemImage: "lock.shield")
            .font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
    }

    private func activityChart(_ stats: DictationActivity) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("A little every day adds up.").font(VoiceStyle.serif(28))
                Spacer()
                Text("\(stats.days.count) DAYS · OUTPUT WORDS").font(VoiceStyle.font(10, .semibold)).foregroundStyle(VoiceStyle.muted)
            }
            Chart(stats.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words))
                    .foregroundStyle(VoiceStyle.teal).cornerRadius(3)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(day.words) words")
                if let hoveredDate = controls.hoveredDate, let day = stats.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hoveredDate) }) {
                    RuleMark(x: .value("Selected day", day.date, unit: .day))
                        .foregroundStyle(VoiceStyle.ink.opacity(0.3))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("\(day.date.formatted(.dateTime.month(.abbreviated).day())) · \(day.words) words")
                                .font(VoiceStyle.font(11, .semibold)).padding(7).background(VoiceStyle.paper, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let frame = proxy.plotFrame {
                                let plot = geometry[frame]
                                controls.hoveredDate = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                            }
                        case .ended: controls.hoveredDate = nil
                        }
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: stats.days.count > 14 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYScale(domain: 0...max(10, (stats.days.map(\.words).max() ?? 0)))
            .frame(height: 155)
            Text(stats.sessions.isEmpty ? "No dictations in this period yet. Try a wider controls.range." : "\(stats.activeDays) active days in this period. Hover over a bar for the daily total.")
                .font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
        }.voiceCard()
    }
    private func wordsCard(_ voice: DictationFingerprint) -> some View {
        let ranked = controls.wordSort == "Reach" ? voice.vocabulary.sorted { $0.dictations == $1.dictations ? ($0.count == $1.count ? $0.text < $1.text : $0.count > $1.count) : $0.dictations > $1.dictations } : voice.vocabulary
        return VStack(alignment: .leading, spacing: 17) {
            Text("Words you reach for").font(VoiceStyle.font(22, .semibold))
            Picker("Rank words by", selection: $controls.wordSort) { Text("Frequency").tag("Frequency"); Text("Reach").tag("Reach") }.pickerStyle(.segmented).labelsHidden()
            Text(controls.wordSort == "Frequency" ? "How often each word appears." : "How many different dictations use each word.")
                .font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
            if ranked.isEmpty { Text("More meaningful words will appear as your sample grows.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted) }
            ForEach(Array(ranked.prefix(10).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted).frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(item.text).font(VoiceStyle.font(15, .medium)).textSelection(.enabled); Spacer(); Text(controls.wordSort == "Frequency" ? "\(item.count)×" : "\(item.dictations) dictations").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.teal) }
                        GeometryReader { proxy in
                            Capsule().fill(VoiceStyle.selected).overlay(alignment: .leading) {
                                Capsule().fill(VoiceStyle.teal.opacity(0.65)).frame(width: max(0, proxy.size.width * Double(controls.wordSort == "Frequency" ? item.count : item.dictations) / Double(max(1, controls.wordSort == "Frequency" ? ranked.first?.count ?? 1 : ranked.first?.dictations ?? 1))))
                            }
                        }.frame(height: 4)
                    }
                }
            }
            Divider()
            Text("\(voice.uniqueWords.formatted()) distinct words across \(voice.words.formatted()) total words, before filtering.").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .topLeading).voiceCard()
    }
    private func phrasesCard(_ voice: DictationFingerprint) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your recurring phrases").font(VoiceStyle.font(22, .semibold))
            Text("Two or three words that appear together in at least two different dictations.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
            if voice.phrases.isEmpty {
                Image(systemName: "text.quote").font(.system(size: 32)).foregroundStyle(VoiceStyle.teal).padding(.top, 20)
                Text("Patterns take a few conversations.").font(VoiceStyle.serif(26))
                Text("Recurring phrases will show up as your retained sample grows.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted)
            }
            ForEach(voice.phrases.prefix(7)) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) { Text("“\(item.text)”").font(VoiceStyle.serif(24)).textSelection(.enabled); Spacer(); Text("\(item.count)×").font(VoiceStyle.font(13, .semibold)).foregroundStyle(VoiceStyle.teal) }
                    Text("Across \(item.dictations) dictations").font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted)
                }
                Divider()
            }
            Text("A useful place to spot repeated wording or ideas for snippets.").font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .topLeading).voiceCard()
    }
    private func expressionCard(_ voice: DictationFingerprint) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("The little expressions").font(VoiceStyle.font(22, .semibold)); Spacer(); Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(VoiceStyle.teal) }
            Text("Familiar turns of phrase in your output. These can carry meaning; they are not automatically filler words.").font(VoiceStyle.font(13)).foregroundStyle(VoiceStyle.muted)
            if voice.expressions.isEmpty {
                Text("None of the tracked expressions appear in this sample yet.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 12) {
                    ForEach(voice.expressions.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.text).font(VoiceStyle.font(15, .semibold)); Spacer(); Text("\(item.count)×").foregroundStyle(VoiceStyle.teal) }
                            Text(String(format: "%.1f per 1,000 words", Double(item.count) * 1000 / Double(max(1, voice.words)))).font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted)
                        }.padding(14).background(VoiceStyle.paper, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Text("Transcription can omit spoken hesitations. These are text patterns, not a measure of speech quality.").font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted)
        }.voiceCard()
    }
    private func appCard(_ stats: DictationActivity) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Where your words go").font(VoiceStyle.font(22, .semibold)); Spacer(); Text("\(stats.appUsage.count) APPS").font(VoiceStyle.font(11, .semibold)).foregroundStyle(VoiceStyle.muted) }
            ForEach(stats.appUsage.prefix(8), id: \.0) { app, words in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Label(app, systemImage: "macwindow"); Spacer(); Text("\(words.formatted()) words · \(Int(Double(words) * 100 / Double(max(1, stats.words))))%").foregroundStyle(VoiceStyle.muted) }.font(VoiceStyle.font(13))
                    ProgressView(value: Double(words), total: Double(max(1, stats.words))).tint(VoiceStyle.teal)
                }
            }
            if stats.appUsage.isEmpty { Text("Your app breakdown grows as you dictate.").font(VoiceStyle.font(14)).foregroundStyle(VoiceStyle.muted) }
            Text("App focused when recording began; this does not confirm text was pasted.").font(VoiceStyle.font(11)).foregroundStyle(VoiceStyle.muted)
        }.voiceCard()
    }
    private func metric(_ value: String, _ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(value).font(VoiceStyle.font(34, .semibold))
            Text(title).font(VoiceStyle.font(10, .semibold)).tracking(0.7).foregroundStyle(VoiceStyle.muted)
            Divider().padding(.vertical, 4)
            Text(detail).font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).voiceCard()
    }
    private func observation(_ title: String, icon: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(VoiceStyle.font(13, .semibold)).foregroundStyle(VoiceStyle.teal)
            Text(value).font(VoiceStyle.serif(30))
            Text(detail).font(VoiceStyle.font(12)).foregroundStyle(VoiceStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading).voiceCard()
    }
    private func duration(_ seconds: Int) -> String { seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s" }
    private func peakHour(_ stats: DictationActivity) -> String {
        guard let hour = stats.peakHour else { return "—" }
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }
    private func weekComparison(_ stats: DictationActivity) -> String {
        guard stats.previousWeekWords > 0 else { return "Words in the last 7 days. A week-over-week comparison appears once the prior 7 days have activity." }
        let difference = stats.currentWeekWords - stats.previousWeekWords
        let percent = Int((Double(abs(difference)) * 100 / Double(stats.previousWeekWords)).rounded())
        return "\(percent)% \(difference >= 0 ? "more" : "fewer") than the prior 7 days (\(stats.previousWeekWords.formatted()) words). Independent of the selected period."
    }
}
