# VANTA — arquitectura modular

Un solo script ejecuta todos los módulos. Cada módulo está en su archivo,
con su propio estado, sus propias conexiones y su propio error. **Ninguno
toca a otro.**

```
loader.lua                 baja y ejecuta el script único, muestra el trabajo real
VANTA-BreakIn2.lua         generado: 17 módulos empaquetados por separado
src/
├── init.lua               arranque y menú: declara, carga, monta UI
├── core/
│   ├── bus.lua            aislamiento de errores y conexiones
│   ├── remotes.lua        única puerta al servidor + presupuesto + firmas
│   ├── registry.lua       declaración, carga, descarga y despacho de acciones
│   └── player.lua         lecturas del mundo (vida, mochila, NPC, stats)
├── lib/
│   ├── items.lua          catálogo de objetos
│   └── places.lua         coordenadas de la historia
├── ui/kit.lua             envoltorio de Rayfield, a prueba de fallos
└── features/
    ├── survival.lua       curar, curar a todos, semi godmode, anti-slip
    ├── trainer.lua        fuerza y velocidad con lectura de stat
    ├── items.lua          dar, equipar y verificar en la mochila
    ├── combat.lua         daño a NPC verificado por Humanoid
    ├── navigation.lua     teleports de la historia y a jugadores
    ├── movement.lua       velocidad, salto, noclip — todo local
    ├── visuals.lua        ESP y fullbright — restaura al apagar
    ├── lobby.lua          roles Hacker y Nerd
    └── diagnostics.lua    estado real de todo
```

---

## Las cinco reglas que hacen que no se pisen

### 1. Un módulo roto no tumba a los demás

`registry.lua` carga cada módulo con `pcall` y en su propio hilo. Si uno
explota al arrancar, queda marcado como roto, se registra su error y los
otros ocho siguen funcionando.

Medido: con `combat` lanzando a propósito al cargar, **8/9 módulos sanos**.

### 2. Ningún módulo llama a otro

Se comunican por el Bus. Un módulo publica, otro escucha, y ninguno
necesita que el otro exista.

```lua
bus.On("algo", "miModulo", function(dato) ... end)
bus.Emit("algo", dato)
```

### 3. Cada módulo ve solo su propio estado

`Registry.Run` inyecta el estado del módulo como primer argumento de la
acción. No hay estado global compartido, así que dos módulos no pueden
escribir la misma variable sin que se note.

### 4. Las conexiones se limpian por módulo

Toda señal se conecta por `bus.Connect(nombreDelModulo, ...)`. Descargar
`movement` cierra **solo** las conexiones de `movement`; `visuals` sigue
vivo.

Medido: descargar `movement` cierra 1 conexión `Stepped`, deja la de
`visuals` intacta, y `visuals` sigue cargado.

### 5. Dos acciones con el mismo nombre no se pisan en silencio

El registro es dueño de las claves de acción. Si un segundo módulo declara
`heal`, se registra un **conflicto** y se reporta en Diagnóstico en lugar
de sobrescribir la primera.

Medido: un módulo intruso que declara `heal` produce
`conflicto: heal lo declaran survival y thief`.

---

## Contrato de un módulo

Un módulo es un archivo que devuelve una tabla con `spec`. Nada más.

```lua
return {
    spec = {
        id = "movement",
        name = "Movimiento",
        kind = "local",                 -- local | remote | core
        tab = "Movimiento",
        order = 50,
        description = "texto que ve el usuario",

        actions = {
            setSpeed = function(state, enabled)
                state.speedEnabled = enabled and true or false
                return true, "velocidad " .. (enabled and "activa" or "apagada")
            end,
        },

        setup = function(ctx)
            -- ctx.id, ctx.state, ctx.bus, ctx.registry
        end,
    },
}
```

Reglas del contrato:

- **Toda acción devuelve `(ejecutado, motivo)`.** `ejecutado` es `true` solo
  si el efecto ocurrió de verdad y se comprobó.
