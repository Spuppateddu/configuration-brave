#!/usr/bin/env bash
# Apply this repo to Brave: policy, launcher, profile settings, Vimium.
# Usage: ./install.sh [--extensions=vimium,bitwarden|all|none] [--dry-run]   Idempotent. Does NOT install Brave itself.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STDIN_IS_TTY=false; [[ -t 0 ]] && STDIN_IS_TTY=true

# setup.sh --dry-run sets DRY_RUN in the environment; accept the usual spellings of a boolean.
case "${DRY_RUN:-false}" in
    true|1|yes|on) DRY_RUN=true ;;
    *)             DRY_RUN=false ;;
esac
# Empty means "not asked", which is not the same as `none`.
WANT_EXT=""
for arg in "$@"; do
    case "$arg" in
        '')         ;;
        --dry-run)  DRY_RUN=true ;;
        --extensions=*) WANT_EXT="${arg#--extensions=}" ;;
        -h|--help)  sed -n '2,3p' "$0"; exit 0 ;;
        *) printf '%s: unknown argument %s\n' "${0##*/}" "$arg" >&2; exit 2 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
would() { printf '%s  would %s:%s %s\n' "$C_DIM" "$1" "$C_OFF" "${*:2}"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
# A tty for the password prompt, or cached credentials — never hang the boot cron.
can_sudo() { [[ "$STDIN_IS_TTY" == true ]] || sudo -n true 2>/dev/null; }
tilde()   { printf '%s' "${1/#$HOME/\~}"; }

# write_user DEST — content on stdin. An identical file is left alone.
write_user() {
    local dst="$1" new; new="$(cat)"
    if [[ -f "$dst" && "$new" == "$(cat "$dst")" ]]; then skip "$(tilde "$dst") already up to date."; return 0; fi
    if [[ "$DRY_RUN" == true ]]; then would write "$(tilde "$dst")"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    printf '%s\n' "$new" > "$dst"
    ok "wrote $(tilde "$dst")"
}

# write_root DEST — the same through sudo. Non-zero when sudo is unavailable.
write_root() {
    local dst="$1" new tmp; new="$(cat)"
    if [[ -f "$dst" && "$new" == "$(cat "$dst")" ]]; then skip "$dst already up to date."; return 0; fi
    if [[ "$DRY_RUN" == true ]]; then would write "$dst"; return 0; fi
    can_sudo || { warn "sudo unavailable (no terminal) — skipped $dst."; return 1; }
    tmp="$(mktemp)"; printf '%s\n' "$new" > "$tmp"
    step "Writing $dst"
    # Checked by hand: callers use `||`, which switches off `set -e` in here.
    sudo mkdir -p "$(dirname "$dst")" && sudo install -m 0644 "$tmp" "$dst" \
        || { rm -f "$tmp"; warn "could not write $dst."; return 1; }
    rm -f "$tmp"; ok "wrote $dst"
}

printf '\n%s══ Brave config ══%s\n' "$C_BOLD" "$C_OFF"

if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    warn "Don't run this with sudo — run it as $SUDO_USER. It asks for sudo itself."
    exit 2
fi
if [[ ! -x /usr/bin/brave-browser-stable ]]; then
    skip "Brave is not installed — nothing to configure."
    skip "Install it with best-linux-environment: ./setup.sh only brave"
    exit 0
fi

# ── 1. Policy: extensions + browser settings ─────────────────────────────────
# Chromium's admin mechanism, which Brave keeps. normal_installed = installed and kept
# updated; force_pinned puts the button on the toolbar, like Firefox's layout.
POLICY_FILE="/etc/brave/policies/managed/brave-config.json"

build_policy() {
    local ext='{}' i id
    for i in "${!EXT_ID[@]}"; do
        selected "${EXT_SLUG[$i]}" || continue
        id="${EXT_ID[$i]}"
        ext="$(jq --arg id "$id" '.[$id] = {
            installation_mode: "normal_installed",
            update_url: "https://clients2.google.com/service/update2/crx",
            toolbar_pin: "force_pinned" }' <<< "$ext")"
    done
    # Rewards, Wallet, VPN and Leo AI off: their toolbar buttons go away too.
    jq -n --argjson ext "$ext" '{
        ExtensionSettings: $ext,
        BraveRewardsDisabled: true,
        BraveWalletDisabled: true,
        BraveVPNDisabled: true,
        BraveAIChatEnabled: false,
        BraveP3AEnabled: false,
        BraveStatsPingEnabled: false,
        BraveWebDiscoveryEnabled: false,
        PasswordManagerEnabled: false,
        AutofillAddressEnabled: false,
        AutofillCreditCardEnabled: false,
        MetricsReportingEnabled: false,
        NetworkPredictionOptions: 2,
        DefaultBrowserSettingEnabled: false
    }'
}

