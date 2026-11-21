--[[
    VANTA | Diagnóstico
    Dice la verdad sobre lo que hay y lo que no.

    Esto existe porque gran parte de este juego está ofuscada y no todo se
    pudo verificar. Mejor un panel que diga "remoto de códigos: no
    encontrado" que un botón que no hace nada.
]]

local Diagnostics = {}

local Sections = require("sections")
local Remotes = require("remotes")
local Stats = require("stats")
local State = require("state")

local PlayersService = game:GetService("Players")

local PLACE_ID = 6766156863

function Diagnostics.Report()
    local health = Sections.Health()
    local inventory = Remotes.Inventory()
    local missing = Remotes.Missing()
    local values = Stats.Report()

    local remotes = {}

    for key, path in pairs(inventory) do
        table.insert(remotes, key .. " → " .. path)
    end

    table.sort(remotes)

    local gaps = {}

    for key, why in pairs(missing) do
        table.insert(gaps, key .. ": " .. why)
    end

    table.sort(gaps)

    return {
        placeOk = game.PlaceId == PLACE_ID,
        placeId = game.PlaceId,
        sections = health,
        connections = Sections.ConnectionCount(),
        strength = values.strength,
        strengthWhere = values.strengthWhere,
        energy = values.energy,
        energyWhere = values.energyWhere,
        remotes = remotes,
        gaps = gaps,
        players = #PlayersService:GetPlayers(),
    }
end

function Diagnostics.Describe()
    local report = Diagnostics.Report()
    local lines = {}

    if not report.placeOk then
        table.insert(lines, string.format(
            "⚠ estás en otro juego (PlaceId %s, no %d)",
            tostring(report.placeId),
            PLACE_ID
        ))
    end

    table.insert(lines, string.format(
        "secciones: %d/%d",
        report.sections.healthy,
        report.sections.total
    ))

    table.insert(lines, string.format(
        "fuerza: %s   energía: %s",
        report.strength and string.format("%.0f", report.strength) or "no encontrada",
        report.energy and string.format("%.0f", report.energy) or "no encontrada"
    ))

    if #report.remotes == 0 then
        table.insert(lines, "remotos: ninguno encontrado")
    else
        table.insert(lines, "remotos: " .. table.concat(report.remotes, " | "))
    end

    for _, gap in ipairs(report.gaps) do
        table.insert(lines, "✖ " .. gap)
    end

    return table.concat(lines, "\n")
end

function Diagnostics.Print()
    local report = Diagnostics.Report()

    print("─── VANTA | Strongman Simulator ───")
    print(Diagnostics.Describe())

    if report.strengthWhere then
        print("fuerza en: " .. tostring(report.strengthWhere))
    end

    if report.energyWhere then
        print("energía en: " .. tostring(report.energyWhere))
    end

    print("conexiones: " .. tostring(report.connections))

    if report.strength then
        return true, string.format(
            "fuerza %.0f, energía %s, %d remoto(s), %d hueco(s)",
            report.strength,
            report.energy and string.format("%.0f", report.energy) or "?",
            #report.remotes,
            #report.gaps
        )
    end

    return false, "no pude leer tu fuerza: " .. tostring(report.strengthWhere)
end

function Diagnostics.Setup()
    -- Nada que conectar.
end

return Diagnostics
