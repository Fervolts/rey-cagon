#!/usr/bin/env bash
# Publica una versión para el actualizador dentro de la app.
#   scripts/publicar.sh "Notas de la versión"
#   SIN_LINK=1 scripts/publicar.sh "…"   # no toca el link fijo
# Sube build/…/app-release.apk y version.json al bucket público `releases` de Supabase.
# Antes: subir `version:` en pubspec.yaml (el número después del + es el que compara la app).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTAS="${1:-}"
# El proyecto sale de lib/config.dart (no está en el repo).
REF=$(grep -oE 'https://[a-z0-9]+\.supabase\.co' lib/config.dart | head -1 | sed -E 's#https://([a-z0-9]+)\..*#\1#')
LINEA=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION=${LINEA%+*}
BUILD=${LINEA#*+}

flutter build apk --release --flavor directo --target-platform android-arm,android-arm64
APK=build/app/outputs/flutter-apk/app-directo-release.apk
SHA=$(shasum -a 256 "$APK" | awk '{print $1}')
NOMBRE="rey-cagon-$VERSION+$BUILD.apk"

# Service key del proyecto vía Management API. Requiere SUPABASE_ACCESS_TOKEN (token de acceso sbp_…).
T="${SUPABASE_ACCESS_TOKEN:?Define SUPABASE_ACCESS_TOKEN con un token de https://supabase.com/dashboard/account/tokens}"
K=$(curl -s -H "Authorization: Bearer $T" "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" |
  python3 -c "import json,sys;print([k['api_key'] for k in json.load(sys.stdin) if k.get('name')=='service_role'][0])")

subir() { # $1 archivo local, $2 nombre en el bucket, $3 tipo
  curl -sf -X POST -H "Authorization: Bearer $K" -H "apikey: $K" -H "x-upsert: true" \
    -H "Content-Type: $3" -H "cache-control: max-age=0" --data-binary @"$1" \
    "https://$REF.supabase.co/storage/v1/object/releases/$2" >/dev/null
}

subir "$APK" "$NOMBRE" application/vnd.android.package-archive
# Link fijo para la primera instalación. SIN_LINK=1 lo deja en la versión anterior.
[ "${SIN_LINK:-}" = 1 ] || subir "$APK" rey-cagon.apk application/vnd.android.package-archive

TMP=$(mktemp)
python3 - "$VERSION" "$BUILD" "$NOMBRE" "$SHA" "$NOTAS" "$REF" > "$TMP" <<'PY'
import json, sys
v, b, n, sha, notas, ref = sys.argv[1:]
print(json.dumps({
    "version": v, "build": int(b), "sha256": sha, "notas": notas,
    "url": f"https://{ref}.supabase.co/storage/v1/object/public/releases/{n}",
}, ensure_ascii=False))
PY
subir "$TMP" version.json application/json
rm -f "$TMP"
[ "${SIN_LINK:-}" = 1 ] || cp "$APK" ~/Desktop/rey-cagon.apk

# Release en GitHub: el README descarga releases/latest/download/rey-cagon.apk.
if [ "${SIN_LINK:-}" != 1 ] && command -v gh >/dev/null; then
  D=$(mktemp -d) && cp "$APK" "$D/rey-cagon.apk"
  gh release create "v$VERSION" "$D/rey-cagon.apk" --title "$VERSION" --notes "$NOTAS" >/dev/null && echo "Release v$VERSION en GitHub"
  rm -rf "$D"
fi

# Aviso push de versión nueva (avisarVersion en supabase/functions/notificaciones).
W=$(curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d "{\"query\":\"select decrypted_secret s from vault.decrypted_secrets where name='webhook_secret'\"}" \
  "https://api.supabase.com/v1/projects/$REF/database/query" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['s'])")
ENVIADOS=$(curl -s -X POST -H "x-webhook-secret: $W" -H 'Content-Type: application/json' \
  -d "{\"tipo\":\"version\",\"version\":\"$VERSION\",\"build\":$BUILD}" \
  "https://$REF.supabase.co/functions/v1/notificaciones")
echo "Push de actualización: $ENVIADOS"

echo "Publicada $VERSION+$BUILD"
echo "Link fijo: https://$REF.supabase.co/storage/v1/object/public/releases/rey-cagon.apk"
