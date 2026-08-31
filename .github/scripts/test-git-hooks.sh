#!/usr/bin/env bash
# Behaviour tests for the git-hook Sensors (pre-commit / pre-push).
#
# CI already runs shellcheck and `bash -n` over these files, which proves they
# parse — not that they gate. Two defect classes survive a syntax check and are
# what this suite exists for:
#
#   1. Stack misrouting. A project matched by the wrong block runs another
#      stack's tools and never reaches its own.
#   2. A gate that prints a number it never compares, or that skips silently when
#      the number cannot be read. Both render as a pass, which is worse than
#      having no gate at all — the absence is at least visible.
#
# Every external the hooks shell out to is stubbed, so a case exercises the
# hook's own logic and never the machine's toolchain.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$ROOT/plugins/coding-pipeline/git-hooks"
WORK="${TMPDIR:-/tmp}/devkit-githook-tests"
fail=0
pass=0

rm -rf "$WORK"

# fixture <name> — fresh directory with every external stubbed to a silent
# success. A case overwrites the specific stub whose output it is testing.
fixture() {
    local dir="$WORK/$1" bin
    bin="$dir/.stub-bin"
    mkdir -p "$bin"
    for t in cargo cargo-audit cargo-tarpaulin composer mvn npx npm flutter lcov dart go govulncheck \
             golangci-lint ktlint; do
        printf '#!/bin/sh\nexit 0\n' > "$bin/$t"
        chmod +x "$bin/$t"
    done
    printf '#!/bin/sh\nexit 0\n' > "$dir/gradlew"
    chmod +x "$dir/gradlew"
    printf '%s' "$dir"
}

run_hook() {        # run_hook <hook> <fixture-dir> — echoes output, returns exit code
    local hook="$1" dir="$2"
    ( cd "$dir" && PATH="$dir/.stub-bin:$PATH" bash "$HOOKS/$hook" 2>&1 )
}

expect_exit() {     # expect_exit <name> <hook> <fixture-dir> <want-exit>
    local name="$1" hook="$2" dir="$3" want="$4" got
    run_hook "$hook" "$dir" >/dev/null 2>&1; got=$?
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL: $name — $hook exited $got, expected $want"
        fail=1
    fi
}

expect_says() {     # expect_says <name> <hook> <fixture-dir> <yes|no> <substring>
    local name="$1" hook="$2" dir="$3" want="$4" needle="$5" out saw
    out="$(run_hook "$hook" "$dir")"
    case "$out" in *"$needle"*) saw=yes ;; *) saw=no ;; esac
    if [ "$saw" = "$want" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL: $name — expected '$needle' present=$want, got present=$saw"
        fail=1
    fi
}

# ── Gradle routing: `android {}` may live in either DSL ──────────────────────
# Checking only build.gradle sends a Kotlin-DSL Android project down the Java
# branch, where `jacocoTestReport` is not even a registered task.
d="$(fixture kts-android)"
printf 'android {\n}\n' > "$d/build.gradle.kts"
mkdir -p "$d/build/reports/kover"
printf '<report name="app"><counter type="LINE" missed="5" covered="95"/></report>\n' \
    > "$d/build/reports/kover/report.xml"
expect_says "kts android reaches kotlin gates"  pre-push   "$d" yes "Kotlin Android"
expect_says "kts android skips java gates"      pre-push   "$d" no  "Java/Gradle"
expect_says "kts android reaches detekt"        pre-commit "$d" yes "Kotlin: detekt"
expect_says "kts android skips checkstyle"      pre-commit "$d" no  "Java/Gradle: checkstyle"

d="$(fixture groovy-android)"
printf 'android {\n}\n' > "$d/build.gradle"
mkdir -p "$d/build/reports/kover"
printf '<report name="app"><counter type="LINE" missed="5" covered="95"/></report>\n' \
    > "$d/build/reports/kover/report.xml"
expect_says "groovy android still routes to kotlin" pre-push "$d" yes "Kotlin Android"

d="$(fixture plain-gradle)"
printf 'plugins { id "java" }\n' > "$d/build.gradle"
mkdir -p "$d/build/reports/jacoco/test"
printf 'GROUP,PACKAGE,CLASS,IM,IC,BM,BC,LINE_MISSED,LINE_COVERED\napp,x,Foo,1,9,0,0,5,95\n' \
    > "$d/build/reports/jacoco/test/jacocoTestReport.csv"
expect_says "non-android gradle routes to java" pre-push "$d" yes "Java/Gradle"
expect_says "non-android gradle skips kotlin"   pre-push "$d" no  "Kotlin Android"

# ── Coverage gates must be able to fail ─────────────────────────────────────
# Each language: one run below its declared minimum, one at or above it, and —
# where the number is parsed out of tool output — one where it cannot be read.
# The unreadable case is the one that silently passed before.

# Rust ≥ 85%
d="$(fixture rust-low)"
printf '[package]\nname = "x"\n' > "$d/Cargo.toml"
printf '#!/bin/sh\n[ "$1" = tarpaulin ] && echo "70.00%% coverage, 7/10 lines covered"\nexit 0\n' \
    > "$d/.stub-bin/cargo"; chmod +x "$d/.stub-bin/cargo"
expect_exit "rust below threshold blocks" pre-push "$d" 1

d="$(fixture rust-ok)"
printf '[package]\nname = "x"\n' > "$d/Cargo.toml"
printf '#!/bin/sh\n[ "$1" = tarpaulin ] && echo "85.00%% coverage, 17/20 lines covered"\nexit 0\n' \
    > "$d/.stub-bin/cargo"; chmod +x "$d/.stub-bin/cargo"
