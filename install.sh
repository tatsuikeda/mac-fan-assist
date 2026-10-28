#!/bin/bash
# Install Mac Fan Assist.
#   ./install.sh                     fanassist only (plus the export-guard and stress-sensors tools)
#   ./install.sh --with-autopower    also run autopower (Low Power Mode off until the CPU stays hot)
#   ./install.sh --with-smclog       also log every SMC temperature every 30 s (needs iSMC)
#   ./install.sh --force             install on a model other than the tested one (check sensors first)
set -euo pipefail
cd "$(dirname "$0")"
SMC_REPO=https://github.com/hholtmann/smcFanControl.git
SMC_COMMIT=e1bd672bcd2d72eddff9b6da7b9cae38e35c4206
TESTED=MacBookPro16,1
NEEDED="F0Md F1Md F0Mn F1Mn F0Mx F1Mx F0Tg F1Tg TC0F TGDD Th1H TB0T TB1T TB2T"
autopower=0 smclog=0 force=0
for a in "$@"; do case $a in
  --with-autopower) autopower=1 ;; --with-smclog) smclog=1 ;; --force) force=1 ;;
  *) sed -n '2,6s/^# //p' "$0"; exit 1 ;;
esac; done

[ "$(uname -m)" = x86_64 ] || { echo "Mac Fan Assist is for Intel Macs. Apple silicon Macs manage their own fans well."; exit 1; }
model=$(sysctl -n hw.model)
if [ "$model" != "$TESTED" ] && [ "$force" = 0 ]; then
  echo "Only tested on $TESTED; this Mac is $model. Read 'Other Macs' in the README, then rerun with --force."; exit 1
fi
xcode-select -p >/dev/null 2>&1 || { echo "Needs the Command Line Tools first: xcode-select --install"; exit 1; }
if [ "$smclog" = 1 ] && ! [ -x /usr/local/bin/iSMC ]; then
  echo "--with-smclog needs iSMC: brew install dkorunic/tap/ismc"; exit 1
fi

echo "Building the smc tool from smcFanControl ($SMC_COMMIT)..."
tmp=$(mktemp -d); trap '/bin/rm -rf "$tmp"' EXIT
git clone -q "$SMC_REPO" "$tmp/smcFanControl"
git -C "$tmp/smcFanControl" checkout -q "$SMC_COMMIT"
make -s -C "$tmp/smcFanControl/smc-command" >/dev/null 2>&1
smc=$tmp/smcFanControl/smc-command/smc

missing=""
for k in $NEEDED; do "$smc" -k "$k" -r | grep -q 'no data' && missing="$missing $k"; done
if [ -n "$missing" ]; then
  echo "This Mac is missing SMC keys:$missing"
  echo "Edit RAMPS in bin/fanassist to use sensors this Mac has (see README), then rerun."
  case "$missing" in *F0*|*F1*) echo "Fan keys are missing too, so fanassist can't drive the fans here."; exit 1 ;; esac
  [ "$force" = 1 ] || exit 1
fi

echo "Installing (sudo will ask for your password)..."
# Programs that run as root live in a folder only root can write to, all the way up, so nothing
# running as you can swap them out. (Homebrew often makes /usr/local folders user-owned.)
sudo install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools/mac-fan-assist
d=/Library/PrivilegedHelperTools/mac-fan-assist
while [ "$d" != / ]; do
  perm=$(/usr/bin/stat -f '%Su %Mp%Lp' "$d")
  case $perm in "root "*[0145][0145]) ;; *) echo "Refusing to install: $d isn't root-only ($perm)."; exit 1 ;; esac
  d=$(dirname "$d")
done
sudo install -d /usr/local/bin
sudo install -o root -g wheel -m 755 "$smc" /Library/PrivilegedHelperTools/mac-fan-assist/smc
sudo install -m 755 bin/export-guard bin/stress-sensors /usr/local/bin/

daemon() {
  local label=com.github.tatsuikeda.$1 plist=/Library/LaunchDaemons/com.github.tatsuikeda.$1.plist
  sudo launchctl bootout "system/$label" 2>/dev/null && sleep 3 || true
  sudo install -o root -g wheel -m 755 "bin/$1" "/Library/PrivilegedHelperTools/mac-fan-assist/$1"
  sed "s/@NAME@/$1/g" launchd/daemon.plist.in | sudo tee "$plist" >/dev/null
  sudo chown root:wheel "$plist"; sudo chmod 644 "$plist"
  sudo launchctl bootstrap system "$plist"
  echo "  $1 running (log: /Library/Logs/$1.log)"
}
daemon fanassist
[ "$autopower" = 1 ] && daemon autopower
if [ "$smclog" = 1 ]; then
  plist=$HOME/Library/LaunchAgents/com.github.tatsuikeda.smclog.plist
  launchctl bootout "gui/$(id -u)/com.github.tatsuikeda.smclog" 2>/dev/null && sleep 3 || true
  sudo install -o root -g wheel -m 755 bin/smclog /Library/PrivilegedHelperTools/mac-fan-assist/smclog
  cp launchd/smclog.plist.in "$plist"
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "  smclog running (logs: ~/Library/Logs/smclog/)"
fi
echo "Done. Keep Macs Fan Control (or any other fan app) on Auto: only one program should drive the fans."
