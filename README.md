# VANTA | BREAK IN 2

Script con interfaz Rayfield Gen2 para Break In 2, reescrito sobre los remotos
verificados de la historia y del lobby.

## Carga rápida (recomendado)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/loader.lua"))()
```

El loader muestra la pantalla de carga, descarga `VANTA.lua`, lo ejecuta y se
cierra. Si algo falla, deja el error en pantalla y en la consola en vez de
desaparecer en silencio.

## Carga directa

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/VANTA.lua"))()
```

## Probar una branch sin merge

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/<branch>/loader.lua"))()
```

`main` solo sirve la versión mergeada. Para probar cambios sin merge, apunta a
la branch.

## PlaceIds

| Lugar | PlaceId |
| --- | --- |
| Historia | `13864667823` |
| Lobby privado | `14775231477` |
| Lobby | `13864661000` |

El script no bloquea por PlaceId: en un lugar ajeno los remotos simplemente no
existen y el diagnóstico lo dice.

## Remotos usados

Todos viven en `ReplicatedStorage.Events` salvo donde se indique.

| Remoto | Firma | Uso |
| --- | --- | --- |
| `GiveTool` | `(nombre)` | Dar herramienta o comida |
| `Vending` | `(3, item, categoria, jugador, 1)` | Armor (`Armor2`), armas (`Weapons`) |
| `Energy` | `(delta, item)` | Cura (`+25`) o daño (`-n`) |
| `HealTheNoobs` | `()` | Curar a todos los NPC |
| `RainbowWhatStat` | `("Strength"\|"Speed")` | Entrenar |
| `HitBadguy` | `(modelo, daño, 4)` | Daño a NPC — el modelo, no la parte |
| `RoadMissionEvent` | `(1, TreeHitPart, 5)` | Romper árboles |
| `OutsideFood` | `(6, {item2=, placement=})` | Caja de pizza / Bloxy Pack |
| `LarryEndingEvent` | `(clave, true)` | Final secreto |
| `IceSlip` | `(Vector3)` | Resbalón — lo bloquea el anti-slip |
| `OnDoorHit` | `(parte)` | Golpear puerta |
| `CatFed`, `LouiseGive`, `KeyEvent` | — | Verificados, sin botón dedicado |
| `ReplicatedStorage.RemoteEvents.OutsideRole` | `(item, true, false)` | Roles Hacker / Nerd (solo lobby) |

## Funciones

**Inicio** — kit rápido (armor + curas + arma + entrenamiento), entrenar,
matar NPC cercanos, curar a todos.

**Supervivencia**
- Semi godmode: convierte el daño negativo de `Energy` en 0
- Anti-slip: corta `IceSlip` completo
- Cura: manual o automática, con cantidad (10–150 HP) e intervalo
- Entrenamiento: fuerza / velocidad / ambos, con repeticiones

**Objetos** — 29 ítems, acceso rápido a 10, y spawn de comida en la cocina por
slot.

**Combate** — radio, daño, golpes por NPC e intervalo configurables; ataque
único, barrido completo, auto-ataque, congelar NPC, traer NPC, romper
barricadas.

**Mundo** — 13 teleports de la historia, quitar viento/granizo, quitar lodo,
empujar NPC, final secreto, golpear puerta.

**Movimiento** — WalkSpeed (16–300), JumpPower (50–300), salto infinito,
noclip, teleport a jugador por nombre exacto o parcial.

**Visuales** — ESP de jugadores, ESP de enemigos, fullbright.

**Lobby** — solicitar Hacker, solicitar Nerd, tocar objetos con
`TouchInterest`.

**Diagnóstico** — escaneo de 15 remotos, volcado del árbol de
`ReplicatedStorage`, estado del script, y parada limpia.

## Lo que es local y lo que no

| Local (no toca el servidor) | Remoto (el servidor decide) |
| --- | --- |
| WalkSpeed, JumpPower, salto infinito | Objetos, armas, armor |
| Noclip, congelar NPC, empujar NPC | Cura, `HealTheNoobs` |
| Fullbright, ESP | Entrenamiento, daño a NPC |
| Quitar viento / lodo | Barricadas, comida, final secreto |

`FireServer` no confirma nada. Un paquete enviado puede ser rechazado por el
servidor sin aviso. Los contadores del script cuentan envíos, no resultados, y
lo dicen así.

## Seguridad de ejecución

- **Limitador de paquetes**: 40 remotos por segundo. Lo que sobra se descarta y
  se cuenta en `Paquetes descartados`. Evita el kick por spam.
- **Auto-curación** solo actúa si la vida está por debajo del máximo, y no pide
  pizza nueva si ya hay una en la mochila.
- **`Safe`** envuelve todo con `xpcall` y guarda el traceback en
  `Estado del script`.
- **Parada limpia**: desconecta todo, restaura colisiones, luz, WalkSpeed,
  JumpPower, desancla NPC y devuelve el `__namecall` original.
- **Degradación**: si el executor no expone `hookmetamethod`, semi godmode y
  anti-slip se apagan solos y la UI lo dice.

## Verificación

`VANTA.lua` se ejecutó completo contra un árbol de Roblox simulado con los 15
remotos reales: 77 elementos de UI registrados, los 77 callbacks disparados sin
un solo error, y los argumentos de cada remoto comprobados contra la referencia
del juego.

## Parámetros rápidos

| Constante | Línea aprox. | Qué controla |
| --- | --- | --- |
| `RateLimit.Max` | ~230 | Remotos por segundo antes de descartar |
| `Items` | ~280 | Lista del dropdown |
| `PlaceCFrames` | ~1200 | Teleports |
| `RemoteChecks` | ~2000 | Lista del diagnóstico |

## Notas

- Los remotos pueden cambiar con una actualización del juego. El diagnóstico
  marca cuáles faltan.
- El final secreto y el rol de lobby dependen de que el servidor acepte; no hay
  forma de confirmarlo desde el cliente.
