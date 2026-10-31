import { readFileSync } from "node:fs";
const values = Object.fromEntries(
  readFileSync(".dev.vars", "utf8")
    .split(/\r?\n/)
    .flatMap((l) => {
      const m = l.match(/^([A-Z_]+)=(.*)$/);
      if (!m) return [];
      return [[m[1], m[2].startsWith('"') ? JSON.parse(m[2]) : m[2]]];
    }),
);
const base =
  process.env.VIA_API_URL || "https://via-tracker-api.junxuan-bao.workers.dev";
const command = process.argv[2] || "refresh";
if (!["refresh", "apns-probe"].includes(command))
  throw Error("Unsupported operation");
const r = await fetch(`${base}/internal/${command}`, {
  method: "POST",
  headers: { authorization: `Bearer ${values.OPS_TOKEN}` },
});
console.log(r.status, await r.text());
if (!r.ok) process.exitCode = 1;
