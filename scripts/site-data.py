#!/usr/bin/env python3
"""Write the Qur'an text and root data the public site's two live demos read.

The design mockups carried hand-typed text and invented scholarship. The site
ships neither: every word, gloss, root, sense, count and aya here comes from
the corpus the app bundles and the sense drafts the API serves.

    python3 scripts/site-data.py [--db app/assets/corpus.db]

Writes server/internal/site/static/site-data.js. Commit the result.
"""
import argparse
import csv
import json
import re
import sqlite3
from collections import Counter

# Same range as app/lib/data/root_repo.dart `_pauseMarks`: recitation marks
# only. U+06DF-U+06E8 are spelling and stay.
PAUSE = re.compile('[ۖ-۞۩-ۭ]')
# The Prayer demo's passages, as the mockup chose them.
PRAYER = {1: None, 2: (1, 5), 103: None, 108: None, 112: None}
ENGLISH, FRENCH = 19, 779
OTHER_AYAS = 3


# A lemma's gloss is borrowed from its commonest occurrence, which can carry
# the conjunction joined to that word ("and mercy").
# ponytail: English prefixes only; a lemma gloss column in the corpus ends this.
JOINED = re.compile(r'^(and|so|then|but|or) ', re.I)


def bare(text):
    return ' '.join(PAUSE.sub('', text).split())


def words_of(db, surah, span=None):
    q = ('SELECT a.number, w.text_ar, w.translit, w.gloss_en, w.gloss_fr, w.root_letters '
         'FROM words w JOIN ayahs a ON a.id = w.ayah_id WHERE a.surah_id = ?')
    args = [surah]
    if span:
        q += ' AND a.number BETWEEN ? AND ?'
        args += list(span)
    return db.execute(q + ' ORDER BY w.id', args).fetchall()


def senses(path):
    rows = {}
    with open(path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            rows[row['root']] = row  # the last row for a root wins, as senseseed reads it
    split = lambda s: [x.strip() for x in (s or '').split(';') if x.strip()]
    return {r: (split(v['sense_en']), split(v['sense_fr'])) for r, v in rows.items()}


def translation(db, ayah_id, resource):
    row = db.execute('SELECT text FROM ayah_translations WHERE ayah_id = ? AND resource_id = ?',
                     (ayah_id, resource)).fetchone()
    return row[0].strip() if row else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--db', default='app/assets/corpus.db')
    p.add_argument('--senses', default='data/root_senses_draft.tsv')
    p.add_argument('--out', default='server/internal/site/static/site-data.js')
    a = p.parse_args()
    db = sqlite3.connect(f'file:{a.db}?mode=ro', uri=True)
    sense = senses(a.senses)

    fatiha = words_of(db, 1)
    lemmas = [bare(l) if l else None for (l,) in db.execute(
        'SELECT w.lemma FROM words w JOIN ayahs a ON a.id = w.ayah_id WHERE a.surah_id = 1 ORDER BY w.id')]
    reader_words = [{'ar': bare(ar), 'tr': tr, 'gl': en, 'glFr': fr or en, 'a': n, 'r': r, 'lemma': lemma}
                    for (n, ar, tr, en, fr, r), lemma in zip(fatiha, lemmas)]

    roots = {}
    for r in sorted({w['r'] for w in reader_words if w['r']}):
        display, tl, n = db.execute(
            'SELECT display, translit, quran_occurrences FROM roots WHERE letters = ?', (r,)).fetchone()
        forms = []
        for key, lemma, count in db.execute(
                'SELECT lemma_key, lemma, COUNT(*) n FROM words WHERE root_letters = ? '
                'AND lemma_key IS NOT NULL GROUP BY lemma_key ORDER BY n DESC, lemma_key', (r,)):
            glosses = Counter(g for (g,) in db.execute(
                'SELECT gloss_en FROM words WHERE root_letters = ? AND lemma_key = ? AND gloss_en IS NOT NULL',
                (r, key)))
            gloss = Counter(JOINED.sub('', g) for g in glosses.elements()).most_common(1)
            forms.append({'ar': bare(lemma), 'gl': gloss[0][0] if gloss else '', 'n': count})
        occ = []
        for ayah_id, number, surah, text in db.execute(
                'SELECT DISTINCT a.id, a.number, a.surah_id, a.text_uthmani FROM words w '
                'JOIN ayahs a ON a.id = w.ayah_id WHERE w.root_letters = ? AND a.surah_id != 1 '
                'ORDER BY a.id LIMIT ?', (r, OTHER_AYAS)):
            occ.append({'ref': f'{surah}:{number}', 'ar': bare(text),
                        'en': translation(db, ayah_id, ENGLISH), 'fr': translation(db, ayah_id, FRENCH)})
        en, fr = sense.get(r, ([], []))
        roots[r] = {'letters': display, 'tl': tl, 'n': n, 'senses': en, 'sensesFr': fr,
                    'forms': forms, 'occ': occ}

    ayas = {n: {'en': translation(db, 1000 + n, ENGLISH), 'fr': translation(db, 1000 + n, FRENCH)}
            for n in range(1, 8)}

    prayer = {}
    for surah, span in PRAYER.items():
        rows = []
        for n, ar, _tr, en, _fr, _r in words_of(db, surah, span):
            while len(rows) < n - (span[0] - 1 if span else 0):
                rows.append([])
            rows[-1].append([bare(ar), en])
        prayer[surah] = rows

    data = {'reader': {'words': reader_words, 'roots': roots, 'ayas': ayas}, 'prayer': prayer}
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write('// Generated by scripts/site-data.py from the corpus and the sense drafts. Do not edit.\n')
        f.write('window.WIRD_SITE = ' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n')
    print(f'{a.out}: {len(reader_words)} words, {len(roots)} roots, '
          f'{sum(len(r) for r in prayer.values())} prayer ayas')


if __name__ == '__main__':
    main()
