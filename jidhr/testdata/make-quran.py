#!/usr/bin/env python3
"""Write testdata/quran.json from the corpus the phase 3 ETL builds.

corpus.db is a build artifact and is not in the repository, so the corpus jidhr
resolves against is committed as JSON instead. Forms and roots go in spelled
exactly as the corpus spells them: the store normalises both when it indexes
them, so this file makes no orthographic decisions of its own.

    python3 jidhr/testdata/make-quran.py app/assets/corpus.db
"""

import collections
import json
import pathlib
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1] if len(sys.argv) > 1 else "app/assets/corpus.db")

roots = [
    {"letters": l, "display": d, "translit": t, "quran": {"occurrences": n}}
    for l, d, t, n in db.execute(
        "SELECT letters, display, translit, quran_occurrences FROM roots ORDER BY letters"
    )
]

attested = collections.defaultdict(list)
for form, root in db.execute(
    "SELECT DISTINCT text_ar, root_letters FROM words "
    "WHERE root_letters IS NOT NULL AND root_letters <> '' ORDER BY text_ar, root_letters"
):
    attested[form].append(root)

out = pathlib.Path(__file__).with_name("quran.json")
with out.open("w", encoding="utf-8") as f:
    json.dump(
        {
            "note": __doc__.splitlines()[0],
            "roots": roots,
            "attested": attested,
        },
        f,
        ensure_ascii=False,
        indent=0,
    )
    f.write("\n")
print(f"{out}: {len(roots)} roots, {len(attested)} attested forms")
