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
| `main.dart` | `main()` (init de Supabase, push, widget, idioma, tema), `db`, `esDeRed`, `conReintento`, `escucharCagadas` (Realtime), `PantallaEntrar`, `PantallaInicio` (barra de 5 pestañas TRONO/RANKING/IMPERIO/BAÑO/YO; RANKING = CAGADAS o IMPERIO; BAÑO = `PantallaMuro`), `PantallaRanking` (`trono: true` = pestaña TRONO con tarjeta HOY y CAGUÉ; `trono: false` = RANKING con podio; también el PageView al lado secreto) |
| `imperio/` | Modo clicker Imperio: motor puro en `motor.dart`/`catalogo.dart`/`estado.dart`, nube en `nube.dart`, pantalla en `pantalla.dart`, eventos en `telemetria.dart` (RPC `imperio_registrar`, catálogo de eventos en su dartdoc), flags remotos y A/B en `flags.dart` (RPC `imperio_flags_mias`); consultas a mano en `supabase/consultas/imperio_analisis.sql` |
| `imperio/sala.dart` | Sala de juegos: tarjetas de los 11 juegos; abiertos Tubería Express, Destapa y Fusión real, el resto "PRÓXIMAMENTE". `PantallaSala({control})` cae a `ControlImperio.vivo` |
| `imperio/minijuegos/estadisticas.dart` | Récords y partidas por juego en memoria (sin imports) que leen los logros de la Sala; los llena `ControlImperio` desde el servidor |
| `imperio/minijuegos/datos.dart` | Lo que contestan las RPC `imperio_minijuego`, `imperio_minijuegos_resumen` y `imperio_minijuego_ranking`, la cuenta del premio (`minutosDePartida`, igual que el servidor) y `NubeMinijuegos` |
| `imperio/minijuegos/marco.dart` | Marco común: instrucción + JUGAR, el juego, pantalla de fin (puntos, récord, MJ, lo que queda hoy), botón de silencio; `RelojJuego` (Ticker con tope de dt) y `vibracionSuave` |
| `imperio/minijuegos/sonido.dart` | `Sonido`: efectos (AudioPool) y loop de música por juego, silencio guardado; archivos en `assets/sonidos/` generados por `scripts/sonidos.py` (síntesis propia, numpy + ffmpeg) |
| `imperio/minijuegos/tuberia_logica.dart`, `tuberia_vista.dart`, `tuberia_pintor.dart`, `tuberia_efectos.dart` | Tubería Express: surf de una mano (mantener = pesado, soltar = liviano; tutorial con caída prevista solo en la primera partida (hasta 6 limpios)), aterrizaje limpio da velocidad y combo, plaf solo abajo de una subida (arriba de la loma cae suave, `alturaSuave`); rampa cada ~200 m que lanza alto con fila de rollos y nunca da plaf; el Atasco persigue por la izquierda; rollos en el piso hasta 140 m y luego en arco, dorado cada ~25 s = fiebre x2 5 s; cucarachas (aplastar pesado o a más de 9 m/s = bonus); 5 zonas cada 400 m; 16 pts/s, tope 16000 |
| `imperio/minijuegos/destapa_logica.dart`, `destapa_vista.dart`, `destapa_pintor.dart`, `destapa_efectos.dart` | Destapa: baño del estadio, ritmo exponencial (0.99^t), 2→4 inodoros, 5 atascos (normal, gordo, patito, celular, cucaracha), combo x2/x3, dorado cada 30 s, medio tiempo 90 s + prórroga, 3 desbordes; tope 14 pts/s |
| `imperio/minijuegos/memoria_logica.dart`, `memoria_vista.dart`, `memoria_pintor.dart` | Fusión real (id `memoria`): fusión tipo Suika en la poceta con física propia, 9 niveles (caen del 1 al 4), Rey+Rey = descarga real, palanca que traga los chicos, desborde a los 2 s, sin reloj ni tope práctico (acaba al desbordar; tope 1000000 = columna del servidor, flags `minijuego_tope_memoria`/`minijuego_max_ms_memoria`), presión x1/x2/x4, evento imán, con dos Reyes vivos la poceta crece (piezas a `escala`, hasta 3 veces) y los Reyes se atraen; cada descarga real paga más; arranca con N mojones al azar (flag `fusion_piezas_inicio`, 0 a 6, por defecto 4); telemetría `fusion_fin` |
| `imperio/minijuegos/ranking_vista.dart` | Ranking semanal de un minijuego, amigos o global |
| `muro.dart` | Pestaña BAÑO: `PantallaMuro` (muro con TODOS/AMIGOS, RPC `muro_feed` paginada por `created_at`, 💩 como like, comentarios en `_PantallaPost`, publicar en `_PantallaPublicar`; botón de chats arriba a la derecha que abre `PantallaChat`; avisos de chat los pasa con `Ir.muro`). Sin Realtime ni push |
| `muro_dibujo.dart` | Dibujo del muro: `Dibujo` (JSON `{v, fondo, trazos}`, coordenadas 0..1000), `dibujoInvalido` (igual que el trigger `validar_muro`), `VistaDibujo`, editor tipo Paint `abrirEditorDibujo` |
| `chat.dart` | Baño: `PantallaChat` (lista de chats: General, Amigos, Soporte; se abre desde el botón de arriba a la derecha del muro; cada uno abre su pantalla), `elegirMotivoReporte` (también lo usa el muro), `_PantallaGeneral` (salas global/es/en con selector fijo), `Sala` sobre la tabla `mensajes`, reportar/bloquear/ocultar/fijar, `ofrecerPresumir`, hitos |
| `privados.dart` | Chats privados: sala `dm:<a>:<b>` (ids en minúsculas, menor primero) en `mensajes`, bandeja `PantallaPrivados` (RPC `dm_bandeja`), conversación sobre `Sala`, `PuntoSinLeer`; quién te escribe en `profiles.mensajes_de` (todos/amigos/nadie, RPC `dm_puedo`); tope 20/min y 20 conversaciones nuevas al día en `validar_mensaje` |
| `chat_rapido.dart` | `ChatRapido`: últimos mensajes de una sala y caja para escribir ahí mismo (zona de la Cloaca) |
| `cloaca.dart` | Cloacas (clanes de hasta 25): modelos de `cloaca_mia`/`cloaca_ranking`, `NubeCloacas` (crear, unirse, salir, expulsar, cobrar premio, `cloaca_bono`), `PantallaZonaCloaca` (zona propia con barra CLOACA/LIGA/CHAT; se abre desde YO con `TarjetaMiCloaca`, `abrirCloaca()` o `ir('cloaca' | 'cloaca_liga' | 'cloaca:<id>')`), `RankingCloacasVista` (mi Cloaca o la liga), `PestanaCloaca` (vista CHAT), `TarjetaCloaca` (tarjeta del cierre semanal en el chat); el bono de producción lo aplica `imperio/motor.dart` (`bonoCloaca`) |
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
| `diagnostico.dart` | `Diagnostico`: errores sin atrapar (`error_app`), datos del teléfono (`equipo`), por qué se cerró (`app_salida`), partidas cortadas y fotos de memoria; prende `telefonoLiviano` (Android Go o < 3 GB: `Sonido.liviano`, caché de imágenes chica). Canal `rey_cagon/equipo` en MainActivity.kt. Símbolos del APK directo en `~/.rey-cagon/simbolos/<build>` |
| `animaciones.dart` | Niveles de movimiento |
| `tema.dart` | `Paleta`, `tema()`, `Rotulo`, `numeros()` |
| `emoji.dart` | Mapa emoji → PNG Fluent, widget `Emoji` |
| `onboarding.dart`, `recordatorio.dart`, `periodos.dart`, `peso.dart`, `tipos.dart`, `popups.dart`, `comunidad.dart`, `actualizar.dart`, `recuperar.dart`, `invitar_play.dart` | Lo que dice el nombre |

