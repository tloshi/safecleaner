#!/usr/bin/env python3
"""Lightweight architecture guard. Behavioral safety lives in the test suites."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
rules = [
    ("Sources/ViggoClean/Views", r"\b(FileManager|NSWorkspace|NSOpenPanel|UserDefaults|ProcessInfo|NSHomeDirectory|WorkspaceViewModel|CleaningRepository|byteLabel)\b"),
    ("Sources/ViggoClean/DesignSystem", r"\b(FileManager|NSWorkspace|NSOpenPanel|UserDefaults|WorkspaceViewModel|CleaningRepository)\b"),
    ("Sources/ViggoCleanPresentation", r"\b(import\s+(SwiftUI|AppKit)|FileManager|NSWorkspace|NSOpenPanel|UserDefaults|ProcessInfo)\b"),
    ("Sources/ViggoCleanCore", r"\bimport\s+(SwiftUI|AppKit|Combine)\b"),
]
failures = []
for directory, pattern in rules:
    for file in (root / directory).rglob("*.swift"):
        for number, line in enumerate(file.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if re.search(pattern, code):
                failures.append(f"{file.relative_to(root)}:{number}: layer violation: {code.strip()}")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Architecture boundaries passed: passive Views, isolated Presentation, UI-free Core.")
