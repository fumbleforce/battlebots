# Shared contracts — owner A; changes reviewed with B

Read docs/CONTRACTS.md from the repository root. No networking serialization is
implemented yet. BotCommand, BotView and BotSource are the only current runtime
interfaces. Extend these deliberately rather than coupling UI to physics internals.
