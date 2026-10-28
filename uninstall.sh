#!/bin/bash
# Remove Mac Fan Assist and hand the fans back to macOS. Logs are left in place.
cd "$(dirname "$0")"
for n in fanassist autopower; do
  sudo launchctl bootout "system/com.github.tatsuikeda.$n" 2>/dev/null
  sudo /bin/rm -f "/Library/LaunchDaemons/com.github.tatsuikeda.$n.plist" "/usr/local/libexec/$n"
done
launchctl bootout "gui/$(id -u)/com.github.tatsuikeda.smclog" 2>/dev/null
/bin/rm -f "$HOME/Library/LaunchAgents/com.github.tatsuikeda.smclog.plist"
if [ -x /usr/local/libexec/smc ]; then
  sudo /usr/local/libexec/smc -k F0Md -w 00 >/dev/null; sudo /usr/local/libexec/smc -k F1Md -w 00 >/dev/null
fi
sudo /bin/rm -f /usr/local/libexec/smc /usr/local/libexec/smclog /usr/local/bin/export-guard /usr/local/bin/stress-sensors
echo "Removed. Fans are on Auto. Low Power Mode is left as it is: check it in System Settings > Battery."
