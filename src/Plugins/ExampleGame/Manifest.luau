--!nonstrict
return function(_services: any?): any
    -- These names describe an opt-in, owner-authored test place, not an asserted integration with a live game.
    local manifest = {
        Name = "Example Game", PlaceIds = {}, UniverseIds = {},
        Coordinates = { Lobby = CFrame.new(0, 5, 0) },
        Doors = { Tag = "B0XazExampleDoor", OpenTransparency = 0.75 },
        Weapons = { Names = { "ExampleBlaster" }, Attributes = { Spread = 0, FireDelay = 0.08 } },
    }
    local function freezeDeep(value: any): any
        if type(value) == "table" then
            for _, child in pairs(value) do freezeDeep(child) end
            table.freeze(value)
        end
        return value
    end
    return freezeDeep(manifest)
end
