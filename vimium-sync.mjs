// Writes vimium-settings.json into Chrome's storage for Vimium (a LevelDB).
// Usage: node vimium-sync.mjs <leveldb dir> <settings.json>  → prints unchanged|written
import { readFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";

// classic-level lives in the cache dir install.sh sets up, not in this repo.
const require = createRequire(process.env.BLE_CHROME_NODE_MODULES + "/");
const { ClassicLevel } = require("classic-level");

const [dir, src] = process.argv.slice(2);
const want = JSON.parse(readFileSync(src, "utf8"));

// Chrome keeps one row per setting: the key as is, the value JSON-encoded.
mkdirSync(dir, { recursive: true });
const db = new ClassicLevel(dir, { keyEncoding: "utf8", valueEncoding: "utf8" });
await db.open();

const changes = [];
for (const [key, value] of Object.entries(want)) {
  const current = await db.get(key).catch(() => undefined);
  const next = JSON.stringify(value);
  if (current !== next) changes.push({ type: "put", key, value: next });
}
// Other keys (marks, exclusion rules you set by hand) are left alone.
if (changes.length) await db.batch(changes);
await db.close();
console.log(changes.length ? "written" : "unchanged");
