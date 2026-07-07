# PR Dashboard

A zero-build board that shows GitHub PRs grouped like a projects board:

| Draft | Needs review | Reviewed / Approved | Merged (last 2 wks) | Closed (last 2 wks) |
|-------|--------------|---------------------|---------------------|---------------------|

Each PR is a tile linking to GitHub, with repo, author, diff size, labels, comment count and review status.

## Requirements

- **Node.js** 18+ (for the local server's built-in `fetch`)
- **GitHub CLI** (`gh`), logged in: `gh auth login`

No personal access token to manage — the server reuses your existing `gh` authentication.

## Run

```bash
./start.sh        # start the server and open the dashboard
./stop.sh         # stop the server
```

`start.sh` checks prerequisites, (re)starts the server, waits until it's live, then opens
`http://localhost:4321` in your browser. Run it again any time to restart cleanly.

Custom port:

```bash
PORT=8080 ./start.sh
PORT=8080 ./stop.sh
```

Logs go to `server.log` (`tail -f server.log`).

## Use

1. Your own PRs load by default.
2. **Add user** — track teammates' PRs too; remove with the `×` on each chip.
3. **Orgs** — toggle the org pills to filter which organizations' PRs are shown.
4. **Theme** — pick from 10 themes in the top bar.

Your user list, org filter, and theme persist in the browser's `localStorage`.

## How it works

- **`server.js`** — a tiny zero-dependency Node server. It reads your token from `gh auth token`
  at startup and proxies GraphQL requests to `api.github.com`. The token never reaches the browser.
- **`index.html`** — the whole UI (markup, styles, logic) in one file. It calls the local
  `/api/graphql` proxy, so no credentials live client-side.

## Notes

- **Columns:** open PRs are split by review state; merged/closed columns only show the last 14 days.
- **Refresh:** auto-refreshes every 5 minutes; the *Refresh* button forces an immediate reload.
- **One request per user:** each tracked user is fetched in a separate parallel request (batching
  them into one query makes GitHub's GraphQL time out with a 502). A user with too many PRs to fetch
  at once is retried with a smaller page size, and a single failing user won't blank the whole board.
- **Targets github.com.** To point at GitHub Enterprise, change the GraphQL endpoint in `server.js`
  to your host's `/api/graphql` (and authenticate `gh` against that host).
