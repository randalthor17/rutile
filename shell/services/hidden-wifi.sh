#!/bin/sh
# Joins a hidden Wi-Fi network through NetworkManager (plan 2.6, D100): hidden-wifi.sh NAME open|psk
# With psk, the password is read from stdin, never from the arguments (anyone can read a process's arguments).
# A saved connection of that name is reused (and marked hidden); otherwise one is added, and removed again when
# joining fails, so a mistyped name or password leaves nothing behind. NetworkManager keeps the password with the
# connection, as it does for a visible network.
name=$1
security=$2
[ -n "$name" ] || { echo "hidden-wifi: no network name" >&2; exit 2; }
case $security in
    open | psk) ;;
    *) echo "hidden-wifi: security is open or psk, not '$security'" >&2; exit 2 ;;
esac

added=
if nmcli connection show id "$name" >/dev/null 2>&1; then
    nmcli connection modify id "$name" 802-11-wireless.hidden yes || exit 1
else
    if [ "$security" = psk ]; then
        nmcli connection add type wifi con-name "$name" ifname '*' ssid "$name" 802-11-wireless.hidden yes \
            wifi-sec.key-mgmt wpa-psk >/dev/null || exit 1
    else
        nmcli connection add type wifi con-name "$name" ifname '*' ssid "$name" 802-11-wireless.hidden yes \
            >/dev/null || exit 1
    fi
    added=1
fi

if [ "$security" = psk ]; then
    IFS= read -r password || [ -n "$password" ] || { echo "hidden-wifi: no password on stdin" >&2; exit 2; }
    # nmcli reads the secrets from a file; a pipe from here keeps the password off the disk. 90 s: finding a hidden
    # network takes an active scan of every channel, then the address
    printf '802-11-wireless-security.psk:%s\n' "$password" | nmcli --wait 90 connection up id "$name" passwd-file /dev/stdin
else
    nmcli --wait 90 connection up id "$name" </dev/null
fi
status=$?
if [ $status -ne 0 ] && [ -n "$added" ]; then
    nmcli connection delete id "$name" >/dev/null 2>&1
fi
exit $status
