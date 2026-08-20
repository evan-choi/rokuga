#!/usr/bin/env python3
"""Localization gates (tasks 9a.1/9a.2).

Gate 1 — no user-facing string literal outside the catalog: every localizable
literal in App/Sources must have a matching key in Localizable.xcstrings.
Gate 2 — completeness: every catalog key must carry translated units for all
required languages (ko, ja, zh-Hans).
"""

import json
import os
import re
import sys

CATALOG = "App/Resources/Localizable.xcstrings"
SOURCE_ROOT = "App/Sources"
REQUIRED_LANGUAGES = ["ko", "ja", "zh-Hans"]

LITERAL_PATTERNS = [
    r'Text\("((?:[^"\\]|\\.)+)"\)',
    r'String\(localized:\s*"((?:[^"\\]|\\.)+)"\)',
    r'L10n\.string\("((?:[^"\\]|\\.)+)"\)',
    r'Label\("((?:[^"\\]|\\.)+)",',
    r'Button\("((?:[^"\\]|\\.)+)"[,)]',
    r'Toggle\("((?:[^"\\]|\\.)+)",',
    r'Picker\("((?:[^"\\]|\\.)+)",',
    r'LabeledContent\("((?:[^"\\]|\\.)+)"\)',
    r'Recorder\("((?:[^"\\]|\\.)+)",',
    r'section\("((?:[^"\\]|\\.)+)"\)',
    r'\.alert\(\s*"((?:[^"\\]|\\.)+)"',
    r'accessibilityLabel\(Text\("((?:[^"\\]|\\.)+)"\)\)',
    r'accessibilityHint\(Text\("((?:[^"\\]|\\.)+)"\)\)',
    r'Text\((?:[^()"\n]*)\?\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)+)"\)',
    r'Button\((?:[^()"\n]*)\?\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)+)",',
]


def extract_source_keys():
    keys = set()
    for root, _, files in os.walk(SOURCE_ROOT):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            src = open(path).read()
            filtered = "\n".join(
                line for line in src.split("\n") if "verbatim" not in line
            )
            for pattern in LITERAL_PATTERNS:
                for match in re.finditer(pattern, filtered):
                    for group in match.groups():
                        if group and not is_interpolation_only(group):
                            keys.add((group.replace("\\n", "\n"), path))
    return keys


def is_interpolation_only(literal):
    return re.fullmatch(r"(\\\([^)]*\)|\s)*", literal) is not None


def main():
    catalog = json.load(open(CATALOG))
    catalog_keys = set(catalog["strings"].keys())

    failures = []

    for key, path in sorted(extract_source_keys()):
        if key not in catalog_keys:
            failures.append(f"[missing-key] {path}: \"{key}\" not in {CATALOG}")

    for key, entry in sorted(catalog["strings"].items()):
        localizations = entry.get("localizations", {})
        for lang in REQUIRED_LANGUAGES:
            unit = localizations.get(lang, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                failures.append(f"[untranslated] \"{key}\" missing {lang}")

    if failures:
        print("\n".join(failures))
        print(f"\nFAILED: {len(failures)} localization issue(s)")
        return 1

    print(
        f"OK: {len(catalog_keys)} keys, "
        f"{len(REQUIRED_LANGUAGES)} languages fully translated"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
