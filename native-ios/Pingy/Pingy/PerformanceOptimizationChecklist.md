# Pingy v4.0.0 - Performance Optimization Checklist

## Rendering
- [x] Use one blur/material layer per glass container.
- [x] Avoid nested `UIVisualEffectView`/material stacks.
- [x] Keep message bubbles on a single compositing layer.
- [x] Avoid parent opacity changes for media content.
- [x] Keep image content fully opaque to prevent dimming.

## Scrolling
- [x] Dynamic blur tied to scroll velocity (`LiquidScrollBlurManager`).
- [x] Fast-scroll mode lowers blur radius and opacity for GPU relief.
- [x] Header compression and avatar scaling are lightweight value animations.
- [x] Message list remains `LazyVStack` and only renders visible cells.

## Messaging Updates
- [x] Message cell uses `Equatable` diffing.
- [x] Avoid full list reload for status updates.
- [x] Search results computed off main thread (`Task.detached`).

## Media and IO
- [x] Use cached image loader for avatar/media thumbnails.
- [x] Keep media operations async and off the main thread.
- [x] Do not decode large media synchronously on UI thread.

## Interaction
- [x] Bubble press/long-press animation is transform-only (no layout thrash).
- [x] Floating menu uses morph transition with spring timing.
- [x] Dock drag effect updates only highlight/tilt state (no view rebuild).

## Frame Pacing Validation
- [ ] Verify minimum 60 FPS on long chats with mixed media.
- [ ] Verify smoothness on fast scroll + rapid reactions.
- [ ] Verify no dropped frames while opening media viewer.
- [ ] Verify no tap latency on bottom dock interactions.

## Release Gate
- [ ] Messages send reliably.
- [ ] Voice playback reliable.
- [ ] Media open/retry reliable.
- [ ] No overlay blocks taps.
- [ ] No severe lag spikes under stress.
