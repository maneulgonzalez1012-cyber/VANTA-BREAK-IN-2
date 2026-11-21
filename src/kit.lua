--[[
    VANTA | Kit de interfaz
    Envoltorio único del menú (Rayfield Gen2).

    Por qué: si cada sección llamara al menú directo, una sección rota
    podría tumbar la ventana entera. Aquí toda creación de elemento pasa
    por pcall y devuelve un handle mudo si falla, así el resto sigue vivo.

    Un solo formato de reporte para todo el script:
        ✔ hecho de verdad
        ✖ no ocurrió, con el motivo

    Nada de "solicitud enviada".
]]

local Kit = {}

local window = nil
local tabs = {}

-- ─── Ventana y tabs ────────────────────────────────────────

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

-- ─── Elementos ─────────────────────────────────────────────

-- Handle inerte: la sección puede seguir llamando sin comprobar nada.
local function nullHandle()
    return {
        Set = function() end,
        Lock = function() end,
        Unlock = function() end,
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
        warn(string.format("[VANTA][UI] no se pudo crear %s: %s", label, tostring(handle)))
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

function Kit.Report(title, executed, detail)
    if executed then
        Kit.Notify(title, "✔ " .. tostring(detail))
    else
        Kit.Notify(title, "✖ " .. tostring(detail))
    end

    return executed
end

-- ─── Botón de acción ───────────────────────────────────────
-- La sección devuelve (ejecutado, motivo). Aquí solo se informa.

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

-- ─── Toggle de bandera ─────────────────────────────────────
-- El setter de la sección devuelve (ejecutado, motivo).

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

-- ─── Cierre ────────────────────────────────────────────────

function Kit.Unload()
    if window then
        pcall(function()
            window:Unload()
        end)
    end
end

return Kit
