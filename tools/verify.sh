#!/usr/bin/env bash
# VANTA — verificación completa.
# Un comando, todos los controles que importan.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

fail=0
line() { printf '%s\n' "────────────────────────────────────────────────────────"; }

line
echo "1. Sintaxis de los 17 módulos"
line
if python3 tools/tests/luacheck.py $(find src -name '*.lua' | sort) >/tmp/syntax.log 2>&1; then
    grep -c '^OK' /tmp/syntax.log | xargs printf '   %s archivos compilan\n'
else
    grep '^FAIL' /tmp/syntax.log
    fail=1
fi

line
echo "2. Recompilar el script único"
line
python3 tools/build.py || fail=1

line
echo "3. Aislamiento de módulos"
line
for scenario in ok reject conflict broken mutecombat; do
    printf '   %-12s ' "$scenario"
    if out=$(python3 tools/tests/modtest.py "$scenario" 2>&1); then
        echo "$out" | grep -q 'AISLAMIENTO OK' \
            && echo "OK" \
            || { echo "FALLO"; fail=1; }
    else
        echo "FALLO"
        echo "$out" | grep '✖' | sed 's/^/       /'
        fail=1
    fi
done

line
echo "4. Script único de punta a punta"
line
if out=$(python3 tools/tests/bundletest.py 2>&1); then
    echo "$out" | grep -q 'BUNDLE OK' && echo "   OK" || { echo "   FALLO"; fail=1; }
else
    echo "   FALLO"
    echo "$out" | grep '✖' | sed 's/^/       /'
    fail=1
fi

line
echo "5. Loader (9 escenarios)"
line
for mode in ok missing brokenmodule notmodules neterr empty syntax runerr nostate; do
    printf '   %-14s ' "$mode"
    out=$(python3 /tmp/lt_clean.py "$mode" 2>&1)
    if echo "$out" | grep -q 'resultado: TERMINADO'; then
        echo "$out" | grep -oE '\[[0-9]+/[0-9]+ (módulos|remotos)[^]]*\]|WARN.*' | head -1 | sed 's/^WARN \[VANTA Loader\] //' || true
        echo
    else
        echo "SE COLGÓ"
        fail=1
    fi
done

line
if [ "$fail" -eq 0 ]; then
    echo "TODO OK"
else
    echo "HAY FALLOS"
fi
line

exit "$fail"
