--!nonstrict
return function(services: any): any
    local disposer = services:Get("Disposer")
    local DOM = {}
    function DOM:Create(className: string, properties: any?, children: { Instance }?): any
        local instance = Instance.new(className)
        local props = properties or {}
        local ok, err = pcall(function()
            for property, value in pairs(props) do if property ~= "Parent" then instance[property] = value end end
            for _, child in ipairs(children or {}) do child.Parent = instance end
            -- Parenting last avoids half-built layouts becoming visible or firing ancestry listeners.
            if props.Parent ~= nil then instance.Parent = props.Parent end
        end)
        if not ok then instance:Destroy(); error("DOM " .. className .. ": " .. tostring(err)) end
        disposer:Add(instance)
        return instance
    end
    function DOM:DestroyInstance(instance: Instance)
        -- Temporary UI (toasts, dropdown options, search headers) must not accumulate in the master bag.
        for _, child in ipairs(instance:GetDescendants()) do disposer:Forget(child) end
        disposer:Forget(instance)
        instance:Destroy()
    end
    function DOM:CreateStroke(parent: Instance, color: Color3, thickness: number?): UIStroke
        return self:Create("UIStroke", { Parent = parent, Color = color, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    end
    function DOM:CreatePadding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
        return self:Create("UIPadding", { Parent = parent, PaddingTop = UDim.new(0, top), PaddingRight = UDim.new(0, right or top),
            PaddingBottom = UDim.new(0, bottom or top), PaddingLeft = UDim.new(0, left or right or top) })
    end
    function DOM:RandomName(): string
        return "_" .. game:GetService("HttpService"):GenerateGUID(false):gsub("%-", "")
    end
    return DOM
end
