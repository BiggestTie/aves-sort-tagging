#!/usr/bin/env python3
"""Builds the bundled tag catalog files (assets/tag_catalog_*.txt).

Each file lists nested tag paths, one per line, e.g.
`Blue Archive|Millennium|C&C|Asuna`.

Sources (shallow git clones):
- Blue Archive: SchaleDB/SchaleDB, data/en/students.json + localization.json
- Azur Lane: AzurAPI/azurapi-js-setup, ships.json
- Genshin: theBowja/genshin-db, src/data/English/characters/*.json

Extra entries, for characters missing from those sources, are kept by hand
in tools/tag_catalog/extra_<franchise>.txt and merged in.

Usage: build.py <schale dir> <azurapi dir> <genshin-db dir>
"""
import glob
import json
import os
import re
import sys

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


AZUR_LANE_COLLABS = {
    'Neptunia', 'SSSS', 'The Idolmaster', 'Venus Vacation', 'Hololive',
    'Utawarerumono', 'Atelier Ryza', 'Kizuna AI',
}


def azur_lane(azurapi_dir):
    ships = json.load(open(os.path.join(azurapi_dir, 'ships.json')))
    base_names = {s['names']['en'] for s in ships if s.get('nationality') != 'META'}
    paths = set()
    for s in ships:
        name = s['names']['en'].strip()
        nation = s.get('nationality') or 'Other'
        if nation == 'META':
            # META ships are alternate versions of existing ships
            base = re.sub(r'[\s.]*META$', '', name)
            if base in base_names:
                continue
        if nation in AZUR_LANE_COLLABS:
            paths.add(path('Azur Lane', 'Collab', nation, name))
        elif nation in ('Universal', 'Bilibili'):
            paths.add(path('Azur Lane', 'Other', name))
        else:
            paths.add(path('Azur Lane', nation, name))
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
    extra = extras(key)
    extra_leaves = {(p.split('|')[0], p.split('|')[-1]) for p in extra}
    paths = {p for p in paths if (p.split('|')[0], p.split('|')[-1]) not in extra_leaves} | extra
    out = os.path.join(ASSETS, f'tag_catalog_{key}.txt')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sorted(paths, key=lambda v: [s.lower() for s in v.split('|')])) + '\n')
    print(f'{out}: {len(paths)} entries')


if __name__ == '__main__':
    schale_dir, azurapi_dir, gdb_dir = sys.argv[1:4]
    write('blue_archive', blue_archive(schale_dir))
    write('azur_lane', azur_lane(azurapi_dir))
    write('genshin', genshin(gdb_dir))
