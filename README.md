# VANTA | BREAK IN 2

Script con interfaz Rayfield Gen2 para Break In 2.

**Arquitectura modular**: 9 módulos independientes, cada uno en su archivo,
con su propio estado y sus propias conexiones. Un módulo roto no tumba a los
demás y ninguno puede interferir con otro. Detalle en
[ARQUITECTURA.md](ARQUITECTURA.md).

## La regla

**Ninguna acción dice "solicitud enviada".** Cada botón:

1. **Dispara** el remoto.
2. **Verifica** en el cliente que pasó de verdad — mochila, vida, stat o el
   Humanoid del NPC.
3. **Si no pasó**, intenta otra variante de argumentos u otro remoto.
4. **Informa qué ocurrió**, con `✔` o `✖` y el motivo.

Y aprende: la variante que el servidor aceptó se guarda y la siguiente sesión
empieza por ahí.

## Carga

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/loader.lua"))()
```

Para probar una branch sin merge:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/<branch>/loader.lua"))()
```

## El loader

La barra **no es una animación**. Cada etapa se marca cuando ocurre de verdad:

| Etapa | Qué la hace pasar |
| --- | --- |
| `Conectar` | el loader arranca |
| `Descargar` | llegan los KB de `VANTA-BreakIn2.lua` (dos intentos de red) |
| `Compilar` | `loadstring` devuelve una función |
| `Ejecutar` | el script corre sin error |
| `Verificar módulos` | el script confirma que sus 9 módulos cargaron y 7/7 remotos existen |

La verificación la hace el **propio script** a través de `State.Verify()`, no una
copia de su lista. Una sola fuente de verdad.

Cómo se ve cada final:

| Situación | Marcas | Qué queda en pantalla |
| --- | --- | --- |
| Todo bien | ✔ ✔ ✔ ✔ ✔ | `9/9 módulos \| 7/7 remotos` |
| Remotos incompletos | ✔ ✔ ✔ ✔ **!** ámbar | `faltan X, Y (PlaceId ...)` |
| Módulo roto | ✔ ✔ ✔ ✔ **!** ámbar | `1 módulo roto (PlaceId ...)` |
| Red caída | ✔ **✖** · · · | `no se pudo descargar: HttpError 502` |
| Respuesta vacía | ✔ **✖** · · · | `no se pudo descargar: respuesta vacía` |
| Error de sintaxis | ✔ ✔ **✖** · · | `error de sintaxis: syntax error near '='` |
| Script falla al correr | ✔ ✔ ✔ **✖** · | `el script falló: ...` |
| Script corre pero no deja estado | ✔ ✔ ✔ ✔ **✖** | `corrió pero no dejó estado` |

Si hay `✖`, el mensaje **se queda en pantalla** y la barra no desaparece sola.
Un clic cierra. Un `!` ámbar significa que el script cargó pero estás en el lugar
equivocado o el juego cambió algo.

## PlaceIds

| Lugar | PlaceId |
| --- | --- |
| Historia | `13864667823` |
| Lobby privado | `14775231477` |
| Lobby | `13864661000` |

## Ejecutar, no pedir

Estas funciones no mandan remoto: se escriben en la propiedad cada frame desde
`RunService.Stepped`. El servidor no puede rechazarlas.

- WalkSpeed, JumpPower, salto infinito
- Noclip, con restauración real de colisiones al apagar
- Fullbright
- ESP

## Variantes por acción

El servidor decide qué firma acepta. Se prueban todas y gana la que produce un
efecto medible.

| Acción | Variantes (en orden) | Prueba |
| --- | --- | --- |
| Dar objeto | `GiveTool(sin espacios)` → `GiveTool(con espacios)`; armas y armadura empiezan por `Vending` | el ítem aparece en la mochila |
| Curar | `Energy(delta, ítem)` → `Energy(delta, bool, bool)` × Pizza → Gold Pizza → Rainbow Pizza | la vida sube |
| Entrenar | `"Strength"` → `"strength"` → `"STRENGTH"` | el stat sube |
| Atacar | `HitBadguy(modelo, daño, 4)` → `(parte, daño, 4)` → `(modelo, daño)` | el Humanoid del NPC baja |
| Rol de lobby | `OutsideRole(ítem, true, false)` → `OutsideRole(ítem)` | llega la herramienta del rol |
| Teleport | escritura de `CFrame` ×3 | el personaje sigue en el destino |

## Remotos

