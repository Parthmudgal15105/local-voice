import Foundation
struct LearningRevision: Codable {var date: Date;var before: String;var after: String}
struct LearningSample: Codable, Identifiable {
 var id: UUID
 var seconds: Double
 var original: String
 var corrected: String
 var confirmed = false
 var revisions: [LearningRevision]? = nil
 mutating func correct(_ text: String) {
  guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
  if corrected != text {
   var log=revisions ?? []
   log.append(LearningRevision(date:Date(),before:corrected,after:text))
   revisions=Array(log.suffix(50))
  }
  corrected=text;confirmed=true
 }
}

struct TrainingSchedule: Codable {
 var attempted: Set<UUID> = []
 var completed: Set<UUID> = []
 func pending(_ samples: [LearningSample]) -> Set<UUID> {
  Set(samples.filter { $0.confirmed && $0.corrected != $0.original && !$0.corrected.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.map(\.id)).subtracting(attempted)
 }
 func shouldStart(_ samples: [LearningSample], idle: Bool) -> Bool {idle && pending(samples).count >= 10}
}