if ! has_cmd jq; then
    warn "jq not found — install it (sudo apt install jq) and re-run."
    exit 1
fi

# ── Extensions: the checkbox list ────────────────────────────────────────────
# The same widget as best-linux-environment's lib/ui.sh, copied: this repo runs on its own.
# CHK_LABELS=(…) what to show, CHK_STATE=(1 0 …) pre-ticked; checklist edits CHK_STATE.
CHK_LABELS=(); CHK_STATE=()

# Arrow keys are three bytes (ESC [ A); the tail is read with a timeout so a bare Esc can't hang.
read_key() {
    local k rest=''
    IFS= read -rsn1 k 2>/dev/null || { printf 'enter'; return; }
    case "$k" in
        $'\e') read -rsn2 -t 0.3 rest 2>/dev/null || rest=''
               case "$rest" in '[A') printf 'up' ;; '[B') printf 'down' ;; *) printf 'esc' ;; esac ;;
        '')  printf 'enter' ;;
        ' ') printf 'space' ;;
        *)   printf '%s' "$k" ;;
    esac
}

# A row must never wrap: the redraw moves up one line per row.
fit() {
    local s="$1" max="$2"
    (( max < 10 )) && max=10
    if (( ${#s} > max )); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

checklist() {
    local heading="$1" hint="${2:-}" n=${#CHK_LABELS[@]} i cur=0 first=1 key width
    (( n )) || return 0
    width="$(tput cols 2>/dev/null || echo 80)"; (( width > 20 )) || width=80
    printf '\n%s══ %s ══%s\n' "$C_BOLD" "$heading" "$C_OFF"
    [[ -n "$hint" ]] && printf '%s   %s%s\n' "$C_DIM" "$hint" "$C_OFF"
    printf '%s   ↑/↓ move · space toggle · a all · n none · enter confirm%s\n\n' "$C_DIM" "$C_OFF"
    # Cursor hidden while drawing, and put back on every exit, Ctrl-C included.
    printf '\033[?25l'
    trap 'printf "\033[?25h"; exit 130' INT
    while :; do
        if (( first )); then first=0; else printf '\033[%dA' "$n"; fi
        for i in "${!CHK_LABELS[@]}"; do
            local mark=' ' box="${C_DIM}[ ]${C_OFF}" row
            (( i == cur )) && mark="${C_BLUE}❯${C_OFF}"
            (( CHK_STATE[i] )) && box="${C_GREEN}[x]${C_OFF}"
            row="$(fit "${CHK_LABELS[$i]}" $((width - 10)))"
            (( i == cur )) && row="${C_BOLD}${row}${C_OFF}"
            printf '\033[2K %s %s %s\n' "$mark" "$box" "$row"
        done
        key="$(read_key)"
        # x=$(( … )), never (( x = … )): a zero result would end the run under `set -e`.
        case "$key" in
            up|k)    cur=$(( (cur - 1 + n) % n )) ;;
            down|j)  cur=$(( (cur + 1) % n )) ;;
            space|x) CHK_STATE[cur]=$(( 1 - CHK_STATE[cur] )) ;;
            a|A)     for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=1; done ;;
            n|N)     for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=0; done ;;
            enter|q|Q) break ;;
        esac
    done
    printf '\033[?25h'
    trap - INT
    return 0
}

# ── Extensions: which ones ───────────────────────────────────────────────────
EXT_ID=(); EXT_SLUG=(); EXT_LABEL=(); EXT_DEFAULT=()
while IFS='|' read -r id slug label def; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    EXT_ID+=("$id"); EXT_SLUG+=("$slug"); EXT_LABEL+=("$label"); EXT_DEFAULT+=("${def:-1}")
done < "$REPO/extensions.conf"

# In order: --extensions= (setup.sh already asked), the list on a terminal, the last choice, defaults.
# The choice is this machine's, so it lives in ~/.cache, not in the repo. launch.sh reads it too.
STATE_FILE="$HOME/.cache/brave-config/extensions"
SELECTED=(); selection_source=""

select_by_slug() {
    local i
    for i in "${!EXT_SLUG[@]}"; do
        [[ "${EXT_SLUG[$i]}" == "$1" ]] && { SELECTED+=("$1"); return 0; }
    done
    warn "Unknown extension '$1' — not in extensions.conf, ignored."
}

