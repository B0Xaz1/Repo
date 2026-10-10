return function(_services: any?): any
    local CONFIG = {
        Name = "Da Hood",

        PlaceIds = { 2788229376 },
        UniverseIds = {},

        TagPrefix = "B0XazDaHood",
    }

    local function freezeDeep(value: any): any
        if type(value) == "table" then
            for _, child in pairs(value) do freezeDeep(child) end
            table.freeze(value)
        end
        return value
    end

    return freezeDeep(CONFIG)
end
