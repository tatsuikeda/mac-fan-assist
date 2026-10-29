#!/bin/bash
# Remove Mac Fan Assist and hand the fans back to macOS. Logs are left in place.
cd "$(dirname "$0")"
# autopower switches Low Power Mode on as it stops, so remember whether it was installed.
had_autopower=0
[ -f /Library/LaunchDaemons/com.github.tatsuikeda.autopower.plist ] && had_autopower=1
for n in fanassist autopower; do
  sudo launchctl bootout "system/com.github.tatsuikeda.$n" 2>/dev/null
  sudo /bin/rm -f "/Library/LaunchDaemons/com.github.tatsuikeda.$n.plist" "/Library/PrivilegedHelperTools/mac-fan-assist/$n"
done
launchctl bootout "gui/$(id -u)/com.github.tatsuikeda.smclog" 2>/dev/null
/bin/rm -f "$HOME/Library/LaunchAgents/com.github.tatsuikeda.smclog.plist"
if [ -x /Library/PrivilegedHelperTools/mac-fan-assist/smc ]; then
  sudo /Library/PrivilegedHelperTools/mac-fan-assist/smc -k F0Md -w 00 >/dev/null; sudo /Library/PrivilegedHelperTools/mac-fan-assist/smc -k F1Md -w 00 >/dev/null
fi
sudo /bin/rm -f /Library/PrivilegedHelperTools/mac-fan-assist/smc /Library/PrivilegedHelperTools/mac-fan-assist/smclog /usr/local/bin/export-guard /usr/local/bin/stress-sensors
if [ "$had_autopower" = 1 ]; then
  sudo /usr/bin/pmset -a lowpowermode 0
  echo "Removed. Fans are on Auto. autopower switched Low Power Mode on as it stopped, so it has been switched back off."
else
  echo "Removed. Fans are on Auto. Low Power Mode is unchanged."
fi
