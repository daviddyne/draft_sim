#!/usr/bin/env python3
"""Builds the data files the web app reads from its own origin.

The browser can't call 17lands or Scryfall directly (no CORS headers), so this
runs in CI instead: it fetches both, merges them, and writes files in the same
shape the app's cache uses.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

OUT = 'web/data'
UA = {'User-Agent': 'DraftSim/1.0', 'Accept': 'application/json'}
EVENTS = ['PremierDraft', 'QuickDraft', 'TradDraft']
PAIRS = ['WU', 'WB', 'WR', 'WG', 'UB', 'UR', 'UG', 'BR', 'BG', 'RG']
# Bonus sheets that show up in a set's draft packs
SHEETS = {
    'OTJ': ['big', 'otp'],
    'MKM': ['clu'],
    'WOE': ['wot'],
    'LCI': ['rex'],
    'MOM': ['mul'],
    'BRO': ['brr'],
    'DMU': ['dmr'],
}


def get(url, tries=3):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if attempt == tries - 1:
                print(f'  failed {url}: {e}')
                return None
            time.sleep(3)


def scryfall_search(query):
    """All cards matching a Scryfall query, following pagination."""
    cards = []
    url = 'https://api.scryfall.com/cards/search?q=' + urllib.parse.quote(query) + '&unique=cards'
    while url:
        page = get(url)
        if not page:
            break
        cards.extend(page.get('data', []))
        url = page.get('next_page') if page.get('has_more') else None
        time.sleep(0.1)
    return cards


def card_info(set_code):
    """name -> extra fields, main set last so it wins name collisions."""
    info = {}
    queries = ['set:spg game:arena']
    queries += [f'set:{s} game:arena' for s in SHEETS.get(set_code.upper(), [])]
    queries += [f'set:{set_code}', f'set:{set_code} game:arena']
    for q in queries:
        for c in scryfall_search(q):
            faces = c.get('card_faces') or []
            oracle = c.get('oracle_text') or '\n'.join(f.get('oracle_text', '') for f in faces)
            uris = c.get('image_uris') or (faces[0].get('image_uris') if faces else {}) or {}
            image = uris.get('normal', '')
            # A smaller variant for grids and stacks, much less to download
            small = uris.get('small', '')
            entry = {
                'cmc': int(c.get('cmc') or 0),
                'type': c.get('type_line', ''),
                'oracle': oracle,
                'image': image,
                'small': small,
                'arenaId': c.get('arena_id'),
            }
            full = c['name']
            for key in {full, full.split(' // ')[0]}:
                info[key.lower()] = entry
    return info


def basics(set_code):
    """Basic lands fill the pack land slot but have no ratings."""
    out = []
    url = ('https://api.scryfall.com/cards/search?q='
           + urllib.parse.quote(f'set:{set_code} type:basic game:arena') + '&unique=prints')
    while url:
        page = get(url)
        if not page:
            break
        for c in page.get('data', []):
            if c.get('arena_id') is None:
                continue
            out.append({
                'name': c['name'], 'color': '', 'rarity': 'basic',
                'image': (c.get('image_uris') or {}).get('normal', ''),
                'gihwr': None, 'iwd': None, 'alsa': None,
                'cmc': 0, 'type': 'Basic Land', 'oracle': '',
                'arenaId': c['arena_id'],
            })
        url = page.get('next_page') if page.get('has_more') else None
    return out


def merge(cards, info):
    out = []
    for c in cards:
        extra = info.get((c.get('name') or '').lower(), {})
        image = extra.get('image') or c.get('url') or ''
        if not image:
            continue
        small = extra.get('small') or image
        out.append({
            'name': c.get('name', ''),
            'color': c.get('color', ''),
            'rarity': c.get('rarity', ''),
            'image': image,
            'small': small,
            'gihwr': c.get('ever_drawn_win_rate'),
            'iwd': c.get('drawn_improvement_win_rate'),
            'alsa': c.get('avg_seen'),
            'cmc': extra.get('cmc', 0),
            'type': extra.get('type', ''),
            'oracle': extra.get('oracle', ''),
            'arenaId': extra.get('arenaId'),
        })
    return out


def is_merged(path):
    """True if the file is already in the app's merged format."""
    try:
        with open(path) as f:
            data = json.load(f)
        return isinstance(data, list) and (not data or 'image' in data[0])
    except Exception:
        return False


def main():
    active = os.environ.get('ACTIVE', '').split()
    refresh_all = os.environ.get('REFRESH_ALL', 'false') == 'true'
    os.makedirs(OUT, exist_ok=True)

    codes = get('https://www.17lands.com/data/expansions') or []
    print(f'{len(codes)} sets on 17lands')

    # Set names and release dates for the dropdown
    names = {}
    url = 'https://api.scryfall.com/sets'
    while url:
        page = get(url)
        if not page:
            break
        for s in page.get('data', []):
            names[s['code'].upper()] = (s.get('name', ''), s.get('released_at', ''))
        url = page.get('next_page') if page.get('has_more') else None

    for code in codes:
        # Rebuild when asked, when the set is active, when missing, or when the
        # file is still in an older format the app can't read
        wanted = [e for e in EVENTS
                  if refresh_all or code in active
                  or not os.path.exists(f'{OUT}/{code}_{e}.json')
                  or not is_merged(f'{OUT}/{code}_{e}.json')]
        if not wanted:
            continue
        info = None
        for event in wanted:
            raw = get(f'https://www.17lands.com/api/card_data?expansion={code}'
                      f'&event_type={event}&time_period=ALL_TIME')
            rows = (raw.get('data') if isinstance(raw, dict) else raw) or []
            if not rows:
                continue
            if info is None:
                info = card_info(code)
            merged = merge(rows, info)
            if not merged:
                continue
            with open(f'{OUT}/{code}_{event}.json', 'w') as f:
                json.dump(merged, f)
            print(f'  {code} {event}: {len(merged)} cards')
            time.sleep(1)
        # Per pair ratings, only for sets being drafted now, they multiply the data
        if code in active:
            for pair in PAIRS:
                path = f'{OUT}/{code}_PremierDraft_{pair}.json'
                if os.path.exists(path) and not refresh_all and code not in active:
                    continue
                raw = get(f'https://www.17lands.com/api/card_data?expansion={code}'
                          f'&event_type=PremierDraft&time_period=ALL_TIME&colors={pair}')
                rows = (raw.get('data') if isinstance(raw, dict) else raw) or []
                if not rows:
                    continue
                slim = [{'name': r.get('name', ''), 'gihwr': r.get('ever_drawn_win_rate')}
                        for r in rows if r.get('name')]
                with open(path, 'w') as f:
                    json.dump(slim, f)
                print(f'  {code} {pair}: {len(slim)} cards')
                time.sleep(1)

        if info is not None:
            lands = basics(code)
            if lands:
                with open(f'{OUT}/{code}_lands.json', 'w') as f:
                    json.dump(lands, f)

    # Only list sets that ended up with data, so the dropdown can't offer a
    # set the app would fail to open. Newest first, unknown dates last.
    sets = []
    for code in codes:
        events = [e for e in EVENTS if is_merged(f'{OUT}/{code}_{e}.json')]
        if not events:
            continue
        name, released = names.get(code.upper(), ('', ''))
        sets.append({'code': code, 'name': name or code, 'released': released, 'events': events})
    sets.sort(key=lambda s: s['released'], reverse=True)
    with open(f'{OUT}/sets.json', 'w') as f:
        json.dump(sets, f)
    print(f'{len(sets)} sets available to the app')


if __name__ == '__main__':
    sys.exit(main())