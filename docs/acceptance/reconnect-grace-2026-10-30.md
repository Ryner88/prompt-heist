# Reconnect grace and browser return — 2026-10-30

The release branch includes [PR #25](https://github.com/Ryner88/prompt-heist/pull/25), which reserves a disconnected seat for two minutes, and [PR #26](https://github.com/Ryner88/prompt-heist/pull/26), which retries recovery once when a backgrounded Web game becomes visible again. PR #26 merged at `1923cf7`. Both PRs passed protocol, Godot, and container CI; PR #26 also passed review after its two findings were addressed.

| Check | Result |
| --- | --- |
| Two-minute boundary | Node tests pass at 119,999 ms and expire at 120,000 ms. All 63 Node tests passed. |
| Public grace past old cutoff | Against `wss://prompt-heist-pni7.onrender.com/ws`, a seat resumed after 38.3 seconds with the same player ID and a rotated token. |
| Local hidden/visible tab | A 390×844 Chromium touch viewport made no recovery request while hidden. On visibility, it resumed the same room and player with a rotated token; zero page errors. |
| Local duplicate tab | A second Chromium tab with copied recovery storage opened no socket after focus/visibility events. The original socket stayed open. |
| Expired seat | A Godot regression test confirms a rejected recovery clears the token, explains expiry, and returns to Create/Join. Godot tests and mobile UI smoke passed. |
| Public hidden/visible tab | After the public Web package changed following the release merge, a 390×844 Chromium session created a room over HTTPS/WSS. Closing its socket while hidden caused no resume; showing the tab recovered the same room and player with a rotated token and zero page errors. |

These browser checks simulated background visibility and socket loss in Chromium. A physical phone and switching between separate browser apps still need a user retest. Recovery credentials are held in the original browser tab's session storage; another browser app cannot automatically reclaim that private seat. The room remains in server memory, so a service restart still clears it.
