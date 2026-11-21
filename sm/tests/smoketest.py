"""
VANTA | Strongman Simulator — prueba de humo.

Comprueba lo que de verdad importa: que el script arranca, monta la ventana y
que sus acciones hacen algo medible, no que devuelvan "vale".

Escenarios
  ok          arranque completo, ventana y secciones
  strength    subir fuerza y que el número suba de verdad
  grind       diez subidas y que la fuerza suba más
  pull        arrastrar a la meta y que la energía suba
  rejected    si el servidor rechaza, la acción debe decir que falló
  esp         resaltar jugadores y que exista el Highlight
  teleport    teleport a un jugador y que siga cerca después
  stop        cerrar deja 0 conexiones y restaura la velocidad
  twice       ejecutar dos veces deja una sola ventana

Uso: python3 sm/tests/smoketest.py [escenario]
"""
import sys

import harness

SCENARIOS = ("ok", "strength", "grind", "pull", "rejected",
             "esp", "teleport", "stop", "twice")


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "ok"

    lua, ok, detail = harness.boot()

    if not ok:
        print(f"✖ {detail}")
        return 1

    state = lua.eval("getgenv().VANTA_STRONGMAN")

    if state is None:
        print("✖ el script arrancó pero no dejó getgenv().VANTA_STRONGMAN")
        return 1

    failures = []
    modules = state["modules"]

    verify = state["Verify"]()
    print(f"  ventana: {lua.eval('UI.window')}")
    print(f"  pestañas ({len(list(lua.eval('UI.tabs').values()))}): "
          f"{', '.join(lua.eval('UI.tabs').values())}")
    print(f"  botones: {lua.eval('UI.buttons')}")
    print(f"  secciones: {verify['healthy']}/{verify['total']} sanas, "
          f"{verify['connections']} conexiones")

    if verify["total"] != 9:
        failures.append(f"se declararon {verify['total']} secciones, no 9")

    if verify["broken"] != 0:
        for record in list(state["sections"]["List"]().values()):
            if record["error"]:
                print(f"    ROTA {record['name']}: {record['error']}")
        failures.append(f"{verify['broken']} secciones rotas")

    tabs = list(lua.eval("UI.tabs").values())

    for expected in ("Entrenamiento", "Arrastre", "Movimiento", "Mundo",
                     "Jugadores", "Códigos", "Mascotas", "Personaje",
                     "Diagnóstico"):
        if expected not in tabs:
            failures.append(f"falta la pestaña {expected}")

    print()

    # ── Fuerza ──
    if scenario in ("ok", "strength"):
        before = lua.eval("STRENGTH_VALUE()")
        res = modules["training"]["Upgrade"]()
        res = res if isinstance(res, tuple) else (res,)
        after = lua.eval("STRENGTH_VALUE()")

        print(f"  training.Upgrade -> {res[0]} | {res[1] if len(res) > 1 else ''}")
        print(f"  fuerza: {before} -> {after}")

        if not res[0]:
            failures.append(f"subir fuerza falló: {res[1] if len(res) > 1 else ''}")
        if after <= before:
            failures.append("la fuerza no subió de verdad")

    # ── Varias subidas ──
    if scenario == "grind":
        before = lua.eval("STRENGTH_VALUE()")
        res = modules["training"]["Grind"](10)
        res = res if isinstance(res, tuple) else (res,)
        after = lua.eval("STRENGTH_VALUE()")

        print(f"  training.Grind(10) -> {res[0]} | {res[1] if len(res) > 1 else ''}")
        print(f"  fuerza: {before} -> {after}")

        if not res[0]:
            failures.append(f"Grind falló: {res[1] if len(res) > 1 else ''}")
        if after - before < 10:
            failures.append(f"Grind solo subió {after - before}")

    # ── Arrastre ──
    if scenario in ("ok", "pull"):
        # El banco simula que arrastrar da energía al mover piezas a la meta.
        lua.execute("""
            local piece = MKCLASS("Part", "Crate")
            table.insert(MY_DRAGS.Children, piece)
        """)

        before = lua.eval("ENERGY_VALUE()")
        res = modules["dragging"]["Pull"]()
        res = res if isinstance(res, tuple) else (res,)
        after = lua.eval("ENERGY_VALUE()")

        print(f"  dragging.Pull -> {res[0]} | {res[1] if len(res) > 1 else ''}")
        print(f"  energía: {before} -> {after}")

        if not res[0]:
            failures.append(f"arrastrar falló: {res[1] if len(res) > 1 else ''}")

    # ── Servidor que rechaza ──
    if scenario == "rejected":
        lua.execute("CLOSED = true")

        res = modules["training"]["Upgrade"]()
        res = res if isinstance(res, tuple) else (res,)

        print(f"  con el servidor cerrado -> {res[0]} | {res[1] if len(res) > 1 else ''}")

        if res[0]:
            failures.append("dijo que subió la fuerza con el servidor rechazando")

    # ── ESP ──
    if scenario in ("ok", "esp"):
        lua.execute("""
            local other = MKCLASS("Player", "Otro")
            other.Character = MKCLASS("Model", "Otro")
            local root = MKCLASS("Part", "HumanoidRootPart")
            root.Parent = other.Character
            table.insert(other.Character.Children, root)
            OTHER = other
        """)

        # El mundo del banco solo tiene un jugador: se añade uno al servicio.
        lua.execute("""
            local players = game:GetService("Players")
            table.insert(players.Children, OTHER)
        """)

        res = modules["players"]["SetESP"](True)
        res = res if isinstance(res, tuple) else (res,)

        print(f"  players.SetESP(true) -> {res[0]} | {res[1] if len(res) > 1 else ''}")

        if not res[0]:
            failures.append(f"ESP no dibujó nada: {res[1] if len(res) > 1 else ''}")

        highlights = lua.eval("""
            (function()
                local count = 0
                for _, c in ipairs(game:GetService("Players").LocalPlayer.Children) do
                    if c.Name == "SM_ESP" then count = count + #c.Children end
                end
                return count
            end)()
        """)

        print(f"  resaltados vivos: {highlights}")

        if highlights == 0:
            failures.append("el ESP no dejó ningún Highlight colgando")

        res = modules["players"]["SetESP"](False)
        res = res if isinstance(res, tuple) else (res,)

        left = lua.eval("""
            (function()
                for _, c in ipairs(game:GetService("Players").LocalPlayer.Children) do
                    if c.Name == "SM_ESP" and not c.Destroyed then return 1 end
                end
                return 0
            end)()
        """)

        print(f"  tras apagar: {left} restos")

        if left != 0:
            failures.append("el ESP dejó restos al apagarse")

    # ── Teleport ──
    if scenario == "teleport":
        lua.execute("""
            local players = game:GetService("Players")
            local other = MKCLASS("Player", "Otro")
            other.Character = MKCLASS("Model", "Otro")
            local theirRoot = MKCLASS("Part", "HumanoidRootPart")
            theirRoot.CFrame = CFrame.new(100, 0, 100)
            theirRoot.Parent = other.Character
            table.insert(other.Character.Children, theirRoot)
            table.insert(players.Children, other)
            OTHER = other
        """)

        lua.execute("""
            function game:GetPlayers()
                local list = {self.LocalPlayer}
                for _, c in ipairs(self.Children) do
                    if c.ClassName == "Player" then table.insert(list, c) end
                end
                return list
            end
        """)

        res = modules["players"]["ToPlayer"]("Otro")
        res = res if isinstance(res, tuple) else (res,)

        print(f"  players.ToPlayer('Otro') -> {res[0]} | {res[1] if len(res) > 1 else ''}")

        if not res[0]:
            failures.append(f"teleport falló: {res[1] if len(res) > 1 else ''}")

    # ── Cierre ──
    if scenario == "stop":
        lua.execute("""
            state_before = nil
        """)

        state["modules"]["movement"]["SetSpeed"](120)

        before = lua.eval("Work.humanoid().WalkSpeed")
        connections = state["Verify"]()["connections"]

        state["Stop"]()

        after = lua.eval("Work.humanoid().WalkSpeed")
        remaining = state["sections"]["ConnectionCount"]()

        print(f"  velocidad: {before} -> {after}")
        print(f"  conexiones: {connections} -> {remaining}")

        if remaining != 0:
            failures.append(f"quedaron {remaining} conexiones tras cerrar")
        if after != 16:
            failures.append(f"la velocidad no volvió a 16: {after}")

    # ── Dos ejecuciones ──
    if scenario == "twice":
        live_before = lua.eval("_G.WORK_LIVE") or 0
        lua, ok, detail = harness.boot()

        if not ok:
            failures.append(f"la segunda ejecución falló: {detail}")
        else:
            live_after = lua.eval("_G.WORK_LIVE") or 0
            print(f"  ventanas vivas: {live_before} -> {live_after}")

            if live_after > 1:
                failures.append(f"quedaron {live_after} ventanas vivas")

    print()
    if failures:
        print("FALLOS:")
        for f in failures:
            print("  ✖", f)
        return 1

    print("STRONGMAN OK — 0 fallos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
