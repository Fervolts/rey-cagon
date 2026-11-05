#!/usr/bin/env bash
# Publica una versión para el actualizador dentro de la app.
#   scripts/publicar.sh "Notas de la versión"
#   SIN_LINK=1 scripts/publicar.sh "…"   # no copia el APK al escritorio
# Sube el APK al release de GitHub y version.json al bucket público `releases` de Supabase.
# Antes: subir `version:` en pubspec.yaml (el número después del + es el que compara la app).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTAS="${1:-}"
# El proyecto sale de lib/config.dart (no está en el repo).
REF=$(grep -oE 'https://[a-z0-9]+\.supabase\.co' lib/config.dart | head -1 | sed -E 's#https://([a-z0-9]+)\..*#\1#')
LINEA=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION=${LINEA%+*}
BUILD=${LINEA#*+}

# Candado: la OTA sale junto con Play, nunca antes. Orden: subir el AAB a Play, esperar que la consola lo
# muestre disponible, subir el flag build_play a ese build y recién ahí publicar aquí (migraciones y reinicios
# que dependan de la versión nueva también van después). ANTES_DE_PLAY=1 lo salta, solo con permiso explícito.
T="${SUPABASE_ACCESS_TOKEN:?Define SUPABASE_ACCESS_TOKEN con un token de https://supabase.com/dashboard/account/tokens}"
if [ "${ANTES_DE_PLAY:-}" != 1 ]; then
  EN_PLAY=$(curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
    -d '{"query":"select public.imperio_build_play() b"}' "https://api.supabase.com/v1/projects/$REF/database/query" |
    python3 -c "import json,sys;print(json.load(sys.stdin)[0]['b'])")
  if [ "$EN_PLAY" -lt "$BUILD" ]; then
    echo "Play sirve el build $EN_PLAY y esta es la $BUILD. Espera la aprobación de Play y sube build_play antes de publicar." >&2
    exit 1
  fi
fi

# Símbolos por build y fuera de build/ (flutter clean lo borra): las pilas de `error_app` del APK directo vienen sin nombres
# y se leen con `flutter symbolize -i pila.txt -d ~/.rey-cagon/simbolos/<build>/app.android-arm64.symbols`.
SIMBOLOS="$HOME/.rey-cagon/simbolos/$BUILD"
mkdir -p "$SIMBOLOS"
flutter build apk --release --flavor directo --target-platform android-arm,android-arm64 --split-debug-info="$SIMBOLOS"
APK=build/app/outputs/flutter-apk/app-directo-release.apk
SHA=$(shasum -a 256 "$APK" | awk '{print $1}')
NOMBRE="rey-cagon-$VERSION+$BUILD.apk"

# Service key del proyecto vía Management API.
K=$(curl -s -H "Authorization: Bearer $T" "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" |
  python3 -c "import json,sys;print([k['api_key'] for k in json.load(sys.stdin) if k.get('name')=='service_role'][0])")

subir() { # $1 archivo local, $2 nombre en el bucket, $3 tipo
  curl -sf -X POST -H "Authorization: Bearer $K" -H "apikey: $K" -H "x-upsert: true" \
    -H "Content-Type: $3" -H "cache-control: max-age=0" --data-binary @"$1" \
    "https://$REF.supabase.co/storage/v1/object/releases/$2" >/dev/null
}

# La APK va en el release de GitHub: Supabase Free no acepta archivos de más de 50 MiB.
# El actualizador (OkHttp) sigue la redirección de GitHub. El README baja releases/latest/download/rey-cagon.apk.
# Primero el release y después version.json: si algo falla, nadie ve una versión sin APK.
REPO=$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')
D=$(mktemp -d) && cp "$APK" "$D/rey-cagon.apk"
gh release create "v$VERSION" "$D/rey-cagon.apk" -R "$REPO" --target "$(git rev-parse HEAD)" --title "$VERSION" --notes "$NOTAS" >/dev/null
rm -rf "$D"
URL="https://github.com/$REPO/releases/download/v$VERSION/rey-cagon.apk"
# GitHub tarda unos segundos en servir el archivo nuevo.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  BAJADA=$(curl -sL "$URL" | shasum -a 256 | awk '{print $1}')
  [ "$BAJADA" = "$SHA" ] && break
  sleep 10
done
[ "$BAJADA" = "$SHA" ] || { echo "El APK de $URL no coincide con el compilado." >&2; exit 1; }
echo "Release v$VERSION en GitHub"

TMP=$(mktemp)
python3 - "$VERSION" "$BUILD" "$URL" "$SHA" "$NOTAS" > "$TMP" <<'PY2'
import json, sys
v, b, url, sha, notas = sys.argv[1:]
print(json.dumps({"version": v, "build": int(b), "sha256": sha, "notas": notas, "url": url}, ensure_ascii=False))
PY2
subir "$TMP" version.json application/json
rm -f "$TMP"
[ "${SIN_LINK:-}" = 1 ] || cp "$APK" ~/Desktop/rey-cagon.apk

# Igual en local: AABs de Play guardados en ~/Desktop/rey-cagon-play, quedan los 2 más nuevos.
ls -t ~/Desktop/rey-cagon-play/*-play.aab 2>/dev/null | tail -n +3 | while read -r VIEJA; do rm -f "$VIEJA"; done

# Aviso push de versión nueva (avisarVersion en supabase/functions/notificaciones).
W=$(curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d "{\"query\":\"select decrypted_secret s from vault.decrypted_secrets where name='webhook_secret'\"}" \
  "https://api.supabase.com/v1/projects/$REF/database/query" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['s'])")
ENVIADOS=$(curl -s -X POST -H "x-webhook-secret: $W" -H 'Content-Type: application/json' \
  -d "{\"tipo\":\"version\",\"version\":\"$VERSION\",\"build\":$BUILD}" \
  "https://$REF.supabase.co/functions/v1/notificaciones")
echo "Push de actualización: $ENVIADOS"

echo "Publicada $VERSION+$BUILD"
echo "Link fijo: https://github.com/$REPO/releases/latest/download/rey-cagon.apk"
