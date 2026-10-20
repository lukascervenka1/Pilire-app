#!/bin/zsh
set -eu
calendar_root="$(cd "$(dirname "$0")/.." && pwd)"
calendar_checks="$(mktemp -d "${TMPDIR:-/tmp}/pillars-weekly-chest.XXXXXX")"
trap 'rm -rf "$calendar_checks"' EXIT
cd "$calendar_root"

# Localization's UI picker is unrelated to the domain checks.
python3 - "$calendar_checks/LocalizationCore.swift" <<'PY'
from pathlib import Path
import sys
source = Path("Pilire/Localization.swift").read_text()
Path(sys.argv[1]).write_text(source[:source.index("struct LanguagePickerView")])
PY

swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$calendar_checks/modules" \
    Pilire/WeeklyChestProgress.swift Tests/WeeklyChestProgressChecks.swift \
    -o "$calendar_checks/progress"
"$calendar_checks/progress"

swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$calendar_checks/modules" \
    Pilire/Models.swift "$calendar_checks/LocalizationCore.swift" Pilire/Strings.swift \
    Pilire/UserSettings.swift Pilire/WeeklyChestProgress.swift Pilire/WeeklyChestClaims.swift \
    Tests/WeeklyChestClaimsChecks.swift -o "$calendar_checks/claims"
"$calendar_checks/claims"
