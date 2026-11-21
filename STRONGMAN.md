# Strongman Simulator — lo que está verificado

Juego: **Strongman Simulator**, de The Gang Stockholm.
`PlaceId 6766156863` · `UniverseId 2564505263` · 1.600 millones de visitas.

El **"[ESP]"** de la captura no es parte del nombre: es la etiqueta de la
versión en español de la página de Roblox.

---

## Cómo se juega (para saber qué tiene sentido automatizar)

1. Arrastras objetos pesados pasando la línea → ganas **energía**.
2. Gastas la energía en el gimnasio → ganas **fuerza**.
3. La fuerza te sube de rango (Baby Noob → Dominator) y te deja arrastrar
   cosas más pesadas.
4. Quitas la salida para abrir zonas nuevas (Start, Gym, Food, Arcade, Farm,
   Castle, Steampunk, Disco… y hasta `Area18_Apartment`).
5. Hay mascotas y códigos.

Las dos palancas reales son **energía** y **fuerza**. Todo lo demás
(velocidad, noclip, ESP, teleport) es cliente y no depende del servidor.

---

## Remotos y estructura: verificado

Corpus: 1.694 archivos Lua descargados de 17 repos de GitHub relacionados con
el juego. La mayoría están ofuscados (PSU 4.5, MoonSec V2/V3, Boronide, Burn),
así que **solo cuento lo que aparece en código legible y coincide en varias
fuentes**.

### `ReplicatedStorage.StrongMan_UpgradeStrength` — RemoteFunction

Aparece en **10 lugares** y en 5 repos distintos:

```lua
game:GetService("ReplicatedStorage").StrongMan_UpgradeStrength:InvokeServer()
game:GetService("ReplicatedStorage").StrongMan_UpgradeStrength:InvokeServer(multiplicador)
game:GetService("ReplicatedStorage").StrongMan_UpgradeStrength:InvokeServer(2 ^ 1024)
```

- Es un **RemoteFunction** (`InvokeServer`, no `FireServer`), y cuelga de
  `ReplicatedStorage` directamente, no de una carpeta.
- El argumento es un multiplicador de fuerza. Sin argumento funciona.
- **No está verificado** cuál es el tope que acepta el servidor. El script lo
  prueba y mide el resultado: si el número no sube, lo dice.

### Estructura del mundo

Confirmada por tres scripts independientes:

```
Workspace
├── Areas
│   ├── Area1_Gym
│   │   └── Gym.TrainingEquipment.WorkoutStation.Collider
│   │   └── Gym.ProximityPrompt
│   ├── Area9_Space, Area14_Retro, Area18_Apartment …
│   │   ├── DraggableItems   (MeshPart con InteractionPoint)
│   │   └── Goal             (la línea que hay que cruzar)
├── PlayerDraggables
│   └── [UserId]             (las piezas que arrastras; algunas traen un
│                             hijo llamado "Coins")
└── BadgeColliders
```

- Para arrastrar: `ProximityPrompt:InputHoldBegin()` + `InputHoldEnd()`, o
  `fireproximityprompt(prompt)` si el ejecutor lo expone.
- El objeto que vale la pena se reconoce por `StringValue "Title"`.
- El gimnasio se usa llevando al personaje al `Collider` del `WorkoutStation`
  y disparando sus `ProximityPrompt`. Mientras arrastras o entrenas,
  `HumanoidRootPart.Anchored` pasa a `true`: eso sirve para saber si el
  servidor aceptó el gesto.

### Lo que NO está verificado

- El nombre exacto del remoto de **códigos**. En el corpus aparece
  `RedeemCode:InvokeServer(código)`, pero **todos** los casos salen de scripts
  de otros juegos (Brawl Legends, Bubble Gum Simulator). No lo doy por bueno:
  el script lo busca por nombre entre varios candidatos y, si no lo encuentra,
  lo dice en pantalla en vez de fingir.
- El remoto de **equipar mascotas**. Igual: se busca, no se inventa.
- El nombre del stat de energía y de fuerza. `leaderstats.Strength` /
  `leaderstats.Energy` es lo habitual en este género, pero no aparece escrito
  en ninguna fuente de este juego. El script lee el stat probando varios
  sitios y **muestra el que encontró**.
- El tope de fuerza que acepta el servidor.
- Las coordenadas: las de los scripts públicos son de versiones anteriores
  del mapa. El script usa `Area1_Gym` y la `Goal` del área activa, nunca un
  CFrame clavado.

---

## Códigos conocidos (públicos, de la descripción del juego)

```
1500likes  5000likes  10000  25k  10m  100M  400M  season1  strongman
```

No todos siguen activos. El script los manda uno a uno y comprueba si la
energía cambió.

---

## De dónde sale todo esto

| Repo | Qué aportó |
| --- | --- |
| `1Shawn1/Strongman-Simulator` | `StrongMan_UpgradeStrength`, gimnasio, `PlayerDraggables`, `Coins` |
| `StarPikicito/Random-Scripts` | `ProximityPrompt` del gimnasio, `Anchored`, `BadgeColliders`, códigos |
| `Brineeee/Strongman-Simulator-SHAREHACK` | `InputHoldBegin/End`, `Areas[...].Goal`, `PlayerDraggables` |
| `OptionalCosmic/StrongManSimulator` | `Workout_Mul`, `Area9_Space`, `ProximityPrompt` |
| `Squex01/StrongmanSimulatorScript` | misma familia de remotos (ofuscado) |

El resto de los 17 repos estaban ofuscados de arriba abajo y no se usaron.
Nada de lo que hay en el script viene de adivinar: lo que no se pudo
comprobar está en la lista de "no verificado" y el script lo trata como tal.
