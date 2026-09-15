--!nonstrict
-- Murderers VS Sheriffs DUELS data manifest. Duel rounds are tracked through the Match
-- player attribute plus team membership, so every downstream service keys off those two
-- signals exactly like the reference combat script. Remote paths and action timings are
-- frozen here so the drivers stay in one readable place.
return function(_services: any?): any
    local manifest = {
        Name = "Murderers VS Sheriffs DUELS",
        PlaceIds = { 12355337193 },
        UniverseIds = { 4348829796 },
        TagPrefix = "B0XazMvSDuels",

        -- Enemy scope: both players must share the same Match attribute value and sit on
        -- different (non-nil) teams. Nil attributes or teams mean spectators or lobby.
        Match = { Attribute = "Match" },

        -- Aim part preference inside an enemy character; the root is HumanoidRootPart with
        -- the aim part as fallback, matching the reference script's resolution order.
        AimParts = { "Head", "UpperTorso", "HumanoidRootPart" },

        -- Knife detection: KnifeTool tag, "Stab" in ActivatedAnimation, or "Knife" in
        -- PulloutAnimation. Engage: teleport behind the target, simulate a client-side
        -- click with Tool:Activate() (pure script-level; no synthetic mouse input), wait a
        -- heartbeat, then fire remotes.Stab:FireServer(aimPart).
        Knife = {
            Remote = { "Remotes", "Stab" },
            Tag = "KnifeTool",
            ActivatedField = "ActivatedAnimation", ActivatedNeedle = "Stab",
            PulloutField = "PulloutAnimation", PulloutNeedle = "Knife",
            BackOffset = 2.25, UpOffset = 0.4, Settle = 0.025,
            DefaultCooldown = 0.45, MinCooldown = 0.05,
            SimulateClick = true,
        },

        -- Revolver detection: GunTool tag or "Shoot" in ActivatedAnimation. Fire:
        -- remotes.ShootGun:FireServer(origin, hitPosition, aimPart, hitPosition) where
        -- origin is the top of our head. The tool's Cooldown attribute gates re-fire.
        Gun = {
            Remote = { "Remotes", "ShootGun" },
            Tag = "GunTool",
            ActivatedField = "ActivatedAnimation", ActivatedNeedle = "Shoot",
            CooldownAttribute = "Cooldown",
            BackOffset = 4, UpOffset = 0.4, Settle = 0.025,
            DefaultCooldown = 2.55, MinCooldown = 0.05,
        },

        -- ESP overlay pacing and palette mirror the reference script (gamesense accent).
        Esp = {
            MaxVisuals = 16, Interval = 0.033, GuiName = "B0XazMvSEsp",
            Accent = Color3.fromRGB(50, 119, 186),
            Outline = Color3.fromRGB(20, 20, 20),
            Text = Color3.fromRGB(239, 239, 239),
        },

        -- Auto-queue settings and remote discovery targets
        Queue = {
            DefaultMode = "1v1",
            Modes = { "1v1", "2v2", "3v3", "4v4" },
            DefaultDelay = 3.0,
            MinDelay = 0.5,
            PierPath = { "Lobby", "Environment", "Pier" },
            Positions = {
                ["1v1"] = {
                    Vector3.new(56.9468994140625, -93.15959167480469, -203.5184783935547),
                    Vector3.new(27.4266357421875, -93.15959167480469, -203.4810028076172),
                },
                ["2v2"] = {
                    Vector3.new(56.784793853759766, -93.17820739746094, -189.26991271972656),
                    Vector3.new(27.93301010131836, -93.17820739746094, -189.24061584472656),
                },
                ["3v3"] = {
                    Vector3.new(56.6617431640625, -93.03361511230469, -173.23150634765625),
                    Vector3.new(28.4437255859375, -93.03361511230469, -173.20989990234375),
                },
                ["4v4"] = {
                    Vector3.new(56.58056640625, -92.84336853027344, -155.25958251953125),
                    Vector3.new(28.959228515625, -92.84336853027344, -155.24517822265625),
                },
            },
            Leeway = 1.0,
            RemoteNames = { "Queue", "QueueRemote", "JoinQueue", "EnterQueue", "Matchmaking", "Queue1v1", "QueueDuel" },
        },
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
