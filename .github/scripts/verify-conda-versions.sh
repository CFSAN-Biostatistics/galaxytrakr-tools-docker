#!/bin/sh
# verify-conda-versions.sh
#
# Verify that the conda/mamba-resolved package versions baked into a built
# Docker image match the version pins declared in the Dockerfile that built
# it. Guards against silent dependency-resolution fallback (e.g. mamba
# resolving `mlst>=2.32` down to `mlst 2.11.x` because of a channel/solver
# regression).
#
# Usage:
#   verify-conda-versions.sh <image> <Dockerfile_path> [--skip-on-error]
#
# Exit codes:
#   0  all pinned packages satisfied (or nothing to check: skip)
#   1  a pinned package version mismatch was found
#   2  usage error
#   3  docker (or the image) unusable; only reachable when --skip-on-error
#      is NOT set, otherwise this case exits 0 with a warning.
set -eu

SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: ${SCRIPT_NAME} <image> <Dockerfile_path> [--skip-on-error]" >&2
    exit 2
}

IMAGE="${1:-}"
DOCKERFILE="${2:-}"
[ $# -ge 2 ] || usage
shift 2

SKIP_ON_ERROR=0
for arg in "$@"; do
    case "$arg" in
        --skip-on-error) SKIP_ON_ERROR=1 ;;
        *) usage ;;
    esac
done

[ -n "$IMAGE" ] && [ -n "$DOCKERFILE" ] || usage
if [ ! -f "$DOCKERFILE" ]; then
    echo "ERROR: Dockerfile not found: ${DOCKERFILE}" >&2
    exit 2
fi

CONDA_ROOT="${CONDA_ROOT:-/opt/conda}"
DOCKERFILE_DIR=$(dirname "$DOCKERFILE")
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

fail_soft() {
    # Used for environment/tooling problems (not version mismatches).
    echo "WARNING: $1" >&2
    if [ "$SKIP_ON_ERROR" -eq 1 ]; then
        echo "Skipping conda version verification (--skip-on-error set)." >&2
        exit 0
    fi
    echo "ERROR: $1" >&2
    exit 3
}

if ! command -v docker >/dev/null 2>&1; then
    fail_soft "docker not found on PATH."
fi

# ---------------------------------------------------------------------------
# 1. Parse the Dockerfile (and any COPY'd environment.yml files) for
#    mamba/conda/micromamba create|install|update pins.
#
# Output format (tab-separated) written to $PINS_FILE:
#   ENV_NAME<TAB>PACKAGE<TAB>OP<TAB>VERSION
# ---------------------------------------------------------------------------
PINS_FILE="${WORKDIR}/pins.tsv"
: > "$PINS_FILE"

# Join RUN instruction continuation lines (trailing '\') into single logical
# lines so multi-line `mamba create \ ... \ ...` blocks parse correctly, then
# emit one full command string per RUN instruction that mentions
# mamba/conda/micromamba create|install|update.
LOGICAL_RUNS="${WORKDIR}/logical_runs.txt"
awk '
    BEGIN { buf = ""; active = 0 }
    {
        line = $0
        if (!active) {
            if (line ~ /^[ \t]*RUN[ \t]+/) {
                active = 1
                buf = line
            } else {
                next
            }
        } else {
            buf = buf " " line
        }
        # strip a single trailing backslash (with optional trailing whitespace)
        if (buf ~ /\\[ \t]*$/) {
            sub(/\\[ \t]*$/, "", buf)
            next
        } else {
            print buf
            active = 0
            buf = ""
        }
    }
' "$DOCKERFILE" > "$LOGICAL_RUNS"

# For each logical RUN command, split into segments starting at each
# mamba/conda/micromamba create|install|update occurrence and extract the
# env name (-n/--name or -p/--prefix) plus package version pins.
extract_pins_from_text() {
    text="$1"
    # Split into one segment per create/install/update invocation by
    # inserting a real newline before each occurrence.
    printf '%s\n' "$text" | sed -E 's/(mamba|conda|micromamba)[ \t]+(create|install|update)/\n&/g' | while IFS= read -r segment; do
        case "$segment" in
            *mamba\ create*|*mamba\ install*|*mamba\ update*| \
            *conda\ create*|*conda\ install*|*conda\ update*| \
            *micromamba\ create*|*micromamba\ install*|*micromamba\ update*) ;;
            *) continue ;;
        esac

        env_name=$(printf '%s' "$segment" | grep -oE '(-n|--name)[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $2}')
        if [ -z "$env_name" ]; then
            env_name="base"
        fi

        # Extract package pin tokens: name<op>version, e.g. mlst>=2.32
        printf '%s' "$segment" | grep -oE '[A-Za-z0-9_.-]+(==|>=|<=|=|<|>)[0-9][A-Za-z0-9_.-]*' | \
        while IFS= read -r tok; do
            pkg=$(printf '%s' "$tok" | sed -E 's/(==|>=|<=|=|<|>).*$//')
            op=$(printf '%s' "$tok" | grep -oE '(==|>=|<=|=|<|>)')
            ver=$(printf '%s' "$tok" | sed -E 's/^[^=<>]+(==|>=|<=|=|<|>)//')
            printf '%s\t%s\t%s\t%s\n' "$env_name" "$pkg" "$op" "$ver" >> "$PINS_FILE"
        done
    done
}

