#!/usr/bin/env bash
# CI only: picks an iPhone simulator of the newest iOS on the runner, boots it (so it is ready
# while the app compiles) and prints its UDID.
set -euo pipefail
udid="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
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
