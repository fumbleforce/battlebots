# B-08b — post-match results and rematch

Owner B; branch codex/b-match-results; dependency d983612 (B match HUD).
Intent: reusable results screen using session_event("results") participant stats;
rematch request via public vote_rematch(), explicit leave, and automatic return
to lobby when the authoritative phase changes. Never infer vote acceptance.
B reserves results UI/presentation, independent fixtures/tests, and lobby_game
integration. No A-owned runtime or protocol changes planned. F5 remains A-owned.
Acceptance: malformed/missing/stale result handling, actual two-peer full match
and rematch through UI, phase-gated requests and neutral gameplay under results.
