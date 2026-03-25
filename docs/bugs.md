# Known Bugs

## Active

### Lyric/song mismatch
**Severity:** High
**Status:** Open

Lyrics sometimes don't match the currently playing song. Possible causes:

1. **Search returns wrong track** — LRCLIB and NetEase match by artist + track name, which can return a different version (live, remix, acoustic, remaster) or a completely different song from an artist with similar track names.
2. **Duration mismatch not enforced** — LRCLIB accepts a `duration` param but the search fallback (`/api/search?q=...`) doesn't filter by duration at all. NetEase has a 3s tolerance but that may be too loose.
3. **Cached stale lyrics** — If the user skips tracks quickly, a slow provider response could arrive after the track has already changed, and the cache stores lyrics under the wrong track ID.
4. **Track ID race condition** — SpotifyBridge polls every 0.5s. If a track change happens between a fetch starting and completing, the lyrics could be assigned to the new track.

**Potential fixes:**
- Always validate that the fetched lyrics' track matches the *current* track before displaying (compare track ID at fetch-start vs. fetch-complete)
- Enforce duration matching on search results (reject if >5s difference)
- Cancel in-flight fetch tasks immediately on track change (partially done but verify)
- Add a confidence score to provider results and prefer high-confidence matches
- Log which provider returned the lyrics so users can report which source is wrong
