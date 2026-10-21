# Rey Cagón 👑💩

¿Quién de tus amigos caga más esta semana? Ahora hay ranking.

Rey Cagón es una app Android de chiste: cada vez que vas al baño le das al botón, y compites con tus amigos por la corona de la semana, el mes, el trimestre y el año.

> Es solo entretenimiento. No es una app de salud ni da consejos médicos.

## Descargar

### Prueba en Play Store

Estamos en prueba cerrada antes de salir en Play Store. Para entrar:

1. Únete al grupo de testers: [groups.google.com/g/rey-cagon-testers](https://groups.google.com/g/rey-cagon-testers) (botón "Unirse al grupo").
2. Acepta la prueba: [play.google.com/apps/testing/com.ahimismito.rey_cagon](https://play.google.com/apps/testing/com.ahimismito.rey_cagon).
3. Instala desde Play: [play.google.com/store/apps/details?id=com.ahimismito.rey_cagon](https://play.google.com/store/apps/details?id=com.ahimismito.rey_cagon).

Usa la misma cuenta de Google que tienes en el teléfono. El link de instalar da error hasta que hagas los pasos 1 y 2, y puede tardar unos minutos en activarse.

Si ya tenías la APK instalada, desinstálala primero: la versión de Play no se instala encima. Tu cuenta y tus cagadas no se pierden, están en la nube.

Déjala instalada al menos 14 días: Google pide eso para publicarla para todos.

### APK directa

[**Bajar la APK para Android**](https://github.com/Fervolts/rey-cagon/releases/latest/download/rey-cagon.apk)

Android te va a pedir permiso para instalar apps de fuera de la tienda. Después de la primera vez, la app te avisa sola cuando hay versión nueva.

## Qué trae

- **Un botón:** cagaste, lo tocas. Opcionalmente eliges qué tipo salió (Anaconda, Volcán, Piedritas de conejo…).
- **Ranking** entre tus amigos o entre todos, por semana, mes, trimestre y año.
- **Notificaciones** cuando un amigo caga ("Fulanito cagó 3 veces hoy… vas perdiendo"), cuando alguien te sigue y un recordatorio a las 8 p. m. si no has registrado nada.
- **Perfiles** con estadísticas, calendario y tu "especialidad de la casa".
- **Accesorios** para tu avatar (sombreros, lentes, mascotas) que se desbloquean mientras más cagas.
- **Tips** para cagar mejor. No son consejo médico.
- **Widgets** para la pantalla de inicio: el botón para registrar sin abrir la app y tu puesto en el ranking.
- Una por hora como máximo. Sin trampas.

## Hecho con

Flutter, Supabase (base de datos, login, tiempo real) y Firebase Cloud Messaging para las notificaciones. Los widgets son nativos en Kotlin.

## Tus datos

La app guarda tu correo, tu username y la hora de cada registro. Tus amigos ven tu username, tus totales y tu calendario. Nada más.

## Correrlo tú mismo

Necesitas tu propio proyecto de Supabase y de Firebase:

1. Aplica las migraciones de `supabase/migrations/` y despliega `supabase/functions/notificaciones`. En el Vault crea `project_url` (la URL de tu proyecto) y `webhook_secret`.
2. Copia `lib/config.example.dart` como `lib/config.dart` con tu URL y clave publicable de Supabase, y pon tu `google-services.json` en `android/app/`. Ninguno de los dos se sube al repo.
3. `flutter run`

## Créditos

Emojis de [Fluent Emoji](https://github.com/microsoft/fluentui-emoji) (Microsoft) e ícono de [Noto Emoji](https://github.com/googlefonts/noto-emoji) (Google).

## Licencia

MIT
