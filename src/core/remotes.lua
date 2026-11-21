--[[
    VANTA | CORE — Remotos
    Única puerta al servidor. Ningún módulo llama FireServer directo.

    Responsabilidades
    1. Resolver remotos con caché y verificar que sigan vivos.
    2. Presupuesto de paquetes: nadie puede inundar el servidor.
    3. Firmas aprendidas: si una forma de argumentos ganó, se recuerda.
    4. Devolver siempre ok/motivo, nunca lanzar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local cache = {}
local budget = {
    window = 1,
    max = 60,
    count = 0,
    started = os.clock(),
}

local stats = {
    sent = 0,
    dropped = 0,
    failed = 0,
}

local learned = {}

-- ─── Resolución ────────────────────────────────────────────

function Remotes.Resolve(folderName, remoteName)
    local key = folderName .. "." .. remoteName
    local cached = cache[key]

    if cached and cached.Parent then
        return cached
    end

    local folder = ReplicatedStorage:FindFirstChild(folderName)

    if not folder then
        return nil, "falta ReplicatedStorage." .. folderName
    end

    local remote = folder:FindFirstChild(remoteName)

    if not remote or not remote:IsA("RemoteEvent") then
        return nil, "falta " .. key
    end

    cache[key] = remote

    return remote
end

function Remotes.Exists(folderName, remoteName)
    return Remotes.Resolve(folderName, remoteName) ~= nil
end

-- ─── Presupuesto ───────────────────────────────────────────

local function BudgetAllows()
    local now = os.clock()

    if now - budget.started >= budget.window then
        budget.started = now
        budget.count = 0
    end

    if budget.count >= budget.max then
        stats.dropped += 1
        return false
    end

    budget.count += 1

    return true
end

-- ─── Disparo ───────────────────────────────────────────────

function Remotes.Fire(folderName, remoteName, ...)
    local remote, reason = Remotes.Resolve(folderName, remoteName)

    if not remote then
        stats.failed += 1
        return false, reason
    end

    if not BudgetAllows() then
        return false, "presupuesto de paquetes agotado"
    end

    local args = table.pack(...)

    local ok, err = pcall(function()
        remote:FireServer(table.unpack(args, 1, args.n))
    end)

    if not ok then
        stats.failed += 1
        return false, tostring(err)
    end

    stats.sent += 1

    return true
end

function Remotes.Event(remoteName, ...)
    return Remotes.Fire("Events", remoteName, ...)
end

-- ─── Firmas aprendidas ─────────────────────────────────────

function Remotes.GetSignature(action)
    return learned[action]
end

function Remotes.SetSignature(action, label)
    if learned[action] ~= label then
        learned[action] = label
        print(string.format("[VANTA] firma %s -> %s", action, tostring(label)))
    end
end

function Remotes.Signatures()
    local list = {}

    for action, label in pairs(learned) do
        table.insert(list, {action = action, label = label})
    end

    table.sort(list, function(a, b)
        return a.action < b.action
    end)

    return list
end

-- ─── Espera de efecto ──────────────────────────────────────

-- Ninguna acción se cree la primera respuesta: se mide.
function Remotes.Await(predicate, timeout, interval)
    timeout = timeout or 1.5
    interval = math.max(interval or 0.05, 0.02)

    local started = os.clock()
    local spins = 0

    repeat
        local ok, value = pcall(predicate)

        if ok and value then
            return true, value
        end

        spins += 1
        task.wait(interval)
    until os.clock() - started >= timeout or spins >= 200

    return false
end

-- ─── Variantes ─────────────────────────────────────────────

-- Prueba cada variante hasta que una produzca efecto medible.
-- La ganadora queda aprendida para la próxima sesión.
function Remotes.TryVariants(action, variants, verify, timeout)
    local winner = learned[action]
    local ordered = {}

    if winner then
        for _, variant in ipairs(variants) do
            if variant.label == winner then
                table.insert(ordered, variant)
            end
        end
    end

    for _, variant in ipairs(variants) do
        if variant.label ~= winner then
            table.insert(ordered, variant)
        end
    end

    for _, variant in ipairs(ordered) do
        local fired, reason = variant.fire()

        if not fired and variant.fatal then
            return false, reason, 0
        end

        if Remotes.Await(verify, timeout or 1.0) then
            Remotes.SetSignature(action, variant.label)

            return true, variant.label, 1
        end
    end

    return false, nil, #ordered
end

-- ─── Estado ────────────────────────────────────────────────

function Remotes.Stats()
    return {
        sent = stats.sent,
        dropped = stats.dropped,
        failed = stats.failed,
        cached = (function()
            local n = 0

            for _ in pairs(cache) do
                n += 1
            end

            return n
        end)(),
    }
end

function Remotes.ClearCache()
    table.clear(cache)
end

return Remotes
