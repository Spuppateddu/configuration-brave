# Brave's own shortcut table (brave://settings/system/shortcuts): command id → keys.
# Adds the Firefox keys next to Brave's defaults. "Meta" is the Super key.
def add($id; $key): .[$id] = ((.[$id] // []) - [$key] + [$key]);
def drop($id; $key): .[$id] = ((.[$id] // []) - [$key]);

def keybindings: .brave.accelerators |= (
    add("34016"; "Meta+KeyK")        # next tab
  | add("34017"; "Meta+KeyJ")        # previous tab
  | add("33000"; "Meta+KeyH")        # back
  | add("33001"; "Meta+KeyL")        # forward
  | reduce range(1; 9) as $n (.; add("\(34017 + $n)"; "Meta+Digit\($n)"))   # tab 1..8
  | add("34026"; "Meta+Digit9")      # last tab
  # Ctrl+d duplicates the tab, as in Firefox, so it leaves "bookmark this tab".
  | drop("35000"; "Control+KeyD")
  | add("34027"; "Control+KeyD")
);
