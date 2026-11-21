#!/usr/bin/env bash
# VANTA — verificación completa.
# Un comando, todos los controles que importan.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

fail=0
line() { printf '%s\n' "────────────────────────────────────────────────────────"; }

line
echo "1. Sintaxis de los 13 módulos"
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
for scenario in ok broken toggle restore hook teardown; do
    printf '   %-12s ' "$scenario"
    if out=$(python3 tools/tests/isolation.py "$scenario" 2>&1); then
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
echo "4. Reentrada: ejecutar dos y tres veces"
line
for scenario in once twice thrice stopstart stopstop; do
    printf '   %-12s ' "$scenario"
    if out=$(python3 tools/tests/reentry.py "$scenario" 2>&1); then
        echo "OK"
    else
        echo "FALLA"
        echo "$out" | grep '✖' | sed 's/^/     /'
        fail=1
    fi
done

line
echo "5. Script único de punta a punta"
line
if out=$(python3 tools/tests/bundletest.py 2>&1); then
    echo "$out" | grep -q 'BUNDLE OK' && echo "   OK" || { echo "   FALLO"; fail=1; }
else
    echo "   FALLO"
    echo "$out" | grep '✖' | sed 's/^/       /'
    fail=1
fi

line
echo "6. Loader (12 escenarios)"
line
for mode in ok pr404 slow missing brokenmodule notmodules neterr empty syntax runerr nostate hang; do
    printf '   %-14s ' "$mode"
    # A un archivo, no a una tubería: `echo "$out" | grep -q` corta la
    # tubería al encontrar la coincidencia y con `pipefail` eso se lee como
    # fallo aunque el test haya terminado bien. Archivo y listo.
    log=$(mktemp)
    python3 tools/tests/loadertest.py "$mode" >"$log" 2>&1
    if grep -qE 'resultado: (TERMINADO|LOADER TERMINADO)' "$log"; then
        grep -oE '\[[0-9]+/[0-9]+ (secciones|remotos)[^]]*\]' "$log" | head -1
        grep -oE 'WARN \[VANTA Loader\] .*' "$log" | head -1 | sed 's/^WARN \[VANTA Loader\] //'
        echo
    else
        echo "SE COLGÓ"
        tail -5 "$log" | sed 's/^/       /'
        fail=1
    fi
    rm -f "$log"
done

line
if [ "$fail" -eq 0 ]; then
    echo "TODO OK"
else
    echo "HAY FALLOS"
fi
line

exit "$fail"
