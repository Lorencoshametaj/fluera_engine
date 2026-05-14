// 🎓 Atlas Exam V3.4 ω — ExamPhase enum.
//
// The 3 distinct Gemini surfaces in the Exam pipeline. Each phase has its
// own pedagogy + output contract → its own cached system prompt cell in
// `exam_pedagogy_{it,en,bootstrap}.dart`.
//
// Why not "per question-type" (open/MC/T-F/formula)? One Exam batch call
// emits N questions of MIXED types — splitting per type would 4× the
// token cost AND break the Bloom distribution contract (40% Apply etc.
// is computed across the batch). Phase is the natural unit.

enum ExamPhase {
  /// Question generation. System prompt: Bloom rubric + QUESTION_MIX +
  /// HARD_CONSTRAINTS + OUTPUT_SCHEMA template. Payload per-call:
  /// difficulty, count, cluster summary, variation seed, avoid list.
  generation,

  /// Open-answer grading. System prompt: 3-way verdict rubric
  /// (CORRETTO/PARZIALE/SBAGLIATO) + growth-mindset feedback style.
  /// Payload per-call: question, correct answer, student answer.
  evaluation,

  /// Single hint when student is stuck. System prompt: ≤12 words,
  /// no preamble, no reveal, point to underlying principle. Payload
  /// per-call: question, correct answer.
  hint,
}
