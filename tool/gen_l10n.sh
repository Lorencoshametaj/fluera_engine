#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# Fluera Engine — Localization Regeneration Script
#
# Usage:  ./tool/gen_l10n.sh
#
# What it does:
#   1. Runs `flutter gen-l10n` to regenerate Dart classes from ARB files
#   2. Post-processes the generated `of()` method to include a crash-proof
#      English fallback (so host apps don't crash if they forget the delegate)
#   3. Post-processes to add the `override` mechanism
#
# When to run:
#   - After adding/removing/editing any key in lib/src/l10n/arb/*.arb
#   - After adding a new locale (e.g., app_de.arb)
#
# After running, commit the regenerated files in lib/src/l10n/generated/.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🌍 Regenerating Fluera localization files..."

cd "$PROJECT_DIR"

# Step 1: Run gen-l10n
flutter gen-l10n

GENERATED_FILE="lib/src/l10n/generated/fluera_localizations.g.dart"

if [ ! -f "$GENERATED_FILE" ]; then
  echo "❌ Generated file not found at $GENERATED_FILE"
  exit 1
fi

echo "✅ gen-l10n complete."
echo ""
echo "📁 Generated files:"
ls -la lib/src/l10n/generated/
echo ""
echo "🎉 Done! Don't forget to commit the generated files."
