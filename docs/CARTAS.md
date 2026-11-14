# Cartas, sobres y misiones

El TRONO se rehace (opción "Modo juego") con misiones del día al azar. Deslizando el TRONO a la
izquierda aparece el lado secreto (solo quien tiene `placer_desbloqueado`): sobres de cartas.

## Cartas

- 128 cartas, número `n` 1..128. Cada una: emoji (único entre cartas), nombre y frase es/en, rareza.
- Rarezas: común 64, rara 36, épica 20, legendaria 8. Se marcan con 1 a 4 cuadritos.
- Catálogo en `lib/cartas/catalogo.dart` (texto) y `public.cartas_rareza` (lo que usa el servidor
  para sortear). Los dos tienen que coincidir: lo vigila `test/cartas_catalogo_test.dart`.

### Niveles (con repetidas)

| nivel | nombre | repetidas que cuesta subir a este nivel |
|---|---|---|
| 0 | descolorida | (así sale la primera vez) |
| 1 | normal | 1 |
| 2 | holográfica | 2 |
| 3 | plateada | 3 |
| 4 | dorada | 4 |
| 5 | holográfica rainbow | 5 |

Mejorar es un botón (MEJORAR) en la carta; gasta repetidas. Rainbow = 16 copias en total.
Repetidas disponibles = `copias - 1 - gastadas`.

## Sobres

| tipo | cartas | común | rara | épica | legendaria | garantía |
|---|---|---|---|---|---|---|
| normal | 3 | 60 | 28 | 10 | 2 | |
| plata | 4 | 40 | 38 | 18 | 4 | |
| oro | 5 | 20 | 40 | 30 | 10 | al menos 1 épica o más |
| rey | 5 | 10 | 35 | 35 | 20 | al menos 1 legendaria |

- Sobre diario: 1 gratis por día local. Tipo al azar: normal 80, plata 14, oro 5, rey 1.
- Las misiones sueltas no dan nada. Cumplir las 3 del día da 1 sobre (se cobra una vez por día):
  con el mismo sorteo del diario, o plata 70, oro 25, rey 5 si una de las 3 era rara.
- Dentro de una rareza la carta sale pareja al azar. Todo se sortea en el servidor al abrir.
- Los sobres se guardan aunque no tengas el lado secreto; abrirlos sí lo pide.

## Misiones

- 3 por día local (zona de `imperio_zona`), sacadas al azar de un grupo de ~45, sin repetir las de
  los 6 días anteriores. Algunas son raras (más difíciles, salen menos, mejoran el sobre del día).
- Todas se comprueban en el servidor con datos reales (cagadas, muro, chat, minijuegos, retos...).
  Nada que solo pase en el teléfono (la mosca, el pujo).
- Textos en `lib/cartas/misiones.dart` por clave; condición en `public.mision_progreso`.

## Logros (secretos, lado secreto)

`cartas_10`, `cartas_30`, `cartas_64`, `cartas_100`, `cartas_128` (cartas distintas),
`carta_dorada` (primera dorada), `carta_rainbow` (primera rainbow), `sobre_rey` (abrir un sobre del rey).
Los da la app con `ganarLogro` al ver el estado.

## RPC (todas `security definer`, por `auth.uid()`)

- `misiones_hoy()` → `{dia, proximo, cobrada, misiones: [{id, clave, rara, meta, progreso}]}`.
  Crea las 3 del día si faltan. `proximo` = próxima medianoche local (timestamptz). `cobrada` = ya se
  cobró el sobre de hoy.
- `misiones_cobrar()` → `{sobre: {id, tipo}}`. Solo con las 3 de hoy cumplidas. Error `no_hechas` / `ya_cobrada`.
- `cartas_estado()` → `{dia, proximo, sobres: [{id, tipo, origen}], cartas: [{n, copias, nivel, gastadas}], ultimas: [n...]}`.
  Crea el sobre diario si falta. `sobres` = sin abrir. `ultimas` = las 6 últimas sacadas, la más nueva primero.
  Error `sin_secreto` si no tiene el lado secreto.
- `cartas_abrir(p_sobre bigint)` → `{tipo, cartas: [{n, nueva, copias, nivel}]}`. Idempotente.
- `cartas_mejorar(p_n smallint)` → `{n, nivel, copias, gastadas}`. Error `sin_repetidas` / `nivel_max`.
