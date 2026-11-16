#!/usr/bin/env python3
"""Isolated process per benchmark cell; standard library only; no app launch."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--stress', action='store_true', help='also measure 8/64 MiB at reduced iterations')
    parser.add_argument('--quick', action='store_true', help='smoke-test all scenarios with 4 KiB only')
    args = parser.parse_args()
    binary, output = args.binary.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(binary), '--self-test', str(output / 'self-test')], check=True)
    environment = {
        'platform': platform.platform(), 'machine': platform.machine(),
        'cpu': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
        'physical_memory_bytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
        'swift': subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip(),
        'commit': subprocess.check_output(['git', '-c', 'core.hooksPath=.git/hooks', 'rev-parse', 'HEAD'], text=True).strip(),
        'dirty': bool(subprocess.check_output(['git', '-c', 'core.hooksPath=.git/hooks', 'status', '--porcelain'], text=True)),
        'build': f'xcrun swiftc -O -swift-version 5 -target {platform.machine()}-apple-macosx14.0 -module-cache-path OUTPUT/module-cache; production NoteStore/NoteSession/WatchedNoteStore sources',
        'epoch_seconds': time.time(), 'pid': os.getpid(),
        'source_sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path('Sources/ScribbitCore/NoteStore.swift'), Path('Sources/ScribbitCore/NoteSession.swift'), Path('Sources/ScribbitCore/WatchedNoteStore.swift'), Path('Scripts/FileWatchingBenchmark.swift'), Path('Scripts/benchmark-file-watching.py'), Path('Scripts/benchmark-file-watching.sh')]},
        'filesystem_note': 'warm uncontrolled OS page cache; no purge or claimed cold disk',
    }
    (output / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
    sizes = [4096] if args.quick else [4096, 65536, 1048576, 2097152]
    if args.stress:
        sizes += [8388608, 67108864]
    results = []
    with (output / 'results.jsonl').open('w') as stream:
        for size_index, size in enumerate(sizes):
            for layer in ['store', 'session']:
                for scenario in ['quiet', 'save', 'external', 'sibling']:
                    iterations = 3 if args.quick else (8 if size > 2097152 else (100 if scenario == 'quiet' else 30))
                    warmups = 1 if args.quick else (2 if size > 2097152 else 5)
                    # Alternate pair order by size to avoid always giving one
                    # mode the first position. Processes do not retain state.
                    modes = ['disk', 'watched'] if size_index % 2 == 0 else ['watched', 'disk']
                    for mode in modes:
                        fixture_root = output / 'fixtures'
                        fixture_root.mkdir(parents=True, exist_ok=True)
                        idle = 1.0 if scenario == 'quiet' and layer == 'session' and not args.quick else 0
                        command = [str(binary), mode, layer, scenario, str(size), str(iterations), str(warmups), str(idle)]
                        with tempfile.TemporaryDirectory(prefix=f'{size}-{layer}-{scenario}-{mode}-', dir=fixture_root) as fixture:
                            result = json.loads(subprocess.check_output(command, cwd=fixture, text=True))
                        # Schema/contract checks, never timing thresholds.
                        assert len(result['samples_us']) == iterations
                        assert len(result['open_samples_us']) == iterations
                        assert result['iterations'] == iterations and result['bytes'] == size
                        if mode == 'disk' or scenario in ('save', 'external'):
                            assert result['measured_reads'] == iterations, result
                        # Asynchronous invalidation can cause conservative quiet
                        # misses too. Record hit rates, never require perfect hits.
                        assert 0 <= result['measured_reads'] <= iterations, result
                        stream.write(json.dumps(result, sort_keys=True) + '\n')
                        stream.flush()
                        results.append(result)
                        print(f"{size:>8} {layer:7} {scenario:8} {mode:7}: median {result['median_us']:.2f} us, p95 {result['p95_us']:.2f} us; reads {result['measured_reads']}/{iterations}", flush=True)
    keyed = {(r['bytes'], r['layer'], r['scenario'], r['mode']): r for r in results}
    lines = ['| Bytes | Layer | Scenario | Disk median/p95 us | Watched median/p95 us | Watched reads | Median reduction |',
             '| ---: | --- | --- | ---: | ---: | ---: | ---: |']
    for r in results:
        if r['mode'] != 'disk':
            continue
        w = keyed[r['bytes'], r['layer'], r['scenario'], 'watched']
        reduction = 100 * (1 - w['median_us'] / r['median_us'])
        lines.append(f"| {r['bytes']} | {r['layer']} | {r['scenario']} | {r['median_us']:.2f} / {r['p95_us']:.2f} | {w['median_us']:.2f} / {w['p95_us']:.2f} | {w['measured_reads']}/{w['iterations']} | {reduction:.1f}% |")
    (output / 'summary.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
