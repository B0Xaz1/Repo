local HttpService = game:GetService("HttpService")

return function(services: any): any
    local disposer = services:Get("Disposer")
    local DOM = {}

    function DOM:Create(className: string, properties: any?, children: { Instance }?): any
        local instance = Instance.new(className)
        local props = properties or {}
        -- Parent is applied last so the instance only mounts once every property is set
        local ok, err = pcall(function()
            for property, value in pairs(props) do if property ~= "Parent" then instance[property] = value end end
            for _, child in ipairs(children or {}) do child.Parent = instance end
            if props.Parent ~= nil then instance.Parent = props.Parent end
        end)
        if not ok then instance:Destroy(); error(`DOM {className}: {tostring(err)}`) end
        disposer:Add(instance)
        return instance
    end

    function DOM:DestroyInstance(instance: Instance)
        for _, child in ipairs(instance:GetDescendants()) do disposer:Forget(child) end
        disposer:Forget(instance)
        instance:Destroy()
    end

    function DOM:CreateStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
        local theme = services:Get("ThemeEngine")
        local tokenColor = if type(color) == "string" then theme:GetToken(color) else nil
        local resolvedColor = if typeof(color) == "Color3" then color
            elseif typeof(tokenColor) == "Color3" then tokenColor
            else Color3.new(1, 1, 1)
        local resolvedThickness = math.max(0, tonumber(thickness) or 1)
        local stroke = self:Create("UIStroke", { Parent = parent, Color = resolvedColor, Thickness = resolvedThickness })
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        return stroke
    end

    function DOM:CreatePadding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
        return self:Create("UIPadding", { Parent = parent, PaddingTop = UDim.new(0, top), PaddingRight = UDim.new(0, right or top),
            PaddingBottom = UDim.new(0, bottom or top), PaddingLeft = UDim.new(0, left or right or top) })
    end

    function DOM:RandomName(): string
        return `_{(HttpService:GenerateGUID(false):gsub("%-", ""))}`
    end

    return DOM
end
