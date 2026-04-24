/// Fluera Engine — INTERNAL barrel (not part of public SDK API).
///
/// This file re-exports symbols that are used by the Fluera consumer app but
/// should NOT appear in the public SDK surface. Moved here during the SDK
/// split to keep `fluera_engine.dart` clean for external developers.
///
/// ⚠️  DO NOT import this file from code outside the Fluera monorepo.
///     Public SDK users should import `package:fluera_engine/fluera_engine.dart`.
///
/// ```dart
/// import 'package:fluera_engine/fluera_engine_internal.dart';
/// ```
library;

export 'src/layers/fluera_layer_controller.dart';
export 'src/collaboration/fluera_realtime_adapter.dart';
export 'src/canvas/fluera_canvas_screen.dart';
export 'src/canvas/fluera_canvas_config.dart';
export 'src/canvas/ai/srs_due_count_provider.dart'; // 📊 Gallery badge: due review count
export 'src/canvas/ai/srs_stage_indicator.dart'; // 🌱→👻 5-stage mastery enum
export 'src/canvas/ai/pedagogical_accessibility_config.dart'; // ♿ A11 accessibility
export 'src/canvas/ai/content_taxonomy.dart'; // 📋 A20.3 input method tracking
export 'src/canvas/ai/passeggiata_controller.dart'; // 🚶 A10 contemplative mode
export 'src/canvas/ai/red_wall_controller.dart'; // 🧱 A20.4 crisis response
export 'src/canvas/ai/interleaving_path_controller.dart' hide PathNode; // ✨ P6-15 sentiero luminoso
export 'src/canvas/ai/step_transition_choreographer.dart'; // 🎭 A13.2 step transitions
export 'src/canvas/ai/socratic/socratic_output_filter.dart'; // 🛡️ A2-04 G2 guardrail
export 'src/canvas/ai/onboarding_controller.dart'; // 🎓 A20.1 onboarding esperienziale
export 'src/canvas/ai/celebration_controller.dart'; // 🎉 A13.8 discrete celebrations
export 'src/canvas/ai/tier_gate_controller.dart'; // 💳 A17 feature gating
export 'src/canvas/ai/step_onboarding_controller.dart'; // 📖 A13.6 per-step onboarding
export 'src/canvas/ai/hypercorrection_effect.dart'; // ⚡ P3-21 visual shock
export 'src/canvas/ai/fog_cinematic_controller.dart'; // 🌫️ P10-21 cinematic reveal
export 'src/canvas/ai/ghost_map_cache.dart'; // 🗺️ A3-04 concept map cache
export 'src/canvas/ai/fsrs_calibration.dart'; // 📊 A5-06 personal calibration
export 'src/canvas/ai/srs_pull_controller.dart'; // 📅 A9 pull mechanism
export 'src/services/semantic_embedding_service.dart'; // 🧠 A7 MiniLM embeddings
export 'src/canvas/ai/gdpr_consent_manager.dart'; // 📋 A16 GDPR consent
export 'src/canvas/ai/data_deletion_service.dart'; // 🗑️ A16 Art.17 deletion
export 'src/canvas/ai/user_data_export_service.dart'; // 📦 A16 Art.20 export
export 'src/canvas/ai/llm_payload_anonymizer.dart'; // 🔒 A16 Art.25 anonymizer
export 'src/storage/encrypted_database_provider.dart'; // 🔐 A16 Art.32 SQLCipher
export 'src/canvas/ai/pedagogical_telemetry_service.dart'; // 📊 A19 telemetry
export 'src/canvas/ai/knowledge_type_controller.dart'; // 📚 A20.6 knowledge types
export 'src/canvas/ai/degraded_mode_controller.dart'; // 📱 A20.7 degraded mode
export 'src/canvas/ai/celebration_painters.dart'; // 🎨 A13.8 celebration rendering
export 'src/p2p/p2p_session_state.dart'; // 🤝 A4 FSM
export 'src/p2p/p2p_message_types.dart'; // 📡 A4 wire protocol
export 'src/p2p/p2p_session_controller.dart'; // 🤝 A4 session orchestrator
export 'src/p2p/channels/ghost_cursor_channel.dart'; // 👻 A4-03 cursor sync
export 'src/p2p/channels/viewport_sync_channel.dart'; // 🖥️ A4-03 viewport sync
export 'src/p2p/p2p_privacy_guard.dart'; // 🛡️ A4-09, P7-31 hidden areas
export 'src/p2p/collab_invite_service.dart'; // 🔗 P7-02 invite links
export 'src/p2p/p2p_session_data.dart'; // 📊 P7-07 session data
export 'src/p2p/p2p_engine.dart'; // ⚙️ A4 central orchestrator
export 'src/p2p/channels/voice_channel.dart'; // 🎙️ A4-05 voice state
export 'src/p2p/channels/laser_pointer_channel.dart'; // ✨ P7-15 laser pointer
export 'src/p2p/in_memory_p2p_adapters.dart'; // 🧪 testing adapters
export 'src/p2p/fluera_p2p_connector.dart'; // 🔌 abstract P2P connector
export 'src/p2p/canvas_rasterizer.dart'; // 🎬 canvas frame capture
export 'src/rendering/canvas/ghost_cursor_painter.dart'; // 👻 P7-05 ghost cursor
export 'src/rendering/canvas/laser_pointer_painter.dart'; // ✨ P7-15 laser pointer
export 'src/rendering/canvas/p2p_marker_painter.dart'; // 📌 P7-08 markers
export 'src/canvas/overlays/p2p_session_overlay.dart'; // 🤝 P2P session overlay
export 'src/canvas/overlays/p2p_mode_selection_sheet.dart'; // 🎯 mode selection
export 'src/canvas/overlays/p2p_invite_sheet.dart'; // 🔗 invite sharing
export 'src/canvas/overlays/p2p_duel_overlay.dart'; // ⚔️ duel countdown/timer
export 'src/canvas/overlays/invite_code_painter.dart'; // 📱 visual invite code
export 'src/canvas/liquid_canvas_config.dart';
export 'src/canvas/spring_animation_controller.dart';
export 'src/storage/fluera_storage_adapter.dart';
export 'src/storage/fluera_cloud_adapter.dart';
export 'src/ai/ai_usage_tracker.dart';
export 'src/ai/noop_ai_usage_tracker.dart';
export 'src/ai/telemetry_recorder.dart'; // 📊 Product telemetry sink
// NOTE: GeminiProxyConfig + Exceptions stay in the public barrel — host apps
// need them to construct EngineScope with a proxy. Non-public classes from
// gemini_client (GeminiClient, ProxiedGeminiClient, DirectGeminiClient) are
// reached via the app's own service layer, not through a re-export.
export 'src/l10n/fluera_localizations.dart';
