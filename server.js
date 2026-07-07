#!/usr/bin/env node
// PR Dashboard server — zero dependencies.
//
// Two modes, chosen automatically:
//   • Hosted mode  — when GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET are set (a GitHub
//                    OAuth App). Anyone visits the URL, clicks "Sign in with GitHub",
//                    approves, and gets their own per-session token. Use this to host
//                    the dashboard for others (e.g. on an EC2 free-tier box).
//   • Local mode   — when those env vars are absent. Falls back to your `gh` CLI token
//                    (single user); the original local-only behaviour, unchanged.
//
// The GraphQL proxy uses the signed-in user's session token (hosted) or the gh token
// (local). The browser never sees a token, and the client secret never leaves the server.
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execSync } = require("child_process");

const PORT = process.env.PORT || 4321;
const CLIENT_ID = process.env.GITHUB_CLIENT_ID || "";
const CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET || "";
const SCOPES = process.env.OAUTH_SCOPES || "read:user repo read:org";
const REDIRECT_OVERRIDE = process.env.OAUTH_REDIRECT_URI || ""; // set if a proxy rewrites Host
const OAUTH = !!(CLIENT_ID && CLIENT_SECRET);

let GH_TOKEN = "";
if (!OAUTH) {
  try {
    GH_TOKEN = execSync("gh auth token", { encoding: "utf8" }).trim();
  } catch {
    console.error("Not in hosted mode (no GITHUB_CLIENT_ID/SECRET) and `gh auth token` failed.\n" +
      "Set the OAuth env vars to enable GitHub login, or run `gh auth login` for local single-user mode.");
    process.exit(1);
  }
}

const HTML = fs.readFileSync(path.join(__dirname, "index.html"));
const sessions = new Map();      // sid   -> { token, login, avatar }
const pendingStates = new Map(); // state -> expiry (ms) — CSRF guard for the OAuth redirect
const UA = "pr-dashboard";

const parseCookies = (req) => {
  const out = {};
  (req.headers.cookie || "").split(";").forEach((c) => {
    const i = c.indexOf("=");
    if (i > 0) out[c.slice(0, i).trim()] = decodeURIComponent(c.slice(i + 1).trim());
  });
  return out;
};
const isHttps = (req) => (req.headers["x-forwarded-proto"] || "").split(",")[0].trim() === "https";
const baseUrl = (req) => `${isHttps(req) ? "https" : "http"}://${req.headers["x-forwarded-host"] || req.headers.host}`;
const redirectUri = (req) => REDIRECT_OVERRIDE || baseUrl(req) + "/callback";
function setCookie(res, name, value, { maxAge, secure } = {}) {
  const parts = [`${name}=${value}`, "Path=/", "HttpOnly", "SameSite=Lax"];
  if (maxAge != null) parts.push(`Max-Age=${maxAge}`);
  if (secure) parts.push("Secure");
  const prev = res.getHeader("Set-Cookie") || [];
  res.setHeader("Set-Cookie", [...(Array.isArray(prev) ? prev : [prev]), parts.join("; ")]);
}
const redirect = (res, loc) => { res.writeHead(302, { Location: loc }); res.end(); };
const json = (res, code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
const sessionFor = (req) => { const sid = parseCookies(req).sid; return sid ? sessions.get(sid) : null; };

// prune expired OAuth states occasionally so the map can't grow unbounded
function sweepStates() { const now = Date.now(); for (const [k, exp] of pendingStates) if (exp < now) pendingStates.delete(k); }

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, baseUrl(req));
  const p = url.pathname;

  // Tells the frontend which mode we're in and who (if anyone) is signed in.
  if (p === "/api/config") {
    if (!OAUTH) return json(res, 200, { oauth: false, authenticated: true });
    const s = sessionFor(req);
    return json(res, 200, { oauth: true, authenticated: !!s, user: s ? { login: s.login, avatar: s.avatar } : null });
  }

  // Start the OAuth flow.
  if (p === "/login" && OAUTH) {
    sweepStates();
    const state = crypto.randomBytes(16).toString("hex");
    pendingStates.set(state, Date.now() + 10 * 60 * 1000);
    setCookie(res, "oauth_state", state, { maxAge: 600, secure: isHttps(req) });
    const a = new URL("https://github.com/login/oauth/authorize");
    a.searchParams.set("client_id", CLIENT_ID);
    a.searchParams.set("redirect_uri", redirectUri(req));
    a.searchParams.set("scope", SCOPES);
    a.searchParams.set("state", state);
    return redirect(res, a.toString());
  }

  // OAuth redirect target: verify state, exchange code for a token, open a session.
  if (p === "/callback" && OAUTH) {
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const cookieState = parseCookies(req).oauth_state;
    if (!code || !state || state !== cookieState || !pendingStates.has(state)) {
      res.writeHead(400); return res.end("Sign-in check failed — please try again.");
    }
    pendingStates.delete(state);
    try {
      const tr = await fetch("https://github.com/login/oauth/access_token", {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json", "User-Agent": UA },
        body: JSON.stringify({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET, code, redirect_uri: redirectUri(req) }),
      });
      const token = (await tr.json()).access_token;
      if (!token) { res.writeHead(400); return res.end("Sign-in failed (token exchange)."); }
      const u = await (await fetch("https://api.github.com/user", { headers: { Authorization: "bearer " + token, "User-Agent": UA } })).json();
      const sid = crypto.randomBytes(24).toString("hex");
      sessions.set(sid, { token, login: u.login, avatar: u.avatar_url });
      setCookie(res, "sid", sid, { maxAge: 7 * 24 * 3600, secure: isHttps(req) });
      setCookie(res, "oauth_state", "", { maxAge: 0, secure: isHttps(req) });
      return redirect(res, "/");
    } catch (e) {
      res.writeHead(502); return res.end("Sign-in error: " + e.message);
    }
  }

  if (p === "/logout") {
    const sid = parseCookies(req).sid;
    if (sid) sessions.delete(sid);
    setCookie(res, "sid", "", { maxAge: 0, secure: isHttps(req) });
    return redirect(res, "/");
  }

  // GraphQL proxy — token comes from the session (hosted) or the gh CLI (local).
  if (req.method === "POST" && p === "/api/graphql") {
    let token = GH_TOKEN;
    if (OAUTH) {
      const s = sessionFor(req);
      if (!s) return json(res, 401, { errors: [{ message: "not authenticated" }] });
      token = s.token;
    }
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", async () => {
      try {
        const r = await fetch("https://api.github.com/graphql", {
          method: "POST",
          headers: { Authorization: "bearer " + token, "Content-Type": "application/json", "User-Agent": UA },
          body,
        });
        const text = await r.text();
        const headers = { "Content-Type": "application/json" };
        for (const h of ["retry-after", "x-ratelimit-remaining", "x-ratelimit-reset"]) {
          const v = r.headers.get(h);
          if (v != null) headers[h] = v;
        }
        res.writeHead(r.status, headers);
        res.end(text);
      } catch (e) {
        json(res, 502, { errors: [{ message: String(e) }] });
      }
    });
    return;
  }

  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(HTML);
});

server.listen(PORT, () =>
  console.log(`PR Dashboard on http://localhost:${PORT}  (${OAUTH ? "GitHub sign-in enabled" : "local gh-token mode"})`)
);
