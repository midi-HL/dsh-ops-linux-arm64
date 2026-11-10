#!/usr/bin/env bash
# Install the linux-arm64 worker into a DSH profile and open the platform gate.
#
# Usage:
#   ./scripts/install.sh [--artifact-dir DIR] [--profile NAME] [--dry-run]
#
#   --artifact-dir  directory holding dsh-ops-worker + provenance.json
#                   (default: prebuilt/linux-arm64 in this repository)
#   --profile       DSH profile to install into (default: web)
#   --dry-run       print the plan and change nothing
#
# What it does, in order:
#   1. verifies the worker's sha256 against its own provenance.json
#   2. backs up the plugin directory, the profile manifest and the patch layer
#   3. copies the worker into <plugin>/runtime/linux-arm64/
#   4. opens the three platform gates in the installed plugin:
#        lib/ptc/runtime.js       PLATFORMS
#        lib/profile-install.js   SUPPORTED_TARGETS
#        dsh-plugin.json          x-components[].targets
#   5. re-resolves the worker to prove the gate is open
#
# It does not touch cordis.patch.yml, the profile's dependency list, or DSH itself.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")

ARTIFACT_DIR="$REPO/prebuilt/linux-arm64"
PROFILE="web"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --artifact-dir) ARTIFACT_DIR=$2; shift 2 ;;
    --profile)      PROFILE=$2; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

DSH_HOME=${DSH_HOME:-$HOME/.dsh}
PLUGIN="$DSH_HOME/profiles/$PROFILE/node_modules/dsh-ops"
WORKER="$ARTIFACT_DIR/dsh-ops-worker"
RECEIPT="$ARTIFACT_DIR/provenance.json"

die() { echo "install: $*" >&2; exit 1; }

[ -d "$PLUGIN" ] || die "dsh-ops is not installed in profile '$PROFILE' ($PLUGIN missing).
Install it first:  dsh plugin --profile $PROFILE add dsh-ops"
[ -f "$WORKER" ] || die "no worker at $WORKER
Build it (gh workflow run build-all-targets.yml) or point --artifact-dir at the artifact."
[ -f "$RECEIPT" ] || die "no provenance receipt at $RECEIPT"

# --- 1. verify the artifact before touching anything -------------------------
actual=$(sha256sum "$WORKER" | cut -d' ' -f1)
declared=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$RECEIPT")
[ "$actual" = "$declared" ] || die "sha256 mismatch: file $actual, receipt $declared"
target=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["target"])' "$RECEIPT")
[ "$target" = "linux-arm64" ] || die "receipt targets $target, expected linux-arm64"
echo "artifact verified: sha256 $actual"

if [ "$DRY_RUN" = 1 ]; then
  echo "dry run: would install into $PLUGIN and open the platform gate"
  exit 0
fi

# --- 2. back up -------------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S)
backup="$DSH_HOME/dsh-ops-arm64-backup-$stamp"
mkdir -p "$backup"
cp -a "$PLUGIN" "$backup/dsh-ops-pkg"
cp -a "$DSH_HOME/profiles/$PROFILE/package.json" "$backup/profile-package.json" 2>/dev/null || true
[ -f "$DSH_HOME/profiles/$PROFILE/cordis.patch.yml" ] && \
  cp -a "$DSH_HOME/profiles/$PROFILE/cordis.patch.yml" "$backup/cordis.patch.yml"
echo "$backup" > "$DSH_HOME/dsh-ops-arm64-backup-path"
echo "backup: $backup"

# --- 3. install the worker --------------------------------------------------
mkdir -p "$PLUGIN/runtime/linux-arm64"
install -m 0755 "$WORKER" "$PLUGIN/runtime/linux-arm64/dsh-ops-worker"
cp "$RECEIPT" "$PLUGIN/runtime/linux-arm64/provenance.json"
echo "worker installed: $PLUGIN/runtime/linux-arm64/dsh-ops-worker"

# --- 4. open the platform gate ---------------------------------------------
python3 - "$PLUGIN" <<'PY'
import io, json, sys, os

plugin = sys.argv[1]
version = json.load(io.open(f'{plugin}/package.json', encoding='utf-8'))['version']
print(f'  plugin version: {version}')

def patch(rel, old, new, expect=None):
    path = f'{plugin}/{rel}'
    if not os.path.exists(path):
        return False
    text = io.open(path, encoding='utf-8').read()
    if new in text:
        print(f'  {rel}: already open')
        return True
    count = text.count(old)
    if count == 0:
        return False
    if expect is not None and count != expect:
        raise SystemExit(f'{rel}: expected {expect} occurrence(s), found {count}. '
                         f'Upstream changed this line; update scripts/install.sh.')
    io.open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new))
    print(f'  {rel}: {count} replacement(s)')
    return True

# The authoritative resolver moved in 0.5.x; 0.4.x uses lib/ptc/runtime.js.
runtime_rel = 'lib/execution/runtime.js' if os.path.exists(f'{plugin}/lib/execution/runtime.js') else 'lib/ptc/runtime.js'

