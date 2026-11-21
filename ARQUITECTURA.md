# VANTA — un archivo, ocho módulos

Un solo script. Los módulos van juntos, cada uno en su sección, y **activar
una zona no toca las otras**.

```
src/
├── init.lua        arranque y menú
├── sections.lua    carga y aislamiento de las secciones
├── state.lua       las banderas de todos, con prefijo
├── remotes.lua     única puerta al servidor, con firmas verificadas
├── kit.lua         envoltorio del menú, a prueba de fallos
├── survival.lua    curar, curar a todos, semi god, anti-slip, auto-cura
├── trainer.lua     fuerza y velocidad
├── items.lua       dar y equipar objetos
├── combat.lua      daño a NPC y auto-ataque
├── movement.lua    velocidad, salto, noclip
├── visuals.lua     ESP y fullbright
├── navigation.lua  teleports
└── lobby.lua       roles Hacker y Nerd
```

Todo Luau. No hay otro lenguaje en el proyecto: ni en el script ni en el
empaquetado. `tools/build.py` solo copia texto de un archivo a otro.

---

## Qué significa "solo esa zona se prende"

Cuatro cosas, cada una comprobada con un test:

### 1. Cada zona tiene su tab

Ocho tabs, una por sección. Tocar un botón de Supervivencia no repinta
Objetos ni Combate.

### 2. Cada bandera lleva el nombre de su sección

`state.lua` es una tabla sola, y las llaves van con prefijo:

```
survival.autoHeal    survival.semiGod    survival.antiSlip
combat.auto          movement.speed      movement.noclip
visuals.esp          visuals.fullbright
```

Medido: al encender Supervivencia, **la única llave que cambia es
`survival.autoHeal`**. Ninguna otra se mueve. Y al encender Combate, la
bandera de Supervivencia sigue encendida.

### 3. Cada sección registra sus conexiones a su nombre

Nada de `Heartbeat:Connect(...)` suelto. Todo pasa por
`Sections.Connect("movement", RunService.Stepped, ...)`, así cerrar una
sección o el script entero corta solo lo suyo.

Medido: 7 conexiones registradas, 7 cortadas al cerrar, **0 quedan**.

### 4. Ejecutar dos veces no rompe nada

Antes, volver a pegar el script dejaba **dos ventanas, dos hooks y dos
Heartbeats** sobre el mismo personaje. Activabas algo y la copia vieja lo
deshacía en el mismo frame. Ahora, al arrancar, se apaga la copia anterior:

```lua
local previous = getgenv().VANTA_BI2
if type(previous) == "table" and type(previous.Stop) == "function" then
    pcall(previous.Stop)
end
```

Además el hook del semi godmode **ya no guarda copias de sus banderas**.
Antes tenía `hook.semiGod` y `hook.antiSlip`, y el `Heartbeat` las
recalculaba en cada frame: encendías semi god, la UI decía "activo", y al
frame siguiente el `Heartbeat` escribía `false` encima. Duraba un parpadeo.
Ahora el hook lee `state.lua` en cada llamada: una sola fuente de verdad.

Medido: `Energy(-25)` con semi god deja la vida en **100**; al apagarlo,
vuelve a **75**.

### 5. Una sección rota no tumba a las demás

Cada `Setup()` corre dentro de un `pcall` en su propio hilo. Si una revienta,
queda marcada como rota, se avisa en Diagnóstico, y las otras siete siguen
funcionando.

Medido: con `combat` lanzando a propósito al cargar, **7/8 secciones sanas** y
6 conexiones vivas (la de combate nunca llegó a crearse).

---

## El contrato de un módulo

```lua
local X = {}

local State = require("state")
local Sections = require("sections")

function X.Setup()
    -- opcional. Corre una vez, dentro de pcall.
    Sections.Connect("x", game:GetService("RunService").Heartbeat, function()
        if not State.Get("x.algo") then return end
        -- ...
    end)
end

function X.HacerAlgo()
    -- Toda acción devuelve (ejecutado, motivo).
    -- `ejecutado` es true SOLO si el efecto se comprobó.
    return true, "qué pasó exactamente"
end

return X
```

Reglas:

- **Nunca** `require` de otro módulo de los ocho. Si hacen falta datos
  compartidos, van en `state.lua` o en `remotes.lua`.
- **Todo** lo que se encienda se apaga: `Setup` guarda lo original y
  `Restore`/`Shutdown` lo devuelve.
- **Toda** acción devuelve `(ejecutado, motivo)`. Nada de "solicitud enviada".

---

## Remotos: lo que se verificó

Se cruzaron cinco scripts públicos que funcionan para sacar la forma real de
cada remoto. No hay adivinanzas:

