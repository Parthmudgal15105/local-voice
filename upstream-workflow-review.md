# Dictation reliability: upstream review and adaptations

Reviewed public source on 21 October 2026. These are Swift adaptations of selected patterns; Local Voice continues to use its existing Swift app, Whisper, Qwen, IndicXlit, and private HP services. No upstream installers or application runtimes are bundled.

## Sources and attribution

- Handy, copyright 2025 CJ Pais, MIT. Reviewed commit `93c9ee05efe294cf2a56bd534b77ea1079f21b77`.
  - [Model capability and chunking policy](https://github.com/cjpais/Handy/blob/93c9ee05efe294cf2a56bd534b77ea1079f21b77/src-tauri/src/managers/transcription/policy.rs): bounded long-form chunks; streaming and batch fallback use the same recording.
  - [Actions](https://github.com/cjpais/Handy/blob/93c9ee05efe294cf2a56bd534b77ea1079f21b77/src-tauri/src/actions.rs): cancellation checks between recording, recognition, postprocessing, and paste.
  - [Audio management](https://github.com/cjpais/Handy/blob/93c9ee05efe294cf2a56bd534b77ea1079f21b77/src-tauri/src/managers/audio.rs): separate capture and recognition lifecycles.
- OpenWhispr, copyright 2024 OpenWhispr Team, MIT. Reviewed commit `2aaa7bcb23699daf65feecf7ca2a18d141174279`.
  - [Recording guard](https://github.com/OpenWhispr/openwhispr/blob/2aaa7bcb23699daf65feecf7ca2a18d141174279/src/helpers/recordingGuard.js): validate real audio rather than rejecting short utterances by wall-clock time. Local Voice validates decoded PCM instead of copying the WebM-specific byte threshold.
  - [Dictionary echo filter](https://github.com/OpenWhispr/openwhispr/blob/2aaa7bcb23699daf65feecf7ca2a18d141174279/src/utils/dictionaryEchoFilter.js): the vocabulary-echo shape checks were ported to `VocabularyEchoGuard`, retaining Unicode combining marks for Hindi. Suspect output is offered for review, not silently removed or pasted.
  - [Transcription timeout](https://github.com/OpenWhispr/openwhispr/blob/2aaa7bcb23699daf65feecf7ca2a18d141174279/src/helpers/transcriptionTimeout.js): time budgets scale with audio duration; Local Voice uses its own bounded budgets.
  - [Failure outcomes](https://github.com/OpenWhispr/openwhispr/blob/2aaa7bcb23699daf65feecf7ca2a18d141174279/src/helpers/transcriptionFailureOutcome.js): retain original audio and partial text when later processing fails.
  - [Fallback routing](https://github.com/OpenWhispr/openwhispr/blob/2aaa7bcb23699daf65feecf7ca2a18d141174279/src/helpers/transcriptionFallback.js): explicitly choose fallback destinations and honor cancellation. Local Voice only routes to the configured HP service and this Mac.

Full upstream MIT notices are preserved in `ThirdParty/Handy/LICENSE` and `ThirdParty/OpenWhispr/LICENSE`, and copied into the app's `Contents/Resources/Licenses/` folder.

## Implemented behavior

1. Freeze the recognition route, language, and dictionary at recording start. Keep only language/model/route in a private recovery sidecar; retry uses the saved route and current vocabulary/corrections. Current privacy settings still control learning and history retention.
2. Validate actual decoded PCM, including short utterances. Reject empty, corrupt, unsupported, or digitally silent input before inference.
3. Start recognizing complete ~20–30-second chunks while recording continues. Read the recorder's existing PCM stream without interrupting microphone capture. Prefer a quiet boundary; forced cuts carry 0.5 seconds into the following chunk. Only exact multi-word boundary overlaps are reconciled. Single-word uncertainty is retained rather than deleting possible speech.
4. Keep live output in memory as a preview. After Finish, process the tail, combine the recognition results, romanize/correct once, and insert once. Never paste partial live results into the destination.
5. On a live reader/chunk failure, retain the original full recording and use batch recognition after Finish. Unsupported provisional WAV layouts also use this fallback. Batch recognition uses pause-aware ~30-second segments for recordings longer than 40 seconds.
6. On technical failures, use HP → selected Mac recognizer → independent Whisper helper when Qwen failed → Whisper CLI. Stop retrying a failed HP route for the remainder of that recognition run. Empty or suspicious responses remain available for review rather than blindly cycling models.
7. If any batch segment fails or returns empty output, preserve earlier recognized words and the full audio; do not present the incomplete result as a successful dictation. Recovery has explicit local-Whisper and current-settings retries.
8. Use monotonic, duration-scaled deadlines and cancel owned HTTP tasks/processes. Cancellation cannot start a later fallback or paste a late result. Keep the model warm while recording, then apply the existing idle release.
9. Give the recording pill an elapsed timer and explicit Finish control.

## Practical limits

Chunking is incremental batch recognition, not word-by-word streaming. It begins after roughly 20–30 seconds and only reduces final wait if inference keeps up with capture. Quiet-boundary detection is an energy heuristic; forced overlaps can still produce boundary recognition errors. Translation in separate chunks can lose sentence context. The switch in Settings allows whole-recording processing instead, and the original audio is retained whenever the pipeline fails.

The upstream clipboard code was also reviewed. Handy's receipt-based paste path is marked experimental upstream; this update prioritizes transcription reliability and retains Local Voice's existing paste safety checks.