## Base (Supabase)

Tablas: `profiles` (total en `cagadas`, `placer_desbloqueado`, accesorios), `cagadas` (`tipo`, `peso`, `placer`, `etiquetas`), `follows`, `mensajes`, `mensaje_reportes`, `bloqueos`, `push_tokens`, `desbloqueos`, avisos y retos, muro (`muro`, `muro_likes`, `muro_comentarios`, `muro_reportes`). RPC: `leaderboard`, `ranking_placer`, `victorias`, `es_admin`, `muro_feed`. Triggers: `limitar_cagadas` (una por hora), `cagadas_contar`, `cagadas_racha` (tarjeta en el chat), `validar_desbloqueos`, `validar_secreto`, `validar_muro`, `validar_muro_comentario`, `contar_reportes_muro` (3 reportes ocultan el post).
Edge Function `supabase/functions/notificaciones` manda los push (FCM v1).

## Exploits

- Todo nerf va en el servidor (trigger o RPC), nunca solo en la app.
- Cagar y deshacer: `limitar_cagadas` + `cagadas_borradas`. Un deshacer rápido al día es gratis; desde el segundo cuenta la hora de la borrada; al tercero en 24 h (o dos en una hora) se tapa la poceta 3 h (`pocetas_tapadas`, hint `poceta_tapada`, logro secreto). `imperio_cargar` descuenta Fichas de cagadas cobradas y borradas.
- Sospechas: tabla `sospechas` (la llenan triggers y el cron `detectar_exploits`), se ven en el panel (`panel_sospechas`). Consultas a mano en `supabase/consultas/exploits.sql`. Para un exploit nuevo: consulta ahí, chequeo en `detectar_exploits()` con un tipo nuevo, nerf en el servidor.