- **`state` es el único sitio donde el módulo guarda cosas.**
- **No se llama `require` de otro módulo de features.** Si de verdad hace
  falta comunicación, se usa el Bus.
- **El teardown va en `state.teardown`** y `Registry.Unload` lo ejecuta.

---

## Cómo se comprueba que algo pasó

Cada módulo mide su propio efecto. No hay "solicitud enviada".

| Acción | Cómo sabe que funcionó |
| --- | --- |
| Curar | la vida del Humanoid subió |
| Dar objeto | el `Tool` está en la mochila |
| Curar a todos | la manzana está equipada y el remoto existe |
| Atacar NPC | la vida del NPC bajó por el remoto |
| Entrenar | el número del stat subió en la UI |
| Teleport | sigues en el destino 0.6 s después |
| Rol | tienes la herramienta del rol |
| Velocidad/salto/noclip | la propiedad escrita es la que pediste |
| ESP | el Highlight existe y cuelga de tu carpeta |

Y cuando solo funciona en el cliente, **se dice**:

```
✖ Atacar NPC cercanos: 1 dañados, 0 caídos, 1 solo en cliente
```

Medido con un servidor que ignora todos los remotos: `give` responde
`Golden Apple no llegó por ninguna de 2 vías`, `heal` responde
`Energy no movió la vida con ningún ítem ni firma`, y el combate que mata
solo en pantalla responde `solo en cliente` en vez de dar éxito.

---

## Las tres clases de módulo

**`local`** — no manda ni un remoto: `movement`, `visuals`, `navigation`
(escribe CFrame directamente). El servidor no puede rechazar lo que no le
pediste.

**`remote`** — habla con el servidor por `core/remotes.lua`, con
presupuesto de 60 paquetes/s y firmas aprendidas: `survival`, `items`,
`combat`, `trainer`, `lobby`.

**`core`** — solo informa: `diagnostics`.

---

## El script único

`tools/build.py` mete los 17 archivos en `VANTA-BreakIn2.lua`. **No los
concatena**: cada uno va en su propia entrada de una tabla y se compila
por separado al cargarse.

```lua
FILES["core.bus"] = [==[ ...código... ]==]
FILES["features.combat"] = [==[ ...código... ]==]
```

Ventajas frente a pegar los archivos uno detrás de otro:

- Un error de sintaxis en un módulo no impide que los otros se compilen.
- Un `return` en un módulo no termina el script.
- Un nombre repetido entre archivos no choca: cada uno tiene su propio
  ámbito.
- Las dependencias circulares se detectan y se avisan en vez de colgar.

Sobrecarga del cargador: 2.3 KB sobre 81.7 KB de código.

```bash
python3 tools/build.py     # regenerar
./tools/verify.sh          # comprobar todo
```

---

## Partirlo en repositorios

El árbol está preparado para moverse tal cual. Cada carpeta es un módulo
de código con una sola responsabilidad y sin dependencias hacia arriba:

```
vanta-core     core/ + lib/       bus, remotes, registry, player, catálogos
vanta-ui       ui/kit.lua         envoltorio de Rayfield
vanta-features features/*.lua     9 módulos independientes entre sí
vanta-loader   loader.lua + tools/build.py
vanta-dist     VANTA-BreakIn2.lua  artefacto publicado
```

Reglas que hacen que se puedan separar sin romper nada:

- `features/*` solo depende de `core/` y `lib/`. Nunca de otro feature.
- `core/` no conoce a `features/`.
- `ui/` no conoce a `features/`.
- El único archivo que los junta es `init.lua`.

Para mover un feature a su propio repo basta con copiar su archivo: sus
dos `require` son `core.player` y `core.remotes`.

Si en algún momento quieres repos separados de verdad, el orden es:
primero `vanta-core` (todos lo necesitan), después cada feature, y al
final el `vanta-dist` que los empaqueta. **No puedo crear repositorios
desde aquí** — este checkout solo puede escribir en su propia branch.
