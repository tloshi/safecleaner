#!/usr/bin/env python3
"""Lightweight architecture guard. Behavioral safety lives in the test suites."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
rules = [
    ("Sources/SafeCleaner/Views", r"\b(FileManager|NSWorkspace|NSOpenPanel|UserDefaults|ProcessInfo|NSHomeDirectory|WorkspaceViewModel|CleaningRepository|byteLabel)\b"),
    ("Sources/SafeCleaner/DesignSystem", r"\b(FileManager|NSWorkspace|NSOpenPanel|UserDefaults|WorkspaceViewModel|CleaningRepository)\b"),
    ("Sources/SafeCleanerPresentation", r"\b(import\s+(SwiftUI|AppKit)|FileManager|NSWorkspace|NSOpenPanel|UserDefaults|ProcessInfo)\b"),
    ("Sources/SafeCleanerCore", r"\bimport\s+(SwiftUI|AppKit|Combine)\b"),
]
failures = []
for directory, pattern in rules:
    for file in (root / directory).rglob("*.swift"):
        for number, line in enumerate(file.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if re.search(pattern, code):
                failures.append(f"{file.relative_to(root)}:{number}: layer violation: {code.strip()}")

# The rename to SafeCleaner missed the sidebar wordmark, because it is built as
# Text("viggo") + Text("clean") for the weight contrast and no search for the old
# product name could ever match it. The app shipped under the wrong name.
# Catch the fragments, not the whole word.
# Scoped to the layers that render text. Services legitimately still name the old
# bundle identifier, because settings saved under it have to be migrated forward.
for directory in ("Sources/SafeCleaner/Views", "Sources/SafeCleaner/DesignSystem",
                  "Sources/SafeCleanerPresentation"):
    for file in (root / directory).rglob("*.swift"):
        for number, line in enumerate(file.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if re.search(r'"[^"]*[Vv]iggo', code):
                failures.append(f"{file.relative_to(root)}:{number}: legacy product name in a user-facing string: {code.strip()}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Architecture boundaries passed: passive Views, isolated Presentation, UI-free Core.")
