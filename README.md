# configuration-brave

Brave set up like the Firefox config: the same keys, a smaller top bar, and only
three extensions. Brave keeps its **default fonts** — nothing here sets a font.

## Install

```bash
./install.sh                                # asks which extensions, and for sudo once (the policy file)
./install.sh --extensions=vimium,bitwarden  # exactly these (or all / none), no question
./install.sh --dry-run                      # show what it would do
```

The extensions to pick from are in `extensions.conf` (all three ticked by
default). Your answer is kept in `~/.cache/brave-config/extensions`, and a run
with no terminal (boot) uses it — it never re-adds one you unticked. Unticking
never uninstalls: remove it from the browser's extensions page. From
best-linux-environment's `./setup.sh`, the list is asked there instead, and only
when you tick the browser.

It does not install Brave. Get it with best-linux-environment:
`./setup.sh only brave`. Safe to re-run; an unchanged file is not touched.

Then **close Brave and start it again from the menu** (rofi). The menu entry is
what applies the smaller UI and the settings.

## What you get

| | How |
|---|---|
| Super+k / Super+j — next / previous tab | Brave's own shortcuts |
| Super+h / Super+l — back / forward | Brave's own shortcuts |
| Super+1 … Super+8 — tab 1..8, Super+9 — last tab | Brave's own shortcuts |
| Ctrl+d — duplicate the tab (instead of "bookmark") | Brave's own shortcuts |
| Smaller top bar: 137px → 108px | `launch.sh` starts Brave with `--force-device-scale-factor=0.8` |
| Pages keep their normal size | default zoom set to 125% (= 1 / 0.8) |
| Address bar shows the full URL, `https://` included | profile pref |
| Blank new tab page | profile pref |
| No "Restore pages?" bubble after a reboot | profile pref |
| No Rewards, Wallet, VPN or Leo AI (and no buttons for them) | policy |
| No password manager, autofill, P3A, stats ping, web discovery, metrics, prefetch | policy |
| Brave never asks to be the default browser | policy |
| Vimium, Bitwarden, Wappalyzer (+ Keepa, opt-in) — installed and pinned | policy |
| Vimium's hint/vomnibar colours, same as Firefox | `vimium-settings.json` |

The keys are Brave's own shortcuts (brave://settings/system/shortcuts), so they
work everywhere: on `brave://` pages, the new tab, and with the address bar
focused. You can see and change them on that settings page.

Brave shows "Managed by your organization" in its menu. That is the policy file
at `/etc/brave/policies/managed/brave-config.json`; nobody else manages it.

## The UI scale

`BRAVE_UI_SCALE` (default `0.8`) sets how big Brave's own UI is. To change it on
one machine:

```bash
cp brave.local.example brave.local   # git-ignored
# edit BRAVE_UI_SCALE, e.g. 0.75 for an even smaller bar
```

Restart Brave from the menu. The default zoom follows the scale by itself.

## Files

| File | What it is |
|---|---|
| `install.sh` | writes the policy, the menu entry, installs classic-level, applies the profile |
| `launch.sh` | what the menu entry runs: applies the profile if Brave is closed, then starts it scaled |
| `keybindings.jq` | the Firefox keys, added to Brave's shortcut table |
| `extensions.conf` | the three extension IDs |
| `vimium-settings.json` | Vimium's CSS; `unmap <c-d>` so Ctrl+d reaches Brave |
| `vimium-sync.mjs` | writes that JSON into Brave's storage for Vimium (a LevelDB) |
| `brave.local.example` | the per-machine UI scale |

## What Firefox has and Brave can't

- **Hiding the whole toolbar** (Ctrl+Shift+B in Firefox) — Brave only hides it in fullscreen (F11).
- **The tab list in the window title** — an extension can't change Brave's window title.
- **One zoom for all sites** — Brave always remembers zoom per site.

## When things change

- Profile settings are written only while Brave is closed: Brave rewrites that
  file when it exits. `launch.sh` does it at every start, `install.sh` when you
  run it with Brave closed.
- On a brand-new profile the keys arrive on the **second** start: Brave builds
  its shortcut table on the first one, and the keys are added to that table.