while IFS= read -r logical_line; do
    [ -n "$logical_line" ] || continue
    case "$logical_line" in
        *mamba\ create*|*mamba\ install*|*mamba\ update*| \
        *conda\ create*|*conda\ install*|*conda\ update*| \
        *micromamba\ create*|*micromamba\ install*|*micromamba\ update*)
            extract_pins_from_text "$logical_line"
            ;;
    esac
done < "$LOGICAL_RUNS"

# Also parse any COPY'd environment.yml/environment.yaml referenced by the
# Dockerfile, if present alongside it.
for envfile in "${DOCKERFILE_DIR}"/environment.yml "${DOCKERFILE_DIR}"/environment.yaml; do
    [ -f "$envfile" ] || continue
    grep -oE '^[[:space:]]*-[[:space:]]*[A-Za-z0-9_.-]+(==|>=|<=|=|<|>)[0-9][A-Za-z0-9_.-]*' "$envfile" | \
    sed -E 's/^[ \t]*-[ \t]*//' | \
    while IFS= read -r tok; do
        pkg=$(printf '%s' "$tok" | sed -E 's/(==|>=|<=|=|<|>).*$//')
        op=$(printf '%s' "$tok" | grep -oE '(==|>=|<=|=|<|>)')
        ver=$(printf '%s' "$tok" | sed -E 's/^[^=<>]+(==|>=|<=|=|<|>)//')
        printf '%s\t%s\t%s\t%s\n' "base" "$pkg" "$op" "$ver" >> "$PINS_FILE"
    done
done

if [ ! -s "$PINS_FILE" ]; then
    echo "No conda/mamba/micromamba package pins found in ${DOCKERFILE} (non-conda image?). Skipping verification."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. For each distinct env referenced by the pins, list the installed
#    packages inside the built image (try micromamba, mamba, conda in turn).
# ---------------------------------------------------------------------------
have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1

list_env_json() {
    env_name="$1"
    if [ "$env_name" = "base" ]; then
        prefixes="${CONDA_ROOT}"
    else
        prefixes="${CONDA_ROOT}/envs/${env_name}"
    fi
    for prefix in $prefixes; do
        for tool in micromamba mamba conda; do
            out=$(docker run --rm --entrypoint "" "$IMAGE" sh -c \
                "command -v ${tool} >/dev/null 2>&1 && ${tool} list -p '${prefix}' --json 2>/dev/null" 2>/dev/null || true)
            case "$out" in
                \[*\])
                    printf '%s' "$out"
                    return 0
                    ;;
            esac
        done
    done
    # Last resort: default/activated env, no explicit prefix.
    for tool in micromamba mamba conda; do
        out=$(docker run --rm --entrypoint "" "$IMAGE" sh -c \
            "command -v ${tool} >/dev/null 2>&1 && ${tool} list --json 2>/dev/null" 2>/dev/null || true)
        case "$out" in
            \[*\])
                printf '%s' "$out"
                return 0
                ;;
        esac
    done
    return 1
}

