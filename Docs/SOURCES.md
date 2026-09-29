# Primary references reviewed for R001 — 2026-09-30

- Swift Evolution SE-0390, Noncopyable structs and enums:
  https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md
  Used for unique ownership, consuming transfer and exclusive mutation. The
  implementation is compiled and tested; the proposal is not treated as proof
  of every current compiler detail.
- Apple, Swift Testing:
  https://developer.apple.com/documentation/testing
  Framework reference for executable tests; actual macro/ownership compatibility
  was checked against the installed toolchains.
- Apple, Embracing Swift concurrency (WWDC25):
  https://developer.apple.com/videos/play/wwdc2025/268/
  Background context for keeping responsive UI distinct from computation. No
  runtime executor or UI scheduling behavior is claimed by this foundation.

No code from these references or retired projects is copied. No statement of
latest Swift/Xcode/iOS support is implied by the conservative package targets.
