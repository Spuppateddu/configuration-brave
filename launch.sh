#!/usr/bin/env bash
# Starts Brave with a smaller UI; if Brave is closed, first writes the profile settings.
# Usage: ./launch.sh [brave args…]  |  ./launch.sh --apply-only (write, don't start)
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DATA="$HOME/.config/BraveSoftware/Brave-Browser"
PROFILE="$DATA/Default"
VIMIUM_ID="dbepggeogbaibhgnhhndojpepiihcmeb"
# classic-level (a LevelDB binding) is installed here by install.sh.
export BLE_CHROME_NODE_MODULES="$HOME/.cache/brave-config/node_modules"

BRAVE_UI_SCALE=0.8
[[ -f "$REPO/brave.local" ]] && source "$REPO/brave.local"
# A bad value must never stop the browser from starting: fall back to 0.8.
if ! awk -v s="$BRAVE_UI_SCALE" 'BEGIN { exit !(s + 0 >= 0.5 && s + 0 <= 1) }'; then
    printf '%s: BRAVE_UI_SCALE=%s is not between 0.5 and 1 — using 0.8\n' \
        "${0##*/}" "$BRAVE_UI_SCALE" >&2
    BRAVE_UI_SCALE=0.8
fi

# SingletonLock is a symlink to "<host>-<pid>" and survives a crash, so check the pid.
brave_running() {
    local target
    target="$(readlink "$DATA/SingletonLock" 2>/dev/null)" || return 1
    kill -0 "${target##*-}" 2>/dev/null
}

apply_prefs() {
    local prefs="$PROFILE/Preferences" tmp zoom keys=true
    command -v jq >/dev/null || { echo "jq not found — profile prefs skipped" >&2; return 1; }
    mkdir -p "$PROFILE"
    [[ -s "$prefs" ]] || echo '{}' > "$prefs"
    # Brave fills its shortcut table on first start; adding to a missing one would drop its defaults.
    jq -e '.brave.accelerators | type == "object"' "$prefs" >/dev/null || keys=false
    # Zoom = 1 / scale keeps pages at normal size. Chromium stores it as a level: zoom = 1.2^level.
    zoom="$(awk -v s="$BRAVE_UI_SCALE" 'BEGIN { printf "%.10f", log(1 / s) / log(1.2) }')"
    tmp="$(mktemp "$PROFILE/.Preferences.XXXXXX")"
    # Full URL in the address bar, blank new tab, and no "Restore pages?" after a reboot.
    if jq --argjson zoom "$zoom" --argjson keys "$keys" -L "$REPO" '
        include "keybindings";
        .partition.default_zoom_level.x = $zoom
        | .omnibox.prevent_url_elisions = true
        | .brave.new_tab_page.shows_options = 2
        | .profile.exit_type = "Normal"
        | .profile.exited_cleanly = true
        | if $keys then keybindings else . end
    ' "$prefs" > "$tmp"; then
        if cmp -s "$tmp" "$prefs"; then rm -f "$tmp"; echo "prefs unchanged"
        else mv "$tmp" "$prefs"; echo "prefs written"; fi
    else
        rm -f "$tmp"; echo "could not parse $prefs — left it alone" >&2; return 1
    fi
    [[ "$keys" == true ]] || echo "key bindings wait for Brave's first start"
}

apply_vimium() {
    # install.sh records the extensions you chose; no Vimium there means nothing to write.
    local chosen="$HOME/.cache/brave-config/extensions"
    if [[ -f "$chosen" ]] && ! grep -Fxq vimium "$chosen"; then echo "vimium not chosen"; return 0; fi
    [[ -d "$BLE_CHROME_NODE_MODULES/classic-level" ]] && command -v node >/dev/null \
        || { echo "classic-level not installed — run install.sh; Vimium settings skipped" >&2; return 1; }
    printf 'vimium settings %s\n' "$(node "$REPO/vimium-sync.mjs" \
        "$PROFILE/Sync Extension Settings/$VIMIUM_ID" "$REPO/vimium-settings.json")"
}

apply_only=false
[[ "${1:-}" == --apply-only ]] && { apply_only=true; shift; }

if brave_running; then
    # Brave is open: new windows join the running one, nothing to write.
    [[ "$apply_only" == true ]] && { echo "Brave is running — close it first"; exit 3; }
else
    status=0
    apply_prefs || status=1
    apply_vimium || status=1
    [[ "$apply_only" == true ]] && exit "$status"
fi

exec /usr/bin/brave-browser-stable --force-device-scale-factor="$BRAVE_UI_SCALE" "$@"
