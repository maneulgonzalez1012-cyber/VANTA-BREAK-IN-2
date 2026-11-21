--[[
    VANTA | STRONGMAN SIMULATOR — arranque

    Esto NO es una animación. Cada etapa hace trabajo de verdad:

        1. esperar a que cargue el juego
        2. descargar el script (main y, si falla, la rama)
        3. compilarlo
        4. ejecutarlo
        5. comprobar que dejó estado y que las secciones arrancaron

    Si una etapa falla, se para ahí, se dice POR QUÉ y el mensaje se queda
    en pantalla. Nada de "cargando..." infinito.
]]

-- El repositorio se renombró a StrongmanSimulator, pero mientras el cambio
-- no esté aplicado la URL vieja es la que responde. Se prueban todas: si el
-- dueño renombra (o no), el script sigue entrando igual.
local SOURCES = {
    {
        name = "repo nuevo",
        url = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/StrongmanSimulator/arena/51187ad8-vanta-break-in-2/StrongmanSimulator.lua",
    },
    {
        name = "repo actual",
        url = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/arena/51187ad8-vanta-break-in-2/StrongmanSimulator.lua",
    },
    {
        name = "main",
        url = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/VANTA-BREAK-IN-2/main/StrongmanSimulator.lua",
    },
}

local PLACE_ID = 6766156863
local RUN_TIMEOUT = 12

-- ─── Interfaz de la barra ──────────────────────────────────

local STAGES = {
    "Conectar",
    "Descargar",
    "Compilar",
    "Ejecutar",
    "Verificar",
}

local state = {
    stage = 1,
    done = false,
    failed = false,
}

local gui, column
local rows = {}

