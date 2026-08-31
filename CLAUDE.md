# claude-devkit — Project Memory

This repository **is** the claude-devkit. The engineering standards live in exactly one file —
[`plugins/coding-pipeline/CLAUDE.md`](plugins/coding-pipeline/CLAUDE.md) — which is what
`scripts/install-global.sh` ships to `~/.claude/devkit/CLAUDE.md`.

**They are deliberately not `@`-imported here.** Anyone who installed the devkit already has that
same file imported globally, so importing it again would load ~6.5k tokens of identical content
twice in every session spent working on the devkit itself — and the standards' own first rule is
that an addition must earn its tokens.

If you are contributing here **without** the devkit installed, install it (`bash install.sh`) or
read `plugins/coding-pipeline/CLAUDE.md` directly — it is the contract this repo is built to.
