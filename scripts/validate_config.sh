#!/bin/sh
# ============================================================================
# validate_config.sh — SFTP accounts-config validator (anti-bluff gate)
# ----------------------------------------------------------------------------
# Purpose:
#   Validate config_schemas/accounts.yaml and accounts.json against
#   config_schemas/schema/accounts.schema.json (JSON Schema draft 2020-12),
#   fully OFFLINE (no network). --selftest runs the negative/positive fixtures
#   in schema/fixtures/ and exits 0 only when every bad-* fixture FAILS and
#   every good-* fixture PASSES — a validator that accepts its bad fixtures is
#   a §11.4 bluff, so this script is the anti-bluff gate for ATM-003.
#
# Usage:
#   scripts/validate_config.sh [--dir <config_dir>] [--selftest] [--quiet]
#     --dir <path>   config directory (default: config_schemas)
#     --selftest     validate fixtures: bad-* MUST FAIL, good-* MUST PASS
#     --quiet        suppress per-file OK lines (verdict summary still printed)
#
# Inputs:
#   <dir>/accounts.yaml, <dir>/accounts.json          (validated files)
#   <dir>/schema/accounts.schema.json                 (draft 2020-12 schema)
#   <dir>/schema/fixtures/{bad-*,good-*}.{yaml,json}  (--selftest only)
#
# Outputs:
#   stdout: per-file verdicts "OK <file>" / "INVALID <file>" with pinpointed
#           schema errors (json_path + message); summary line.
#   exit:   0 = all validations as expected; 1 = validation failure (or a
#           selftest fixture behaving opposite to its name); 2 = usage /
#           environment error (missing python3, missing files, bad schema).
#
# Side-effects: none (read-only; no temp files).
#
# Dependencies:
#   - python3 (>= 3.8) — required.
#   - python3 jsonschema + yaml (PyYAML) — primary validation path.
#   - FALLBACK (documented): if `import jsonschema` fails, the embedded
#     python performs a deterministic structural check enforcing exactly:
#     version==1; accounts is a list; per item: required username+permission;
#     username regex ^[a-z_][a-z0-9_-]{0,31}$; permission enum
#     read_only|read_write|public; uid/gid integers 0..65535; home regex
#     ^/sftp_data/...; enabled/public_acknowledged boolean; comment string;
#     no unknown properties; permission==public => public_acknowledged is
#     true. The fallback does NOT evaluate arbitrary JSON-Schema keywords
#     (it is a hardcoded mirror of the current schema) — the verdict shape
#     and exit codes are identical, and --selftest still proves all four
#     rejection classes.
#
# Cross-references:
#   docs/scripts/validate_config.md (user guide, §11.4.18)
#   config_schemas/README.md (schema semantics, permission model)
#   config_schemas/schema/accounts.schema.json
#   docs/research/mvp/MVP.md (atmoz/sftp evidence)
# ============================================================================
set -eu

CONFIG_DIR="config_schemas"
SELFTEST=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      [ $# -ge 2 ] || { echo "ERROR: --dir needs a path" >&2; exit 2; }
                CONFIG_DIR=$2; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
    --quiet)    QUIET=1; shift ;;
    -h|--help)  sed -n '1,40p' "$0"; exit 0 ;;
    *)          echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 not found on PATH" >&2; exit 2
}

SCHEMA="$CONFIG_DIR/schema/accounts.schema.json"
[ -f "$SCHEMA" ] || {
  echo "ERROR: schema not found: $SCHEMA" >&2; exit 2
}

