local Workspace = game:GetService("Workspace")

local CONFIG = table.freeze({
    CARD_WIDE_HEIGHT = 164,
    CARD_NARROW_HEIGHT = 222,
    CARD_NARROW_WIDTH = 600,
    AVATAR_THUMBNAIL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",
    HIGHLIGHT_FILL_TRANSPARENCY = 0.67,
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.05,
})

return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local dom, theme = services:Get("DOM"), services:Get("ThemeEngine")
    local tracker, movement, state, aimbot = services:Get("PlayerTracker"), services:Get("LocomotionService"), services:Get("StateStore"), services:Get("AimbotService")
    local scope = services:Get("Disposer"):CreateChild("Players tab")

    -- The card is intentionally a dashboard item: it stretches across both working columns while
    -- the directory below remains the single source of truth for the current player selection.
    tab.Dashboard.Visible = true
    local card = dom:Create("Frame", { Parent = tab.Dashboard, Name = "TargetCard", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, CONFIG.CARD_WIDE_HEIGHT),
        LayoutOrder = 0, BackgroundColor3 = theme:GetToken("Panel") })
    dom:Create("UICorner", { Parent = card, CornerRadius = UDim.new(0, 8) })
    theme:BindToken(card, "BackgroundColor3", "Panel")
    theme:BindToken(dom:CreateStroke(card, theme:GetToken("Border"), 1), "Color", "Border")

    local accentLine = dom:Create("Frame", { Parent = card, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = theme:GetToken("Accent") })
    dom:Create("UICorner", { Parent = accentLine, CornerRadius = UDim.new(0, 8) })
    theme:BindToken(accentLine, "BackgroundColor3", "Accent")

    local avatar = dom:Create("ImageLabel", { Parent = card, Name = "Avatar", BackgroundColor3 = theme:GetToken("Elem"), BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 34), Size = UDim2.fromOffset(92, 92), Image = "", ScaleType = Enum.ScaleType.Crop })
    dom:Create("UICorner", { Parent = avatar, CornerRadius = UDim.new(0, 7) })
    theme:BindToken(avatar, "BackgroundColor3", "Elem")
    theme:BindToken(dom:CreateStroke(avatar, theme:GetToken("BorderDim")), "Color", "BorderDim")
    local avatarFallback = dom:Create("TextLabel", { Parent = avatar, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "?", Font = Enum.Font.GothamMedium,
        TextSize = 28, TextColor3 = theme:GetToken("TextMuted"), ZIndex = 2 })
    theme:BindToken(avatarFallback, "TextColor3", "TextMuted")

    local eyebrow = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(122, 15), Size = UDim2.new(1, -370, 0, 13),
        Text = "SELECTED TARGET", Font = Enum.Font.GothamMedium, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Accent") })
    local displayName = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(122, 32), Size = UDim2.new(1, -370, 0, 23),
        Text = "Choose a player", Font = Enum.Font.GothamMedium, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("Text") })
    local username = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(122, 58), Size = UDim2.new(1, -370, 0, 16),
        Text = "Use the Player directory below", Font = Enum.Font.Gotham, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("TextDim") })
    local account = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(122, 78), Size = UDim2.new(1, -370, 0, 16),
        Text = "Account information appears here", Font = Enum.Font.Gotham, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("TextMuted") })
    local statusDot = dom:Create("Frame", { Parent = card, BorderSizePixel = 0, Position = UDim2.fromOffset(122, 111), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = theme:GetToken("TextMuted") })
    dom:Create("UICorner", { Parent = statusDot, CornerRadius = UDim.new(1, 0) })
    local status = dom:Create("TextLabel", { Parent = card, BackgroundTransparency = 1, Position = UDim2.fromOffset(134, 106), Size = UDim2.new(1, -382, 0, 18),
        Text = "No target selected", Font = Enum.Font.GothamMedium, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = theme:GetToken("TextMuted") })
    theme:BindToken(eyebrow, "TextColor3", "Accent"); theme:BindToken(displayName, "TextColor3", "Text")
    theme:BindToken(username, "TextColor3", "TextDim"); theme:BindToken(account, "TextColor3", "TextMuted")

    local actions = dom:Create("Frame", { Parent = card, Name = "TargetActions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 30), Size = UDim2.fromOffset(218, 104) })
    local actionLayout = dom:Create("UIGridLayout", { Parent = actions, CellPadding = UDim2.fromOffset(6, 6), CellSize = UDim2.new(0.5, -3, 0, 49),
        SortOrder = Enum.SortOrder.LayoutOrder })
    local actionScope = scope:CreateChild("Target card actions")
    local function actionButton(text: string, order: number): TextButton
        local button = dom:Create("TextButton", { Parent = actions, AutoButtonColor = false, BorderSizePixel = 0, Text = text, TextSize = 11,
            Font = Enum.Font.GothamMedium, LayoutOrder = order, Selectable = true })
        section:StyleButton(button, actionScope)
        return button
    end
    local teleportButton = actionButton("Teleport", 1)
    local spectateButton = actionButton("Spectate", 2)
    local selectTargetButton = actionButton("Select as Target", 3)
    local highlightButton = actionButton("Highlight", 4)

    local selectedPlayer: Player? = nil
    local highlightedPlayer: Player? = nil
    local highlightScope: any = nil
    local statusScope: any = nil
    local followButton: any = nil

    local function currentStatus(player: Player?): (string, string)
        if not player or not player.Parent then return "No target selected", "TextMuted" end
        local assets = tracker:GetPlayerAssets(player)
        if not assets then return "SPAWNING", "Warning" end
        if assets.Humanoid.Health <= 0 then return "ELIMINATED", "Danger" end
        local camera = Workspace.CurrentCamera
        if camera then
            local distance = math.floor((camera.CFrame.Position - assets.RootPart.Position).Magnitude)
            return `{distance} studs away`, "Success"
        end
        return "Ready", "Success"
    end

    local function setStatus(player: Player?)
        local text, token = currentStatus(player)
        status.Text = text
        theme:BindToken(status, "TextColor3", token)
        theme:BindToken(statusDot, "BackgroundColor3", token)
    end

    local function watchStatus(player: Player?)
        if statusScope then statusScope:Dispose(); statusScope = nil end
        if not player then return end
        local owner = scope:CreateChild(`Target status {player.UserId}`)
        statusScope = owner
        local function refresh()
            if selectedPlayer == player then setStatus(player) end
        end
        local function watchCharacter(character: Model)
            refresh()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then owner:Bind("Health changes", humanoid.HealthChanged:Connect(refresh)) end
            -- PlayerTracker resolves required parts asynchronously, so retry once without creating a poll.
            owner:Delay(0.15, refresh)
        end
        owner:ConnectImmediate(player.CharacterAdded, watchCharacter)
        owner:ConnectImmediate(player.CharacterRemoving, refresh)
        if player.Character then watchCharacter(player.Character) else refresh() end
    end

    local function clearHighlight()
        if highlightScope then highlightScope:Dispose(); highlightScope = nil end
        highlightedPlayer = nil
    end

    local function enableHighlight(player: Player): (boolean, string)
        if not player or not player.Parent then return false, "Select a player who is still in the server" end
        clearHighlight()
        highlightedPlayer = player
        local owner = scope:CreateChild(`Target highlight {player.UserId}`)
        highlightScope = owner
        local attachedCharacter: Model? = nil
        local attachedHighlight: Highlight? = nil

        local function detach()
            attachedCharacter, attachedHighlight = nil, nil
            owner:Unbind("Highlight")
        end

        local function attach(): boolean
            if owner:IsDisposed() or highlightedPlayer ~= player then return false end
            local assets = tracker:GetPlayerAssets(player)
            if not assets then return false end
            if attachedCharacter == assets.Character and attachedHighlight and attachedHighlight.Parent then return true end
            detach()
            local object = Instance.new("Highlight")
            object.Name = "B0XazSelectedTarget"
            object.Adornee, object.Parent = assets.Character, assets.Character
            object.FillColor, object.OutlineColor = theme:GetToken("AccentDim"), theme:GetToken("Accent")
            object.FillTransparency, object.OutlineTransparency = CONFIG.HIGHLIGHT_FILL_TRANSPARENCY, CONFIG.HIGHLIGHT_OUTLINE_TRANSPARENCY
            object.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            owner:Bind("Highlight", object)
            attachedCharacter, attachedHighlight = assets.Character, object
            -- The target is now resolved; no retry connection is needed until its next respawn.
            owner:Unbind("Highlight readiness")
            return true
        end

        local function watchCharacter(character: Model)
            owner:Bind("Highlight readiness", character.ChildAdded:Connect(function(child: Instance)
                if child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then attach() end
            end))
            if attach() then return end
            -- PlayerTracker resolves a newly spawned rig asynchronously. These are finite respawn
            -- handoffs, not a persistent poll, and cover a character whose required parts existed
            -- just before the readiness connection was installed.
            owner:Delay(0.1, function()
                if attach() then return end
                owner:Delay(0.4, attach)
            end)
        end

        owner:ConnectImmediate(player.CharacterAdded, watchCharacter)
        owner:ConnectImmediate(player.CharacterRemoving, function(character: Model)
            if attachedCharacter == character then detach() end
        end)
        owner:ConnectImmediate(player.AncestryChanged, function(_, parent)
            if not parent and highlightedPlayer == player then clearHighlight() end
        end)
        owner:Add(services:Get("EventBus"):Subscribe("ThemeChanged", function()
            local current = attachedHighlight
            if current and current.Parent then current.FillColor, current.OutlineColor = theme:GetToken("AccentDim"), theme:GetToken("Accent") end
        end))
        if player.Character then watchCharacter(player.Character) end
        return true, `Highlighting {player.Name}`
    end

    local function refreshActionLabels()
        spectateButton.Text = if selectedPlayer and tracker:GetSpectatingTarget() == selectedPlayer then "Stop spectating" else "Spectate"
        selectTargetButton.Text = if selectedPlayer and aimbot:GetPreferredTarget() == selectedPlayer then "Clear target" else "Select as Target"
        highlightButton.Text = if selectedPlayer and highlightedPlayer == selectedPlayer then "Remove highlight" else "Highlight"
        if followButton then followButton:_Render("") end
    end

    local function setSelected(player: Player?)
        selectedPlayer = if player and player.Parent then player else nil
        if not selectedPlayer then
            avatar.Image, avatarFallback.Text = "", "?"
            displayName.Text, username.Text, account.Text = "Choose a player", "Use the Player directory below", "Account information appears here"
            setStatus(nil)
            watchStatus(nil)
            refreshActionLabels()
            return
        end
        avatar.Image = string.format(CONFIG.AVATAR_THUMBNAIL, selectedPlayer.UserId)
        avatarFallback.Text = ""
        displayName.Text = selectedPlayer.DisplayName
        username.Text = `@{selectedPlayer.Name}  •  ID {selectedPlayer.UserId}`
        account.Text = `Account age  •  {selectedPlayer.AccountAge} days`
        setStatus(selectedPlayer)
        watchStatus(selectedPlayer)
        refreshActionLabels()
    end

    local select = section:Create(tab.LeftCol, "Player directory")
    local query = textbox(select, "Filter players", "")
    local target = dropdown(select, "Selected player", nil, tracker:GetPlayerNames(true), function(value: any)
        setSelected(tracker:GetPlayerByName(tostring(value or "")))
    end)
    local function refresh()
        target:Refresh(tracker:GetPlayerNames(true, query.Box.Text), true)
        setSelected(tracker:GetPlayerByName(target:Get() or ""))
    end
    scope:Connect(query.Box:GetPropertyChangedSignal("Text"), refresh)
    scope:Add(services:Get("EventBus"):Subscribe("PlayerJoined", refresh))
    scope:Add(services:Get("EventBus"):Subscribe("PlayerLeft", function(player: Player)
        if selectedPlayer == player then setSelected(nil) end
        if highlightedPlayer == player then clearHighlight(); refreshActionLabels() end
        refresh()
    end))

    actionScope:ConnectImmediate(teleportButton.Activated, function()
        local ok, message = movement:TeleportToPlayer(selectedPlayer)
        services:Get("EventBus"):Publish("Notify", if ok then "Teleported" else "Teleport unavailable", message)
    end)
    actionScope:ConnectImmediate(spectateButton.Activated, function()
        local ok, message
        if selectedPlayer and tracker:GetSpectatingTarget() == selectedPlayer then
            tracker:StopSpectate()
            ok, message = true, "Camera subject restored"
        else
            ok, message = tracker:StartSpectate(selectedPlayer)
        end
        refreshActionLabels()
        services:Get("EventBus"):Publish("Notify", if ok then "Spectate" else "Spectate unavailable", message)
    end)
    actionScope:ConnectImmediate(selectTargetButton.Activated, function()
        if not selectedPlayer then
            services:Get("EventBus"):Publish("Notify", "Target unavailable", "Choose a player from the directory first")
            return
        end
        local ok, message
        if aimbot:GetPreferredTarget() == selectedPlayer then ok, message = aimbot:ClearPreferredTarget()
        else ok, message = aimbot:SetPreferredTarget(selectedPlayer) end
        refreshActionLabels()
        services:Get("EventBus"):Publish("Notify", if ok then "Aimbot target" else "Target unavailable", message)
    end)
    actionScope:ConnectImmediate(highlightButton.Activated, function()
        if not selectedPlayer then
            services:Get("EventBus"):Publish("Notify", "Highlight unavailable", "Choose a player from the directory first")
            return
        end
        local ok, message
        if highlightedPlayer == selectedPlayer then clearHighlight(); ok, message = true, "Highlight removed"
        else ok, message = enableHighlight(selectedPlayer) end
        refreshActionLabels()
        services:Get("EventBus"):Publish("Notify", if ok then "Target highlight" else "Highlight unavailable", message)
    end)

    -- The active target can change from the Combat workspace, so keep this small status area
    -- synchronized without scanning the player list or running any per-frame 3D work.
    scope:Add(services:Get("EventBus"):Subscribe("TransientChanged:AimbotPreferredTarget", refreshActionLabels))
    scope:Add(services:Get("EventBus"):Subscribe("TransientChanged:FollowTarget", refreshActionLabels))
    scope:Add(services:Get("EventBus"):Subscribe("TransientChanged:AimbotTarget", function()
        if selectedPlayer then setStatus(selectedPlayer) end
        refreshActionLabels()
    end))
    scope:ConnectImmediate(card:GetPropertyChangedSignal("AbsoluteSize"), function()
        local narrow = card.AbsoluteSize.X > 0 and card.AbsoluteSize.X < CONFIG.CARD_NARROW_WIDTH
        if card:GetAttribute("B0XazNarrow") == narrow then return end
        card:SetAttribute("B0XazNarrow", narrow)
        card.Size = UDim2.new(1, 0, 0, if narrow then CONFIG.CARD_NARROW_HEIGHT else CONFIG.CARD_WIDE_HEIGHT)
        if narrow then
            avatar.Position, avatar.Size = UDim2.fromOffset(14, 31), UDim2.fromOffset(62, 62)
            eyebrow.Position, eyebrow.Size = UDim2.fromOffset(88, 15), UDim2.new(1, -102, 0, 13)
            displayName.Position, displayName.Size = UDim2.fromOffset(88, 31), UDim2.new(1, -102, 0, 21)
            username.Position, username.Size = UDim2.fromOffset(88, 54), UDim2.new(1, -102, 0, 15)
            account.Position, account.Size = UDim2.fromOffset(88, 73), UDim2.new(1, -102, 0, 15)
            statusDot.Position, status.Position = UDim2.fromOffset(14, 108), UDim2.fromOffset(26, 103)
            status.Size = UDim2.new(1, -40, 0, 18)
            actions.AnchorPoint, actions.Position, actions.Size = Vector2.new(0, 0), UDim2.fromOffset(14, 137), UDim2.new(1, -28, 0, 71)
            actionLayout.CellPadding, actionLayout.CellSize = UDim2.fromOffset(6, 6), UDim2.new(0.5, -3, 0, 32)
        else
            avatar.Position, avatar.Size = UDim2.fromOffset(14, 34), UDim2.fromOffset(92, 92)
            eyebrow.Position, eyebrow.Size = UDim2.fromOffset(122, 15), UDim2.new(1, -370, 0, 13)
            displayName.Position, displayName.Size = UDim2.fromOffset(122, 32), UDim2.new(1, -370, 0, 23)
            username.Position, username.Size = UDim2.fromOffset(122, 58), UDim2.new(1, -370, 0, 16)
            account.Position, account.Size = UDim2.fromOffset(122, 78), UDim2.new(1, -370, 0, 16)
            statusDot.Position, status.Position = UDim2.fromOffset(122, 111), UDim2.fromOffset(134, 106)
            status.Size = UDim2.new(1, -382, 0, 18)
            actions.AnchorPoint, actions.Position, actions.Size = Vector2.new(1, 0), UDim2.new(1, -14, 0, 30), UDim2.fromOffset(218, 104)
            actionLayout.CellPadding, actionLayout.CellSize = UDim2.fromOffset(6, 6), UDim2.new(0.5, -3, 0, 49)
        end
    end)

    local utilities = section:Create(tab.LeftCol, "Player utilities")
    textbox:CreateButton(utilities, "Copy username", function() return tracker:CopyName(selectedPlayer) end)
    followButton = textbox:CreateButton(utilities, "Follow selected player", function()
        if selectedPlayer and movement:GetFollowingTarget() == selectedPlayer then
            movement:StopFollowing()
            refreshActionLabels()
            return true, "Stopped following"
        end
        local ok, message = movement:StartFollowing(selectedPlayer)
        refreshActionLabels()
        return ok, message
    end)
    local baseFollowRender = followButton._Render
    function followButton:_Render(_value: string)
        local following = movement:GetFollowingTarget()
        local label = if following == selectedPlayer and following then "Stop following"
            elseif following then `Following {following.Name}` else "Follow selected player"
        baseFollowRender(self, label)
    end
    local whitelist = section:Create(tab.RightCol, "Target whitelist", "Settings")
    local summary = section:Info(whitelist, tracker:GetWhitelistSummary())
    scope:Add(state:Observe("Settings.Whitelist", function() summary:Set(tracker:GetWhitelistSummary()) end))
    textbox:CreateButton(whitelist, "Whitelist selected player", function() return tracker:AddWhitelist(selectedPlayer) end)
    textbox:CreateButton(whitelist, "Remove selected from whitelist", function() return tracker:RemoveWhitelist(selectedPlayer) end)
    textbox:CreateButton(whitelist, "Clear whitelist", function() state:Set("Settings.Whitelist", {}); return true, "Whitelist cleared" end)
    local fling = section:Create(tab.RightCol, "Fling attack")
    section:Info(fling, "Client-side only; server authority may block it. Stop flight first.")
    textbox:CreateButton(fling, "Fling selected player", function() return movement:FlingPlayer(selectedPlayer) end)
    textbox:CreateButton(fling, "Stop fling & restore position", function() movement:StopFling(); return true, "Fling stopped" end)

    setSelected(tracker:GetPlayerByName(target:Get() or ""))
    return { Name = tab.Name }
end
