#!/usr/bin/env bash
# Alle Pruefungen vom Addon-Stamm aus ausfuehren. Exit-Code 1 bei Fehler.
# Nutzung:  bash tools/run_tests.sh
set -u
cd "$(dirname "$0")/.."

LUA="${LUA:-lua5.1}"
LUAC="${LUAC:-luac5.1}"
fail=0

# 1. Syntax aller Addon-Dateien
for f in *.lua; do
  if ! "$LUAC" -p "$f"; then echo "SYNTAXFEHLER: $f"; fail=1; fi
done
[ $fail -eq 0 ] && echo "ok    Syntax"

# 2. Leere oder abgeschnittene Dateien: luac meldet die nicht
for f in *.lua; do
  if [ "$(wc -c < "$f")" -lt 50 ]; then echo "VERDAECHTIG KLEIN: $f"; fail=1; fi
done

# 3. Nur Sprachmittel, die es in Lua 5.0 (WoW 1.12) gibt
if out="$("$LUA" tools/check_lua50.lua *.lua 2>&1)"; then
  echo "ok    Lua-5.0-Kompatibilitaet"
else
  printf "FEHLER Lua-5.0-Kompatibilitaet\n%s\n" "$out"; fail=1
fi

# 4. Jede Datei aus der TOC existiert, und jede .lua steht in der TOC
toc_files="$(grep -v '^##' BananaLoot.toc | tr -d '\r' | sed 's/\\/\//g' | grep -v '^[[:space:]]*$')"
for f in $toc_files; do
  if [ ! -f "$f" ]; then echo "FEHLT (steht in der TOC): $f"; fail=1; fi
done
for f in *.lua; do
  if ! echo "$toc_files" | grep -qx "$f"; then echo "NICHT IN DER TOC: $f"; fail=1; fi
done
echo "ok    TOC-Dateiliste"

# 5. Version: TOC und BananaLoot.VERSION muessen gleich sein
toc_ver="$(grep '^## Version:' BananaLoot.toc | sed 's/## Version: *//' | tr -d '\r')"
lua_ver="$(grep -m1 '^BananaLoot.VERSION' BananaLoot.lua | sed 's/.*"\(.*\)".*/\1/')"
if [ "$toc_ver" != "$lua_ver" ]; then
  echo "FEHLER Version: TOC sagt $toc_ver, BananaLoot.VERSION sagt $lua_ver"; fail=1
else
  echo "ok    Version $toc_ver"
fi

# 5b. Der CHANGELOG hat eine Ueberschrift fuer die aktuelle Version ("## v<Version>")
if ! grep -q "^## v$toc_ver" CHANGELOG.md; then
  echo "FEHLER Version: CHANGELOG.md hat keine Ueberschrift '## v$toc_ver' (Version bei jeder Aenderung erhoehen und eintragen)"; fail=1
else
  echo "ok    CHANGELOG-Eintrag fuer v$toc_ver"
fi

# 6. Die Grafiken, die der Code laedt, liegen im Repo
for tex in $(grep -oh 'Interface\\\\AddOns\\\\BananaLoot\\\\[^"]*' *.lua | sed 's/.*BananaLoot\\\\//; s/\\\\/\//g' | sort -u); do
  if [ ! -f "$tex.tga" ] && [ ! -f "$tex.blp" ]; then echo "GRAFIK FEHLT: $tex"; fail=1; fi
done
echo "ok    Grafiken"

[ $fail -eq 0 ] && echo "ALLE TESTS OK"
exit $fail