# ---------------------------------------------------------------------------
# Embedded validator. Args: <schema> <mode> <file> [<file>...]
#   mode = "strict"   -> exit 1 if any file INVALID
#   mode = "report"   -> always exit 0; prints VALID/INVALID per file
# Prints one line per file: "VALID <file>" or "INVALID <file>\t<json_path>: <msg>"
# (first error only per file for readability; all errors would be noisier but
# not more decisive — the first pinpointed error is the actionable one).
# ---------------------------------------------------------------------------
validate_files() {
  mode=$1; shift
  python3 - "$SCHEMA" "$mode" "$@" <<'PYEOF'
import json, re, sys

schema_path, mode, files = sys.argv[1], sys.argv[2], sys.argv[3:]

with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
HOME_RE = re.compile(r"^/sftp_data/[a-z_][a-z0-9_-]{0,31}$")
PERMISSIONS = ("read_only", "read_write", "public")
ACCOUNT_KEYS = {"username", "permission", "public_acknowledged",
                "uid", "gid", "home", "enabled", "comment"}

def load_doc(path):
    with open(path, "r", encoding="utf-8") as fh:
        if path.endswith(".json"):
            return json.load(fh)
        import yaml  # PyYAML — present on the build host; see script header
        return yaml.safe_load(fh)

def structural_errors(doc):
    """Fallback checker: hardcoded mirror of accounts.schema.json.
    Enforces exactly the constraints documented in the script header."""
    errs = []
    if not isinstance(doc, dict):
        return [("/: document is not an object")]
    for key in doc:
        if key not in ("version", "accounts", "$schema", "_comment"):
            errs.append(f"/{key}: unknown top-level property")
    if doc.get("version") != 1:
        errs.append("/version: must be 1")
    accounts = doc.get("accounts")
    if not isinstance(accounts, list):
        errs.append("/accounts: must be a list")
        return errs
    for i, acct in enumerate(accounts):
        base = f"/accounts/{i}"
        if not isinstance(acct, dict):
            errs.append(f"{base}: entry is not an object"); continue
        for key in acct:
            if key not in ACCOUNT_KEYS:
                errs.append(f"{base}/{key}: unknown property")
        if "username" not in acct:
            errs.append(f"{base}/username: required property missing")
        elif not isinstance(acct["username"], str) or not USERNAME_RE.match(acct["username"]):
            errs.append(f"{base}/username: must match ^[a-z_][a-z0-9_-]{{0,31}}$")
        if "permission" not in acct:
            errs.append(f"{base}/permission: required property missing")
        elif acct["permission"] not in PERMISSIONS:
            errs.append(f"{base}/permission: must be one of read_only|read_write|public")
        for numkey in ("uid", "gid"):
            if numkey in acct and (not isinstance(acct[numkey], int)
                                   or isinstance(acct[numkey], bool)
                                   or not 0 <= acct[numkey] <= 65535):
                errs.append(f"{base}/{numkey}: must be an integer 0..65535")
        if "home" in acct and (not isinstance(acct["home"], str)
                               or not HOME_RE.match(acct["home"])):
            errs.append(f"{base}/home: must match ^/sftp_data/<username>$")
        for boolkey in ("enabled", "public_acknowledged"):
            if boolkey in acct and not isinstance(acct[boolkey], bool):
                errs.append(f"{base}/{boolkey}: must be a boolean")
        if "comment" in acct and not isinstance(acct["comment"], str):
            errs.append(f"{base}/comment: must be a string")
        if acct.get("permission") == "public" and acct.get("public_acknowledged") is not True:
            errs.append(f"{base}: permission 'public' requires public_acknowledged: true")
    return errs

def schema_errors(doc):
    """Primary path: jsonschema Draft 2020-12."""
    import jsonschema
    validator_cls = jsonschema.validators.validator_for(schema)
    validator_cls.check_schema(schema)
    validator = validator_cls(schema)
    out = []
    for err in sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path)):
        path = "/" + "/".join(str(p) for p in err.absolute_path) if err.absolute_path else "/"
        out.append(f"{path}: {err.message}")
    return out

try:
    import jsonschema  # noqa: F401
    HAVE_JSONSCHEMA = True
except ImportError:
    HAVE_JSONSCHEMA = False

backend = "jsonschema" if HAVE_JSONSCHEMA else "structural-fallback"
print(f"# validator backend: {backend} (offline)", file=sys.stderr)

any_invalid = False
for path in files:
    try:
        doc = load_doc(path)
    except Exception as exc:  # parse failure = INVALID with pinpoint
        print(f"INVALID {path}\t/: parse error: {exc}")
        any_invalid = True
        continue
    errs = schema_errors(doc) if HAVE_JSONSCHEMA else structural_errors(doc)
    if errs:
        any_invalid = True
        print(f"INVALID {path}\t{errs[0]}")
        for extra in errs[1:]:
            print(f"  also\t{extra}")
    else:
        print(f"VALID {path}")

if mode == "strict" and any_invalid:
    sys.exit(1)
sys.exit(0)
PYEOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "$SELFTEST" -eq 1 ]; then
  FIXTURES="$CONFIG_DIR/schema/fixtures"
  [ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found: $FIXTURES" >&2; exit 2; }

  selftest_fail=0
  tested=0
  for fixture in "$FIXTURES"/bad-*.yaml "$FIXTURES"/bad-*.json \
                 "$FIXTURES"/good-*.yaml "$FIXTURES"/good-*.json; do
    [ -f "$fixture" ] || continue
    tested=$((tested + 1))
    verdict_line=$(validate_files report "$fixture" | grep -E '^(VALID|INVALID)' || true)
    case "$fixture" in
      */bad-*)
        case "$verdict_line" in
          INVALID*) [ "$QUIET" -eq 0 ] && echo "selftest OK (rejected): $fixture" ;;
          *) echo "SELFTEST FAIL: bad fixture ACCEPTED: $fixture" >&2
             echo "  validator output: $verdict_line" >&2
             selftest_fail=1 ;;
        esac ;;
      */good-*)
        case "$verdict_line" in
          VALID*) [ "$QUIET" -eq 0 ] && echo "selftest OK (accepted): $fixture" ;;
          *) echo "SELFTEST FAIL: good fixture REJECTED: $fixture" >&2
             echo "  validator output: $verdict_line" >&2
             selftest_fail=1 ;;
        esac ;;
    esac
  done

  [ "$tested" -ge 5 ] || {
    echo "ERROR: expected >= 5 fixtures in $FIXTURES, found $tested" >&2; exit 2
  }
  if [ "$selftest_fail" -eq 0 ]; then
    echo "SELFTEST PASS: $tested fixtures behaved as named (bad-* rejected, good-* accepted)"
    exit 0
  fi
  echo "SELFTEST FAIL: validator is bluff-capable — see errors above" >&2
  exit 1
fi

# Default mode: validate the two canonical example files.
missing=0
for f in "$CONFIG_DIR/accounts.yaml" "$CONFIG_DIR/accounts.json"; do
  [ -f "$f" ] || { echo "ERROR: required config file not found: $f" >&2; missing=1; }
done
[ "$missing" -eq 0 ] || exit 2

if validate_files strict "$CONFIG_DIR/accounts.yaml" "$CONFIG_DIR/accounts.json"; then
  echo "VALIDATION PASS: accounts.yaml + accounts.json conform to $(basename "$SCHEMA")"
  exit 0
else
  echo "VALIDATION FAIL: see INVALID lines above" >&2
  exit 1
fi
