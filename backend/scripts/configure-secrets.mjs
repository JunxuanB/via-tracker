import { readFileSync, writeFileSync, renameSync } from "node:fs";
import { randomBytes } from "node:crypto";
const [keyPath, teamID, keyID] = process.argv.slice(2);
if (!keyPath || !teamID || !keyID)
  throw new Error(
    "Usage: node scripts/configure-secrets.mjs /path/AuthKey.p8 TEAM_ID KEY_ID",
  );
const key = readFileSync(keyPath, "utf8");
if (!key.includes("BEGIN PRIVATE KEY"))
  throw new Error("Expected an APNs PKCS8 .p8 key");
let existing = {};
try {
  existing = Object.fromEntries(
    readFileSync(".dev.vars", "utf8")
      .split(/\r?\n/)
      .flatMap((line) => {
        const m = line.match(/^([A-Z_]+)=(.*)$/);
        if (!m) return [];
        return [
          [
            m[1],
            m[2].startsWith('"')
              ? JSON.parse(m[2])
              : m[2].replace(/^'|'$/g, ""),
          ],
        ];
      }),
  );
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
const values = {
  ...existing,
  APNS_TEAM_ID: teamID,
  APNS_KEY_ID: keyID,
  APNS_PRIVATE_KEY: key,
  OPS_TOKEN: existing.OPS_TOKEN || randomBytes(32).toString("hex"),
  APNS_PROXY_URL: existing.APNS_PROXY_URL || "",
};
writeFileSync(
  ".dev.vars.tmp",
  Object.entries(values)
    .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
    .join("\n") + "\n",
  { mode: 0o600 },
);
renameSync(".dev.vars.tmp", ".dev.vars");
console.log("Updated .dev.vars (0600). No secret values were logged.");
