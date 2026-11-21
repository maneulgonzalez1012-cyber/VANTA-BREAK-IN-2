--[[
    VANTA | Kit de interfaz
    Envoltorio del menú (Rayfield Gen2).

    Una pestaña rota no puede tumbar la ventana: toda creación de elemento
    pasa por pcall y devuelve un handle inerte si falla.

    Un solo formato de reporte para todo el script:
        ✔ hecho de verdad
        ✖ no ocurrió, con el motivo
]]

local Kit = {}

local window = nil
local tabs = {}

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

local function nullHandle()
    return {
        Set = function() end,
        Fire = function() end,
        Refresh = function() end,
    }
end

local function create(tab, method, props, label)
    if not tab then
        return nullHandle()
    end

    local ok, handle = pcall(function()
        return tab[method](tab, props)
    end)

    if not ok or not handle then
        warn(string.format("[SM][UI] no se pudo crear %s: %s", label, tostring(handle)))
        return nullHandle()
    end

    return handle
end

function Kit.Button(tab, props) return create(tab, "CreateButton", props, props.name) end
function Kit.Toggle(tab, props) return create(tab, "CreateToggle", props, props.name) end
function Kit.Slider(tab, props) return create(tab, "CreateSlider", props, props.name) end
function Kit.Input(tab, props) return create(tab, "CreateInput", props, props.name) end
function Kit.Dropdown(tab, props) return create(tab, "CreateDropdown", props, props.name) end
function Kit.Section(tab, props) return create(tab, "CreateSection", props, props.name) end
function Kit.Text(tab, props) return create(tab, "CreateText", props, props.name) end

-- ─── Reporte ───────────────────────────────────────────────

function Kit.Notify(title, content)
    print(string.format("[SM] %s: %s", tostring(title), tostring(content)))

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

function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

-- La acción devuelve (ejecutado, motivo). Aquí solo se informa.
function Kit.Action(tab, label, description, runner)
    return Kit.Button(tab, {
        name = label,
        description = description,

        callback = function()
            task.spawn(function()
                local ok, executed, detail = pcall(runner)

                if not ok then
                    Kit.Report(label, false, "error: " .. tostring(executed))
                    return
                end

                Kit.Report(label, executed == true, detail or "sin respuesta")
            end)
        end,
    })
end

-- El setter devuelve (ejecutado, motivo).
function Kit.Flag(tab, label, description, flag, setter)
    return Kit.Toggle(tab, {
        name = label,
        description = description,
        flag = flag,
        value = false,

        callback = function(value)
            task.spawn(function()
                local ok, executed, detail = pcall(setter, value)

                if not ok then
                    Kit.Notify(label, "error: " .. tostring(executed))
                    return
                end

                Kit.Notify(label, tostring(
                    detail or (executed and "aplicado" or "no se pudo aplicar")
                ))
            end)
        end,
    })
end

function Kit.Unload()
    if window then
        pcall(function()
            window:Unload()
        end)
    end
end

return Kit