expect_exit "rust at threshold passes" pre-push "$d" 0

d="$(fixture rust-unreadable)"
printf '[package]\nname = "x"\n' > "$d/Cargo.toml"
printf '#!/bin/sh\n[ "$1" = tarpaulin ] && echo "no coverage data"\nexit 0\n' \
    > "$d/.stub-bin/cargo"; chmod +x "$d/.stub-bin/cargo"
expect_exit "rust unmeasured coverage blocks" pre-push "$d" 1

# PHP ≥ 80%
php_stub() {        # php_stub <fixture-dir> <lines-percent>
    mkdir -p "$1/vendor/bin"
    printf '#!/bin/sh\nprintf "  Lines:    %s%%%% (7/10)\\n"\nexit 0\n' "$2" > "$1/vendor/bin/phpunit"
    chmod +x "$1/vendor/bin/phpunit"
}
d="$(fixture php-low)";  printf '{}\n' > "$d/composer.json"; php_stub "$d" "70.00"
expect_exit "php below threshold blocks" pre-push "$d" 1
d="$(fixture php-ok)";   printf '{}\n' > "$d/composer.json"; php_stub "$d" "80.00"
expect_exit "php at threshold passes" pre-push "$d" 0

# Java ≥ 85% — Maven reads JaCoCo's csv, Gradle the same file under build/
jacoco_csv() {      # jacoco_csv <path> <missed> <covered>
    mkdir -p "$(dirname "$1")"
    printf 'GROUP,PACKAGE,CLASS,IM,IC,BM,BC,LINE_MISSED,LINE_COVERED\napp,x,Foo,1,9,0,0,%s,%s\n' \
        "$2" "$3" > "$1"
}
d="$(fixture mvn-low)"; printf '<project/>\n' > "$d/pom.xml"
jacoco_csv "$d/target/site/jacoco/jacoco.csv" 30 70
expect_exit "maven below threshold blocks" pre-push "$d" 1

d="$(fixture mvn-ok)"; printf '<project/>\n' > "$d/pom.xml"
jacoco_csv "$d/target/site/jacoco/jacoco.csv" 5 95
expect_exit "maven at threshold passes" pre-push "$d" 0

d="$(fixture gradle-low)"; printf 'plugins { id "java" }\n' > "$d/build.gradle"
jacoco_csv "$d/build/reports/jacoco/test/jacocoTestReport.csv" 30 70
expect_exit "gradle below threshold blocks" pre-push "$d" 1

# Kotlin Android ≥ 85% — Kover emits a JaCoCo-shaped xml
kover_xml() {       # kover_xml <dir> <missed> <covered>
    mkdir -p "$1/build/reports/kover"
    printf '<report name="app"><counter type="LINE" missed="%s" covered="%s"/></report>\n' \
        "$2" "$3" > "$1/build/reports/kover/report.xml"
}
d="$(fixture kover-low)"; printf 'android {\n}\n' > "$d/build.gradle.kts"; kover_xml "$d" 30 70
expect_exit "kotlin below threshold blocks" pre-push "$d" 1
d="$(fixture kover-ok)";  printf 'android {\n}\n' > "$d/build.gradle.kts"; kover_xml "$d" 5 95
expect_exit "kotlin at threshold passes" pre-push "$d" 0

# Go and Flutter already compared their numbers; neither could fail when the
# number came back empty, which is the same hole one step later.
d="$(fixture go-unreadable)"
printf 'module x\n' > "$d/go.mod"
printf '#!/bin/sh\nexit 0\n' > "$d/.stub-bin/go"; chmod +x "$d/.stub-bin/go"
expect_exit "go unmeasured coverage blocks" pre-push "$d" 1

d="$(fixture flutter-unreadable)"
printf 'name: x\n' > "$d/pubspec.yaml"
printf '#!/bin/sh\necho "no valid records found"\nexit 0\n' > "$d/.stub-bin/lcov"
chmod +x "$d/.stub-bin/lcov"
expect_exit "flutter unmeasured coverage blocks" pre-push "$d" 1

# ── Duplication gate (all stacks) ───────────────────────────────────────────
# Copy-paste passes every other Sensor in the hook — lint, types and coverage
# are all clean on a perfect duplicate — so this gate is the only thing standing
# between a reimplemented helper and the rework it causes. Each fixture below
# carries no stack markers at all: the only gate that can speak is this one,
# which also proves it is not nested inside one language's block.
jscpd_stub() {      # jscpd_stub <fixture-dir> <exit-code>
    printf '#!/bin/sh\necho "jscpd stub ran"\nexit %s\n' "$2" > "$1/.stub-bin/jscpd"
    chmod +x "$1/.stub-bin/jscpd"
}

d="$(fixture dup-over)"; jscpd_stub "$d" 1
expect_exit "duplication above threshold blocks" pre-push "$d" 1

d="$(fixture dup-ok)"; jscpd_stub "$d" 0
expect_exit "duplication at threshold passes"    pre-push "$d" 0
expect_says "clean duplication reaches the end"  pre-push "$d" yes "pre-push gates passed"
expect_says "duplication gate is stack-agnostic" pre-push "$d" yes "Duplication"

# Every optional tool in this hook warns when absent rather than blocking; a hook
# that dies on a machine without jscpd gets uninstalled, which costs every gate.
d="$(fixture dup-missing)"
expect_exit "missing jscpd does not block"    pre-push "$d" 0
expect_says "missing jscpd says UNENFORCED"   pre-push "$d" yes "duplication UNENFORCED"

rm -rf "$WORK"
echo "git-hook tests: $pass passed, exit=$fail"
exit $fail
