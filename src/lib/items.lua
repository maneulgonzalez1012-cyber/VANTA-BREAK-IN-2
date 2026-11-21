--[[
    VANTA | LIB — Catálogo de objetos
    Fuente única. Los módulos no escriben nombres de objeto por su cuenta.
]]

local Items = {}

-- Nombre visible -> nombre interno que espera el servidor.
Items.weapons = {
    ["Crowbar 1"] = "Crowbar1",
    ["Crowbar 2"] = "Crowbar2",
    ["Diamond Crowbar"] = "Crowbar3",
    ["Bat"] = "Bat",
    ["Pitchfork"] = "Pitchfork",
    ["Hammer"] = "Hammer",
    ["Wrench"] = "Wrench",
    ["Broom"] = "Broom",
}

-- Armadura va por otra rama del vending.
Items.armor = "Armor"
Items.armorId = "Armor2"

Items.all = {
    "Golden Apple",
    "Gold Pizza",
    "Rainbow Pizza",
    "Rainbow Pizza Box",
    "Pizza",
    "Cookie",
    "Apple",
    "Chips",
    "Lollipop",
    "Bloxy Cola",
    "Expired Bloxy Cola",
    "Bottle",
    "Battery",
    "Med Kit",
    "Armor",
    "Key",
    "Gold Key",
    "Louise",
    "Book",
    "Phone",
    "Ladder",
    "Crowbar 1",
    "Crowbar 2",
    "Diamond Crowbar",
    "Bat",
    "Pitchfork",
    "Hammer",
    "Wrench",
    "Broom",
}

function Items.toolName(item)
    return (tostring(item):gsub("%s", ""))
end

function Items.isWeapon(item)
    return Items.weapons[item] ~= nil
end

function Items.weaponId(item)
    return Items.weapons[item]
end

function Items.isArmor(item)
    return item == Items.armor
end

return Items
