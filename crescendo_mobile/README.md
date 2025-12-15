## Crescendo Mobile (Flutter)

Offline-first Flutter app that mirrors the Crescendo warmup/analysis flow: generate warmups, play reference audio, record while monitoring pitch, visualize Melodyne-style graph, score, and save/compare takes locally.

### Getting Started
```bash
cd crescendo_mobile
flutter pub get
flutter test
flutter run
```

### Packages
- flutter_sound: mic PCM capture/record
- pitch_detector_dart: on-device pitch estimation
- mic_stream: realtime mic streaming for the SimplySing-style screen
- permission_handler, wakelock_plus: mic permission + keep-awake for realtime pitch
- audioplayers: playback for reference + takes
- sqflite (+ sqflite_common_ffi for tests): local persistence
- path_provider, path, collection, flutter_lints

### Architecture
- models/: WarmupDefinition, NoteSegment, PitchFrame, Metrics, Take
- services/: audio synthesis, recording/pitch detection, scoring, storage (sqflite)
- ui/: Material 3 tabs (Warmups, Record, History), Melodyne-style graph widget, piano builder

### Swapping pitch detector
`services/pitch_detection_service.dart` centralizes pitch extraction. Replace the detector there (and optionally `RecordingService`) with another library; ensure it emits `PitchFrame(time, hz, midi)`.

### Known limitations
- Audio capture/synthesis are simplified; tune buffer sizes if devices under/over-run.
- Graph auto-scroll is basic; adjust in `PitchGraph` if you want sticky playhead behavior.
- Reference synthesis is sine-only; swap out in `AudioSynthService` for richer timbre.

### Realtime pitch screen
- Screen: Realtime tab (RealtimePitchScreen) uses mic_stream + pitch_detector_dart for low-latency pitch.
- Mic permission required on iOS; message set in Info.plist.
- Pitch range defaults to C3–C6; adjust in `PitchTailPainter`.
- If simulator audio is choppy, test on device for smoother updates.
