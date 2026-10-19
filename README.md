# Rey Cagón

App Android para competir con tus amigos por quién caga más en la semana, el mes, el trimestre y el año.

**Es solo entretenimiento.** Nada de lo que se registra es información de salud ni consejo médico.

## Qué hace

- Botón para registrar (máximo una por hora) con tipo opcional.
- Ranking por semana, mes, trimestre y año, entre tus amigos o entre todos.
- Seguir a otros usuarios, perfil con estadísticas y calendario.
- Notificaciones push cuando alguien que sigues registra, cuando alguien te sigue y cuando hay versión nueva.
- Recordatorio diario a las 8 p. m. si no has registrado nada.
- Dos widgets de pantalla de inicio: botón para registrar y ranking semanal.
- Actualizaciones dentro de la app (APK firmada, verificada por SHA-256).

## Stack

| Parte | Tecnología |
|---|---|
| App | Flutter (Android) |
| Base de datos y auth | Supabase (Postgres con RLS, Realtime, Storage) |
| Push | Firebase Cloud Messaging, enviado desde una Edge Function de Supabase |
| Widgets | `home_widget` + `RemoteViews` en Kotlin |

## Estructura

```
lib/                       App Flutter
android/app/src/main/      Widgets en Kotlin, layouts y manifiesto
supabase/migrations/       Esquema de la base (tablas, RLS, triggers, funciones)
supabase/functions/        Edge Function `notificaciones` (FCM)
scripts/publicar.sh        Compila y publica una versión para el actualizador
```

## Seguridad

- No hay secretos en el repo. La clave de Supabase en `lib/main.dart` es la *publishable key*, pública por diseño; el acceso a los datos lo controlan las políticas RLS de `supabase/migrations/`.
- Cada usuario solo puede crear, editar y borrar sus propios registros, follows y tokens de notificación. El límite de una por hora y la fecha de cada registro los impone la base, no la app.
- La cuenta de servicio de Firebase y el secreto del webhook viven como secretos de Supabase (Edge Functions y Vault), nunca en el código.
- `android/app/google-services.json` no es secreto; su clave está restringida a las APIs de FCM.
- La llave de firma (`android/key.properties`, `*.jks`) está fuera del repo.

## Correrlo con tu propio proyecto

1. Crea un proyecto de Supabase y aplica `supabase/migrations/` en orden.
2. Crea un proyecto de Firebase, registra la app `com.ahimismito.rey_cagon` y reemplaza `android/app/google-services.json`.
3. En Supabase, define los secretos de Edge Functions `FCM_SERVICE_ACCOUNT` (JSON de la cuenta de servicio) y `WEBHOOK_SECRET`, guarda el mismo valor en Vault como `webhook_secret` y despliega `supabase/functions/notificaciones` con `verify_jwt` desactivado.
4. Cambia `supabaseUrl` y `supabaseKey` en `lib/main.dart` y la URL de las funciones en las migraciones.
5. `flutter run`

Para firmar en release, crea `android/key.properties` con `storePassword`, `keyPassword`, `keyAlias` y `storeFile`.

## Publicar una versión

```
# Subir version: en pubspec.yaml (el número después del + es el que compara la app)
SUPABASE_ACCESS_TOKEN=sbp_... scripts/publicar.sh "Notas de la versión"
```

## Créditos

- Emojis: [Fluent Emoji](https://github.com/microsoft/fluentui-emoji) de Microsoft (MIT).
- Ícono: [Noto Emoji](https://github.com/googlefonts/noto-emoji) de Google.

## Licencia

MIT
