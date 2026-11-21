--[[
    VANTA | UI — Kit
    Envoltorio único de Rayfield.

    Por qué: si cada módulo llamara a Rayfield directo, un módulo roto
    podría tumbar la ventana. Aquí toda creación de elemento pasa por pcall
    y devuelve un handle mudo si falla, así el módulo sigue vivo.

    Además normaliza el reporte: ✔ hecho de verdad, ✖ no ocurrió.
]]

local Kit = {}

local window = nil
local tabs = {}
local notifications = 0

function Kit.Mount(rayfield, config)
    local ok, result = pcall(function()
        return rayfield:CreateWindow(config)
    end)

    if not ok or not result then
        return nil, tostring(result)
    end

    window = result

    return window
end

function Kit.Window()
    return window
end

function Kit.Tab(name)
    if tabs[name] then
        return tabs[name]
    end

    if not window then
        return nil
    end

    local ok, tab = pcall(function()
        return window:CreateTab({name = name})
    end)

    if not ok or not tab then
        return nil
    end

    tabs[name] = tab

    return tab
end

-- Handle inerte: el módulo puede seguir llamando sin comprobar nada.
local function NullHandle()
    local handle = {}

    handle.Set = function() end
    handle.Lock = function() end
    handle.Unlock = function() end

    return handle
end

local function Create(tab, method, props, label)
    if not tab then
        return NullHandle()
    end

    local ok, handle = pcall(function()
        return tab[method](tab, props)
    end)

    if not ok or not handle then
        warn(string.format("[VANTA][UI] no se pudo crear %s: %s", label, tostring(handle)))
        return NullHandle()
    end

    return handle
end

function Kit.Button(tab, props)
    return Create(tab, "CreateButton", props, props.name)
end

function Kit.Toggle(tab, props)
    return Create(tab, "CreateToggle", props, props.name)
end

function Kit.Slider(tab, props)
    return Create(tab, "CreateSlider", props, props.name)
end

function Kit.Input(tab, props)
    return Create(tab, "CreateInput", props, props.name)
end

function Kit.Dropdown(tab, props)
    return Create(tab, "CreateDropdown", props, props.name)
end

function Kit.Section(tab, props)
    return Create(tab, "CreateSection", props, props.name)
end

function Kit.Text(tab, props)
    return Create(tab, "CreateText", props, props.name)
end

-- ─── Reporte ───────────────────────────────────────────────

function Kit.Notify(title, content)
    notifications += 1

    print(string.format("[VANTA] %s: %s", tostring(title), tostring(content)))

    if not window then
        return
    end

    pcall(function()
        window:Notify({
            title = tostring(title),
            content = tostring(content),
            duration = 4,
        })
    end)
end

-- El único formato de respuesta que usa la UI.
function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

function Kit.Count()
    return notifications
end

return Kit
