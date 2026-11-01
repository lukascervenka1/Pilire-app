#!/bin/zsh
set -eu
market_root="$(cd "$(dirname "$0")/.." && pwd)"
market_checks="$(mktemp -d "${TMPDIR:-/tmp}/pillars-market.XXXXXX")"
trap 'rm -rf "$market_checks"' EXIT
cd "$market_root"
python3 - "$market_checks/LocalizationCore.swift" <<'PY'
from pathlib import Path
import sys
source = Path("Pilire/Localization.swift").read_text()
Path(sys.argv[1]).write_text(source[:source.index("struct LanguagePickerView")])
PY
swiftc -parse-as-library -default-isolation MainActor -module-cache-path "$market_checks/modules" \
    Pilire/Models.swift "$market_checks/LocalizationCore.swift" Pilire/Strings.swift \
    Pilire/UserSettings.swift Pilire/Market.swift Tests/MarketChecks.swift -o "$market_checks/checks"
"$market_checks/checks"
