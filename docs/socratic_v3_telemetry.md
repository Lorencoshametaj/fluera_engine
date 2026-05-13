# Socratic V3 Telemetry — A/B Analysis Reference

**Data:** 2026-05-12
**Audience:** product/data analytics + future Claude sessions

## Background

The Socratic V3 redesign (2026-05-12) introduced pedagogical stages,
discipline awareness, misconception probes, adaptive sequence skip-ahead,
threshold concept detection, multi-turn stage-aware follow-up, and G4
chain-of-verification. The telemetry events below enable production A/B
comparison against V2 baseline (pre-redesign sessions still in the
event store).

## Event: `step_3_socratic_started`

Fired once at session activation. Use as the **enrollment** point for
A/B cohort assignment.

| Property | Type | Meaning |
|---|---|---|
| `cluster_count` | int | Clusters selected by the student in the picker |
| `question_count` | int | Slots in the generated batch |
| `max_questions` | int | Session cap (3-8) |
| `used_fallback` | bool | Whether the AI batch failed and fallback fired |
| `stage_sequence` | string | Comma-separated stage labels (anchor,elaboration,…) |
| `discipline_inferred` | string | Detected discipline name (physics/math/…/generic) |
| `misconception_id` | string | Misconception injected (or 'null') |

**V2 sessions are identifiable by the ABSENCE of `stage_sequence`** — they
predate the redesign. V3 sessions ALWAYS have this property.

## Event: `step_3_socratic_completed`

Fired at session end (when the user dismisses or runs out of questions).
Use as the **outcome** point for the A/B comparison.

| Property | Type | Meaning | Sprint |
|---|---|---|---|
| `questions_answered` | int | Total questions the student engaged with | V1.5 |
| `questions_correct` | int | Total recalled-correct outcomes | V1.5 |
| `questions_wrong` | int | Total wrong outcomes | V1.5 |
| `duration_sec` | int | Total session duration (seconds) | V1.5 |
| `adaptive_jumps_count` | int | Adaptive skip-aheads consumed (max 1/session) | S1.A |
| `threshold_candidates_count` | int | Clusters flagged as liminal after session | S2.B |
| `multiturn_extensions_count` | int | Questions that grew past initial turn | S2.A |
| `redesign_version` | string | `'v3_2026_05_12'` (V2 sessions lack this) | S3.B |
| `avg_confidence` | float | Mean self-declared confidence (1.0-5.0) | S3.B |
| `uncertain_reflections` | int | Count of `uncertain` 3-state reflections (productive struggle signal — HIGHEST FSRS stability bump) | S3.B |
| `satisfied_reflections` | int | Count of `satisfied` reflections (consolidation signal) | S3.B |
| `thinking_reflections` | int | Count of `thinking` reflections (engagement signal) | S3.B |
| `validation_accept_count` | int | Slots where validator returned `accept` directly | Sprint 5 |
| `validation_retry_count` | int | Slots that required a retry call | Sprint 5 |
| `validation_reject_count` | int | Slots rejected outright (generic ceremonial / empty) | Sprint 5 |
| `retry_success_count` | int | Retries that produced a question accepted on re-validation | Sprint 5 |
| `fallback_count` | int | Slots that ended on stage-aware fallback template | Sprint 5 |
| `parse_fail_count` | int | Batch responses that failed JSON parse entirely | Sprint 5 |
| `parse_partial_count` | int | Batch responses where some entries salvaged via regex | Sprint 5 |
| `cross_lang_session` | int (0/1) | At least one slot was a cross-language session | Sprint 5 |
| `accept_rate` | float | accept / total evaluated (per session) | Sprint 5 |
| `retry_success_rate` | float | retry_success / retry_count (per session) | Sprint 5 |
| `reject_reasons` | string | Pipe-separated reason codes for reject/retry events | Sprint 5 |
| `lang_code` | string | ISO 639-1 active language for this session | Sprint D ω |
| `lang_validation_status` | string | `productionNative` (IT/EN) or `aiBootstrap` (14 others) | Sprint D ω |
| `stages_streamed_count` | int | Stages that completed a real stream (1 q parsed) | Sprint D ω |
| `stages_fallback_count` | int | Stages that fell back to template (stream fail/empty) | Sprint D ω |
| `first_question_visible_ms` | int | Perceived latency from stream-start to first parsed q | Sprint D ω |
| `suspicious_tiny_count` | int | Stage calls that returned <80 chars (proxy cap canary) | Sprint E.5 ω |
| `retry_on_tiny_recovered_count` | int | Tiny-response retries that DID recover (defense in depth) | Sprint E.5 ω |