if [[ -n "$WANT_EXT" ]]; then
    selection_source=asked
    case "$WANT_EXT" in
        all)  SELECTED=("${EXT_SLUG[@]}") ;;
        none) ;;
        *)    for slug in ${WANT_EXT//,/ }; do select_by_slug "$slug"; done ;;
    esac
elif [[ -t 0 && -t 1 ]]; then
    # The list opens on the last choice, so confirming it straight through changes nothing.
    selection_source=asked
    for i in "${!EXT_SLUG[@]}"; do
        CHK_LABELS+=("${EXT_LABEL[$i]}")
        if [[ -f "$STATE_FILE" ]]; then
            if grep -Fxq "${EXT_SLUG[$i]}" "$STATE_FILE"; then CHK_STATE+=(1); else CHK_STATE+=(0); fi
        else
            CHK_STATE+=("${EXT_DEFAULT[$i]}")
        fi
    done
    checklist "Brave — which extensions to install" \
        "Installed by Brave's policy and kept updated. Unticking one never uninstalls it — do that in Brave's extensions page."
    for i in "${!CHK_STATE[@]}"; do
        if (( CHK_STATE[i] )); then SELECTED+=("${EXT_SLUG[$i]}"); fi
    done
elif [[ -f "$STATE_FILE" ]]; then
    # An empty file is a real answer — "none" — so it must not fall through to the defaults.
    selection_source=remembered
    while IFS= read -r slug; do [[ -n "$slug" ]] && select_by_slug "$slug"; done < "$STATE_FILE"
else
    selection_source=default
    for i in "${!EXT_SLUG[@]}"; do
        if [[ "${EXT_DEFAULT[$i]}" == 1 ]]; then SELECTED+=("${EXT_SLUG[$i]}"); fi
    done
fi

selected() {
    local s
    for s in ${SELECTED[@]+"${SELECTED[@]}"}; do [[ "$s" == "$1" ]] && return 0; done
    return 1
}

case "$selection_source" in
    asked)      step "Extensions: ${SELECTED[*]:-none}" ;;
    remembered) skip "Extensions: ${SELECTED[*]:-none} (your last choice; --extensions= to change)" ;;
    default)    skip "Extensions: ${SELECTED[*]:-none} (the defaults — never chosen on this machine)" ;;
esac

# Only a real answer is recorded: saving the defaults would invent a choice nobody made.
if [[ "$selection_source" == asked && "$DRY_RUN" != true ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    : > "$STATE_FILE"
    for slug in ${SELECTED[@]+"${SELECTED[@]}"}; do printf '%s\n' "$slug" >> "$STATE_FILE"; done
fi

build_policy | write_root "$POLICY_FILE" \
    || warn "Policy not applied — extensions won't install. Re-run from a terminal."

# ── 2. The launcher: every Brave menu entry goes through launch.sh ──────────
# A copy of Brave's .desktop in ~/.local wins over the system one; rofi and xdg-open use it.
# Through ~/.brave when it links here, so a run from either path writes the same entry.
LAUNCH="$REPO/launch.sh"
[[ "$(readlink -f "$HOME/.brave")" == "$(readlink -f "$REPO")" ]] && LAUNCH="$HOME/.brave/launch.sh"
SYS_DESKTOP=/usr/share/applications/brave-browser.desktop
if [[ -f "$SYS_DESKTOP" ]]; then
    sed "s|^Exec=/usr/bin/brave-browser-stable|Exec=$LAUNCH|" "$SYS_DESKTOP" \
        | write_user "$HOME/.local/share/applications/brave-browser.desktop"
else
    warn "No $SYS_DESKTOP — start Brave with $(tilde "$REPO")/launch.sh yourself."
fi

# ── 3. classic-level: the LevelDB library that writes Vimium's settings ──────
NODE_DIR="$HOME/.cache/brave-config"
if [[ -d "$NODE_DIR/node_modules/classic-level" ]]; then
    skip "classic-level already installed in $(tilde "$NODE_DIR")."
elif ! has_cmd npm; then
    warn "npm not found — Vimium's settings can't be written. Install node, then re-run."
elif [[ "$DRY_RUN" == true ]]; then
    would install "classic-level → $(tilde "$NODE_DIR")"
else
    step "Installing classic-level into $(tilde "$NODE_DIR")"
    mkdir -p "$NODE_DIR"
    (cd "$NODE_DIR" && { [[ -f package.json ]] || npm init -y >/dev/null; } \
        && npm install --silent --no-audit --no-fund classic-level >/dev/null) \
        && ok "classic-level installed." \
        || warn "npm install failed — Vimium's settings not written."
fi

# ── 4. Profile settings: zoom, keys, blank new tab, Vimium ─────────────
if [[ "$DRY_RUN" == true ]]; then
    would apply "profile settings + Vimium settings (via launch.sh --apply-only)"
elif out="$("$REPO/launch.sh" --apply-only 2>&1)"; then
    ok "Profile: ${out//$'\n'/, }"
elif [[ $? -eq 3 ]]; then
    warn "Brave is running — profile settings and Vimium's settings wait."
    warn "They are written the next time you start Brave from the menu (launch.sh)."
else
    warn "Profile settings only partly applied: ${out//$'\n'/, }"
fi

ok "Brave config applied — close Brave and start it again from the menu."
