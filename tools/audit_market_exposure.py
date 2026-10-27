"""Independently verify archived M5-COMBAT-03 geometry and paired outcomes."""
import argparse
import collections
from functools import cache
import gzip
import hashlib
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def vector(value):
    return value if isinstance(value, list) else [float(n) for n in re.findall(r'[-+]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', value)]


@cache
def geometry(map_id, variant):
    path = ROOT / ('src/app/playtest_maps/market_loop_' + variant.lower() + '.tres' if map_id == 'market_loop' else 'src/features/expedition/repair_lane.tres')
    text = path.read_text(encoding='utf-8')
    solid, shots = [], []
    for field in ['bus_block', 'cash_block', 'food_block', 'residences', 'fences']:
        line = next(s for s in text.splitlines() if s.startswith(field + ' = '))
        for raw in re.findall(r'Rect2\(([^)]+)\)', line):
            x, y, width, height = map(float, raw.split(','))
            solid.append((x, y, x + width, y + height))
            if field in ['cash_block', 'food_block', 'residences']:
                shots.append((x, y - 28, x + width, y + height - 28))
    return solid, shots


def clear(point, boxes):
    return 10 <= point[0] < 1910 and 10 <= point[1] < 1430 and not any(x - 18 <= point[0] < right + 18 and y - 18 <= point[1] < bottom + 18 for x, y, right, bottom in boxes)


