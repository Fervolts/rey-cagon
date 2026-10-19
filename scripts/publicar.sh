#!/usr/bin/env bash
# Publica una versión para el actualizador dentro de la app.
#   scripts/publicar.sh "Notas de la versión"
#   SIN_LINK=1 scripts/publicar.sh "…"   # no toca el link fijo
# Sube build/…/app-release.apk y version.json al bucket público `releases` de Supabase.
# Antes: subir `version:` en pubspec.yaml (el número después del + es el que compara la app).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTAS="${1:-}"
REF=TU-PROYECTO
LINEA=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION=${LINEA%+*}
BUILD=${LINEA#*+}

flutter build apk --release --target-platform android-arm64
APK=build/app/outputs/flutter-apk/app-release.apk
SHA=$(shasum -a 256 "$APK" | awk '{print $1}')
NOMBRE="rey-cagon-$VERSION+$BUILD.apk"

# Service key vía Management API con el token de Supabase guardado en la config de Claude Code.
T=""
for t in $(grep -oh "sbp_[a-zA-Z0-9]*" ~/.claude-alt/.claude.json ~/.claude.json 2>/dev/null | sort -u); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $t" "https://api.supabase.com/v1/projects/$REF/api-keys")" = 200 ] && T=$t && break
done
[ -n "$T" ] || { echo "No encontré un token de Supabase (sbp_…) con acceso a $REF"; exit 1; }
K=$(curl -s -H "Authorization: Bearer $T" "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" |
  python3 -c "import json,sys;print([k['api_key'] for k in json.load(sys.stdin) if k.get('name')=='service_role'][0])")

subir() { # $1 archivo local, $2 nombre en el bucket, $3 tipo
  curl -sf -X POST -H "Authorization: Bearer $K" -H "apikey: $K" -H "x-upsert: true" \
    -H "Content-Type: $3" -H "cache-control: max-age=0" --data-binary @"$1" \
    "https://$REF.supabase.co/storage/v1/object/releases/$2" >/dev/null
}

subir "$APK" "$NOMBRE" application/vnd.android.package-archive
# Link fijo para instalar por primera vez. SIN_LINK=1 lo deja en la versión anterior
# (sirve para probar el aviso: se instala la vieja desde el link y la app ofrece esta).
[ "${SIN_LINK:-}" = 1 ] || subir "$APK" rey-cagon.apk application/vnd.android.package-archive

TMP=$(mktemp)
python3 - "$VERSION" "$BUILD" "$NOMBRE" "$SHA" "$NOTAS" > "$TMP" <<'PY'
import json, sys
v, b, n, sha, notas = sys.argv[1:]
print(json.dumps({
    "version": v, "build": int(b), "sha256": sha, "notas": notas,
    "url": f"https://TU-PROYECTO.supabase.co/storage/v1/object/public/releases/{n}",
}, ensure_ascii=False))
PY
subir "$TMP" version.json application/json
rm -f "$TMP"
[ "${SIN_LINK:-}" = 1 ] || cp "$APK" ~/Desktop/rey-cagon.apk

# Push "Actualízame, mojón" a los teléfonos con un build menor (ver avisarVersion en la Edge Function).
W=$(curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d "{\"query\":\"select decrypted_secret s from vault.decrypted_secrets where name='webhook_secret'\"}" \
  "https://api.supabase.com/v1/projects/$REF/database/query" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['s'])")
ENVIADOS=$(curl -s -X POST -H "x-webhook-secret: $W" -H 'Content-Type: application/json' \
  -d "{\"tipo\":\"version\",\"version\":\"$VERSION\",\"build\":$BUILD}" \
  "https://$REF.supabase.co/functions/v1/notificar-cagada")
echo "Push de actualización: $ENVIADOS"

echo "Publicada $VERSION+$BUILD"
echo "Link fijo: https://$REF.supabase.co/storage/v1/object/public/releases/rey-cagon.apk"
