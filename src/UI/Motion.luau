local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local TIMES = table.freeze({ Press = 0.07, Hover = 0.12, Exit = 0.12, Enter = 0.18, Tab = 0.15 })

return function(services: any): any
    local scope = services:Get("Disposer"):CreateChild("Motion")
    local active, controls, engaged, strokeOwners, infos = {}, {}, {}, {}, {}
    local reveals = setmetatable({}, { __mode = "k" })
    local Motion = { Times = TIMES }

    local function visible(instance: Instance): boolean
        local node: Instance? = instance
        while node do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") then return node.Enabled end
            node = node.Parent
        end
        return false
    end

    function Motion:Cancel(instance: Instance, channel: string?)
        local channels = active[instance]
        if not channels then return end
        if not channel then
            for name in pairs(table.clone(channels)) do self:Cancel(instance, name) end
            return
        end
        local record = channels[channel]
        if not record then return end
        channels[channel] = nil
        if next(channels) == nil then active[instance] = nil end
        record.Connection:Disconnect()
        record.Destroying:Disconnect()
        record.Tween:Cancel()
        record.Tween:Destroy()
    end

    function Motion:Tween(instance: Instance, channel: string, goals: any, duration: number?, finished: (() -> ())?)
        if scope:IsDisposed() then return end
        local existing = active[instance] and active[instance][channel]
        if existing and (duration or TIMES.Hover) > 0 then
            local same = true
            for property, value in pairs(goals) do if existing.Goals[property] ~= value then same = false; break end end
            for property in pairs(existing.Goals) do if goals[property] == nil then same = false; break end end
            if same then return end
        end
        self:Cancel(instance, channel)
        local changed = false
        for property, value in pairs(goals) do if instance[property] ~= value then changed = true; break end end
        if not changed then if finished then finished() end; return end
        local seconds = duration or TIMES.Hover
        if seconds <= 0 then
            for property, value in pairs(goals) do instance[property] = value end
            if finished then finished() end
            return
        end
        if not infos[seconds] then infos[seconds] = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end
        local tween = TweenService:Create(instance, infos[seconds], goals)
        local record: any = { Tween = tween, Goals = table.clone(goals) }
        if not active[instance] then active[instance] = {} end
        active[instance][channel] = record
        record.Connection = tween.Completed:Connect(function(status: Enum.PlaybackState)
            if not active[instance] or active[instance][channel] ~= record then return end
            active[instance][channel] = nil
            if next(active[instance]) == nil then active[instance] = nil end
            record.Connection:Disconnect(); record.Destroying:Disconnect(); tween:Destroy()
            if status == Enum.PlaybackState.Completed and not scope:IsDisposed() and finished then finished() end
        end)
        record.Destroying = instance.Destroying:Connect(function() Motion:Cancel(instance) end)
        tween:Play()
    end

    function Motion:Settle(frame: GuiObject)
        local record = reveals[frame]
        if not record then return true end
        if not record.Visible then return false end
        self:Cancel(frame, "Reveal")
        frame.Position, frame.Visible = record.Rest, record.Visible
        return true
    end

    function Motion:IsClosing(frame: GuiObject): boolean
        return reveals[frame] ~= nil and not reveals[frame].Visible
    end

    function Motion:SetRest(frame: GuiObject, position: UDim2)
        local record = reveals[frame]
        if record then record.Rest = position end
    end

    function Motion:Reveal(frame: GuiObject, on: boolean, finished: (() -> ())?)
        local record = reveals[frame]
        if not record then
            record = { Rest = frame.Position, Visible = not on }
            reveals[frame] = record
        end
        if record.Visible == on then return end
        record.Visible = on
        local shifted = record.Rest + UDim2.fromOffset(0, 8)
        if on then
            if not frame.Visible then frame.Position = shifted end
            frame.Visible = true
        else
            self:Reset(frame)
        end
        self:Tween(frame, "Reveal", { Position = if on then record.Rest else shifted }, if on then TIMES.Enter else TIMES.Exit, function()
            if not on then frame.Visible = false; frame.Position = record.Rest end
            if finished then finished() end
        end)
    end

    local function accent(): Color3
        return services:Get("ThemeEngine"):GetToken("Accent")
    end
    local function target(record: any, property: string, base: Color3): Color3
        local amount = if record.Down then 0.20 elseif record.Focused then 0.12 elseif record.Hover then 0.08 else 0
        if property == "Color" then amount = if record.Down or record.Focused then 0.9 elseif record.Hover then 0.6 else 0 end
        if property == "TextColor3" then amount *= 2 end
        return if amount > 0 then base:Lerp(accent(), amount) else base
    end

    function Motion:Color(instance: Instance, property: string, color: Color3)
        local record = controls[instance] or (property == "Color" and strokeOwners[instance])
        if not record then
            self:Cancel(instance, property)
            if instance[property] ~= color then instance[property] = color end
            return
        end
        local bases = if instance == record.Stroke then record.StrokeBases else record.Bases
        local previous = bases[property]
        bases[property] = color
        self:Tween(instance, property, { [property] = target(record, property, color) },
            if previous ~= nil and visible(record.Instance) then TIMES.Hover else 0)
    end

    function Motion:BindStroke(instance: Instance, stroke: UIStroke)
        local record = controls[instance]
        if not record or record.Stroke then return end
        record.Stroke, record.StrokeBases = stroke, { Color = stroke.Color }
        strokeOwners[stroke] = record
    end

    local function paint(record: any, instant: boolean?)
        local instance = record.Instance
        local on = record.Hover or record.Down or record.Focused
        engaged[instance] = if on then record else nil
        if on and not record.Stroke then
            local stroke = Instance.new("UIStroke")
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color, stroke.Transparency, stroke.Thickness = accent(), 1, 1
            stroke.Parent = instance
            record.OwnStroke = true
            Motion:BindStroke(instance, stroke)
        end
        local duration = if instant then 0 elseif record.Down then TIMES.Press else TIMES.Hover
        for property, color in pairs(record.Bases) do
            Motion:Tween(instance, property, { [property] = target(record, property, color) }, duration)
        end
        if record.Stroke then
            local color = record.StrokeBases.Color
            Motion:Tween(record.Stroke, "Color", { Color = target(record, "Color", color) }, duration)
            if record.OwnStroke then
                Motion:Tween(record.Stroke, "Feedback", { Transparency = if on then 0.25 else 1 }, duration)
            end
        end
    end

    function Motion:Reset(root: Instance?)
        for instance, record in pairs(table.clone(engaged)) do
            if not root or instance == root or instance:IsDescendantOf(root) then
                record.Hover, record.Down, record.Focused, record.Input = false, false, false, nil
                if instance:IsA("TextBox") and instance:IsFocused() then instance:ReleaseFocus() end
                paint(record, true)
            end
        end
    end

    function Motion:Bind(instance: Instance)
        if controls[instance] or not (instance:IsA("GuiButton") or instance:IsA("TextBox")) then return end
        local owner = scope:CreateChild("Feedback")
        local record: any = { Instance = instance, Bases = {}, StrokeBases = {}, Hover = false, Down = false, Focused = false }
        controls[instance] = record
        if instance:IsA("GuiButton") then instance.AutoButtonColor = false end
        owner:ConnectImmediate(instance.MouseEnter, function() record.Hover = true; paint(record) end)
        owner:ConnectImmediate(instance.MouseLeave, function() record.Hover = false; paint(record) end)
        owner:ConnectImmediate(instance.InputBegan, function(input: InputObject)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
                or input.KeyCode == Enum.KeyCode.ButtonA then
                if record.Down then return end
                record.Down, record.Input = true, input; paint(record)
            end
        end)
        if instance:IsA("TextBox") then
            owner:ConnectImmediate(instance.Focused, function() record.Focused = true; paint(record) end)
            owner:ConnectImmediate(instance.FocusLost, function() record.Focused = false; paint(record) end)
        else
            owner:ConnectImmediate(instance.SelectionGained, function() record.Focused = true; paint(record) end)
            owner:ConnectImmediate(instance.SelectionLost, function() record.Focused = false; paint(record) end)
        end
        owner:ConnectImmediate(instance.Destroying, function() owner:Dispose() end)
        owner:Add(function()
            controls[instance], engaged[instance] = nil, nil
            Motion:Cancel(instance)
            if record.Stroke then
                strokeOwners[record.Stroke] = nil
                Motion:Cancel(record.Stroke)
                if record.OwnStroke then record.Stroke:Destroy() end
            end
        end)
    end

    scope:ConnectImmediate(UIS.InputEnded, function(input: InputObject)
        for _, record in pairs(engaged) do
            if record.Input == input or (record.Down and record.Input and record.Input.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1) then
                record.Down, record.Input = false, nil
                paint(record)
            end
        end
    end)
    scope:ConnectImmediate(UIS.WindowFocusReleased, function() Motion:Reset() end)
    scope:Add(services:Get("EventBus"):Subscribe("ThemeChanged", function()
        for _, record in pairs(engaged) do paint(record) end
    end))
    scope:Add(function()
        for instance in pairs(table.clone(active)) do Motion:Cancel(instance) end
    end)
    function Motion:Destroy() scope:Dispose() end
    return Motion
end
