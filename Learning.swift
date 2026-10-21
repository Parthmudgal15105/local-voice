import Foundation
extension VoiceModel {
 var learningDirectory: URL { data.appendingPathComponent("Learning", isDirectory:true) }
 func loadLearning() {
  try? FileManager.default.createDirectory(at:learningDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:learningDirectory.path)
  trainingSchedule = (try? JSONDecoder().decode(TrainingSchedule.self,from:Data(contentsOf:learningDirectory.appendingPathComponent("training-schedule.json")))) ?? TrainingSchedule()
  learningSamples = (try? JSONDecoder().decode([LearningSample].self,from:Data(contentsOf:learningDirectory.appendingPathComponent("samples.json")))) ?? []
 }
 func persistLearning() throws {
  try FileManager.default.createDirectory(at:learningDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:learningDirectory.path)
  let file=learningDirectory.appendingPathComponent("samples.json")
  try JSONEncoder().encode(learningSamples).write(to:file,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
 }
 @discardableResult
 func captureLearning(_ source: URL, text: String, seconds: Double, capturedPreferences: Preferences? = nil) -> UUID? {
  let capture = capturedPreferences ?? preferences
  guard preferences.voiceLearning == true, capture.voiceLearning == true, !capture.translates, seconds <= 30 else { return nil }
  let bytes=(try? FileManager.default.contentsOfDirectory(at:learningDirectory,includingPropertiesForKeys:[.fileSizeKey]).reduce(0) { $0 + ((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }) ?? 0
  guard bytes < 500_000_000, learningSamples.count < 2000 else { learningStatus="Learning storage limit reached (500 MB / 2,000 clips).";return nil }
  do {
   try persistLearning()
   let sample=LearningSample(id:UUID(),seconds:seconds,original:text,corrected:text)
   let target=learningDirectory.appendingPathComponent(sample.id.uuidString+".wav")
   try FileManager.default.copyItem(at:source,to:target)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
   learningSamples.insert(sample,at:0);try persistLearning();return sample.id
  } catch { learningStatus="Could not save learning recording.";return nil }
 }
 func learningSampleID(for entry: TranscriptEntry) -> UUID? {
  if let id=entry.learningSampleID, learningSamples.contains(where:{$0.id==id}) {return id}
  // Recover a pre-link history entry only when the original text uniquely identifies a sample.
  let matches=learningSamples.filter{$0.original == (entry.originalText ?? entry.text)}
  return matches.count == 1 ? matches.first?.id : nil
 }
 func editHistory(_ id: UUID, text: String) {
  lastCorrectionEdit=Date()
  guard !trainingVoice, let index=history.firstIndex(where:{$0.id==id}) else {return}
  if history[index].originalText == nil {history[index].originalText=history[index].text}
  history[index].text=text
  history[index].correctedAt=Date()
  if let sampleID=learningSampleID(for:history[index]), let sample=learningSamples.firstIndex(where:{$0.id==sampleID}) {
   history[index].learningSampleID=sampleID
   let wasConfirmed=learningSamples[sample].confirmed
   learningSamples[sample].confirmed=false
   if wasConfirmed {try? persistLearning()}
  }
  persistHistory()
  correctionSaves[id]?.cancel()
  let save=DispatchWorkItem { [weak self] in self?.saveHistoryCorrection(id) }
  correctionSaves[id]=save
  DispatchQueue.main.asyncAfter(deadline:.now()+1.2,execute:save)
 }
 func saveHistoryCorrection(_ id: UUID) {
  correctionSaves[id]?.cancel();correctionSaves[id]=nil
  guard let entry=history.first(where:{$0.id==id}), entry.correctedAt != nil else {return}
  guard !entry.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
        let sampleID=learningSampleID(for:entry),
        FileManager.default.fileExists(atPath:learningDirectory.appendingPathComponent(sampleID.uuidString+".wav").path),
        let index=learningSamples.firstIndex(where:{$0.id==sampleID}) else {return}
  learningSamples[index].correct(entry.text)
  do {try persistLearning();learningStatus="History correction saved for training."}
  catch {learningSamples[index].confirmed=false;learningStatus="Could not save correction for training."}
 }
 func flushHistoryCorrections() {
  for id in Array(correctionSaves.keys) {saveHistoryCorrection(id)}
 }
 func discardLearning(_ id: UUID) {
  guard !trainingVoice else {return}
  let audio=learningDirectory.appendingPathComponent(id.uuidString+".wav")
  do {
   if FileManager.default.fileExists(atPath:audio.path) {try FileManager.default.trashItem(at:audio,resultingItemURL:nil)}
   learningSamples.removeAll{$0.id==id};try persistLearning();learningStatus="Recording moved to Trash."
  } catch {learningStatus="Could not discard recording."}
 }
 func confirmLearning(_ id: UUID) {
  lastCorrectionEdit=Date()
  guard let index=learningSamples.firstIndex(where:{$0.id==id}), !learningSamples[index].corrected.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return}
  learningSamples[index].confirmed=true
  do {try persistLearning();learningStatus="Verified example saved."}catch{learningStatus="Could not save example."}
 }
 func setPersonalAdapter(_ enabled: Bool) {
  let marker=learningDirectory.appendingPathComponent("use-adapter")
  do {
   if enabled {
    guard FileManager.default.fileExists(atPath:learningDirectory.appendingPathComponent("candidate/adapter.safetensors").path) else {return}
    try preserveActiveAdapter(replace:true)
    try Data().write(to:marker,options:.atomic)
    preferences.speechModel="qwen-0.6";preferences.translateToEnglish=false
   } else if FileManager.default.fileExists(atPath:marker.path) {try FileManager.default.removeItem(at:marker)}
   speechForLearningShutdown();learningStatus=enabled ? "Personal candidate enabled. Use the original if results get worse." : "Original model restored."
  } catch {learningStatus="Could not change personal adapter."}
 }
 func saveTrainingSchedule() throws {
  let file=learningDirectory.appendingPathComponent("training-schedule.json")
  try JSONEncoder().encode(trainingSchedule).write(to:file,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
 }
 func preserveActiveAdapter(replace: Bool = false) throws {
  let active=learningDirectory.appendingPathComponent("active",isDirectory:true)
  let weights=active.appendingPathComponent("adapter.safetensors")
  if !replace && FileManager.default.fileExists(atPath:weights.path) {return}
  let bytes=try Data(contentsOf:learningDirectory.appendingPathComponent("candidate/adapter.safetensors"))
  try FileManager.default.createDirectory(at:active,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:active.path)
  try bytes.write(to:weights,options:.atomic)
  try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:weights.path)
 }
 var newCorrectedRecordings: Int {trainingSchedule.pending(learningSamples).count}
 func maybeTrainVoice() {
  guard !shuttingDown, preferences.automaticTraining ?? true,
        correctionSaves.isEmpty, Date().timeIntervalSince(lastCorrectionEdit)>10,
        trainingSchedule.shouldStart(learningSamples,idle: !busy && !recording && !trainingVoice) else {return}
  let available=learningSamples.filter {FileManager.default.fileExists(atPath:learningDirectory.appendingPathComponent($0.id.uuidString+".wav").path)}
  guard trainingSchedule.shouldStart(available,idle:true) else {return}
  trainVoice()
 }
 func trainVoice() {
  flushHistoryCorrections()
  guard !shuttingDown, !busy, !recording, !trainingVoice, learningSamples.filter({$0.confirmed}).count>=10 else {return}
  // A running personal model keeps its own weights when a new candidate is produced.
  do {
   if FileManager.default.fileExists(atPath:learningDirectory.appendingPathComponent("use-adapter").path) {try preserveActiveAdapter()}
  } catch {learningStatus="Could not preserve active adapter. Training did not start.";return}
  let batch=Set(trainingSchedule.pending(learningSamples).sorted{$0.uuidString<$1.uuidString}.prefix(10))
  let previousSchedule=trainingSchedule
  trainingSchedule.attempted.formUnion(batch)
  do {try saveTrainingSchedule()} catch {trainingSchedule=previousSchedule;learningStatus="Could not save training schedule.";return}
  trainingVoice=true;learningStatus="Training a candidate · dictation is paused"
  speechForLearningShutdown()
  let job=ProcessingJob(timeout:660);learningJob=job
  let python=AppResources.python("asr")
  let script=Bundle.main.resourceURL!.appendingPathComponent("ASR/train.py")
  let directory=learningDirectory
  DispatchQueue.global(qos:.utility).async {
   let p=Process();p.environment=AppResources.environment();p.executableURL=python;p.arguments=["-B",script.path,directory.path,batch.map{$0.uuidString}.joined(separator:",")]
   p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
   var succeeded=false
   do {try job.run(p,timeout:660);succeeded=p.terminationStatus==0}catch{}
   let success=succeeded
   DispatchQueue.main.async {
    self.trainingVoice=false;self.learningJob=nil
    if success {
     self.trainingSchedule.completed.formUnion(batch)
     do {try self.saveTrainingSchedule()}catch{}
     self.learningStatus="Candidate ready for review. Your current model has not changed."
    } else {self.learningStatus="Training failed or cancelled. Retry with Train candidate; automatic training waits for 10 further corrected recordings."}
   }
  }
 }
}
