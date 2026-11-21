# VANTA — Strongman Simulator

Cheat para **Strongman Simulator** (The Gang Stockholm, `PlaceId 6766156863`).
Un solo script, 15 módulos dentro, cada pestaña aislada de las demás.

> El "[ESP]" de la página de Roblox es la etiqueta en español; el juego se
> llama *Strongman Simulator*.

## Cargar

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/arena/51187ad8-vanta-break-in-2/StrongmanLoader.lua"))()
```

El loader prueba varias URLs y usa la primera que responda: la del repo con
el nombre nuevo, la del repo actual y `main`. Renombres el repositorio o no,
el comando de arriba sigue entrando.

## Qué hace

| Pestaña | Qué hace | Cómo lo comprueba |
| --- | --- | --- |
| **Entrenamiento** | Sube fuerza con `StrongMan_UpgradeStrength` | Mide la fuerza antes y después |
| **Arrastre** | Lleva tus piezas a la meta, sujeta objetos | Mide la energía y si la pieza se sujetó |
| **Movimiento** | Velocidad, salto, noclip, salto infinito, flotar | Lee la propiedad después de escribirla |
| **Mundo** | Quita puertas, quita el peso extra | Cuenta los objetos que cambió |
| **Jugadores** | ESP y teleport | El Highlight existe; el teleport se mide a 0,6 s |
| **Códigos** | Canjea los códigos públicos | Mide la energía antes y después |
| **Mascotas** | Lista las tuyas y el catálogo | Lee tu inventario |
| **Personaje** | Tamaño, anti-AFK | Lee la escala del Humanoid |
| **Diagnóstico** | Dice qué remotos hay y qué falta | — |

**Nada de "solicitud enviada".** Cada acción devuelve `(ejecutado, motivo)` y
`ejecutado` solo es `true` si el efecto se vio en el cliente.

```
✔ Curarme ahora: strength +50 (120 → 170)
✖ Subir fuerza: el servidor no aplicó el cambio (120 → 120)
```

## Lo verificado y lo que no

Todo está en [STRONGMAN.md](STRONGMAN.md), separado en dos listas. Resumen:

- **Verificado**: `ReplicatedStorage.StrongMan_UpgradeStrength` (RemoteFunction,
  con multiplicador), la estructura `Workspace.Areas[...].Goal`,
  `PlayerDraggables[UserId]`, los `ProximityPrompt` del gimnasio y de los
  objetos, y que el servidor ancla al personaje mientras arrastras.
- **No verificado**: el remoto de códigos y el de equipar mascotas. En vez de
  inventarlos, el script los busca por nombre, y si no aparecen **lo dice en
  pantalla**. Es preferible un módulo honesto a un botón que finge.

## Desarrollo

```bash
cd sm
python3 build.py      # sm/src/ (15 módulos) -> StrongmanSimulator.lua
./verify.sh           # 24 comprobaciones
```

`build.py` no concatena: cada módulo va en su propia entrada de `FILES` y se
compila aparte. Un módulo roto no impide que arranquen los otros.

## Verificación

```
./verify.sh  →  TODO OK
```

| Bloque | Qué mide |
| --- | --- |
| Sintaxis | 15 módulos + el script único + el loader |
| `ok` | 9 pestañas, 19 botones, 9/9 secciones |
| `strength` | la fuerza sube de verdad (120 → 170) |
| `grind` | 10 llamadas suben la fuerza |
| `pull` | la energía sube al llegar a la meta (5000 → 5250) |
| `rejected` | si el servidor rechaza, la acción **dice que falló** |
| `esp` | el Highlight existe y no deja restos al apagar |
| `teleport` | de 141 a 3 studs, medido |
| `stop` | 0 conexiones y velocidad restaurada |
| `twice` | dos ejecuciones dejan una sola ventana |
| Loader | 9 escenarios: 404, sin red, vacío, sintaxis, error, sin estado, otro lugar, sin personaje |

## Estructura

```
StrongmanSimulator.lua   el entregable
StrongmanLoader.lua      el arranque con barra real
STRONGMAN.md             investigación: lo verificado y lo que no
sm/
├── src/                 15 módulos
├── tests/               harness + smoketest + loadertest
├── build.py
└── verify.sh
vanta/                   el proyecto anterior (Break In 2), intacto
```

## Si algo falla

El loader nunca se queda mudo: si una etapa falla, se marca en rojo, se
escribe el motivo y el mensaje **se queda en pantalla**. Pásame esa línea.
