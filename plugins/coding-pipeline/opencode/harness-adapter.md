# OpenCode Harness Adapter — Phase 0 Spike Findings

**Status:** Phase 0 complete. These findings are the contract the rest of the OpenCode harness feature is written against. Do not design PR 1/2/3 against the original plan's assumptions where this doc disagrees with them — this doc wins.

**Method:** live testing against the installed binary (`opencode 1.18.23`, `@opencode-ai/plugin` / `@opencode-ai/sdk` `1.17.15`) in a throwaway `XDG_CONFIG_HOME`, plus static inspection of the installed SDK's `.d.ts` files. Every finding below was reproduced against the running binary unless marked otherwise.

## S1 — Can `tool.execute.before` abort a call, and does the message surface? **PASS**

A plugin's `"tool.execute.before"` hook that `throw`s an `Error` aborts the tool call. The thrown message lands in the tool result's `error` field and the model sees and reports it — confirmed via a live `opencode run` where a `read` of a sentinel file was blocked and the model's final answer quoted the thrown message instead of the file's real content.

```json
{"type":"tool","tool":"read","state":{"status":"error","input":{"filePath":"/tmp/devkit-sentinel.txt"},"error":"DEVKIT_SENTINEL_BLOCKED: this read was blocked by the spike guard."}}
```

**Consequence:** the four blocking guards (`env-guard.sh`, `destructive-guard.sh`, `secret-write-guard.sh`, `dispatch-budget.sh`) are wired through `tool.execute.before`, throwing on exit 2, exactly as the revised plan (B1/B2) specified. No fallback to `permission.ask` is needed.

## S2 — Does a skill under `skills/<name>/SKILL.md` get a free `/name` slash command? **FAIL**

The skill was correctly auto-registered and visible via `opencode debug skill`, but it did **not** appear when the model was asked to list every slash command it knows. `SkillV2Info` has no `slash` field set from a plain directory skill in this install.

**Consequence:** PR 1 must still generate commands — but see S5, which changes *how*.

## S3 — Is `disable-model-invocation: true` honored? **FAIL**

A skill with `disable-model-invocation: true` in its frontmatter and an explicit trigger phrase was still invoked unprompted by the model when the trigger phrase appeared in the user's message — confirmed via a live `tool_use` event calling the `skill` tool with `{"name":"devkit-spike-skill"}`.

**Consequence:** the devkit's manual-skill rule ("skills never call skills; only the user starts one") is **unenforceable under OpenCode as installed**. This is a documented parity gap, not something PR 1 can work around — there is no flag to flip. Record in the parity matrix: "Manual-skill invocation — gap, OpenCode auto-invokes on trigger phrases regardless of the flag."

## S4 — Is `<config>/AGENTS.md` loaded as a global instruction with no `opencode.json` edit? **PASS**

A sentinel line placed in `<XDG_CONFIG_HOME>/opencode/AGENTS.md`, with no corresponding entry added to `opencode.json`'s `instructions` array, was loaded into the session — confirmed by the model echoing the sentinel value back exactly as instructed by the file's content, while `opencode debug config`'s resolved `instructions` array showed only the pre-existing unrelated entry, never AGENTS.md itself (it is loaded by convention, not by being listed).

**Consequence:** the installer **never** needs to write to `opencode.json` for standards wiring. Drop the JSONC-merge idea (B8) entirely for this purpose.

## S5 — `command/` vs `commands/` directory, and does `$ARGUMENTS` work? **Directory convention FAILS; config-based commands PASS and `$ARGUMENTS` works**

Markdown files dropped into either `<config>/opencode/command/<name>.md` or `<config>/opencode/commands/<name>.md` were **not** picked up as slash commands by the model (neither name appeared when asked to list every slash command).

Instead, commands are **entries inside `opencode.json` itself**, matching the SDK's `Config.command: { [name]: { template, description, agent?, model?, subtask? } }` shape. A command added this way — `"command": {"spike-test": {"template": "... $ARGUMENTS ...", "description": "..."}}` — worked correctly when invoked via `opencode run --command spike-test "hello world"`: the template loaded, and `$ARGUMENTS` was substituted with the CLI-supplied text (model-mediated interpolation, not literal shell substitution, but the argument text reliably reaches the template).