json_to_name_version() {
    # Reads a conda/mamba/micromamba `list --json` document on stdin and
    # prints "name<TAB>version" pairs, one per package.
    if [ "$have_jq" -eq 1 ]; then
        jq -r '.[] | "\(.name)\t\(.version)"'
    else
        # conda/mamba/micromamba emit pretty-printed JSON with alphabetically
        # sorted object keys, so "name" always appears before "version"
        # within the same object.
        awk '
            /"name"[ \t]*:/ {
                line = $0
                sub(/^[^"]*"name"[ \t]*:[ \t]*"/, "", line)
                sub(/".*$/, "", line)
                last_name = line
            }
            /"version"[ \t]*:/ {
                line = $0
                sub(/^[^"]*"version"[ \t]*:[ \t]*"/, "", line)
                sub(/".*$/, "", line)
                if (last_name != "") print last_name "\t" line
            }
        '
    fi
}

# ---------------------------------------------------------------------------
# 3. Compare pinned versions against installed versions.
# ---------------------------------------------------------------------------
version_ge() { # $1 >= $2
    [ "$1" = "$2" ] && return 0
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}
version_le() { # $1 <= $2
    [ "$1" = "$2" ] && return 0
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}
version_prefix_match() { # $1 (installed) starts with $2 (pin)
    case "$1" in
        "$2") return 0 ;;
        "$2".*) return 0 ;;
        *) return 1 ;;
    esac
}

RESULTS_FILE="${WORKDIR}/results.tsv"
: > "$RESULTS_FILE"
FAILED=0

ENVS=$(awk -F'\t' '{print $1}' "$PINS_FILE" | sort -u)
for env_name in $ENVS; do
    installed_json=$(list_env_json "$env_name" || true)
    installed_file="${WORKDIR}/installed_${env_name}.tsv"
    if [ -n "$installed_json" ]; then
        printf '%s' "$installed_json" | json_to_name_version > "$installed_file"
    else
        : > "$installed_file"
    fi

    awk -F'\t' -v env="$env_name" '$1 == env {print $2"\t"$3"\t"$4}' "$PINS_FILE" | \
    while IFS='	' read -r pkg op pin_ver; do
        installed_ver=$(awk -F'\t' -v p="$pkg" 'tolower($1) == tolower(p) {print $2; exit}' "$installed_file")
        if [ -z "$installed_ver" ]; then
            printf 'FAIL\t%s\t%s\t%s%s\t(not found)\n' "$env_name" "$pkg" "$op" "$pin_ver" >> "$RESULTS_FILE"
            continue
        fi
        ok=1
        case "$op" in
            ">=") version_ge "$installed_ver" "$pin_ver" || ok=0 ;;
            "<=") version_le "$installed_ver" "$pin_ver" || ok=0 ;;
            ">")  version_ge "$installed_ver" "$pin_ver" && [ "$installed_ver" != "$pin_ver" ] || ok=0 ;;
            "<")  version_le "$installed_ver" "$pin_ver" && [ "$installed_ver" != "$pin_ver" ] || ok=0 ;;
            "==") [ "$installed_ver" = "$pin_ver" ] || ok=0 ;;
            "=")  version_prefix_match "$installed_ver" "$pin_ver" || ok=0 ;;
        esac
        if [ "$ok" -eq 1 ]; then
            printf 'OK\t%s\t%s\t%s%s\t%s\n' "$env_name" "$pkg" "$op" "$pin_ver" "$installed_ver" >> "$RESULTS_FILE"
        else
            printf 'FAIL\t%s\t%s\t%s%s\t%s\n' "$env_name" "$pkg" "$op" "$pin_ver" "$installed_ver" >> "$RESULTS_FILE"
        fi
    done
done

# ---------------------------------------------------------------------------
# 4. Tool-specific runtime guard: SeqSero2S must not silently fall back to
#    mlst 2.11.x when the pin requires mlst>=2.32.
# ---------------------------------------------------------------------------
case "$IMAGE $DOCKERFILE" in
    *[Ss]eq[Ss]ero2[Ss]*)
        mlst_version_out=$(docker run --rm --entrypoint "" "$IMAGE" sh -c 'mlst --version 2>&1' || true)
        mlst_runtime_ver=$(printf '%s' "$mlst_version_out" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)
        if [ -n "$mlst_runtime_ver" ] && version_ge "$mlst_runtime_ver" "2.32"; then
            printf 'OK\t%s\t%s\truntime mlst --version\t%s\n' "runtime" "mlst" "$mlst_version_out" >> "$RESULTS_FILE"
        else
            printf 'FAIL\t%s\t%s\truntime mlst --version (want >=2.32)\t%s\n' "runtime" "mlst" "$mlst_version_out" >> "$RESULTS_FILE"
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# 5. Report.
# ---------------------------------------------------------------------------
printf '\n%-6s %-14s %-14s %-14s %s\n' "STATUS" "ENV" "PACKAGE" "PIN" "INSTALLED"
printf '%s\n' "------------------------------------------------------------------"
while IFS='	' read -r status env pkg pin installed; do
    printf '%-6s %-14s %-14s %-14s %s\n' "$status" "$env" "$pkg" "$pin" "$installed"
    [ "$status" = "FAIL" ] && FAILED=1
done < "$RESULTS_FILE"
printf '\n'

if [ "$FAILED" -eq 1 ]; then
    echo "ERROR: conda/mamba dependency verification FAILED for ${IMAGE}." >&2
    exit 1
fi

echo "conda/mamba dependency verification passed for ${IMAGE}."
exit 0
