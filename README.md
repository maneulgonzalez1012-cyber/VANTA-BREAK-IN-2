# VANTA | BREAK IN 2

Script con interfaz Rayfield Gen2 para Break In 2.

## La regla

**Ninguna acción dice "solicitud enviada".** Cada botón hace cuatro cosas:

1. **Dispara** el remoto.
2. **Verifica** en el cliente que pasó de verdad — leyendo la mochila, la vida,
   el stat, o el Humanoid del NPC.
3. **Si no pasó**, reintenta por otra vía (otro remoto, otra forma de
   argumentos, otro ítem).
4. **Informa qué ocurrió**, con `✔` o `✖` y el motivo.

Si el servidor lo rechaza, lo ves en la pantalla. No hay éxito falso.

## Carga

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/loader.lua"))()
```

Para probar una branch sin merge:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/<branch>/loader.lua"))()
```

## PlaceIds

| Lugar | PlaceId |
| --- | --- |
| Historia | `13864667823` |
| Lobby privado | `14775231477` |
| Lobby | `13864661000` |

## Ejecutar, no pedir

La mitad de las funciones del script no mandan nada. Escriben la propiedad local
cada frame desde `RunService.Stepped`, así que el servidor no puede rechazarlas:

- WalkSpeed, JumpPower, salto infinito
- Noclip (con restauración real de colisiones al apagar)
- Fullbright
- ESP
- Daño de último recurso (marcado como *local*, porque el servidor puede revertirlo)

Lo que sí es remoto se verifica contra el estado del cliente.

## Cómo se verifica cada cosa

| Acción | Se dispara | Se verifica con | Respaldo si falla |
| --- | --- | --- | --- |
| Dar objeto | `GiveTool(nombre)` | el ítem aparece en la mochila | `Vending(...)` para armas y armadura, luego el nombre con espacios |
| Curar | `Energy(cantidad, ítem)` | la vida sube | escalera Pizza → Gold Pizza → Rainbow Pizza |
| Curar a todos | `GiveTool("GoldenApple")` + `HealTheNoobs()` | manzana equipada; vida de aliados si el juego los expone | — |
| Entrenar | `RainbowWhatStat(stat)` | el valor del stat sube | reintenta y, si no sube, lo dice |
| Atacar | `HitBadguy(modelo, daño, 4)` | el Humanoid del NPC baja | parte raíz, 2 argumentos, y por último escritura local |
| Rol de lobby | `OutsideRole(ítem, true, false)` | la herramienta del rol llega | variante de un solo argumento |
| Teleport | escritura de `CFrame` | el personaje sigue en el destino | detecta anti-teleport y lo dice |

## Remotos

| Remoto | Firma |
| --- | --- |
| `Events.GiveTool` | `(nombre)` |
| `Events.Vending` | `(3, ítem, categoría, jugador, 1)` |
| `Events.Energy` | `(delta, ítem)` |
| `Events.HealTheNoobs` | `()` |
| `Events.RainbowWhatStat` | `("Strength" \| "Speed")` |
| `Events.HitBadguy` | `(modelo, daño, 4)` |
| `Events.IceSlip` | `(Vector3)` — lo corta el anti-slip |
| `RemoteEvents.OutsideRole` | `(ítem, true, false)` |

## Seguridad de ejecución

- **Presupuesto de paquetes**: 60 remotos/s. Los reintentos de verificación no
  pueden convertirse en flood. Lo descartado se cuenta y se muestra.
- **Auto-curación** solo actúa si estás herido, y no pide ítem si ya lo tienes.
- **`Safe`** envuelve todo con `xpcall` y guarda el traceback.
- **Parada limpia**: devuelve WalkSpeed, JumpPower, colisiones, luz, destruye el
  ESP y reinstala el `__namecall` original.
- **Degradación**: sin `hookmetamethod`, semi godmode y anti-slip se apagan y la
  UI lo dice.

## Funciones

- Semi godmode y anti-slip
- Curación y auto-curación verificada
- Curar a todos
- Objetos y armas (28 ítems)
- Entrenamiento de velocidad y fuerza con lectura de stat
- Ataque a NPC / auto-ataque con escalera de argumentos
- ESP de jugadores
- WalkSpeed, JumpPower, salto infinito y noclip
- Teleport a jugador
- Fullbright
- Roles de lobby
- Diagnóstico de remotos y estado
- Limpieza al cerrar

## Verificación

Se ejecutó completo contra un árbol de Roblox simulado con dos servidores: uno
que **acepta** cada remoto y uno que **rechaza** todos.

- **Acepta**: 25 acciones `✔` verificadas, 0 crash.
- **Rechaza**: 23 acciones `✖`, cada una con su motivo, 0 éxito falso, 0 crash.

Sin el servidor real no se puede probar lo que el juego decide. Por eso el
script no promete: comprueba, y cuando no puede comprobar lo dice.

## Notas

- Los remotos cambian con las actualizaciones. `Diagnóstico → Comprobar remotos`
  marca los que faltan.
- `HitBadguy` por escritura local daña en tu pantalla, no en la partida. Está
  marcado como *local* precisamente para que no te confunda.
- El rol de lobby depende del gamepass o de que estés en el lobby correcto.