local function build()
    local player = game:GetService("Players").LocalPlayer

    for _ = 1, 50 do
        if player:FindFirstChild("PlayerGui") then
            break
        end

        task.wait(0.1)
    end

    local playerGui = player:FindFirstChild("PlayerGui")

    if not playerGui then
        return false, "tu PlayerGui no está listo todavía"
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "VANTA_Strongman_Loader"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    gui.Parent = playerGui

    local backdrop = Instance.new("Frame")
    backdrop.Size = UDim2.fromOffset(430, 250)
    backdrop.Position = UDim2.new(0.5, -215, 0.5, -125)
    backdrop.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
    backdrop.BorderSizePixel = 0
    backdrop.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = backdrop

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -32, 0, 26)
    title.Position = UDim2.fromOffset(16, 14)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(240, 240, 245)
    title.Text = "VANTA"
    title.Parent = backdrop

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -32, 0, 18)
    subtitle.Position = UDim2.fromOffset(16, 38)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = 13
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.TextColor3 = Color3.fromRGB(140, 145, 160)
    subtitle.Text = "Strongman Simulator"
    subtitle.Parent = backdrop

    column = Instance.new("Frame")
    column.Size = UDim2.new(1, -32, 0, 120)
    column.Position = UDim2.fromOffset(16, 66)
    column.BackgroundTransparency = 1
    column.Parent = backdrop

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = column

    for index, name in ipairs(STAGES) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 20)
        row.BackgroundTransparency = 1
        row.LayoutOrder = index
        row.Parent = column

        local mark = Instance.new("TextLabel")
        mark.Size = UDim2.fromOffset(22, 20)
        mark.BackgroundTransparency = 1
        mark.Font = Enum.Font.GothamBold
        mark.TextSize = 14
        mark.TextColor3 = Color3.fromRGB(90, 90, 100)
        mark.Text = "·"
        mark.Parent = row

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -26, 1, 0)
        label.Position = UDim2.fromOffset(24, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextColor3 = Color3.fromRGB(180, 185, 200)
        label.Text = name
        label.Parent = row

        rows[index] = {mark = mark, label = label}
    end

    return true
end

local function paint()
    for index, row in ipairs(rows) do
        local done = index < state.stage or state.done
        local current = index == state.stage and not state.done

        if done then
            row.mark.Text = "✔"
            row.mark.TextColor3 = Color3.fromRGB(80, 200, 130)
        elseif current and state.failed then
            row.mark.Text = "✖"
            row.mark.TextColor3 = Color3.fromRGB(230, 90, 90)
        elseif current then
            row.mark.Text = "→"
            row.mark.TextColor3 = Color3.fromRGB(90, 170, 255)
        else
            row.mark.Text = "·"
            row.mark.TextColor3 = Color3.fromRGB(90, 90, 100)
        end
    end
end

local function setStage(index, detail)
    state.stage = index

    if rows[index] then
        rows[index].label.Text = STAGES[index] .. (detail and (" — " .. detail) or "")
    end

    paint()
end

local function fail(index, reason)
    state.failed = true
    state.done = false
    setStage(index, nil)

    if rows[index] then
        rows[index].label.Text = STAGES[index] .. " falló"
        rows[index].label.TextColor3 = Color3.fromRGB(230, 90, 90)
    end

    local box = Instance.new("TextLabel")
    box.Size = UDim2.new(1, -32, 0, 46)
    box.Position = UDim2.fromOffset(16, 196)
    box.BackgroundTransparency = 1
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.TextWrapped = true
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.TextColor3 = Color3.fromRGB(235, 120, 120)
    box.Text = "✖ " .. tostring(reason) .. "\nEl mensaje se queda aquí: no se cierra."
    box.Parent = gui and gui:FindFirstChildWhichIsA("Frame")

    warn("[VANTA Loader] " .. tostring(reason))
end

-- ─── Trabajo real ──────────────────────────────────────────

local function download()
    local errors = {}

    for _, source in ipairs(SOURCES) do
        local ok, body = pcall(function()
            return game:HttpGet(source.url, true)
        end)

        if ok and type(body) == "string" and #body > 1000 then
            return body, source.name
        end

        table.insert(errors, string.format(
            "%s: %s",
            source.name,
            ok and "respuesta vacía" or tostring(body)
        ))
    end

    return nil, table.concat(errors, " | ")
end

local function worker()
    setStage(1, "esperando el juego")

    local okGui, guiError = build()

    if not okGui then
        return false, guiError
    end

    -- 1. El juego tiene que estar cargado. No es una espera decorativa: sin
    --    esto, el script arranca sin personaje y todas las secciones fallan.
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    local player = game:GetService("Players").LocalPlayer

    for _ = 1, 100 do
        if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
            break
        end

        task.wait(0.1)
    end

    if not player.Character then
        return false, "no apareciste en el mundo (¿sigues en el menú del juego?)"
    end

    setStage(1, "en " .. tostring(game.PlaceId))

    if game.PlaceId ~= PLACE_ID then
        -- No es un fallo: puede haber otro lugar del mismo juego.
        warn(string.format(
            "[VANTA Loader] estás en PlaceId %s, no en %d",
            tostring(game.PlaceId),
            PLACE_ID
        ))
    end

    -- 2. Descargar.
    setStage(2, "descargando")

    local source, origin, downloadError = download()

    if not source then
        return false, "no se pudo descargar: " .. tostring(origin)
    end

    setStage(2, string.format("%d KB desde %s", math.floor(#source / 1024), tostring(origin)))

    -- 3. Compilar.
    setStage(3, "compilando")

    local chunk, compileError = loadstring(source, "VANTA:strongman")

    if not chunk then
        return false, "error de sintaxis: " .. tostring(compileError)
    end

    -- 4. Ejecutar, con límite de tiempo para no colgarse.
    setStage(4, "ejecutando")

    local outcome = nil
    local finished = false

    task.spawn(function()
        local ranOk, ranError = pcall(chunk)
        outcome = { ok = ranOk, err = ranError }
        finished = true
    end)

    local started = os.clock()

    while not finished and (os.clock() - started) <= RUN_TIMEOUT do
        task.wait(0.1)
    end

    if outcome and not outcome.ok then
        return false, "el script falló: " .. tostring(outcome.err)
    end

    if not finished then
        setStage(4, "sigue montándose")
    end

    -- 5. Verificar: el script deja su estado en getgenv.
    setStage(5, "comprobando")

    local exposed = getgenv and getgenv().VANTA_STRONGMAN

    if not exposed then
        local problems = {}

        if type(loadstring) ~= "function" then
            table.insert(problems, "tu ejecutor no tiene loadstring")
        end

        if type(getgenv) ~= "function" then
            table.insert(problems, "tu ejecutor no tiene getgenv")
        end

        if not game:GetService("ReplicatedStorage"):FindFirstChild("StrongMan_UpgradeStrength") then
            table.insert(problems, "no está StrongMan_UpgradeStrength: no parece Strongman Simulator")
        end

        if #problems == 0 then
            table.insert(problems, "arrancó pero no dejó estado")
        end

        return false, table.concat(problems, "; ")
    end

    local report = nil

    if type(exposed.Verify) == "function" then
        local okVerify, result = pcall(exposed.Verify)

        if okVerify then
            report = result
        end
    end

    state.done = true
    paint()

    local summary = "listo"

    if report then
        summary = string.format("%d/%d secciones", report.healthy, report.total)

        if report.broken > 0 then
            summary = summary .. string.format(" (%d rota/s)", report.broken)
        end
    end

    setStage(5, summary)

    -- La barra se cierra sola cuando de verdad está todo dentro.
    task.delay(2.2, function()
        if gui then
            pcall(function()
                gui:Destroy()
            end)
        end
    end)

    return true
end

task.spawn(function()
    local ok, ran, reason = pcall(worker)

    -- Tres salidas posibles: reventó, falló una etapa con motivo, o terminó.
    if not ok then
        fail(state.stage, tostring(ran))
        return
    end

    if ran ~= true then
        fail(state.stage, tostring(reason))
    end
end)