# Three upstream target matrices: 0.4.1 (3), 0.4.2-0.4.4 (4), 0.5.x (4, same).
# The resolver's PLATFORMS literal is the single source of truth we edit.
platform_olds = [
    "Object.freeze(['win32-x64', 'linux-x64', 'darwin-arm64'])",
    "Object.freeze(['win32-x64', 'linux-x64', 'darwin-arm64', 'darwin-x64'])",
]
platform_news = [
    "Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64'])",
    "Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64', 'darwin-x64'])",
]
runtime_text = io.open(f'{plugin}/{runtime_rel}', encoding='utf-8').read()
if "'linux-arm64'" in runtime_text:
    print(f'  {runtime_rel}: linux-arm64 already present')
else:
    ok = False
    for old, new in zip(platform_olds, platform_news):
        if patch(runtime_rel, old, new, 1):
            ok = True
            break
    if not ok:
        raise SystemExit(f'{runtime_rel}: PLATFORMS literal not recognised. Upstream changed it; update scripts/install.sh.')

# Error text is informational only; update whichever variant is present.
patch(runtime_rel,
      'dsh-ops supports Windows x64, Linux x64 and macOS Apple Silicon (darwin-arm64) only',
      'dsh-ops supports Windows x64, Linux x64, Linux arm64 and macOS Apple Silicon (darwin-arm64) only', 1)
patch(runtime_rel,
      'dsh-ops supports Windows x64, Linux x64 and macOS (arm64/x64) only',
      'dsh-ops supports Windows x64, Linux x64/arm64 and macOS (arm64/x64) only', 1)

# SUPPORTED_TARGETS differs between 0.4.1 and 0.4.2+.
patch('lib/profile-install.js',
      "Object.freeze({ win32: ['x64'], linux: ['x64'], darwin: ['arm64'] })",
      "Object.freeze({ win32: ['x64'], linux: ['x64', 'arm64'], darwin: ['arm64'] })", 1)
patch('lib/profile-install.js',
      "Object.freeze({ win32: ['x64'], linux: ['x64'], darwin: ['arm64', 'x64'] })",
      "Object.freeze({ win32: ['x64'], linux: ['x64', 'arm64'], darwin: ['arm64', 'x64'] })", 1)

# dsh-plugin.json: 0.4.x has 5-6 single-line target rows, 0.5.x has one
# multi-line row. Replace every declaration, asserting the count is plausible.
manifest = f'{plugin}/dsh-plugin.json'
text = io.open(manifest, encoding='utf-8').read()
single_olds = [
    '"targets": ["win32-x64", "linux-x64", "darwin-arm64"]',
    '"targets": ["win32-x64", "linux-x64", "darwin-arm64", "darwin-x64"]',
]
single_news = [
    '"targets": ["win32-x64", "linux-x64", "linux-arm64", "darwin-arm64"]',
    '"targets": ["win32-x64", "linux-x64", "linux-arm64", "darwin-arm64", "darwin-x64"]',
]
changed = 0
for old, new in zip(single_olds, single_news):
    n = text.count(old)
    if n:
        text = text.replace(old, new)
        changed += n

if changed == 0:
    multiline_old = '''"targets": [
          "win32-x64",
          "linux-x64",
          "darwin-arm64",
          "darwin-x64"
        ]'''
    multiline_new = '''"targets": [
          "win32-x64",
          "linux-x64",
          "linux-arm64",
          "darwin-arm64",
          "darwin-x64"
        ]'''
    n = text.count(multiline_old)
    if n:
        text = text.replace(multiline_old, multiline_new)
        changed += n

if changed == 0:
    if 'linux-arm64' not in text:
        raise SystemExit('dsh-plugin.json: no recognised targets declaration and linux-arm64 absent. '
                         'Upstream changed the manifest; update scripts/install.sh.')
    print('  dsh-plugin.json: already open')
else:
    if changed > 10:
        raise SystemExit(f'dsh-plugin.json: unexpected {changed} target rows; refusing to edit.')
    io.open(manifest, 'w', encoding='utf-8', newline='').write(text)
    print(f'  dsh-plugin.json: {changed} target declaration(s)')

json.load(io.open(manifest, encoding='utf-8'))
PY

# --- 5. prove the gate is open ---------------------------------------------
echo "resolving the worker through the plugin's own resolver:"
(cd "$PLUGIN" && node -e "
import('./lib/ptc/runtime.js').then(m => {
  console.log('  platforms:', m.PLATFORMS.join(','))
  console.log('  resolved :', m.resolveWorker({}))
}).catch(e => { console.error('  FAILED:', e.message); process.exit(1) })
")

cat <<EOF

Done. Restart DSH so the profile reloads:

  dsh-web.sh --stop && dsh-web.sh          # if you use the dsh-web.sh wrapper
  # or: <your dsh launcher> --profile $PROFILE

Verify after restart:

  cd $PLUGIN && node bin/dsh-ops.mjs ladder

Roll back:

  rm -rf $PLUGIN && cp -a $backup/dsh-ops-pkg $PLUGIN
EOF
