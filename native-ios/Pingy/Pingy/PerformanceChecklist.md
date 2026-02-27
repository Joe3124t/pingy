# Pingy v3.9.0 Performance Checklist

## Rendering and Scrolling
- [x] Chat messages render with `LazyVStack`.
- [x] Message rows are wrapped in `ChatMessageCell` (`Equatable`) to reduce redraw churn.
- [x] Message list updates use existing diffed message source from `MessengerViewModel`.
- [x] Fast-scroll detection is enabled and reduces expensive glass rendering in real time.

## Blur and Glass Cost Control
- [x] One blur/material layer per bubble path.
- [x] Dynamic opacity is applied by `SmartGlassOpacityManager`.
- [x] Gloss highlight is disabled for media and while fast-scrolling.
- [x] Decorative overlays are marked `.allowsHitTesting(false)`.

## Text and Contrast
- [x] Adaptive contrast is driven by `AdaptiveTextEngine`.
- [x] Dark backgrounds force high-contrast text (`#FFFFFF` equivalent).
- [x] Subtle text glow is applied conditionally (non-neon).

## Media Clarity
- [x] Media bubble uses separate backdrop and fully opaque image content.
- [x] Fullscreen viewer applies light brightness/contrast boost.
- [x] Fullscreen viewer uses smooth fade-in and dimmed background layer.

## Voice Playback
- [x] Playback session uses `AVAudioSession` `.playback`.
- [x] Single active playback is enforced via `VoicePlayerEngine` notifications.
- [x] Progress/waveform animation updates while playing.
- [x] Audio session deactivates on stop/end.

## Runtime Safety
- [x] No force unwraps introduced in new v3.9.0 files.
- [x] Async tasks are canceled where needed (scroll speed reset task).
- [x] Interactive hit targets remain enabled (no overlay touch blocking).
