# Rey Cagón

App Android de chiste (Flutter + Supabase). Botón CAGUÉ, ranking con amigos, chat, rachas, secreto.
Repo público: nada de refs de proyecto, keys, correos ni usernames reales en código, comentarios o commits.

## Reglas

- Nombres del código en español (`PantallaRanking`, `_cargar`). Tablas y columnas de la base en inglés o como ya están: no renombrar, rompe apps viejas instaladas.
- Textos de UI siempre con `tr('es', 'en')` (`lib/idioma.dart`). Rey/reina con `segun()` (`lib/genero.dart`).
- Emojis en pantalla con el widget `Emoji` (`lib/emoji.dart`, PNG Fluent en `assets/emoji/`), no con `Text`.
- Estilo: cuadrado, `radio = 2`, bordes de 1px, sin sombras, un acento `#FFD60A` (`lib/tema.dart`, `paleta(context)`). Nada redondeado genérico. El botón CAGUÉ redondo se queda.
- Animaciones: respetar `movimiento(context)` (`lib/animaciones.dart`: completo / simple / nada). Con `nada` no se anima; con `simple` solo lo barato.
- Líneas largas (hasta ~150). No correr `dart format` sobre archivos existentes: reescribe todo.
- `lib/config.dart` y `android/app/google-services.json` están en .gitignore. No subirlos.
- Antes de terminar: `flutter analyze` sin errores nuevos y `flutter test`.
- Base de datos: los cambios van como migración nueva en `supabase/migrations/AAAAMMDDHHMMSS_nombre.sql`. Se aplican aparte, no desde el código.
- Errores de red: `conReintento()` y `textoError()` en `lib/main.dart`.

## Mapa de módulos (`lib/`)

| Archivo | Qué tiene |
|---|---|
| `main.dart` | `main()` (init de Supabase, push, widget, idioma, tema), `db`, `esDeRed`, `conReintento`, `escucharCagadas` (Realtime), `PantallaEntrar`, `PantallaInicio` (barra de 5 pestañas TRONO/RANKING/IMPERIO/BAÑO/YO), `PantallaRanking` (`trono: true` = pestaña TRONO con tarjeta HOY y CAGUÉ; `trono: false` = RANKING con podio; también el PageView al lado secreto) |
| `imperio/` | Modo clicker Imperio: motor puro en `motor.dart`/`catalogo.dart`/`estado.dart`, nube en `nube.dart`, pantalla en `pantalla.dart`, eventos en `telemetria.dart` (RPC `imperio_registrar`, catálogo de eventos en su dartdoc), flags remotos y A/B en `flags.dart` (RPC `imperio_flags_mias`); consultas a mano en `supabase/consultas/imperio_analisis.sql` |
| `chat.dart` | Baño: `PantallaChat` (pestañas), sala general y DMs sobre la tabla `mensajes`, reportar/bloquear/ocultar/fijar, `ofrecerPresumir`, hitos |
| `amigos.dart` | `PantallaAmigos` (listas sigues/te siguen) y `PantallaBuscarAmigos` |
| `perfil.dart` | `PantallaPerfil` (YO y perfil de otros), `_EditarPerfil`, `PantallaBuscar`, ajustes en la tuerca |
| `vitrina.dart` | Trofeos (`trofeos()`, `Vitrina`), `tituloPorTotal`, `MapaDelMes` |
| `racha.dart` | `nombreRacha`, `estiloRacha`, `mostrarRacha` (anuncio a pantalla completa), historia para compartir |
| `inodoro.dart` | Animación del mojón al inodoro al cagar |
| `parte.dart` | Hoja "Parte de cagada" (tipo, peso, placer si tiene el secreto) |
| `placer.dart` | Lado secreto: `minimoSecreto`, etiquetas, `MojonDelMomento`, desbloqueo (`placer_desbloqueado`) |
| `tips.dart` | `PantallaTips` y la esquina doblada que desbloquea el secreto |
| `secreto.dart` | Easter egg "psst…" (🍺 Rey Meón, 🚿 Rey Pulcro) |
| `accesorios.dart` | `Avatar`, catálogo `desbloqueos`, lentes/sombreros, mascotas, efectos |
| `cagadon.dart` | Retos 1 contra 1 del día |
| `calendario.dart` | `PantallaCalendario`, `meses` |
| `avisos.dart` | Notificaciones dentro de la app, navegación `ir()` |
| `push.dart` | FCM (`iniciarPush`, handler en segundo plano) |
| `widget.dart` | Widgets de pantalla de inicio, `clienteDeFondo()` (Supabase en motor aparte) |
| `animaciones.dart` | Niveles de movimiento |
| `tema.dart` | `Paleta`, `tema()`, `Rotulo`, `numeros()` |
| `emoji.dart` | Mapa emoji → PNG Fluent, widget `Emoji` |
| `onboarding.dart`, `recordatorio.dart`, `periodos.dart`, `peso.dart`, `tipos.dart`, `popups.dart`, `comunidad.dart`, `actualizar.dart`, `recuperar.dart`, `invitar_play.dart` | Lo que dice el nombre |

## Base (Supabase)

Tablas: `profiles` (total en `cagadas`, `placer_desbloqueado`, accesorios), `cagadas` (`tipo`, `peso`, `placer`, `etiquetas`), `follows`, `mensajes`, `mensaje_reportes`, `bloqueos`, `push_tokens`, `desbloqueos`, avisos y retos. RPC: `leaderboard`, `ranking_placer`, `victorias`, `es_admin`. Triggers: `limitar_cagadas` (una por hora), `cagadas_contar`, `cagadas_racha` (tarjeta en el chat), `validar_desbloqueos`, `validar_secreto`.
Edge Function `supabase/functions/notificaciones` manda los push (FCM v1).