| Remoto | Firma |
| --- | --- |
| `Events.GiveTool` | `(nombre)` |
| `Events.Vending` | `(3, ítem, categoría, jugador, 1)` — `Armor2` para armadura, `Crowbar1/2/3` para palancas |
| `Events.Energy` | `(delta, ítem)` |
| `Events.HealTheNoobs` | `()` |
| `Events.RainbowWhatStat` | `("Strength" \| "Speed")` |
| `Events.HitBadguy` | `(modelo, daño, 4)` |
| `Events.IceSlip` | `(Vector3)` — lo corta el anti-slip |
| `RemoteEvents.OutsideRole` | `(ítem, true, false)` |

## Diagnóstico

- **Sondear firmas** — prueba cada variante, mide el efecto real y guarda la
  ganadora. Deja el informe en la consola (F9). Es lo primero que hay que
  pulsar en el juego.
- **Comprobar remotos** — dice cuáles de los 8 existen en el lugar actual.
- **Volcar ReplicatedStorage** — imprime el árbol por si el juego renombró algo.
- **Estado del script** — acciones ejecutadas, fallidas, reintentos, paquetes
  descartados, firmas aprendidas.

## Seguridad de ejecución

- **Presupuesto de paquetes**: 60 remotos/s. Los reintentos no pueden convertirse
  en flood. Lo descartado se cuenta.
- **Auto-curación** solo actúa si estás herido y no pide ítem si ya lo tienes.
- **`Safe`** envuelve todo con `xpcall` y guarda el traceback.
- **Parada limpia**: devuelve movimiento, colisiones, luz, destruye el ESP y
  reinstala el `__namecall` original.
- **Degradación**: sin `hookmetamethod`, semi godmode y anti-slip se apagan y la
  UI lo dice.

## Funciones

- Semi godmode y anti-slip
- Curación y auto-curación verificada
- Curar a todos
- Objetos y armas (29 ítems, incluida Diamond Crowbar)
- Entrenamiento de velocidad y fuerza con lectura de stat
- Ataque a NPC / auto-ataque con escalera de variantes
- ESP de jugadores
- WalkSpeed, JumpPower, salto infinito y noclip
- Teleport a jugador
- Fullbright
- Roles de lobby
- Diagnóstico y sonda de firmas
- Limpieza al cerrar

## Verificación

**Loader**: ejecutado contra siete escenarios (todo bien, remotos incompletos,
red caída, respuesta vacía, error de sintaxis, error en ejecución, script sin
estado). Cada uno termina en la etapa correcta con el mensaje correcto, y la
GUI se destruye sin fugas.

**Script**: ejecutado completo contra un árbol de Roblox simulado con dos servidores:

| Servidor | Resultado |
| --- | --- |
| Acepta todo | 25 acciones `✔` verificadas, 30 firmas aprendidas, 0 crash |
| Rechaza todo | 24 acciones `✖` con motivo, 0 éxito falso, 0 crash |

Memoria entre sesiones comprobada: tras aprender `Energy(delta, ítem)`, la
segunda carga cura con **un solo** remoto en vez de reintentar variantes.

## Notas

- El daño de último recurso (`Humanoid.Health` desde el cliente) se marca como
  **local**. Daña en tu pantalla, no en la partida, y el script lo dice así.
- `HitBadguy` aceptado por el servidor baja la vida de verdad; la sonda
  distingue un caso del otro.
- Los scripts públicos de Break In 2 no leen el stat en ningún punto: solo
  disparan y esperan. El lector de stat de VANTA es propio, y si el juego no lo
  expone, la acción se informa sin afirmar que subió.

## Módulos

Nueve módulos, cada uno en su archivo. Ninguno llama a otro: se hablan por el
Bus, y cada uno tiene su propio estado, sus conexiones y su error.

| Módulo | Tipo | Qué hace |
| --- | --- | --- |
| `survival` | remoto | Curar, curar a todos, semi godmode, anti-slip |
| `trainer` | remoto | Fuerza y velocidad, leyendo el stat para verificar |
| `items` | remoto | Dar y equipar, comprobando la mochila |
| `combat` | remoto | Daño a NPC, comprobando el Humanoid |
| `navigation` | local | Teleports de la historia y a jugadores |
| `movement` | local | Velocidad, salto, noclip |
| `visuals` | local | ESP y fullbright |
| `lobby` | remoto | Roles Hacker y Nerd |
| `diagnostics` | core | Estado real de módulos, remotos y firmas |

Todo el detalle del aislamiento, el contrato de un módulo y cómo partirlo en
repositorios está en [ARQUITECTURA.md](ARQUITECTURA.md).

## Desarrollo

```bash
python3 tools/build.py     # src/ (17 archivos) -> VANTA-BreakIn2.lua
./tools/verify.sh          # sintaxis + aislamiento + script único + loader
```

El script único **no** es una copia pegada: cada módulo va en su propia entrada
y se compila por separado, así un error en uno no impide que arranquen los demás.
