// Pure-Dart enum, isolated so tool scripts (which can't pull `dart:ui`
// transitively through the rest of socratic_model.dart) can import the
// library transitively without dragging Flutter in.
//
// Re-exported by `socratic_model.dart` for backward compatibility.

/// One of 10 academic disciplines used to route discipline-aware
/// pedagogy hints (Tier-1 IT investment per
/// docs/prompt_engineering_cognitive.md §10) and misconception
/// injection. `generic` is the fallback when no discipline keyword
/// matches the cluster content — in that case the prompt's
/// discipline-specific section is skipped and misconception
/// injection is suppressed.
enum Discipline {
  physics,
  math,
  chemistry,
  biology,
  medicine,
  law,
  economics,
  philosophy,
  history,
  generic,
}
