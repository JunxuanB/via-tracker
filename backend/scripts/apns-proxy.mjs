// Local development only. Keep this bound to loopback; the deployed Worker talks to APNs directly.
import http from "node:http";
import http2 from "node:http2";
http
  .createServer((req, res) => {
    if (req.method !== "POST" || !req.url?.startsWith("/3/device/")) {
      res.writeHead(404).end();
      return;
    }
    const host =
      req.headers["x-apns-environment"] === "production"
        ? "api.push.apple.com"
        : "api.sandbox.push.apple.com";
    const client = http2.connect(`https://${host}`);
    client.on("error", () => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
      client.destroy();
    });
    const headers = { ":method": "POST", ":path": req.url };
    for (const key of [
      "authorization",
      "apns-topic",
      "apns-push-type",
      "apns-priority",
      "apns-expiration",
      "apns-collapse-id",
      "content-type",
    ])
      if (req.headers[key]) headers[key] = req.headers[key];
    const upstream = client.request(headers);
    upstream.setTimeout(12000, () => {
      upstream.close();
      client.destroy();
      if (!res.headersSent) res.writeHead(504);
      res.end();
    });
    upstream.on("response", (headers) =>
      res.writeHead(Number(headers[":status"]), {
        "content-type": "application/json",
      }),
    );
    upstream.on("error", () => {
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
    upstream.on("end", () => client.close());
    req.pipe(upstream);
    upstream.pipe(res);
  })
  .listen(8790, "127.0.0.1", () =>
    console.log("APNs HTTP/2 development proxy: http://127.0.0.1:8790"),
  );
