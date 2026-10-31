import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
const source = process.argv[2] || ".dev.vars";
const values = {};
for (const line of readFileSync(source, "utf8").split(/\r?\n/)) {
  const m = line.match(
    /^(APNS_TEAM_ID|APNS_KEY_ID|APNS_PRIVATE_KEY|OPS_TOKEN)=(.*)$/,
  );
  if (!m) continue;
  let value = m[2];
  if (value.startsWith('"')) value = JSON.parse(value);
  else if (value.startsWith("'")) value = value.slice(1, -1);
  if (value) values[m[1]] = value;
}
if (!values.APNS_TEAM_ID || !values.APNS_KEY_ID || !values.APNS_PRIVATE_KEY)
  throw new Error("Expected APNS_TEAM_ID, APNS_KEY_ID and APNS_PRIVATE_KEY");
const result = spawnSync("npx", ["wrangler", "secret", "bulk"], {
  input: JSON.stringify(values),
  encoding: "utf8",
  stdio: ["pipe", "inherit", "inherit"],
});
process.exitCode = result.status ?? 1;
