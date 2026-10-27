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
import io, json, sys

plugin = sys.argv[1]

def patch(rel, old, new, expect):
    path = f'{plugin}/{rel}'
    text = io.open(path, encoding='utf-8').read()
    if new in text:
        print(f'  {rel}: already open')
        return
    count = text.count(old)
    if count != expect:
        raise SystemExit(f'{rel}: expected {expect} occurrence(s) of the old value, found {count}. '
                         f'Upstream changed this line; update scripts/install.sh.')
    io.open(path, 'w', encoding='utf-8', newline='').write(text.replace(old, new))
    print(f'  {rel}: {count} replacement(s)')

patch('lib/ptc/runtime.js',
      "Object.freeze(['win32-x64', 'linux-x64', 'darwin-arm64'])",
      "Object.freeze(['win32-x64', 'linux-x64', 'linux-arm64', 'darwin-arm64'])", 1)

patch('lib/ptc/runtime.js',
      'dsh-ops supports Windows x64, Linux x64 and macOS Apple Silicon (darwin-arm64) only',
      'dsh-ops supports Windows x64, Linux x64, Linux arm64 and macOS Apple Silicon (darwin-arm64) only', 1)

patch('lib/profile-install.js',
      "Object.freeze({ win32: ['x64'], linux: ['x64'], darwin: ['arm64'] })",
      "Object.freeze({ win32: ['x64'], linux: ['x64', 'arm64'], darwin: ['arm64'] })", 1)

manifest = f'{plugin}/dsh-plugin.json'
text = io.open(manifest, encoding='utf-8').read()
old = '"targets": ["win32-x64", "linux-x64", "darwin-arm64"]'
new = '"targets": ["win32-x64", "linux-x64", "linux-arm64", "darwin-arm64"]'
if new not in text:
    count = text.count(old)
    if count != 5:
        raise SystemExit(f'dsh-plugin.json: expected 5 target rows, found {count}. '
                         f'Upstream changed the manifest; update scripts/install.sh.')
    text = text.replace(old, new)
    io.open(manifest, 'w', encoding='utf-8', newline='').write(text)
    print(f'  dsh-plugin.json: {count} target row(s)')
else:
    print('  dsh-plugin.json: already open')

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
