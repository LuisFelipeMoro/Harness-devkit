# Stack Detection

Detection command (stop at first match per stack; multi-language monorepos match all):

```bash
find . -maxdepth 2 -name "go.mod" -o -name "Cargo.toml" -o -name "pom.xml" \
  -o -name "build.gradle" -o -name "package.json" -o -name "composer.json" \
  -o -name "tsconfig.json" -o -name "pubspec.yaml" 2>/dev/null
```

| File | Stack |
|------|-------|
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` / `build.gradle*` | Java |
| `package.json` + `tsconfig.json` + `next.config.*` | Next.js |
| `package.json` + `tsconfig.json` + `"react"` in deps | React |
| `package.json` + `tsconfig.json` | TypeScript |
| `composer.json` | PHP |
| `pubspec.yaml` | Flutter |
| `build.gradle.kts` + `android {}` | Kotlin Android |

For the gate commands per stack, see `references/quality-gate-reference.md`.