## Sprint 5 failure-mode dashboard queries

```sql
-- Top reject reasons across the last 30 days
SELECT
  reason,
  COUNT(*) AS occurrences
FROM events,
     UNNEST(SPLIT(JSON_EXTRACT_STRING(properties, '$.reject_reasons'), '|')) AS reason
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '30 days'
  AND reason != ''
GROUP BY reason
ORDER BY occurrences DESC
LIMIT 10;
```

```sql
-- Fallback rate (>0 fallbacks per session is a smell)
SELECT
  CASE
    WHEN JSON_EXTRACT_DOUBLE(properties, '$.fallback_count') >= 1 THEN 'has_fallback'
    ELSE 'clean'
  END AS bucket,
  COUNT(*) AS sessions
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY bucket;
```

```sql
-- Retry effectiveness (does the retry path actually recover questions?)
SELECT
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.retry_success_rate')) AS avg_rate,
  COUNT(*) AS sessions
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '30 days'
  AND JSON_EXTRACT_DOUBLE(properties, '$.validation_retry_count') > 0;
```

## Sprint D ω dashboard queries

```sql
-- Per-language quality A/B (production_native vs ai_bootstrap)
SELECT
  JSON_EXTRACT_STRING(properties, '$.lang_code') AS lang,
  JSON_EXTRACT_STRING(properties, '$.lang_validation_status') AS status,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.first_question_visible_ms')) AS avg_perceived_latency,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.stages_fallback_count')) AS avg_fallback,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.uncertain_reflections')) AS avg_uncertain,
  COUNT(*) AS sessions
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY lang, status;
```

```sql
-- Native validation candidates: bootstrap langs with consistent quality
SELECT
  JSON_EXTRACT_STRING(properties, '$.lang_code') AS lang,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.stages_fallback_count')) AS avg_fallback,
  COUNT(*) AS sessions
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND JSON_EXTRACT_STRING(properties, '$.lang_validation_status') = 'aiBootstrap'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY lang
HAVING AVG(JSON_EXTRACT_DOUBLE(properties, '$.stages_fallback_count')) < 1.0
ORDER BY sessions DESC;
```

## Sprint E.5 ω canary query

```sql
-- Proxy/model output cap regression detector: any session with
-- `suspicious_tiny_count > 0` indicates the proxy returned ≥1
-- stage call with <80 chars. Spike = imminent quality drop.
SELECT
  DATE_TRUNC('day', timestamp) AS day,
  SUM(JSON_EXTRACT_DOUBLE(properties, '$.suspicious_tiny_count')) AS total_tiny,
  SUM(JSON_EXTRACT_DOUBLE(properties, '$.retry_on_tiny_recovered_count')) AS total_recovered,
  COUNT(*) AS sessions,
  CASE
    WHEN COUNT(*) > 0 THEN
      SUM(JSON_EXTRACT_DOUBLE(properties, '$.suspicious_tiny_count')) * 1.0
        / COUNT(*)
    ELSE 0
  END AS avg_tiny_per_session
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY day
ORDER BY day DESC;
```

Alert thresholds:
- `avg_tiny_per_session > 0.2` for ≥2 consecutive days → proxy regression suspected
- `total_recovered / total_tiny > 0.7` → retry path effective (system self-heals)
- `total_recovered / total_tiny < 0.3` → retry not helping; investigate proxy

## Sprint 6 decision thresholds

After 1 week of post-Sprint 5 telemetry:

- `accept_rate ≥ 0.80` AND `parse_fail_count = 0` for ≥ 95% sessions → architecture stable, no further changes.
- `parse_fail_count ≥ 1` for ≥ 10% sessions → consider Gemini Pro upgrade for Socratic batch.
- `retry_success_rate ≤ 0.50` → retry path adds cost without recovering quality; remove retry, accept reject → fallback directly.
- Top reject reason: if `language_drift`, system prompt language pin needs work. If `no_specificity`, fallback template OR stage detection. If `generic_ceremonial`, model prompt is producing fluff.

## Analysis queries

### A/B effect: retention rate V3 vs V2

```sql
WITH sessions AS (
  SELECT
    user_id,
    session_id,
    COALESCE(JSON_EXTRACT_STRING(properties, '$.redesign_version'), 'v2') AS version,
    timestamp AS session_started_at
  FROM events
  WHERE event_name = 'step_3_socratic_started'
),
returns AS (
  -- Did the user return for another Socratic session within 7 days?
  SELECT
    s1.user_id,
    s1.session_id,
    s1.version,
    EXISTS (
      SELECT 1 FROM sessions s2
      WHERE s2.user_id = s1.user_id
        AND s2.session_started_at > s1.session_started_at
        AND s2.session_started_at < s1.session_started_at + INTERVAL '7 days'
    ) AS returned_within_7d
  FROM sessions s1
)
SELECT
  version,
  COUNT(*) AS sessions,
  SUM(CASE WHEN returned_within_7d THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS retention_7d_pct
FROM returns
GROUP BY version;
```

### Effect: avg uncertain reflections per session

```sql
SELECT
  COALESCE(JSON_EXTRACT_STRING(properties, '$.redesign_version'), 'v2') AS version,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.uncertain_reflections')) AS avg_uncertain,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.satisfied_reflections')) AS avg_satisfied,
  AVG(JSON_EXTRACT_DOUBLE(properties, '$.avg_confidence')) AS avg_confidence
FROM events
WHERE event_name = 'step_3_socratic_completed'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY version;
```

Pedagogical interpretation:
- **Higher `uncertain_reflections` in V3 = WIN.** Productive struggle (Bjork)
  is the strongest learning signal; the redesign explicitly rewards it
  with the highest FSRS stability bump (+1.0).
- **Lower `avg_confidence` paired with stable `questions_correct` = WIN.**
  Better calibration; over-confidence (high conf + wrong = hypercorrection)
  drops because the redesign surfaces those clusters as priority
  counterfactual in the next session (S1.B).
- **Higher `threshold_candidates_count` over time = WIN.** The system is
  identifying clusters where the student is in Meyer & Land liminality;
  the consolidation sheet surfaces them with encouraging framing.

### Funnel: G4 rejection rate

The G4 chain-of-verification (S3.A) rejects questions with quality score
< 0.6, swapping for `fallbackForStage`. This is NOT a telemetry property
(yet), but `🛡️ G4 rejected` log lines on device can be grepped
post-session for offline analysis. Future: surface as `g4_rejections_count`.

## Cohort definition

- **V2 cohort**: events where `step_3_socratic_started.stage_sequence IS NULL`
- **V3 cohort**: events where `step_3_socratic_started.stage_sequence IS NOT NULL`

Users are not randomized — V2 is historical baseline, V3 is current. This
is a **before/after** observational study, not a true RCT. Account for
seasonality and tier mix (Pro vs Free) when comparing.

## Privacy guardrails

- No question text, cluster text, or stroke content is sent to telemetry.
- Only structural counters + enum names.
- `discipline_inferred` is the discipline LABEL (physics/math/…), not the
  cluster content. Safe to log.
- `misconception_id` is the canonical id (e.g. `motion-requires-force`),
  not the text. Safe to log.

## Future enhancements (out of Sprint 3 scope)

- `g4_rejections_count` per session
- Per-stage time spent (anchor took 30s, counterfactual took 3min)
- A/B framework with explicit randomization (not before/after)
- Per-discipline retention analysis
