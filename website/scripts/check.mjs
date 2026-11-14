// Static checks for the website: translation coverage, release version consistency and CSP hygiene.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => readFileSync(join(root, p), "utf8");
const html = read("public/index.html");
const js = read("public/app.js");
const llms = read("public/llms.txt");
const buildScript = readFileSync(join(root, "..", "script", "build_and_run.sh"), "utf8");
const failures = [];

const enBlock = js.slice(js.indexOf("const EN = {"), js.indexOf("};", js.indexOf("const EN = {")));
const enKeys = new Set([...enBlock.matchAll(/^\s{2}(\w+):/gm)].map((m) => m[1]));
for (const [, key] of html.matchAll(/data-i18n(?:-aria|-alt)?="(\w+)"/g)) {
  if (!enKeys.has(key)) failures.push(`missing English text for "${key}"`);
}

const version = buildScript.match(/^APP_VERSION="([^"]+)"/m)?.[1];
if (!version) failures.push("APP_VERSION not found in script/build_and_run.sh");
for (const [name, text] of [["index.html", html], ["app.js", js], ["llms.txt", llms]]) {
  for (const [, found] of text.matchAll(/v(\d+\.\d+\.\d+)/g)) {
    if (found !== version) failures.push(`${name} mentions v${found}, but the app version is ${version}`);
  }
}
const schemaVersion = html.match(/"softwareVersion": "([^"]+)"/)?.[1];
if (schemaVersion !== version) failures.push(`JSON-LD softwareVersion ${schemaVersion} != ${version}`);

for (const file of ["public/index.html", "public/404.html"]) {
  const text = read(file);
  if (/\sstyle="/.test(text)) failures.push(`${file}: inline style attribute (blocked by CSP)`);
  if (/<script(?![^>]*\bsrc=)(?![^>]*application\/ld\+json)[^>]*>/.test(text)) failures.push(`${file}: inline script (blocked by CSP)`);
}

if (failures.length) {
  console.error(failures.map((f) => `✗ ${f}`).join("\n"));
  process.exit(1);
}
console.log(`✓ ${enKeys.size} English strings cover every key; version ${version} consistent; no inline script/style`);
