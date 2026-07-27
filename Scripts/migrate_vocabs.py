#!/usr/bin/env python3
"""
Convert legacy `{term: definition}` word maps in vocabs.json into ordered
`[{term, definition}]` arrays.

Why
---
A JSON *object* has no defined key order. Python happens to preserve insertion
order, but Swift's JSONDecoder gives no such guarantee, so an app that decodes
`{"abandon": "...", "keen": "..."}` into a Swift dictionary can present those
words in any order it likes. Since the app is required to walk a new section's
words *in book order*, the order has to live in the data, and the only JSON
construct that guarantees order is an array.

Section order and book order are handled separately, by catalog.json.

The app still reads the legacy object form (falling back to alphabetical order),
so running this is a correctness upgrade, not a hard requirement. Run it any
time you paste a new day in the old `{term: definition}` style:

    python Scripts/migrate_vocabs.py
    python Scripts/migrate_vocabs.py --check     # report only, change nothing
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCABS_PATH = REPO_ROOT / "Resources" / "VocabData" / "vocabs.json"


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalise vocabs.json word lists to ordered arrays.")
    parser.add_argument("--check", action="store_true", help="report what would change, write nothing")
    args = parser.parse_args()

    if not VOCABS_PATH.exists():
        print(f"ERROR: {VOCABS_PATH} not found.")
        return 1

    with VOCABS_PATH.open(encoding="utf-8") as handle:
        data = json.load(handle)

    converted_categories = 0
    converted_words = 0

    for book_id, sections in data.items():
        for section_id, categories in sections.items():
            for category, words in list(categories.items()):
                if isinstance(words, list):
                    continue  # already ordered
                if not isinstance(words, dict):
                    print(f"ERROR: {book_id}/{section_id}/{category} is neither an object nor an array.")
                    return 1

                ordered = [
                    {"term": term.strip(), "definition": str(definition).strip()}
                    for term, definition in words.items()
                ]
                categories[category] = ordered
                converted_categories += 1
                converted_words += len(ordered)
                print(f"  {book_id}/{section_id}/{category}: {len(ordered)} words -> array")

    if converted_categories == 0:
        print("Nothing to do - every word list is already an ordered array.")
        return 0

    if args.check:
        print(f"\n--check: {converted_categories} category list(s), {converted_words} word(s) would be converted.")
        return 0

    with VOCABS_PATH.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"\nConverted {converted_categories} category list(s), {converted_words} word(s).")
    print("Run: python Scripts/validate_content.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
