#!/usr/bin/env python3
"""Builds the bundled tag catalog files (assets/tag_catalog_*.txt).

Each file lists nested tag paths, one per line, e.g.
`Blue Archive|Millennium|C&C|Asuna`.

Sources (shallow git clones):
- Blue Archive: SchaleDB/SchaleDB, data/en/students.json + localization.json
- Azur Lane: AzurLaneTools/AzurLaneData, EN/sharecfgdata/ship_data_statistics.json,
  and AzurAPI/azurapi-js-setup, ships.json for older entries
- Genshin: theBowja/genshin-db, src/data/English/characters/*.json

Extra entries, for characters missing from those sources, are kept by hand
in tools/tag_catalog/extra_<franchise>.txt and merged in.

Usage: build.py <schale dir> <azurapi dir> <AzurLaneData dir> <genshin-db dir>
"""
import glob
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', '..', 'assets')


def base_name(name):
    # `Asuna (Bunny Girl)` -> `Asuna`: alternate versions are not listed
    return re.sub(r'\s*\(.*\)\s*$', '', name).strip()


def clean(segment):
    # `|` separates nested tags, so it cannot appear in names
    return segment.replace('|', '/').strip()


def path(*segments):
    return '|'.join(clean(s) for s in segments if s and clean(s))


def blue_archive(schale_dir):
    students = json.load(open(os.path.join(schale_dir, 'data/en/students.json')))
    loc = json.load(open(os.path.join(schale_dir, 'data/en/localization.json')))
    schools = loc['School']
    clubs = dict(loc['Club'])
    # common short names
    clubs['CleanNClearing'] = 'C&C'
    clubs['EmptyClub'] = None
    schools['ETC'] = 'Other'
    paths = {}
    for s in sorted(students, key=lambda v: v['Id']):
        name = base_name(s['Name'])
        if name in paths:
            continue
        paths[name] = path('Blue Archive', schools.get(s['School'], s['School']), clubs.get(s['Club'], s['Club']), name)
    return set(paths.values())


AZUR_LANE_NATIONS = {
    1: 'Eagle Union', 2: 'Royal Navy', 3: 'Sakura Empire', 4: 'Iron Blood',
    5: 'Dragon Empery', 6: 'Sardegna Empire', 7: 'Northern Parliament',
    8: 'Iris Libre', 9: 'Vichya Dominion', 11: 'Kingdom of Tulipa', 96: 'Tempesta',
}
AZUR_LANE_COLLABS = {
    101: 'Neptunia', 103: 'Utawarerumono', 104: 'Kizuna AI', 105: 'Hololive',
    106: 'Venus Vacation', 107: 'The Idolmaster', 108: 'SSSS', 109: 'Atelier Ryza',
    110: 'Senran Kagura', 111: 'To LOVE-Ru', 112: 'Black Rock Shooter',
    113: 'Atelier Yumia', 114: 'DanMachi', 115: 'Date A Live',
}
# META (alternate versions), Universal (Bulins, event units) and Sirens are left out


def azur_lane_base_name(name):
    # `Köln (Retrofit)`, `Roon μ` -> base ship: alternate versions are not listed
    name = re.sub(r'\s*\(?Retrofit\)?\s*$', '', name.strip())
    name = re.sub(r'\s*μ\s*$', '', name)
    return name.strip()


def azur_lane(azurapi_dir, ald_dir):
    paths = set()

    def add(nation_name, collab, name):
        name = name.strip()
        # skip untranslated names
        if not re.search('[A-Za-z]', name):
            return
        if collab:
            paths.add(path('Azur Lane', 'Collab', nation_name, name))
        else:
            paths.add(path('Azur Lane', nation_name, name))

    # game data (AzurLaneTools/AzurLaneData, EN client)
    # each ship has several entries (limit breaks, retrofits, event versions),
    # some with another nationality, so the most common one is kept
    stats = json.load(open(os.path.join(ald_dir, 'EN/sharecfgdata/ship_data_statistics.json')))
    codes_by_name = {}
    for v in stats.values():
        if not isinstance(v, dict):
            continue
        name = azur_lane_base_name(v['name'])
        codes_by_name.setdefault(name, Counter())[v.get('nationality')] += 1
    known = set()
    for name, codes in codes_by_name.items():
        code = codes.most_common(1)[0][0]
        if code in AZUR_LANE_NATIONS:
            add(AZUR_LANE_NATIONS[code], False, name)
            known.add(name)
        elif code in AZUR_LANE_COLLABS:
            add(AZUR_LANE_COLLABS[code], True, name)
            known.add(name)

    # older community data (AzurAPI), for ships missing from the game data
    collab_names = set(AZUR_LANE_COLLABS.values())
    for s in json.load(open(os.path.join(azurapi_dir, 'ships.json'))):
        name = azur_lane_base_name(s['names']['en'])
        nation = s.get('nationality')
        if name in known or nation in (None, 'META', 'Universal', 'Bilibili'):
            continue
        add(nation, nation in collab_names, name)
    return paths


# affiliations shared by enough characters to be a useful level
# (only used when the character is from the group's region)
GENSHIN_GROUPS = {
    'Knights of Favonius': 'Mondstadt',
    'Church of Favonius': 'Mondstadt',
    "Adventurers' Guild": 'Mondstadt',
    'Liyue Qixing': 'Liyue',
    'Yashiro Commission': 'Inazuma',
    'Court of Fontaine': 'Fontaine',
    "Hotel Bouffes d'ete": 'Fontaine',
    'Fatui': 'Snezhnaya',
}


def genshin(gdb_dir):
    paths = set()
    for f in glob.glob(os.path.join(gdb_dir, 'src/data/English/characters/*.json')):
        c = json.load(open(f))
        name = c['name'].strip()
        region = (c.get('region') or '').strip() or 'Other'
        affiliation = (c.get('affiliation') or '').strip()
        group = affiliation if GENSHIN_GROUPS.get(affiliation) == region else None
        paths.add(path('Genshin', region, group, name))
    return paths


def extras(key):
    f = os.path.join(HERE, f'extra_{key}.txt')
    if not os.path.exists(f):
        return set()
    lines = [l.strip() for l in open(f, encoding='utf-8')]
    return {l for l in lines if l and not l.startswith('#')}


def write(key, paths):
    # drop entries replaced by a corrected extra entry (same franchise + leaf name)
    # (extra lines may end with nicknames: `path ; nickname ; nickname`)
    extra = extras(key)

    def franchise_and_leaf(line):
        segments = line.split(';')[0].strip().split('|')
        return segments[0], segments[-1]

    extra_leaves = {franchise_and_leaf(p) for p in extra}
    paths = {p for p in paths if franchise_and_leaf(p) not in extra_leaves} | extra
    out = os.path.join(ASSETS, f'tag_catalog_{key}.txt')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sorted(paths, key=lambda v: [s.lower() for s in v.split('|')])) + '\n')
    print(f'{out}: {len(paths)} entries')


if __name__ == '__main__':
    schale_dir, azurapi_dir, ald_dir, gdb_dir = sys.argv[1:5]
    write('blue_archive', blue_archive(schale_dir))
    write('azur_lane', azur_lane(azurapi_dir, ald_dir))
    write('genshin', genshin(gdb_dir))