**Consequence — this changes PR 1's design, not just a path name:**
- Drop `command/<name>.md` as a generated file format entirely.
- `generate-opencode.py` must instead emit (or the installer must merge) a `"command"` object into the *generated* `<target>/.../opencode.json`-equivalent — but S4 already established the installer should not touch the operator's real `opencode.json`. Resolution: generate a **separate, self-contained** `opencode.json` fragment (e.g. `<devkit>/commands.json`) and print it for the operator to merge by hand, exactly like the Codex adapter's `[agents]` snippet precedent (`generate-codex-agents.sh:127-136`) — never write to the operator's own config.
- Alternatively, and preferably: skip command generation altogether for PR 1, since skills are already manually invokable by name via the `skill` tool and by asking the model to use them; commands are a convenience layer OpenCode does not make free, and generating them requires touching the one file the installer is contracted not to touch. Document this as a deliberate scope cut, not a silent omission.

## S6 — Can a plugin tool create and wait on a child session? **FAIL as originally designed; inconclusive on the fallback path**

- `PluginInput.serverUrl` resolves to the SDK's hardcoded default `http://localhost:4096/`, **not** the real listening address of the running `opencode run` process. Confirmed live: a plugin tool that read `ctx.serverUrl` got back `http://localhost:4096/` verbatim.
- Constructing a **new** v2 client (`createOpencodeClient` from `@opencode-ai/sdk/v2`) against that URL fails with `ConnectionRefused` — confirmed live, reproducibly, across multiple runs.
- The real `opencode run` process does listen on *some* local port (observed once via `ss` as a high ephemeral port, e.g. `127.0.0.1:49374`), but this is not exposed to the plugin through any documented `ctx` field or environment variable found in the SDK sources.
- Whether the **pre-built** `ctx.client` (the v1 client OpenCode itself constructs and hands to the plugin, as opposed to a client the plugin constructs itself) can successfully call `session.create` / `session.prompt` / `session.wait` was **not cleanly confirmed** — test runs attempting this were disrupted by environment instability (see Operational note below) before a clean result was captured.

**Consequence:** the orchestrator's original design — construct a v2 client from `ctx.serverUrl` — is confirmed broken, not just risky. **PR 3 (parallel `/code` orchestrator) is cut from the initial feature.** Before ever attempting it again: retest whether `ctx.client` (the pre-wired one, not a self-constructed one) can drive `session.create`/`session.wait`, in a session that is not itself the one being tested against. Until then, `harness-adapter.md`'s parity matrix records: "Parallel `/code` worktrees — not implemented; `ctx.serverUrl` does not resolve to a reachable server from inside a plugin tool in the installed SDK version, and the pre-wired client path is unverified."

## Operational note — do not kill `opencode` processes while testing from inside an OpenCode session

Mid-spike, this investigation's own tooling runs *inside* an OpenCode session. Running `pkill -9 -f opencode` to clear a suspected stale background server killed the investigation's own process tree and caused the whole session to restart, twice. **Any future live testing against a real `opencode` binary must target PIDs individually (never a blanket `pkill -f opencode`), and should prefer a fully separate machine or container over this workstation's primary session.**

## Revised scope for PR 1 (static generation)

Given S2/S3/S5 above, PR 1's scope is:
- Generate `skills/<name>/SKILL.md` + `references/*.md` for all four plugins — unaffected by any finding above.
- Generate `agents/<name>.md` with `mode`, `tools`, `permission` (singular), `model` — unaffected.
- Generate `<devkit>/AGENTS.md` from canonical `CLAUDE.md` — confirmed sufficient on its own (S4); no `opencode.json` edit.
- **Do not** generate `command/<name>.md` files (S5 proves the directory convention is inert).
- **Do** print a manual-merge `command` JSON snippet as an optional, clearly-labeled extra for operators who want slash-command parity — never written automatically.
- Document S3's gap in the parity matrix; do not claim the manual-skill rule holds under OpenCode.

## Revised scope for PR 2 (sensor bridge plugin)

Unaffected by S2–S6; S1 confirms the core mechanism (`tool.execute.before` abort-by-throw) that every blocking guard depends on. Proceed as planned.

## Revised scope for PR 3 (parallel orchestrator)

**Cut from this feature's first delivery.** Re-spike `ctx.client` (not a self-constructed client) against `session.create`/`session.prompt`/`session.wait` in a disposable environment before resuming this work. Until re-verified, `/code`'s parallel mode is documented as unavailable under OpenCode, exactly as the original plan's own fallback language anticipated (§9's closing line: "the rest of the feature does not depend on it").

## D2 — `coding-pipeline` is a required install, not just the primary one

All 12 generated agents are sourced from `coding-pipeline`'s flat `agents/` directory; `engineering`,
`pr-workflow` and `devtools` ship skills of their own but no agents. Consequence: for those three
plugins' skills to have a working agent to dispatch under OpenCode, `coding-pipeline` must be
installed into the same OpenCode config target first (or alongside them) — this is a documented
requirement an operator must satisfy, not a check `install-opencode.sh` enforces or warns about at
install time.
