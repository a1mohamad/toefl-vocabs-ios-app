#!/usr/bin/env python3
"""
Validate the bundled vocab content before it ever reaches a macOS runner.

Why this exists
---------------
There is no local Xcode and no local Simulator on this project, so the normal
"just run it and see" loop costs a full CI round trip. The single most likely
way to break the app is a hand-edit to vocabs.json — a stray comma, a duplicated
term, an empty definition, or a new day that catalog.json doesn't know about.
This script catches all of that in about a second, on Windows, before you push.

Usage
-----
    python Scripts/validate_content.py
    python Scripts/validate_content.py --strict     # warnings become failures (CI)

Exit codes
----------
    0  clean (or only notices)
    1  at least one error, or a warning while --strict is on
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VOCABS_PATH = REPO_ROOT / "Resources" / "VocabData" / "vocabs.json"
CATALOG_PATH = REPO_ROOT / "Resources" / "VocabData" / "catalog.json"

# Category keys as they appear in vocabs.json. The app maps "extras" -> .extra.
KNOWN_CATEGORIES = ("main", "extras")

errors: list[str] = []
warnings: list[str] = []
notices: list[str] = []


def error(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def notice(msg: str) -> None:
    notices.append(msg)


def load_json(path: Path) -> dict | None:
    if not path.exists():
        error(f"{path.relative_to(REPO_ROOT)} does not exist.")
        return None
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        error(f"{path.relative_to(REPO_ROOT)} is not valid JSON: line {exc.lineno}, column {exc.colno}: {exc.msg}")
        return None


def normalise_word_list(words: object, where: str) -> list[tuple[str, object]] | None:
    """
    Accept both word-list shapes and return them as ordered (term, definition) pairs.

      preferred: [{"term": "...", "definition": "..."}, ...]   order is guaranteed
      legacy:    {"term": "definition", ...}                   order is NOT guaranteed

    The app reads both, but only the array form can promise that words are shown
    in book order. Run Scripts/migrate_vocabs.py to convert.
    """
    if isinstance(words, list):
        pairs: list[tuple[str, object]] = []
        for index, entry in enumerate(words):
            if not isinstance(entry, dict):
                error(f"{where}[{index}] must be an object with \"term\" and \"definition\".")
                return None
            term = entry.get("term")
            if not isinstance(term, str):
                error(f'{where}[{index}] is missing a string "term".')
                return None
            unexpected = set(entry) - {"term", "definition"}
            if unexpected:
                warn(f'{where}[{index}] ("{term}") has unexpected key(s): {sorted(unexpected)}.')
            pairs.append((term, entry.get("definition")))
        return pairs

    if isinstance(words, dict):
        notice(
            f"{where} uses the legacy object form, so word order is not guaranteed "
            f"(the app will fall back to alphabetical). Run: python Scripts/migrate_vocabs.py"
        )
        return list(words.items())

    error(f"{where} must be an array of word objects (or a legacy term -> definition object).")
    return None


def validate_vocabs(vocabs: dict) -> dict[str, dict[str, dict[str, int]]]:
    """Check shape and content quality. Returns {book: {section: {category: count}}}."""
    shape: dict[str, dict[str, dict[str, int]]] = {}

    if not isinstance(vocabs, dict) or not vocabs:
        error("vocabs.json must be a non-empty object keyed by book id (e.g. \"504\").")
        return shape

    for book_id, sections in vocabs.items():
        if not isinstance(sections, dict):
            error(f'vocabs.json: book "{book_id}" must map section ids to section objects.')
            continue

        shape[book_id] = {}

        for section_id, categories in sections.items():
            if not isinstance(categories, dict):
                error(f'vocabs.json: {book_id}/{section_id} must be an object of categories.')
                continue

            shape[book_id][section_id] = {}

            for category, words in categories.items():
                if category not in KNOWN_CATEGORIES:
                    error(
                        f'vocabs.json: {book_id}/{section_id} has unknown category "{category}". '
                        f"Expected one of {KNOWN_CATEGORIES}."
                    )
                    continue
                where = f"{book_id}/{section_id}/{category}"
                entries = normalise_word_list(words, where)
                if entries is None:
                    continue
                if not entries:
                    warn(f"vocabs.json: {where} is empty.")

                shape[book_id][section_id][category] = len(entries)
                seen_lower: dict[str, str] = {}

                for term, definition in entries:

                    if not isinstance(definition, str):
                        error(f'{where}: "{term}" has a non-string definition.')
                        continue
                    if not term.strip():
                        error(f"{where}: found an empty term.")
                        continue
                    if not definition.strip():
                        error(f'{where}: "{term}" has an empty definition.')
                        continue

                    # Word identity is book/section/category/term. A duplicate term
                    # inside one category would collide into a single progress record.
                    key = term.strip().lower()
                    if key in seen_lower:
                        error(f'{where}: duplicate term "{term}" — progress for these two entries would collide.')
                    seen_lower[key] = term

                    if term != term.strip():
                        warn(f'{where}: term "{term}" has leading/trailing whitespace.')
                    if "  " in term:
                        warn(f'{where}: term "{term}" contains a double space.')
                    if definition != definition.strip():
                        warn(f'{where}: definition for "{term}" has leading/trailing whitespace.')
                    if len(definition.strip()) < 2:
                        warn(f'{where}: definition for "{term}" is suspiciously short ("{definition}").')
                    if definition.strip().lower() == term.strip().lower():
                        warn(f'{where}: definition for "{term}" is identical to the term.')
                    if "/" in term:
                        error(
                            f'{where}: term "{term}" contains "/", which is the separator used in '
                            f"internal word ids. Rename it."
                        )

    return shape


def validate_catalog(catalog: dict, shape: dict[str, dict[str, dict[str, int]]]) -> None:
    if not isinstance(catalog, dict):
        error("catalog.json must be an object.")
        return

    books = catalog.get("books")
    if not isinstance(books, list) or not books:
        error('catalog.json must contain a non-empty "books" array.')
        return

    catalogued: dict[str, set[str]] = {}
    seen_book_ids: set[str] = set()

    for index, book in enumerate(books):
        if not isinstance(book, dict):
            error(f"catalog.json: books[{index}] must be an object.")
            continue

        book_id = book.get("id")
        if not isinstance(book_id, str) or not book_id:
            error(f'catalog.json: books[{index}] is missing a string "id".')
            continue
        if book_id in seen_book_ids:
            error(f'catalog.json: duplicate book id "{book_id}".')
        seen_book_ids.add(book_id)

        for field in ("title", "intro"):
            if not isinstance(book.get(field), str) or not book.get(field, "").strip():
                error(f'catalog.json: book "{book_id}" is missing a non-empty "{field}".')

        if book_id not in shape:
            error(
                f'catalog.json: book "{book_id}" is not present in vocabs.json '
                f"(available: {sorted(shape.keys())})."
            )
            continue

        catalogued[book_id] = set()
        sections = book.get("sections")
        if not isinstance(sections, list) or not sections:
            error(f'catalog.json: book "{book_id}" needs a non-empty "sections" array.')
            continue

        for s_index, section in enumerate(sections):
            if not isinstance(section, dict):
                error(f"catalog.json: {book_id}.sections[{s_index}] must be an object.")
                continue

            section_id = section.get("id")
            if not isinstance(section_id, str) or not section_id:
                error(f'catalog.json: {book_id}.sections[{s_index}] is missing a string "id".')
                continue
            if section_id in catalogued[book_id]:
                error(f'catalog.json: duplicate section id "{section_id}" in book "{book_id}".')
            catalogued[book_id].add(section_id)

            if section_id not in shape[book_id]:
                error(
                    f'catalog.json: section "{book_id}/{section_id}" does not exist in vocabs.json. '
                    f"Either add the words or remove this entry."
                )
            if not isinstance(section.get("title"), str) or not section.get("title", "").strip():
                error(f'catalog.json: section "{book_id}/{section_id}" is missing a non-empty "title".')
            kind = section.get("kind", "lesson")
            if kind not in ("lesson", "review"):
                warn(f'catalog.json: section "{book_id}/{section_id}" has kind "{kind}"; expected "lesson" or "review".')

    # The app degrades gracefully here (auto-title + default intro + appended at
    # the end), so this is informational, never fatal — not even under --strict.
    for book_id, sections in shape.items():
        if book_id not in catalogued:
            notice(
                f'book "{book_id}" exists in vocabs.json but not in catalog.json — '
                f"it will render with an auto-generated title and be listed last."
            )
            continue
        for section_id in sections:
            if section_id not in catalogued[book_id]:
                pretty = re.sub(r"_(\d+)$", r" \1", section_id).replace("_", " ").title()
                notice(
                    f'section "{book_id}/{section_id}" is not in catalog.json — it will appear last, '
                    f'titled "{pretty}". Add it to catalog.json to control order and intro text.'
                )


def print_summary(shape: dict[str, dict[str, dict[str, int]]]) -> None:
    print("Content summary")
    print("-" * 58)
    grand_main = grand_extra = 0
    for book_id, sections in shape.items():
        book_main = sum(c.get("main", 0) for c in sections.values())
        book_extra = sum(c.get("extras", 0) for c in sections.values())
        grand_main += book_main
        grand_extra += book_extra
        print(f"  {book_id:<6} {len(sections):>2} sections   main {book_main:>4}   extra {book_extra:>4}")
        for section_id, categories in sections.items():
            main = categories.get("main", 0)
            extra = categories.get("extras", 0)
            flag = "" if extra else "   (no extras)"
            print(f"      {section_id:<12} main {main:>3}   extra {extra:>3}{flag}")
    print("-" * 58)
    print(f"  TOTAL              main {grand_main:>4}   extra {grand_extra:>4}   all {grand_main + grand_extra}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate bundled vocab content.")
    parser.add_argument("--strict", action="store_true", help="treat warnings as failures")
    parser.add_argument("--quiet", action="store_true", help="skip the content summary table")
    args = parser.parse_args()

    vocabs = load_json(VOCABS_PATH)
    catalog = load_json(CATALOG_PATH)

    shape: dict[str, dict[str, dict[str, int]]] = {}
    if vocabs is not None:
        shape = validate_vocabs(vocabs)
    if catalog is not None and shape:
        validate_catalog(catalog, shape)

    if shape and not args.quiet:
        print_summary(shape)

    for message in notices:
        print(f"NOTICE   {message}")
    for message in warnings:
        print(f"WARNING  {message}")
    for message in errors:
        print(f"ERROR    {message}")

    if errors:
        print(f"\nFAILED - {len(errors)} error(s), {len(warnings)} warning(s).")
        return 1
    if warnings and args.strict:
        print(f"\nFAILED - {len(warnings)} warning(s) with --strict enabled.")
        return 1

    print(f"\nOK - {len(warnings)} warning(s), {len(notices)} notice(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
