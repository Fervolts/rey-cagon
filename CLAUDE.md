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
| `imperio/sala.dart` | Sala de juegos: tarjetas de los 11 juegos; abiertos Tubería Express, Destapa y Memoria del rollo, el resto "PRÓXIMAMENTE". `PantallaSala({control})` cae a `ControlImperio.vivo` |
| `imperio/minijuegos/estadisticas.dart` | Récords y partidas por juego en memoria (sin imports) que leen los logros de la Sala; los llena `ControlImperio` desde el servidor |
| `imperio/minijuegos/datos.dart` | Lo que contestan las RPC `imperio_minijuego`, `imperio_minijuegos_resumen` y `imperio_minijuego_ranking`, la cuenta del premio (`minutosDePartida`, igual que el servidor) y `NubeMinijuegos` |
| `imperio/minijuegos/marco.dart` | Marco común: instrucción + JUGAR, el juego, pantalla de fin (puntos, récord, MJ, lo que queda hoy); `RelojJuego` (Ticker con tope de dt) y `vibracionSuave` |
| `imperio/minijuegos/tuberia_logica.dart`, `tuberia_vista.dart` | Tubería Express: lógica pura (2 carriles, codos, velocidad que sube) y vista con CustomPainter |
| `imperio/minijuegos/destapa_logica.dart`, `destapa_vista.dart` | Destapa: ritmo visual (perfecto/bueno/fallo, 3 fallos), háptica suave; puntos de enganche `// sonido:` |
| `imperio/minijuegos/memoria_logica.dart`, `memoria_vista.dart` | Memoria del rollo: parejas con emojis de `lib/emoji.dart` que tienen PNG, 3 niveles seguidos (4x3, 4x4, 5x4) |
| `imperio/minijuegos/ranking_vista.dart` | Ranking semanal de un minijuego, amigos o global |
| `chat.dart` | Baño: `PantallaChat` (pestañas), sala general y DMs sobre la tabla `mensajes`, reportar/bloquear/ocultar/fijar, `ofrecerPresumir`, hitos |
| `cloaca.dart` | Cloacas (clanes de hasta 25): modelos de `cloaca_mia`/`cloaca_ranking`, `NubeCloacas` (crear, unirse, salir, expulsar, cobrar premio, `cloaca_bono`), `RankingCloacasVista` (opción CLOACAS del RANKING), `PestanaCloaca` (pestaña CLOACA del Baño), `TarjetaCloaca` (tarjeta del cierre semanal en el chat); el bono de producción lo aplica `imperio/motor.dart` (`bonoCloaca`) |
| `amigos.dart` | `PantallaAmigos` (listas sigues/te siguen) y `PantallaBuscarAmigos` |
| `perfil.dart` | `PantallaPerfil` (YO y perfil de otros), `_EditarPerfil`, `PantallaBuscar`, ajustes en la tuerca |
| `icono_app.dart` / `icono_app_pantalla.dart` | Íconos alternos ganados con logros: lógica pura (`iconosGanados`), canal `rey_cagon/icono` (MainActivity.kt, activity-alias `.Icono<Alias>` en el manifest), pantalla en Ajustes. PNGs generados por `scripts/iconos_alternos.py` |
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

## Exploits

- Todo nerf va en el servidor (trigger o RPC), nunca solo en la app.
- Cagar y deshacer: `limitar_cagadas` + `cagadas_borradas`. Un deshacer rápido al día es gratis; desde el segundo cuenta la hora de la borrada; al tercero en 24 h (o dos en una hora) se tapa la poceta 3 h (`pocetas_tapadas`, hint `poceta_tapada`, logro secreto). `imperio_cargar` descuenta Fichas de cagadas cobradas y borradas.
- Sospechas: tabla `sospechas` (la llenan triggers y el cron `detectar_exploits`), se ven en el panel (`panel_sospechas`). Consultas a mano en `supabase/consultas/exploits.sql`. Para un exploit nuevo: consulta ahí, chequeo en `detectar_exploits()` con un tipo nuevo, nerf en el servidor.