| Remoto | Argumentos | Qué hace |
| --- | --- | --- |
| `GiveTool` | `(nombre sin espacios)` | da un objeto |
| `Vending` armadura | `(3, "Armor2", "Armor", nombre, 1)` | compra armadura |
| `Vending` arma | `(3, "Crowbar2", "Weapons", nombre, 1)` | compra arma |
| `Energy` | `(cantidad, "Pizza")` | cura. Con negativo, **daña** |
| `HealTheNoobs` | `()` | cura al equipo, exige manzana en la mano |
| `RainbowWhatStat` | `("Speed" \| "Strength")` | entrena |
| `HitBadguy` | `(modelo, 64.8, 4)` | daña NPC |
| `IceSlip` | `(Vector3)` | te resbala; se bloquea en el hook |
| `OutsideRole` | `("Phone" \| "Book", true, false)` | rol del lobby |
| `OutsideFood` | `(6, {item2=, placement=})` | objeto de tienda |
| `RoadMissionEvent` | `(1, parte, 5)` | árbol de la misión |
| `LarryEndingEvent` | `(llave, true)` | final |
| `KeyEvent` | `()` | palanca |
| `CurePlayer` | `(jugador, jugador)` | cura a alguien |
| `CatFed` | `(nombre)` | alimentar al gato |
| `LouiseGive` | `(2)` | Louise |

**Dos carpetas**: el juego expone los mismos remotos en
`ReplicatedStorage.Events` (historia) y en `ReplicatedStorage.RemoteEvents`
(lobby). `remotes.lua` prueba las dos, porque un script que solo mira una
falla en silencio en el otro lugar.

Fuentes cruzadas: `NoobHubV1/Break In 2 Story.lua`, `RScriptz/BreakIn2.lua`,
`Vcsk/BreakingBlitz.lua`, `carlwashere/BreakIn2.lua`,
`Aviiela/CookieHub`.

---

## Cómo se comprueba que algo pasó

| Acción | Cómo sabe que funcionó |
| --- | --- |
| Curar | la vida del Humanoid subió |
| Curar a todos | la manzana está en la mano y el remoto existe |
| Dar objeto | el `Tool` está en la mochila o en la mano |
| Atacar NPC | la vida del NPC bajó (si solo bajó en tu pantalla, **se dice**) |
| Entrenar | el número del stat subió en la interfaz |
| Teleport | sigues en el destino 0.6 s después |
| Rol | tienes la herramienta del rol |
| Velocidad / noclip | la propiedad escrita es la que pediste |
| ESP | el Highlight existe y cuelga de tu carpeta |

Cuando solo funciona en el cliente, lo dice sin adornos:

```
✖ Atacar NPC cercanos: 1 dañados, 0 caídos, 1 solo en tu pantalla
✖ Dar y equipar: Golden Apple no llegó a la mochila (el servidor lo rechazó)
```

---

## El script único

`tools/build.py` junta los 13 módulos en `VANTA-BreakIn2.lua`. **No los
concatena**: cada uno va en su propia entrada de `FILES` y se compila por
separado con `loadstring`.

```lua
FILES["survival"] = [==[ ...código... ]==]
FILES["combat"]   = [==[ ...código... ]==]
```

Por qué importa:

- Un error de sintaxis en un módulo no impide que arranquen los otros.
- Un `return` en un módulo no termina el script.
- Dos módulos pueden usar el mismo nombre de variable local sin chocar.
- Las dependencias circulares se detectan y se avisan.

Sobrecarga del cargador: 2 KB sobre 70 KB de código.

```bash
python3 tools/build.py    # regenerar VANTA-BreakIn2.lua
./tools/verify.sh         # comprobar todo
```

---

## Verificación

```
./tools/verify.sh  →  TODO OK
```

| Control | Qué mide |
| --- | --- |
| Sintaxis | 13 módulos + el bundle compilan |
| Aislamiento `ok` | 8/8 secciones sanas, 7 conexiones |
| Aislamiento `broken` | con una rota, 7/8 sanas |
| Aislamiento `toggle` | tocar una sección no cambia banderas ajenas |
| Aislamiento `restore` | `WalkSpeed 64→16`, `CanCollide false→true` |
| Aislamiento `hook` | `Energy(-25)` no baja la vida con semi god, y sí al apagarlo |
| Aislamiento `teardown` | 7 cortadas, 0 quedan |
| Reentrada `once/twice/thrice` | 1 sola ventana viva tras 1, 2 o 3 ejecuciones |
| Reentrada `stopstart` | tras `Stop`, volver a ejecutar deja 8/8 sanas |
| Reentrada `stopstop` | cerrar dos veces no explota; `getgenv` queda libre |
| Bundle | 8 tabs, 31 botones, arranque completo, `Stop` limpio |
| Loader | 12 escenarios con su mensaje correcto |

Los tests están en `tools/tests/` y corren desde el repo, sin rutas
absolutas ni dependencias fuera de Python y `lupa`.