def intersects(a, b, box):
    x, y, right, bottom = box
    if any(x <= p[0] <= right and y <= p[1] <= bottom for p in (a, b)):
        return True
    def orientation(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    corners = [(x, y), (right, y), (right, bottom), (x, bottom)]
    for index, c in enumerate(corners):
        d = corners[(index + 1) % 4]
        overlaps = all(max(min(a[j], b[j]), min(c[j], d[j])) <= min(max(a[j], b[j]), max(c[j], d[j])) for j in (0, 1))
        if overlaps and orientation(a, b, c) * orientation(a, b, d) <= 0 and orientation(c, d, a) * orientation(c, d, b) <= 0:
            return True
    return False


@cache
def components(map_id, variant):
    boxes, _ = geometry(map_id, variant)
    tiles = {(x, y) for x in range(120) for y in range(90) if clear((8 + 16 * x, 8 + 16 * y), boxes)}
    labels = {}
    for first in tiles:
        if first in labels:
            continue
        label = len(labels)
        queue = collections.deque([first])
        labels[first] = label
        while queue:
            x, y = queue.popleft()
            for neighbor in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]:
                if neighbor in tiles and neighbor not in labels:
                    labels[neighbor] = label
                    queue.append(neighbor)
    return tiles, labels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, default=ROOT / 'docs/evidence/m5-combat-03')
    args = parser.parse_args()
    out = args.evidence.resolve()
    summary = read(out / 'test-summary.json')
    assert summary['status'] == 'FINAL_MATRIX_COMPLETE' and summary['process_count'] == 35
    counts = collections.Counter()
    causal = []
    for row in summary['runs']:
        stage = out / row['family'] / row['mode']
        report = read(stage / 'run-report.json')
        assert not report['failures'] and report['pid'] == row['pid']
        map_id = 'market_loop' if (stage / 'market-ab.json').exists() or 'market' in row['mode'] else 'repair_lane'
        variant = 'A' if row['mode'].startswith('a-hold') else 'B'
        boxes, shot_boxes = geometry(map_id, variant)
        trace_summary = read(stage / 'enemy-contact-summary.json')
        raw = gzip.decompress((stage / 'enemy-contact.json.gz').read_bytes())
        assert hashlib.sha256(raw).hexdigest() == trace_summary['trace']['raw_sha256']
        audit = json.loads(raw)
        assert not audit['anomalies'] and not audit['truncated']
        for sample in audit['samples']:
            assert clear(vector(sample['enemy_foot']), boxes)
            counts['foot_samples'] += 1
        for life in audit['lives']:
            native = life['initial_path']
            points = [vector(p) for p in re.findall(r'\(([^()]+)\)', native)] if isinstance(native, str) else native
            for point in points:
                assert clear(point, boxes)
                counts['initial_path_points'] += 1
            for a, b in zip(points, points[1:]):
                n = max(1, math.ceil(math.dist(a, b) / 2))
                assert all(clear([a[j] + (b[j] - a[j]) * i / n for j in (0, 1)], boxes) for i in range(n + 1))
                counts['clear_path_segments'] += 1
        times = collections.defaultdict(list)
        for hit in audit['actual_hits']:
            assert hit['distance'] < 28 and hit['applied_damage'] == hit['health_before'] - hit['health_after'] == 4
            assert hit['cooldown_after_attack'] == 1.1 and not hit['paused'] and hit['phase'] != 3 and hit['target_activity'] != 2
            assert not any(intersects(vector(hit['enemy_foot']), vector(hit['target_foot']), box) for box in boxes)
            times[(hit['sortie'], hit['enemy_id'])].append(hit['sim_elapsed'])
            counts['actual_hits'] += 1
        for events in times.values():
            assert all(b - a >= 1.1 - .00001 for a, b in zip(events, events[1:]))
        for event in report['combat_events']:
            if event.get('kind') == 'shot':
                assert event['damage'] == 18 and event['interval'] == .65 and event['shot_range'] == 210
                assert not any(intersects(vector(event['shot_from']), vector(event['hit_to']), box) for box in shot_boxes)
                counts['actual_clear_shots'] += 1
        los = read(stage / 'combat-los-report.json')
        for event in los['observations']:
            if event['stage'] == 'wall_before':
                assert event['distance'] < 210 and intersects(vector(event['shot_from']), vector(event['hit_to']), shot_boxes[0])
                counts['actual_blocked_observations'] += 1
        pressure = read(stage / 'night-pressure-report.json')
        tiles, labels = components(map_id, variant)
        def nearest(point):
            return min(tiles, key=lambda t: ((8 + 16 * t[0] - point[0])**2 + (8 + 16 * t[1] - point[1])**2, t))
        for event in pressure['spawns']:
            if event['reason'] != 'spawned':
                continue
            point = event['point']
            x, y, width, height = vector(event['visible_rect'])
            assert clear(point, boxes) and not (x - 32 <= point[0] < x + width + 32 and y - 32 <= point[1] < y + height + 32)
            party = list(map(vector, event['party_points']))
            assert all(math.dist(point, p) >= 280 - .001 for p in party)
            assert all(math.dist(point, vector(p)) >= 32 - .001 for p in event['enemy_points'])
            target = min(party, key=lambda p: math.dist(point, p))
            assert labels[nearest(point)] == labels[nearest(target)]
            assert event['active_enemies'] <= 24
            counts['safe_reachable_births'] += 1
        if row['mode'] in ['scavenge', 'market']:
            chain = read(stage / 'command-chain.json')
            progression = []
            for event in chain['events']:
                if event['phase'] not in (2, 3):
                    continue
                alive = [a for a in event['actors'] if a['activity'] != 3]
                arrived = sum(a['activity'] != 2 and math.dist(vector(a['point']), vector(event['bus_door'])) <= 88 + .0001 for a in alive)
                assert arrived == event['boarding']['arrived'] and len(alive) == event['boarding']['required']
                pair = [arrived, len(alive)]
                if not progression or progression[-1] != pair:
                    progression.append(pair)
            assert all(pair in progression for pair in [[0, 2], [1, 2], [2, 2]])
            accepts = [e for e in chain['events'] if e['action'] == 'accepted_gather']
            assert len(accepts) == 4 and all(e['paused'] and e['goal'] == e['bus_door'] for e in accepts)
            assert sum(e['cue'] == 'bus_start' for e in report['audio_requests']) == 1
            causal.append({'family': row['family'], 'mode': row['mode'], 'actual_feet_progression': progression, 'inputs': [e['input_label'] for e in accepts]})
    for variant, policy in [('A', 'hold'), ('B', 'hold'), ('B', 'avoid')]:
        group = [r for r in summary['ab_trials'] if r['family'] == 'ab' and r['variant'] == variant and r['policy'] == policy]
        assert sorted(r['seed'] for r in group) == [3103, 4103, 5103, 6103, 7103]
        if variant == 'A' or policy == 'avoid':
            assert sum(r['damage'] for r in group) == 0
        else:
            assert sum(r['damage'] for r in group) > 0
    injured = read(out / 'ab/b-hold-5103/run-report.json')['state']
    reopened = read(out / 'injured-reopen/reopen-market/run-report.json')['state']
    assert injured == reopened and next(m for m in reopened['crew'] if m['id'] == 2)['health'] == 196
    result = {'all_passed': True, 'method': 'Independent polygon-edge intersections, footprint inflation and2-unit path sampling, four-connected grid BFS, actual-foot boarding recount, raw trace SHA and exact v5 snapshot equality. No GDScript legal flag used as evidence.',
              'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'counts': dict(counts), 'command_chains': causal, 'injured_v5_reopen_exact': True}
    (out / 'independent-audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print('PASS independent archived audit', dict(counts))


if __name__ == '__main__':
    main()
