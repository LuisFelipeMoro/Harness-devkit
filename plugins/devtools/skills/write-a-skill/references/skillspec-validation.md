# SkillSpec validation — finding → fix map

SkillSpec (`skillspec doctor <skill-dir>`) scores **agent follow-through risk** (0 = best,
100 = worst): the chance an agent skips, reorders, improvises, uses the wrong surface, or
finishes without proof, given the skill's shape. Run it on every new skill and resolve the
actionable findings before declaring the skill done.

## Invocation

```bash
skillspec doctor plugins/<plugin>/skills/<name>     # human-readable findings + score
skillspec doctor plugins/<plugin>/skills/<name> --markdown   # report to a file
```

If `skillspec` is not installed or cannot execute, say so explicitly and skip — do not claim it passed. Fall back to `.github/scripts/validate-wiring.py`.

## Findings and how to fix them

| Finding (severity) | Fix in the SKILL.md |
|---|---|
| Frontmatter missing or malformed (CRITICAL) | Valid YAML between `---` fences; `name:` + one specific `description:` whose first clause names the main use case. |
| No machine-checkable behavior contract (HIGH) | Add explicit, enumerated **Inputs / Outputs / Steps** near the top — obligations a reader can check, not vague prose. |
| Dependencies are implicit (HIGH) | Name the tools/commands/agents the skill uses in the body (a short Dependencies list). |
| Most text loads at activation / dense prose (HIGH) | Move tables, templates, and long detail into `references/*`; keep the activation body lean (≤100 lines). |
| Code mixed into body / ambiguous fences (MEDIUM) | Label every ``` fence with a language; move large code/examples to `references/`. |
| Late load-bearing instructions (MEDIUM) | Lift critical rules toward the top of the body. |
| Runtime success unproven (MEDIUM) | State a clear completion/proof criterion for any action the skill performs. |

## Loop

1. `skillspec doctor` → read findings.
2. Apply fixes for CRITICAL/HIGH (and resolvable MEDIUMs) **without changing what the skill does**.
3. Re-run; repeat until the score stops improving.
4. Justify in one line any finding left unresolved (e.g. a structural MEDIUM the tool always leaves).

> Note: the deep `skill.spec.yml` contract route drives the score lowest, but it adds
> tool-only scaffolding Claude never reads. For a skill meant to ship in a plugin, prefer
> fixing the SKILL.md itself (above) over committing SkillSpec workspace files.
