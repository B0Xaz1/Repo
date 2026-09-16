--!strict
local UIS = game:GetService("UserInputService")
return function(services: any, tab: any): any
    local load = services:Get("Require")
    local section = load("src/UI/Components/Section.luau", services)
    local toggle = load("src/UI/Components/Toggle.luau", services)
    local slider = load("src/UI/Components/Slider.luau", services)
    local dropdown = load("src/UI/Components/Dropdown.luau", services)
    local keybind = load("src/UI/Components/Keybind.luau", services)
    local textbox = load("src/UI/Components/Textbox.luau", services)
    local movement = services:Get("LocomotionService")
    local state, dom, environment = services:Get("StateStore"), services:Get("DOM"), services:Get("Environment")
    local scope = services:Get("Disposer"):CreateChild("Movement tab")
    local humanoid = section:Create(tab.LeftCol, "Character overrides", "Movement")
    section:Info(humanoid, "Zero means leave the game's value alone. Jump power applies when the game uses JumpPower.")
    slider(humanoid, "Walk speed", "Movement.Speed", 0, 200, 1, "", nil)
    slider(humanoid, "Jump power", "Movement.JumpPower", 0, 200, 1, "", nil)
    toggle(humanoid, "Shift to sprint", "Movement.SprintEnabled", nil)
    slider(humanoid, "Sprint speed", "Movement.SprintSpeed", 1, 200, 1, "", nil)
    toggle(humanoid, "Infinite air jump", "Movement.InfJump", nil)
    toggle(humanoid, "No clip", "Movement.NoClip", nil)
    toggle(humanoid, "Walk on walls", "Movement.WallWalkEnabled", nil)
    local touch = section:Create(tab.LeftCol, "Touch fling", "Movement")
    toggle(touch, "Enable touch fling", "Movement.TouchFling", nil)
    section:Info(touch, "Walk into other players. Pulses root velocity between physics steps; the server may reject it.")
    local step = section:Create(tab.LeftCol, "Displacement & world", "Movement")
    toggle(step, "CFrame speed", "Movement.CFrameSpeed", nil)
    slider(step, "Extra displacement speed", "Movement.CFrameSpeedValue", 0, 200, 1, " studs/s", nil)
    slider(step, "World gravity - 0 restores", "Movement.WorldGravity", 0, 400, 1, "", nil)
    slider(step, "Camera FOV - 0 restores", "Camera.FOV", 0, 120, 1, " deg", nil)
    local flight = section:Create(tab.RightCol, "Flight", "Movement")
    local camera = section:Create(tab.RightCol, "Free camera", "Movement")
    toggle(camera, "Enable freecam", "Movement.FreecamEnabled", nil)
    slider(camera, "Freecam speed", "Movement.FreecamSpeed", 1, 300, 1, " studs/s", nil)
    section:Info(camera, "WASD moves freely through the world. Mouse looks around; Space and Shift move vertically. Toggle freecam off to restore the camera.")
    toggle(flight, "Enable flight", "Movement.FlyEnabled", nil)
    slider(flight, "Flight speed", "Movement.FlySpeed", 1, 300, 1, " studs/s", nil)
    keybind(flight, "Flight hotkey", "Settings.Binds.Fly", nil)
    toggle(flight, "Mobile: ascend", "Movement.MobileFlyUp", nil)
    toggle(flight, "Mobile: descend", "Movement.MobileFlyDown", nil)
    local function holdButton(parent: Instance, label: string, transientKey: string)
        local row, text, owner = section:Control(parent, label, 26)
        text.Size = UDim2.new(1, -112, 1, 0)
        local button = dom:Create("TextButton", { Parent = row, BorderSizePixel = 0, Position = UDim2.new(1, -104, 0, 2), Size = UDim2.fromOffset(104, 22),
            Text = "Hold", Font = Enum.Font.Gotham, TextSize = 11, AutoButtonColor = false, Visible = environment:IsMobile() })
        section:StyleButton(button, owner)
        local activeInput: InputObject? = nil
        local function setHeld(value: boolean) state:SetTransient(transientKey, value) end
        owner:Connect(button.InputBegan, function(event: InputObject)
            if event.UserInputType == Enum.UserInputType.Touch or event.UserInputType == Enum.UserInputType.MouseButton1 then
                activeInput = event
                setHeld(true)
            end
        end)
        owner:Connect(UIS.InputEnded, function(event: InputObject)
            if event == activeInput or (activeInput and event.UserInputType == Enum.UserInputType.MouseButton1) then
                activeInput = nil
                setHeld(false)
            end
        end)
        owner:Add(function() activeInput = nil; setHeld(false) end)
    end
    holdButton(flight, "Mobile: hold ascend", "MobileFlyUpHeld")
    holdButton(flight, "Mobile: hold descend", "MobileFlyDownHeld")
    section:Info(flight, if environment:IsMobile() then "Use the movement thumbstick, toggles, or hold buttons. Release a hold button to stop vertical movement. Flight re-engages after a respawn."
        else "WASD follows the camera. Space ascends; Shift descends. Flight pauses while typing.")
    local travel = section:Create(tab.RightCol, "Position bookmarks")
    local name = textbox(travel, "Bookmark name", "Home")
    local selected = dropdown(travel, "Saved position", nil, movement:ListBookmarks())
    textbox:CreateButton(travel, "Save current position", function() return movement:SaveBookmark(name.Box.Text) end)
    textbox:CreateButton(travel, "Go to bookmark", function() return movement:GoToBookmark(selected:Get() or "") end)
    textbox:CreateButton(travel, "Delete bookmark", function() return movement:DeleteBookmark(selected:Get() or "") end)
    toggle(travel, "Return on touch", "Movement.TouchTeleportEnabled", nil)
    textbox:CreateButton(travel, "Set touch return spot", function() return movement:SetTouchTeleportSpot() end)
    scope:Add(services:Get("EventBus"):Subscribe("BookmarksChanged", function() selected:Refresh(movement:ListBookmarks(), true) end))
    section:Info(travel, "Bookmarks are session-only. Teleports clear assembly velocity and temporarily suppress anti-fling.")
    local mouse = section:Create(tab.RightCol, "Click teleport", "Settings")
    toggle(mouse, "Enable click / tap teleport", "Settings.TpToMouse", nil)
    section:Info(mouse, if environment:IsMobile() then "Tap a world surface, outside the menu, to teleport. The hold controls above provide vertical flight movement."
        else "Hold Ctrl and left-click a world surface. UI clicks and focused textboxes are ignored.")
    return { Name = tab.Name }
end
