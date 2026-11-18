#!/usr/bin/env bash
# CI only: picks an iPhone simulator of the newest iOS on the runner, boots it (so it is ready
# while the app compiles) and prints its UDID.
# CENTAVO_SIM_NAME="iPhone SE (3rd generation)" asks for that model (el trabajo «dispositivos» de ci.yml): if the
# runner has none, it is created from the device type on the newest iOS.
set -euo pipefail
udid="$(xcrun simctl list -j | CENTAVO_SIM_NAME="${CENTAVO_SIM_NAME:-}" python3 -c "
import json, os, subprocess, sys
data = json.load(sys.stdin)
devices = data['devices']
wanted = os.environ.get('CENTAVO_SIM_NAME', '')
runtimes = sorted((r for r in data['runtimes'] if r.get('isAvailable') and r['platform'] == 'iOS'),
                  key=lambda r: [int(x) for x in r['version'].split('.')])
newest = runtimes[-1]['identifier']
if wanted:
    for d in devices.get(newest, []):
        if d['name'] == wanted and d.get('isAvailable', True):
            print(d['udid']); sys.exit()
    kind = next((t['identifier'] for t in data['devicetypes'] if t['name'] == wanted), None)
    if kind is None:
        sys.exit(f'El runner no conoce el modelo «{wanted}»')
    print(subprocess.check_output(['xcrun', 'simctl', 'create', wanted, kind, newest], text=True).strip())
    sys.exit()
best = None
for runtime in sorted(devices):
    if 'iOS' not in runtime: continue
    for d in devices[runtime]:
        if d['name'].startswith('iPhone') and d.get('isAvailable', True):
            if best is None or d['name'] == 'iPhone 16 Pro' or 'Pro' not in best[0]:
                best = (d['name'], d['udid'], runtime)
print(best[1])
")"
xcrun simctl list devices available | head -40 >&2
xcrun simctl boot "$udid" >&2 || true
echo "$udid"
