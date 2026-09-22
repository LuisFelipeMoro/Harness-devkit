#!/usr/bin/env bash
# Candidate finder for the Reviewer's security pass.
#
# The Reviewer's job on security is adjudication — is this reachable, is the input
# attacker-controlled, is the control adequate. Finding the *candidates* is not:
# every row in reviewer.md's vulnerability table has a literal shape in source.
# Reading every changed file to locate them costs a full model pass over the diff;
# grepping for them costs nothing, and the model then reads only the hits.
#
# This is a narrowing pass, never a verdict. No hits does NOT mean secure — an
# authz check missing entirely has no pattern to match, and the Reviewer still
# traces auth on every new route. Hits are candidates, and a candidate cleared
# with a reason is a normal outcome.
#
# Usage: security-scan.sh <path>...
# Always exits 0 — it reports, it does not gate. The Reviewer gates.
set -u
[ $# -gt 0 ] || { echo "usage: security-scan.sh <path>..." >&2; exit 2; }

paths=("$@")
total=0
emit() {
    local label="$1" pattern="$2" out
    out=$(grep -rnE --binary-files=without-match "$pattern" "${paths[@]}" 2>/dev/null \
        | grep -vE "_test\.|\.test\.|\.spec\.|/testdata/|/vendor/|/node_modules/" || true)
    if [ -n "$out" ]; then
        printf '%s\n' "$out" | sed "s|^|[$label] |"
        total=$((total + $(printf '%s\n' "$out" | grep -c .)))
    fi
}

echo "## security-scan — candidates for Reviewer adjudication"
echo

# Two shapes: the concat at the call site, and the far more common case of a query
# string built on one line and executed on another. The second is what a call-site
# grep misses, and it is the one that ships.
emit INJECTION-SQL       "(Query|Exec|QueryRow|prepare|execute|raw)\(.*(\+|\\\$\{|%s|%v|format|f\")"
emit INJECTION-SQL-BUILD "(SELECT|INSERT|UPDATE|DELETE|WHERE|FROM)[^\"']*[\"'][[:space:]]*(\+|\.|%|\\\$\{|\|\|)"
emit INJECTION-CMD       "(exec\.Command|os/exec|child_process|subprocess\.|system\(|popen|shell_exec|eval\()"
emit XSS                 "(innerHTML|outerHTML|document\.write|dangerouslySetInnerHTML|v-html|\|safe\b|Html\.raw)"
emit SSRF                "(http\.Get|http\.Post|fetch\(|axios\.|requests\.(get|post)|HttpClient)"
emit PATH-TRAVERSAL      "(os\.Open|ioutil\.ReadFile|readFile|open\(|File\()\(?[^)]*(req|request|param|query|input|user|argv)"
emit WEAK-CRYPTO         "(md5|sha1|MD5|SHA1|DES|ECB|Math\.random\(|rand\.Int\(|mt_rand)"
emit HARDCODED-SECRET    "(password|passwd|secret|api_?key|token|private_?key)[[:space:]]*(:?=|:)[[:space:]]*[\"'][^\"']{8,}"
emit DESERIALIZATION     "(ObjectInputStream|unserialize\(|pickle\.loads|yaml\.load\(|Marshal\.load|eval\()"
emit AUTH-SURFACE        "(router\.(Get|Post|Put|Delete|Patch)|app\.(get|post|put|delete)|@(Get|Post|Put|Delete)Mapping|@app\.route)"
emit SECRET-IN-LOG       "(log|logger|console|print|fmt\.Print)[A-Za-z.]*\(.*(password|token|secret|api_?key|ssn|card)"
emit DEBUG-IN-PROD       "(debug[[:space:]]*(:?=|:)[[:space:]]*(true|True|1)|DEBUG[[:space:]]*=[[:space:]]*True|\.set\(\"debug\")"
emit MISSING-TIMEOUT     "(http\.Client\{\}|new HttpClient\(\)|requests\.(get|post)\([^,)]*\)$)"

echo
if [ "$total" -eq 0 ]; then
    echo "0 candidates. This is NOT a pass — a missing authz check has no pattern."
    echo "Reviewer still traces auth/authz on every new route and follows one error to its exit."
else
    echo "$total candidate(s). Adjudicate each: reachable? attacker-controlled? control adequate?"
    echo "AUTH-SURFACE hits are routes, not defects — each needs its authz check traced."
fi
exit 0
