-- Executed by run_ui_tests.py. These doubles test lifecycles, not Roblox GPU/layout performance.
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks += 1
end
local signals = {}
local function signal()
    local handlers = {}
    local event = {}
    function event:Connect(callback)
        local connection = { Connected = true, _type = "RBXScriptConnection" }
        handlers[connection] = callback
        function connection:Disconnect() self.Connected = false; handlers[self] = nil end
        return connection
    end
    function event:Fire(...)
        for connection, callback in pairs(table.clone(handlers)) do
            if connection.Connected then callback(...) end
        end
    end
    function event:Count() local n = 0; for _ in pairs(handlers) do n += 1 end; return n end
    table.insert(signals, event)
    return event
end
local function connectionCount()
    local count = 0
    for _, event in ipairs(signals) do count += event:Count() end
    return count
end
local Enum = setmetatable({}, { __index = function(self, category)
    local values = setmetatable({}, { __index = function(group, name)
        local value = { Name = name, EnumType = "Enum." .. category, _type = "EnumItem" }
        rawset(group, name, value); return value
    end })
    rawset(self, category, values); return values
end })
local Color3 = {}
local colorMeta = { __eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end }
colorMeta.__index = {
    Lerp = function(a, b, t) return Color3.new(a.R + (b.R-a.R)*t, a.G + (b.G-a.G)*t, a.B + (b.B-a.B)*t) end,
    ToHSV = function(a) return 0, 0, a.R end,
}
function Color3.new(r,g,b) return setmetatable({ R=r, G=g, B=b, _type="Color3" }, colorMeta) end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
function Color3.fromHSV(h,s,v) return Color3.new(v, v*(1-s), v*(1-h*s)) end
local UDim = { new = function(s,o) return {Scale=s,Offset=o} end }
local UDim2 = {}
local udimMeta = {
    __eq = function(a,b) return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset end,
    __add = function(a,b) return UDim2.new(a.X.Scale+b.X.Scale,a.X.Offset+b.X.Offset,a.Y.Scale+b.Y.Scale,a.Y.Offset+b.Y.Offset) end,
}
function UDim2.new(xs,xo,ys,yo) return setmetatable({X=UDim.new(xs,xo),Y=UDim.new(ys,yo)},udimMeta) end
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local Vector2 = {}
local vectorMeta = {
    __eq = function(a,b) return a.X == b.X and a.Y == b.Y end,
    __sub = function(a,b) return Vector2.new(a.X-b.X,a.Y-b.Y) end,
}
function Vector2.new(x,y) return setmetatable({X=x,Y=y},vectorMeta) end
Vector2.zero = Vector2.new(0,0)
local createdInstances = 0
local Instance = {}
function Instance.new(class)
    createdInstances += 1
    local props = { ClassName=class, Name=class, Visible=true, Enabled=true, Text="", Size=UDim2.fromOffset(0,0),
        Position=UDim2.fromOffset(0,0), Rotation=0, BackgroundTransparency=0, Transparency=0, Thickness=1,
        Color=Color3.new(1,1,1), BackgroundColor3=Color3.new(0,0,0), TextColor3=Color3.new(1,1,1),
        AbsolutePosition=Vector2.zero, AbsoluteSize=Vector2.new(100,20), AbsoluteCanvasSize=Vector2.zero, LayoutOrder=0 }
    local object = { _type="Instance", _children={}, _signals={}, _attributes={}, _props=props }
    local methods = {}
    function methods:IsA(name)
        if class == name or name == "Instance" then return true end
        if name == "GuiButton" then return class == "TextButton" or class == "ImageButton" end
        if name == "GuiObject" then return table.find({"Frame","TextButton","ImageButton","TextBox","TextLabel","ScrollingFrame"},class) ~= nil end
        return false
    end
    function methods:GetChildren() return table.clone(self._children) end
    function methods:GetDescendants()
        local all = {}
        for _, child in ipairs(self._children) do
            table.insert(all,child)
            for _, descendant in ipairs(child:GetDescendants()) do table.insert(all,descendant) end
        end
        return all
    end
    function methods:IsDescendantOf(root)
        local parent = self.Parent
        while parent do if parent == root then return true end; parent = parent.Parent end
        return false
    end
    function methods:GetPropertyChangedSignal(name)
        if not self._signals[name] then self._signals[name] = signal() end
        return self._signals[name]
    end
    function methods:SetAttribute(name,value) self._attributes[name] = value end
    function methods:GetAttribute(name) return self._attributes[name] end
    function methods:FindFirstChildOfClass(name)
        for _, child in ipairs(self._children) do if child:IsA(name) then return child end end
    end
    function methods:IsFocused() return self._focus == true end
    function methods:CaptureFocus() self._focus=true; self.Focused:Fire() end
    function methods:ReleaseFocus() self._focus=false; self.FocusLost:Fire(false) end
    function methods:Destroy()
        if self._destroyed then return end
        self.Destroying:Fire()
        for _, child in ipairs(self:GetChildren()) do child:Destroy() end
        self.Parent=nil; self._destroyed=true
    end
    return setmetatable(object, {
        __index = function(self,key)
            if methods[key] then return methods[key] end
            if props[key] ~= nil then return props[key] end
            if table.find({"Destroying","MouseEnter","MouseLeave","InputBegan","Activated","Focused","FocusLost","SelectionGained","SelectionLost"},key) then
                local event=signal(); rawset(self,key,event); return event
            end
            return nil
        end,
        __newindex = function(self,key,value)
            if key == "LayoutOrder" and rawget(self,"_failLayout") then
                rawset(self,"_failLayout",false); error("Injected layout failure")
            end
            local old=props[key]
            if key == "Parent" then
                if old then local at=table.find(old._children,self); if at then table.remove(old._children,at) end end
                if value then table.insert(value._children,self) end
            end
            props[key]=value
            if old ~= value and self._signals[key] then self._signals[key]:Fire() end
        end,
    })
end
local waiting = {}
local task = {}
function task.spawn(worker,...)
    if type(worker)=="function" then worker=coroutine.create(worker) end
    local ok,err=coroutine.resume(worker,...); assert(ok,err); return worker
end
function task.defer(callback,...)
    local args=table.pack(...)
    local worker=coroutine.create(function() callback(table.unpack(args,1,args.n)) end)
    waiting[worker]=true; return worker
end
function task.delay(_seconds,callback)
    if type(callback) == "thread" then waiting[callback]=true; return callback end
    return task.defer(callback)
end
function task.wait() coroutine.yield() end
function task.cancel(worker) waiting[worker]=nil; coroutine.close(worker) end
local function flushTasks()
    for worker in pairs(table.clone(waiting)) do
        waiting[worker]=nil
        if coroutine.status(worker)~="dead" then task.spawn(worker) end
    end
end
local tweens, tweenCount = {}, 0
local TweenService = {}
function TweenService:Create(instance,info,goals)
    tweenCount += 1
    local tween = { Completed=signal(), Instance=instance, Goals=goals, Duration=info.Time }
    function tween:Play() tweens[self]=true end
    function tween:Cancel() tweens[self]=nil; self.Completed:Fire(Enum.PlaybackState.Cancelled) end
    function tween:Destroy() tweens[self]=nil end
    return tween
end
local function flushTweens()
    for tween in pairs(table.clone(tweens)) do
        if tweens[tween] then
            for property,value in pairs(tween.Goals) do tween.Instance[property]=value end
            tweens[tween]=nil; tween.Completed:Fire(Enum.PlaybackState.Completed)
        end
    end
end
local function pendingTween(instance,property)
    for tween in pairs(tweens) do if tween.Instance==instance and tween.Goals[property]~=nil then return tween end end
end
local UIS = { InputBegan=signal(), InputChanged=signal(), InputEnded=signal(), WindowFocusReleased=signal() }
local RunService = { RenderStepped=signal() }
local Workspace = Instance.new("Workspace")
Workspace.CurrentCamera = Instance.new("Camera")
Workspace.CurrentCamera.ViewportSize = Vector2.new(1280,720)
local gameServices = { TweenService=TweenService, UserInputService=UIS, Workspace=Workspace, RunService=RunService,
    HttpService={GenerateGUID=function() return "test-id" end} }
local mock = {
    game={GetService=function(_,name) return assert(gameServices[name],name) end}, Enum=Enum, Color3=Color3, UDim=UDim,
    UDim2=UDim2, Vector2=Vector2, Instance=Instance, task=task,
    TweenInfo={new=function(time) return {Time=time} end},
    typeof=function(value) return if type(value)=="table" and value._type then value._type else typeof(value) end,
    ColorSequence={new=function(value) return value end}, ColorSequenceKeypoint={new=function(...) return {...} end},
    NumberSequence={new=function(value) return value end}, NumberSequenceKeypoint={new=function(...) return {...} end},
}
setmetatable(mock,{__index=getfenv()})
local factories = {}
local function factory(path)
    if not factories[path] then
        local chunk=assert(loadstring(assert(SOURCES[path],path),path)); setfenv(chunk,mock)
        factories[path]=chunk()
    end
    return factories[path]
end
local master=factory("src/Core/Disposer.luau")().new("Test")
local bus=factory("src/Core/EventBus.luau")(master)
local services={ Version="test", Disposer=master, EventBus=bus }
function services:Get(name) return assert(self[name],name) end
function services:Has(name) return self[name]~=nil end
local stateValues = { ["Settings.MenuVisible"]=true, ["Settings.ShowMenuIcon"]=true, ["Settings.UIScale"]=1,
    ["Settings.CompactMenu"]=false, ["Theme.ActivePreset"]="Midnight", ["Theme.CustomTokens"]={},
    ESP={Enabled=false,Color=Color3.new(1,0,0),Rainbow=false}, Chams={Enabled=false,FillColor=Color3.new(0,1,0),Rainbow=false} }
local transients={}
services.StateStore={
    GetDefaultSettings=function() return { Settings = { MotionMode = "Full", MotionSpeed = 1, Tooltips = true } } end,
    GetTransient=function(_,key) return transients[key] end,
    SetTransient=function(_,key,value) transients[key]=value end,
    Peek=function(_,path) return stateValues[path] end,
    Get=function(_,path) return stateValues[path] end,
    Observe=function(_,path,cb) return bus:Subscribe("StateChanged:"..path,cb) end,
    Set=function(_,path,value)
        if stateValues[path]==value then return true end
        stateValues[path]=value; bus:Publish("StateChanged:"..path,value); bus:Publish("StateChanged",path,value); return true
    end,
}
local guiParent=Instance.new("Frame")
services.Environment={
    GetSafeGuiParent=function() return guiParent end, IsMobile=function() return false end,
    ParseKeybind=function(_,value) return value end,
    FormatKeybindName=function() return "Key" end, GetPointerLocation=function(_,input) return input.Position end,
}
services.ConfigService={Export=function() return "{}" end}
local instances={}
services.Require=function(path,container)
    if path:find("src/UI/Tabs/",1,true) then return function() end end
    if container then
        if not instances[path] then instances[path]=factory(path)(container) end
        return instances[path]
    end
    return factory(path)
end
services.Motion=factory("src/UI/Motion.luau")(services)
services.DOM=factory("src/UI/DOM.luau")(services)
services.ThemeEngine=factory("src/UI/ThemeEngine.luau")(services)
services.ThemeEngine:Initialize()
services.Tooltips=factory("src/UI/Tooltips.luau")(services)
services.UIEngine=factory("src/UI/UIEngine.luau")(services)
local motion,dom,theme,ui = services.Motion,services.DOM,services.ThemeEngine,services.UIEngine
local screen=dom:Create("ScreenGui",{Parent=guiParent})
local frame=dom:Create("Frame",{Parent=screen})
local button=dom:Create("TextButton",{Parent=frame})
theme:BindToken(button,"BackgroundColor3","Elem")
local base=button.BackgroundColor3
local completed=0
motion:Tween(frame,"test",{Rotation=20},0.12,function() completed+=1 end)
local first=pendingTween(frame,"Rotation")
local count=tweenCount
motion:Tween(frame,"test",{Rotation=20},0.12)
check(tweenCount==count,"identical tween is reused")
motion:Tween(frame,"test",{Rotation=30},0.12,function() completed+=10 end)
first.Completed:Fire(Enum.PlaybackState.Completed)
flushTweens()
check(frame.Rotation==30 and completed==10,"replacement cancels stale completion")
count=tweenCount
motion:Tween(frame,"test",{Rotation=30})
check(tweenCount==count,"unchanged property creates no tween")
motion:Tween(frame,"test",{Rotation=40})
motion:Tween(frame,"test",{Rotation=40},0)
check(frame.Rotation==40 and not pendingTween(frame,"Rotation"),"instant update cancels matching in-flight tween")
button.MouseEnter:Fire(); flushTweens()
check(button.BackgroundColor3~=base,"hover feedback")
local press={UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown}
button.InputBegan:Fire(press); flushTweens()
local pressed=button.BackgroundColor3
UIS.InputEnded:Fire(press); flushTweens()
check(button.BackgroundColor3~=pressed,"release outside control resets press")
button.MouseLeave:Fire(); flushTweens()
check(button.BackgroundColor3==base,"hover restores base color")
button.MouseEnter:Fire(); flushTweens()
theme:SetPreset("Paper"); flushTweens()
button.MouseLeave:Fire(); flushTweens()
check(button.BackgroundColor3==theme:GetToken("Elem"),"theme changes preserve correct rest color")
button.MouseEnter:Fire(); flushTweens(); motion:Reset(frame)
check(button.BackgroundColor3==theme:GetToken("Elem"),"hidden subtree resets feedback immediately")
button.InputBegan:Fire(press); UIS.WindowFocusReleased:Fire()
check(button.BackgroundColor3==theme:GetToken("Elem"),"focus loss clears held feedback")
local box=dom:Create("TextBox",{Parent=frame})
theme:BindToken(box,"BackgroundColor3","Elem")
box:CaptureFocus(); flushTweens()
check(box.BackgroundColor3~=theme:GetToken("Elem"),"textbox focus feedback")
motion:Reset(frame)
check(not box:IsFocused(),"hidden textbox releases keyboard focus")
local touch1={UserInputType=Enum.UserInputType.Touch,KeyCode=Enum.KeyCode.Unknown}
local touch2={UserInputType=Enum.UserInputType.Touch,KeyCode=Enum.KeyCode.Unknown}
button.InputBegan:Fire(touch1); flushTweens(); pressed=button.BackgroundColor3
UIS.InputEnded:Fire(touch2); flushTweens()
check(button.BackgroundColor3==pressed,"unrelated touch does not release press")
UIS.InputEnded:Fire(touch1); flushTweens()
check(button.BackgroundColor3==theme:GetToken("Elem"),"matching touch releases press")
local popup=dom:Create("Frame",{Parent=screen,Visible=false,Position=UDim2.fromOffset(20,30)})
motion:Reveal(popup,true); flushTweens()
check(popup.Visible and popup.Position==UDim2.fromOffset(20,30),"window entry settles at rest")
motion:Reveal(popup,false)
local closing=pendingTween(popup,"Position")
motion:Reveal(popup,true); closing.Completed:Fire(Enum.PlaybackState.Completed); flushTweens()
check(popup.Visible and popup.Position==UDim2.fromOffset(20,30),"rapid reopen rejects stale hide")
motion:Reveal(popup,false)
check(motion:Settle(popup)==false and pendingTween(popup,"Position")~=nil,"drag cannot cancel a closing window cleanup")
flushTweens()
check(not popup.Visible and popup.Position==UDim2.fromOffset(20,30),"window exit hides and restores position")
motion:Reveal(popup,true); motion:Settle(popup)
check(popup.Visible and not pendingTween(popup,"Position"),"drag settles opening transition")
motion:SetRest(popup,UDim2.fromOffset(100,100)); popup.Position=UDim2.fromOffset(100,100)
motion:Reveal(popup,false); flushTweens(); motion:Reveal(popup,true); flushTweens()
check(popup.Position==UDim2.fromOffset(100,100),"reopening preserves dragged position")
ui:ConstructInterface(); flushTweens()
check(#ui._tabs==8 and ui._active.Name=="Combat","all tabs construct")
local firstTab=ui._active
ui:SelectTab("Visuals"); local secondTab=ui._active
ui:SelectTab("Movement"); ui:SelectTab("Visuals"); flushTweens()
check(not firstTab.Page.Visible and secondTab.Page.Visible and secondTab.Page.Position==secondTab.RestPosition,"rapid tab switching settles one page")
count=tweenCount
ui:SelectTab("Visuals")
check(tweenCount==count,"selecting active tab performs no transition")
services.StateStore:Set("Settings.MenuVisible",false); services.StateStore:Set("Settings.MenuVisible",true); flushTweens()
check(ui._main.Visible,"menu rapid reopen remains visible")
services.StateStore:Set("Settings.CompactMenu",true); flushTweens()
check(secondTab.Page.Position==secondTab.RestPosition,"resize settles tab position")
local section=services.Require("src/UI/Components/Section.luau",services)
local panel=section:Create(secondTab.LeftCol,"Test controls")
local dropdown=services.Require("src/UI/Components/Dropdown.luau",services)(panel,"Choice","one",{"one","two"})
local dropdownButton=dropdown.Row:FindFirstChildOfClass("TextButton")
dropdownButton.Activated:Fire(); flushTweens()
check(dropdown._open and dropdown.Row.Size.Y.Offset>38,"dropdown expands")
ui:CloseAllDropdownsExcept(nil); dropdownButton.Activated:Fire(); flushTweens()
check(dropdown._open and dropdown.Row.Size.Y.Offset>38,"dropdown reversal cancels close")
local allocations=createdInstances
dropdown:Refresh({"one","two"},true)
check(createdInstances==allocations and dropdown._open,"unchanged options do not rebuild or close")
ui:Search("choice"); check(dropdown.Row.Parent.Parent.Parent==secondTab.ResultsCol,"search reparents matching controls")
ui:ClearSearch(); check(dropdown.Row.Parent.Parent.Parent==panel,"clearing search restores original parent")
rawset(dropdown.Row.Parent.Parent,"_failLayout",true)
ui:Search("choice")
check(dropdown.Row.Parent.Parent.Parent==panel and ui._query=="" and not ui._searchActive,"failed search rolls back controls already moved")
check(#ui._searchHeaders==0 and secondTab.Columns.Visible and not secondTab.ResultsCol.Visible,"failed search clears temporary headers and restores columns")

local picker=services.Require("src/UI/Components/ColorPicker.luau",services)(panel,"Color",Color3.new(1,1,1))
picker.Row:FindFirstChildOfClass("TextButton").Activated:Fire(); flushTweens()
check(picker._open and picker.Row.Size.Y.Offset==158,"color picker expands")
ui:CloseAllDropdownsExcept(nil); flushTweens()
check(not picker._open and picker.Row.Size.Y.Offset==28,"color picker collapses")
local slider=services.Require("src/UI/Components/Slider.luau",services)(panel,"Amount",0,0,100,1)
local hit=slider.Row:FindFirstChildOfClass("TextButton")
local track=hit:FindFirstChildOfClass("Frame")
local fill=track:FindFirstChildOfClass("Frame")
slider:Set(50); flushTweens()
check(fill.Size==UDim2.fromScale(0.5,1),"programmatic slider value animates")
local touchDrag={UserInputType=Enum.UserInputType.Touch,KeyCode=Enum.KeyCode.Unknown,Position=Vector2.new(80,0)}
hit.InputBegan:Fire(touchDrag)
check(slider:Get()==80 and fill.Size==UDim2.fromScale(0.8,1),"slider tracks touch immediately without tween lag")
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(10,0)})
check(slider:Get()==80,"slider ignores other touch fingers")
UIS.WindowFocusReleased:Fire(); touchDrag.Position=Vector2.new(20,0); UIS.InputChanged:Fire(touchDrag)
check(slider:Get()==80,"focus loss cancels slider capture")
local dragAgain={UserInputType=Enum.UserInputType.Touch,KeyCode=Enum.KeyCode.Unknown,Position=Vector2.new(70,0)}
hit.InputBegan:Fire(dragAgain)
UIS.InputEnded:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector2.new(10,0)})
dragAgain.Position=Vector2.new(60,0); UIS.InputChanged:Fire(dragAgain)
check(slider:Get()==60,"unrelated mouse release does not end a touch drag")
hit.InputBegan:Fire({UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(5,0)})
dragAgain.Position=Vector2.new(55,0); UIS.InputChanged:Fire(dragAgain)
check(slider:Get()==55,"a second touch cannot steal slider capture")
UIS.InputEnded:Fire(dragAgain)
hit.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector2.new(40,0)})
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(5,0)})
check(slider:Get()==40,"touch movement cannot change a mouse drag")
UIS.InputEnded:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector2.new(40,0)})
button.InputBegan:Fire(touch1); flushTweens(); local touchColor=button.BackgroundColor3
UIS.InputEnded:Fire(press); flushTweens()
check(button.BackgroundColor3==touchColor,"mouse release does not clear touch press feedback")
button.InputBegan:Fire(touch2); UIS.InputEnded:Fire(touch1); flushTweens()
check(button.BackgroundColor3==theme:GetToken("Elem"),"first touch retains feedback ownership")
local pickerPanel=picker.Row:FindFirstChildOfClass("Frame")
local pickerSquare=pickerPanel:FindFirstChildOfClass("TextButton")
local swatch=picker.Row:FindFirstChildOfClass("TextButton")
swatch.Activated:Fire(); flushTweens()
local colorTouch={UserInputType=Enum.UserInputType.Touch,Position=Vector2.new(40,10)}
pickerSquare.InputBegan:Fire(colorTouch)
check(swatch.BackgroundColor3~=picker:Get(),"color drag previews without committing")
UIS.WindowFocusReleased:Fire()
check(swatch.BackgroundColor3==picker:Get(),"losing focus restores an uncommitted color preview")
pickerSquare.InputBegan:Fire(colorTouch)
ui:CloseAllDropdownsExcept(nil); flushTweens()
check(swatch.BackgroundColor3==picker:Get(),"closing a color picker restores uncommitted preview")
local keybinds=services.Require("src/UI/Components/Keybind.luau",services)
local key=keybinds(panel,"Shortcut",Enum.KeyCode.F)
local bindButton=key.Row:FindFirstChildOfClass("TextButton")
bindButton.Activated:Fire()
check(services.StateStore:GetTransient("IsBindingKey")==true,"key capture blocks feature shortcuts")
services.StateStore:Set("Settings.MenuVisible",false); flushTasks()
check(not keybinds._active and services.StateStore:GetTransient("IsBindingKey")==false and key:Get()==Enum.KeyCode.F,"hiding menu cancels capture without changing its bind")
services.StateStore:Set("Settings.MenuVisible",true); flushTweens()
bindButton.Activated:Fire(); ui:SelectTab("Combat"); flushTasks()
check(not keybinds._active and services.StateStore:GetTransient("IsBindingKey")==false,"changing tabs cancels hidden key capture")
ui:SelectTab("Visuals"); bindButton.Activated:Fire(); UIS.WindowFocusReleased:Fire(); flushTasks()
check(not keybinds._active and key:Get()==Enum.KeyCode.F,"focus loss cancels key capture without unbinding")
bindButton.Activated:Fire(); UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.Escape,UserInputType=Enum.UserInputType.Keyboard}); flushTasks()
check(key:Get()==Enum.KeyCode.Unknown and services.StateStore:GetTransient("IsBindingKey")==false,"Escape still clears the captured bind")

local modal=services.Require("src/UI/Modals/ConfigShareModal.luau",services)
modal:Show("{}"); flushTweens(); local oldView=modal._view
modal:Hide(); modal:Show("{}"); flushTweens()
check(oldView:IsDisposed() and modal._view and modal._view.Window.Visible,"modal reopen disposes old view without hiding new view")
modal:Hide(); flushTweens(); check(modal._view==nil,"modal exit finishes cleanup")
local preview=services.Require("src/UI/Modals/VisualsPreview.luau",services)
preview:Mount(ui._root); flushTweens()
check(RunService.RenderStepped:Count()==0,"static preview has no frame connection")
stateValues.ESP.Enabled=true; stateValues.ESP.Rainbow=true; bus:Publish("StateChanged","ESP.Rainbow",true); flushTasks()
check(RunService.RenderStepped:Count()==1,"rainbow preview starts a single frame connection")
ui:SelectTab("Combat")
check(RunService.RenderStepped:Count()==0,"hidden preview stops rendering")
ui:SelectTab("Visuals"); stateValues.ESP.Rainbow=false; bus:Publish("StateChanged","ESP.Rainbow",false); flushTasks()
check(RunService.RenderStepped:Count()==0,"disabling rainbow stops rendering")
services.CommandService={
    GetCommandList=function() return {
        {Name="/help",Category="General",Usage="/help"}, {Name="/menu",Category="UI",Usage="/menu"},
        {Name="/profile",Category="Config",Usage="/profile name"},
    } end,
    GetRecentHistory=function() return {} end,
    Execute=function() return true end,
}
local commandTab=ui._tabByName.Commands
factory("src/UI/Tabs/CommandsTab.luau")(services,commandTab)
local filterBox,commandList
for _, child in ipairs(commandTab.LeftCol:GetDescendants()) do
    if child:IsA("TextBox") then filterBox=child end
    if child:IsA("ScrollingFrame") then commandList=child end
end
local commandRows={}
for _, child in ipairs(commandList:GetChildren()) do if child:IsA("TextButton") then table.insert(commandRows,child) end end
check(#commandRows==3,"command rows built once")
local commandAllocations,commandConnections=createdInstances,connectionCount()
for _=1,20 do filterBox.Text="help"; filterBox.Text="menu"; filterBox.Text="" end
check(createdInstances==commandAllocations and connectionCount()==commandConnections,"command filtering allocates no rows or connections")
filterBox.Text="no match"
local hidden=0
for _, row in ipairs(commandRows) do if not row.Visible then hidden+=1 end end
check(hidden==3,"command filtering hides nonmatches")
filterBox.Text=""
check(commandRows[1].Visible and commandRows[2].Visible and commandRows[3].Visible,"command filter restores rows")
local logFrame
for _, child in ipairs(commandTab.RightCol:GetDescendants()) do if child:IsA("ScrollingFrame") then logFrame=child end end
for index=1,100 do bus:Publish("CommandOutput",`line {index}`) end
local logCount=0
for _, child in ipairs(logFrame:GetChildren()) do if child:IsA("TextLabel") then logCount+=1 end end
check(logCount==80,"command output stays bounded")
for _, duration in pairs(motion.Times) do check(duration>=0.07 and duration<=0.18,"snappy shared timing budget") end
local toggle=services.Require("src/UI/Components/Toggle.luau",services)(panel,"Switch",false)
local toggleButton=toggle.Row:FindFirstChildOfClass("TextButton")
toggleButton.Activated:Fire(); toggleButton.Activated:Fire(); toggleButton.Activated:Fire(); flushTweens()
check(toggle:Get()==true and toggleButton:FindFirstChildOfClass("UIStroke").Transparency==1,"rapid toggle clicks settle at latest value")
-- Additional motion stays bounded, reversible, and event-driven.
local mark=toggleButton:FindFirstChildOfClass("Frame")
check(mark.Rotation==0 and mark.Size==UDim2.fromOffset(8,8),"enabled checkmark settles at full size")
for _, arm in ipairs(mark:GetChildren()) do check(arm.BackgroundTransparency==0,"enabled checkmark strokes are visible") end
toggle:Set(false); toggle:Set(true); toggle:Set(false); flushTweens()
check(mark.Rotation==-12 and mark.Size==UDim2.fromOffset(6,6),"rapid checkmark reversal follows latest toggle")
for _, arm in ipairs(mark:GetChildren()) do check(arm.BackgroundTransparency==1,"disabled checkmark strokes fade out") end
local beforeUnchanged=tweenCount
toggle:Set(false); toggle:Set(false)
check(tweenCount==beforeUnchanged,"unchanged toggle values do not create animations")
ui:SelectTab("Combat"); flushTweens(); local beforeHidden=tweenCount
toggle:Set(true); slider:Set(25)
check(tweenCount==beforeHidden and mark.Rotation==0 and fill.Size==UDim2.fromScale(0.25,1),"hidden control changes settle without starting tweens")
ui:SelectTab("Visuals"); flushTweens()
local thumb=fill:FindFirstChildOfClass("Frame")
hit.MouseEnter:Fire(); flushTweens()
check(thumb.BackgroundTransparency==0 and thumb.Size==UDim2.fromOffset(7,7),"hover reveals slider thumb")
local sliderPress={UserInputType=Enum.UserInputType.MouseButton1,Position=Vector2.new(80,0)}
hit.InputBegan:Fire(sliderPress); flushTweens()
check(thumb.Size==UDim2.fromOffset(9,9) and slider:Get()==80,"pressed thumb expands without changing pointer response")
UIS.InputEnded:Fire(sliderPress); hit.MouseLeave:Fire(); flushTweens()
check(thumb.BackgroundTransparency==1 and track.Size.Y.Offset==3,"slider returns to compact idle track")
hit.MouseEnter:Fire(); flushTweens(); motion:Reset(hit)
check(thumb.BackgroundTransparency==1 and not pendingTween(thumb,"Size"),"reset hides thumb immediately")
local observerCalls=0
local observer=motion:ObserveInteraction(button,function() observerCalls+=1 end)
button.MouseEnter:Fire(); flushTweens(); local observed=observerCalls
bus:Publish("ThemeChanged"); bus:Publish("ThemeChanged"); flushTweens()
check(observerCalls==observed,"theme refreshes do not repeat unchanged interaction callbacks")
observer:Disconnect(); button.MouseLeave:Fire(); flushTweens()
check(observerCalls==observed,"disconnected interaction observer is not called")
local edge=button:FindFirstChildOfClass("UIStroke")
button.InputBegan:Fire(press); flushTweens()
check(edge.Thickness==1.75,"press gives a subtle border response")
UIS.InputEnded:Fire(press); flushTweens()
check(edge.Thickness==1,"release restores original border thickness")
bindButton.Activated:Fire(); flushTweens()
check(bindButton:FindFirstChildOfClass("UIStroke").Thickness==1.5,"key recording has persistent capture emphasis")
UIS.WindowFocusReleased:Fire(); flushTasks(); flushTweens()
check(bindButton:FindFirstChildOfClass("UIStroke").Thickness==1,"cancelled key capture clears emphasis")
dropdownButton.Activated:Fire(); flushTweens()
check(dropdown._selectedChoice==dropdown._choices[1] and dropdown._choices[1].Button.TextColor3==theme:GetToken("Accent"),"dropdown highlights the selected text on open")
dropdown:Set("two"); flushTweens()
check(dropdown._choices[1].Button.TextColor3==theme:GetToken("Text") and dropdown._choices[2].Button.TextColor3==theme:GetToken("Accent"),"selected-text highlight moves to new option")
local beforeSame=tweenCount
dropdown:Set("two")
check(tweenCount==beforeSame,"same dropdown selection does not restart feedback")
dropdown:Refresh({"three","two"},true); flushTweens()
check(dropdown:Get()=="two" and dropdown._selectedChoice==dropdown._choices[2],"rebuilt option list retains selection highlight")
do
    local option = dropdown._choices[1].Button
    check(option:FindFirstChildOfClass("UIStroke") == nil and option:FindFirstChildOfClass("Frame") == nil, "dropdown options have no outlines or selection lines")
    local normal = option.BackgroundColor3
    option.MouseEnter:Fire(); flushTweens()
    check(option.BackgroundColor3 ~= normal, "borderless dropdown keeps smooth hover feedback")
    option.InputBegan:Fire(press); option.SelectionGained:Fire(); flushTweens()
    check(option:FindFirstChildOfClass("UIStroke") == nil, "hover, press and keyboard focus do not recreate dropdown lines")
    UIS.InputEnded:Fire(press); option.SelectionLost:Fire(); option.MouseLeave:Fire(); flushTweens()
    check(option.BackgroundColor3 == normal, "borderless feedback restores normal background")
    theme:SetPreset("Midnight"); theme:SetPreset("Paper"); flushTweens()
    check(option:FindFirstChildOfClass("UIStroke") == nil and dropdown._choices[2].Button.TextColor3 == theme:GetToken("Accent"), "theme changes preserve borderless options and selected highlight")
end
ui:CloseAllDropdownsExcept(nil); flushTweens()
local indicator=ui._indicator
ui._layout.Strip.AbsolutePosition=Vector2.new(10,0)
ui._tabByName.Combat.Button.AbsolutePosition=Vector2.new(10,0)
ui._tabByName.Combat.Button.AbsoluteSize=Vector2.new(80,22)
ui._tabByName.Visuals.Button.AbsolutePosition=Vector2.new(94,0)
ui._tabByName.Visuals.Button.AbsoluteSize=Vector2.new(100,22)
ui:SelectTab("Combat"); flushTweens(); ui:SelectTab("Visuals")
check(pendingTween(indicator,"Position")~=nil,"one shared tab indicator glides to the next tab")
flushTweens()
check(indicator.Position.X.Offset==92 and indicator.Size.X.Offset==84,"tab indicator matches selected label width and position")
ui._tabByName.Visuals.Button.AbsolutePosition=Vector2.new(44,0)
ui._layout.Strip.CanvasPosition=Vector2.new(50,0)
check(indicator.Position.X.Offset==42 and not pendingTween(indicator,"Position"),"tab scrolling realigns indicator immediately")
ui._scale.Scale=0.5
ui._tabByName.Visuals.Button.AbsoluteSize=Vector2.new(50,11)
ui._tabByName.Visuals.Button.AbsolutePosition=Vector2.new(52,0)
check(indicator.Position.X.Offset==92 and indicator.Size.X.Offset==84,"tab indicator accounts for menu scale")
ui._scale.Scale=1; ui:UpdateTabIndicator(false)
local tabConnections=connectionCount()
for _=1,15 do ui:SelectTab("Combat"); ui:SelectTab("Visuals"); flushTweens() end
check(connectionCount()==tabConnections,"rapid tab selection does not accumulate geometry subscriptions")
local actionThread,actionCalls
local actions=services.Require("src/UI/Components/Textbox.luau",services)
actionCalls=0
local action=actions:CreateButton(panel,"Test action",function()
    actionCalls+=1; actionThread=coroutine.running(); task.wait(); return true,"Done"
end)
action.Button.Activated:Fire(); flushTweens()
check(action._busy and action.Button.Text=="Working..." and action.Button:FindFirstChildOfClass("UIStroke").Thickness==1.5,"running actions show non-looping busy feedback")
action.Button.Activated:Fire()
check(actionCalls==1,"busy action rejects duplicate activation")
check(coroutine.resume(actionThread),"busy action completes")
flushTweens()
check(not action._busy and action.Button.Text=="Test action" and action.Button:FindFirstChildOfClass("UIStroke").Thickness==1,"action completion restores its label and emphasis")
ui:Notify("Fade test","Short-lived notification",1)
local toast=ui._toasts[#ui._toasts]
check(toast.Frame.BackgroundTransparency==1,"notification begins transparent")
for _, child in ipairs(toast.Frame:GetChildren()) do
    if child:IsA("TextLabel") then check(child.TextTransparency==1,"notification text starts transparent") end
end
flushTweens()
check(toast.Frame.BackgroundTransparency==0 and toast.Frame.Position.X.Offset==0,"notification entry fades and glides into place")
for _, child in ipairs(toast.Frame:GetChildren()) do
    if child:IsA("TextLabel") then check(child.TextTransparency==0,"notification text fades in") end
end
flushTasks()
check(pendingTween(toast.Frame,"BackgroundTransparency")~=nil,"notification exit fades out")
flushTweens()
check(toast.Scope:IsDisposed(),"notification fade finishes with cleanup")
for index=1,10 do ui:Notify("Bounded",tostring(index),1) end
check(#ui._toasts==4,"notification bursts keep the animation count bounded by four cards")
flushTasks(); flushTweens(); flushTasks(); flushTweens()
motion:Reset(); flushTweens()
local idleTweenCount,idleInstances=tweenCount,createdInstances
for _=1,120 do RunService.RenderStepped:Fire(1/60) end
check(next(tweens)==nil and tweenCount==idleTweenCount and createdInstances==idleInstances,"settled interface creates no idle tweens or instances")
check(RunService.RenderStepped:Count()==0,"new motion adds no persistent frame connection")
local doomed=dom:Create("Frame",{Parent=screen}); local destroyedCallback=false
motion:Tween(doomed,"test",{Rotation=10},0.12,function() destroyedCallback=true end)
dom:DestroyInstance(doomed); flushTweens()
check(not destroyedCallback and not pendingTween(doomed,"Rotation"),"destroy cancels pending animations and callbacks")
local disposableRoot=dom:Create("ScreenGui",{Parent=guiParent})
theme:RegisterRoot(disposableRoot)
local disposableChild=dom:Create("TextLabel",{Parent=disposableRoot})
theme:BindToken(disposableChild,"TextColor3","Text")
dom:DestroyInstance(disposableRoot)
check(theme._roots[disposableRoot]==nil and theme._bindings[disposableChild]==nil,"destroying UI immediately drops theme references, even while callers retain handles")
local baseline=connectionCount()
for _=1,40 do
    local temporary=dom:Create("TextButton",{Parent=screen})
    theme:BindToken(temporary,"BackgroundColor3","Elem")
    temporary.MouseEnter:Fire()
    dom:DestroyInstance(temporary)
end
check(connectionCount()==baseline,"repeated controls leave no feedback/tween connections")
-- Favorites, motion preferences, and shared help use the same real UI services.
do
    ui:ClearSearch(); flushTasks(); flushTweens()
    local function slotOf(handle) return handle.Row.Parent.Parent end
    local function named(parent, name)
        for _, child in ipairs(parent:GetChildren()) do if child.Name == name then return child end end
        error(`Missing {name}`)
    end
    local section = services.Require("src/UI/Components/Section.luau", services)
    local toggles = services.Require("src/UI/Components/Toggle.luau", services)
    local combatPanel = section:Create(ui._tabByName.Combat.LeftCol, "Favorite tests")
    local visualPanel = section:Create(ui._tabByName.Visuals.LeftCol, "Favorite tests")
    local a = toggles(combatPanel, "Shared label", false)
    local b = toggles(visualPanel, "Shared label", "Movement.FreecamEnabled")
    local aSlot, bSlot = slotOf(a), slotOf(b)
    local aRecord, bRecord = ui._controls[aSlot], ui._controls[bSlot]
    local aOrder = aSlot.LayoutOrder
    check(aSlot:GetChildren()[1].Size.X.Offset == -24 and bSlot:GetChildren()[1].Size.X.Offset == -44, "simple controls reclaim help-button space while advanced controls reserve it")
    local hasSimpleHelp = false
    for _, child in ipairs(aSlot:GetChildren()) do if child.Name == "Help" then hasSimpleHelp = true end end
    check(not hasSimpleHelp and named(aSlot, "Favorite") ~= nil, "simple controls retain favorites without a help button")
    local queuedBefore = next(waiting)
    aSlot.MouseEnter:Fire(); aSlot.MouseLeave:Fire()
    check(aSlot.MouseEnter:Count() == 0 and aSlot.MouseLeave:Count() == 0 and next(waiting) == queuedBefore, "simple controls have no tooltip listeners or scheduled hover work")
    check(ui._tabByName.Combat.Button.MouseEnter:Count() == 1, "tabs keep hover feedback without redundant tooltip listeners")
    for _, example in ipairs({
        { "Enabled", "ESP.Enabled", "Toggle" }, { "Flight speed", "Movement.FlySpeed", "Slider" },
        { "Theme preset", "Theme.ActivePreset", "Dropdown" }, { "Accent", nil, "Color" },
        { "Menu hotkey", "Settings.MenuKeybind", "Keybind" }, { "Save as", nil, "Textbox" },
        { "Next comparison page", nil, "Action" }, { "Show tooltips", "Settings.Tooltips", "Toggle" },
    }) do
        check(services.Tooltips:Describe(example[1], example[2], example[3]) == nil, "self-explanatory controls do not get generic help")
    end
    check(services.Tooltips:Describe("Prediction", "Aimbot.Prediction.Horizontal", "Slider") ~= nil, "prediction keeps meaningful technical help")
    check(services.Tooltips:Describe("Speed", "Movement.Speed", "Slider"):find("Zero leaves", 1, true), "zero-value override behavior keeps its explanation")
    check(services.Tooltips:Describe("Turn everything off", nil, "Action") ~= nil, "consequential reset action keeps help")
    check(aRecord.Id ~= bRecord.Id, "favorite identities include their own tab")
    local baseline = connectionCount()
    named(aSlot, "Favorite").Activated:Fire(); flushTasks(); flushTweens()
    check(aSlot.Parent == ui._tabByName.Combat.FavoritesBody, "star pins the original live control")
    check(bSlot.Parent == visualPanel and ui._tabByName.Visuals.FavoriteCount == 0, "favorites never populate another tab")
    check(a:Get() == false and named(aSlot, "Favorite").Text == "★", "pinning changes no feature state")
    check(connectionCount() == baseline, "pinning creates no duplicate control bindings")
    a:Set(true); check(a:Get() == true, "pinned control remains interactive")
    ui:SelectTab("Combat")
    check(ui._tabByName.Combat.Favorites.Visible and not ui._tabByName.Visuals.Page.Visible, "only selected tab page is visible")
    ui:Search("shared label")
    check(aSlot.Parent == ui._active.ResultsCol and not ui._active.Favorites.Visible, "search includes favorite once, hides favorite panel")
    ui:ClearSearch()
    check(aSlot.Parent == ui._tabByName.Combat.FavoritesBody, "clearing search returns pinned row to favorites")
    ui:Search("shared label"); named(aSlot, "Favorite").Activated:Fire(); flushTasks()
    check(aSlot.Parent == ui._active.ResultsCol, "unpinning during search preserves results")
    ui:ClearSearch()
    check(aSlot.Parent == combatPanel and aSlot.LayoutOrder == aOrder, "unpin restores section and original order")
    local remembered = { [aRecord.Id] = true, [bRecord.Id] = true }
    services.StateStore:Set("Settings.Favorites", remembered); flushTasks()
    check(aSlot.Parent == ui._tabByName.Combat.FavoritesBody and bSlot.Parent == ui._tabByName.Visuals.FavoritesBody, "restored favorite map populates each tab separately")
    ui:SelectTab("Visuals")
    check(not ui._tabByName.Combat.Page.Visible and ui._tabByName.Visuals.Favorites.Visible, "tab switch cannot show unrelated favorite panel")
    local oldId = aRecord.Id
    dom:DestroyInstance(combatPanel.Parent); flushTasks()
    check(a.Scope:IsDisposed() and aSlot.Parent == nil and ui._controls[aSlot] == nil, "destroying original section also removes pinned row and subscriptions")
    combatPanel = section:Create(ui._tabByName.Combat.LeftCol, "Favorite tests")
    a = toggles(combatPanel, "Shared label", false); aSlot = slotOf(a); flushTasks()
    check(ui._controls[aSlot].Id == oldId and aSlot.Parent == ui._tabByName.Combat.FavoritesBody, "remounted control recovers stable favorite identity")
    local pluginContainer = dom:Create("Frame", { Parent = ui._tabByName.Game.LeftCol })
    pluginContainer:SetAttribute("B0XazFavoriteContext", "Plugin A")
    local pluginPanel = section:Create(pluginContainer, "Options")
    local pluginControl = toggles(pluginPanel, "Enabled", false)
    local pluginSlot = slotOf(pluginControl)
    local pluginId = ui._controls[pluginSlot].Id
    named(pluginSlot, "Favorite").Activated:Fire(); flushTasks()
    ui:Search("enabled")
    dom:DestroyInstance(pluginPanel.Parent); flushTasks()
    check(pluginControl.Scope:IsDisposed() and ui._controls[pluginSlot] == nil, "plugin teardown cleans a searched favorite")
    ui:ClearSearch()
    pluginContainer:SetAttribute("B0XazFavoriteContext", "Plugin B")
    pluginPanel = section:Create(pluginContainer, "Options")
    pluginControl = toggles(pluginPanel, "Enabled", false); pluginSlot = slotOf(pluginControl); flushTasks()
    check(ui._controls[pluginSlot].Id ~= pluginId and pluginSlot.Parent == pluginPanel, "different plugin never inherits another adapter's favorite")
    -- Exercise the real plugin manager: deactivation disposes the plugin scope before clearing its mount.
    local originalRequire = services.Require
    local registration = { Name = "Fixture adapter", PluginModule = "fixture-plugin" }
    local mountedRow, stopped = nil, 0
    services.Require = function(path, container)
        if path == "src/Plugins/PluginRegistry.luau" then
            return { Resolve = function() return registration end, GetRegistrations = function() return { registration } end }
        elseif path == "fixture-plugin" then
            return function(pluginServices)
                local pluginSection = factory("src/UI/Components/Section.luau")(pluginServices)
                return { Name = registration.Name, Initialize = function() end, Destroy = function() stopped += 1 end,
                    BuildUI = function(_, tab)
                        local panel = pluginSection:Create(tab.LeftCol, "Adapter controls")
                        mountedRow = pluginSection:Control(panel, "Scoped control", 22)
                    end }
            end
        end
        return originalRequire(path, container)
    end
    local manager = factory("src/Plugins/PluginManager.luau")(services)
    manager:Initialize()
    check(manager:MountUI(ui._tabByName.Game), "actual plugin manager mounts controls with favorite context")
    local mountedSlot = mountedRow.Parent.Parent
    local mountedId = ui._controls[mountedSlot].Id
    named(mountedSlot, "Favorite").Activated:Fire(); flushTasks()
    check(mountedSlot.Parent == ui._tabByName.Game.FavoritesBody, "real plugin control pins normally")
    manager:SetEnabled(false); flushTasks()
    check(mountedSlot.Parent == nil and ui._controls[mountedSlot] == nil and stopped == 1, "deactivating plugin scope destroys pinned controls before mount cleanup")
    manager:SetEnabled(true); flushTasks()
    mountedSlot = mountedRow.Parent.Parent
    check(ui._controls[mountedSlot].Id == mountedId and mountedSlot.Parent == ui._tabByName.Game.FavoritesBody, "reenabling adapter restores only its own saved favorite")
    for _ = 1, 4 do manager:SetEnabled(false); manager:SetEnabled(true); flushTasks(); flushTweens() end
    local duplicates = 0
    for _, record in pairs(ui._controls) do if record.Id == mountedId then duplicates += 1 end end
    check(duplicates == 1 and stopped == 5, "repeated adapter remounts do not accumulate pinned rows")
    manager:Destroy()
    dom:DestroyInstance(manager._mount.LeftCol); dom:DestroyInstance(manager._mount.RightCol)
    services.Require = originalRequire

    services.StateStore:Set("Settings.Favorites", {}); flushTasks()
    check(not ui._tabByName.Combat.Favorites.Visible and not ui._tabByName.Visuals.Favorites.Visible, "clearing favorites hides empty panels")

    local tips = services.Tooltips
    services.StateStore:Set("Settings.Tooltips", true)
    ui:SelectTab("Visuals")
    bSlot.MouseEnter:Fire()
    check(not tips._card, "hover does not create tooltip before its delay")
    bSlot.MouseLeave:Fire(); flushTasks()
    check(not tips._card, "leaving before delay creates no tooltip")
    bSlot.MouseEnter:Fire(); flushTasks()
    check(tips._card and tips._card.Visible and tips._text.Text:find("Shared label", 1, true), "delayed hover shows contextual help")
    local card = tips._card
    bSlot.MouseLeave:Fire()
    check(not card.Visible, "leaving hover hides shared card")
    named(bSlot, "Help").Activated:Fire()
    check(card.Visible and tips._sticky, "question mark opens tap-friendly sticky help")
    bSlot.MouseLeave:Fire(); check(card.Visible, "tap help remains readable after pointer leaves")
    named(bSlot, "Help").Activated:Fire(); check(not card.Visible, "second help tap dismisses")
    named(bSlot, "Help").SelectionGained:Fire()
    check(card.Visible, "keyboard focus on help shows description")
    named(bSlot, "Help").SelectionLost:Fire(); check(not card.Visible, "keyboard blur hides help")
    named(bSlot, "Help").Activated:Fire(); ui:Search("shared")
    check(not card.Visible, "search dismisses help before moving its anchor")
    ui:ClearSearch(); named(bSlot, "Help").Activated:Fire(); ui:SelectTab("Combat")
    check(not card.Visible, "tab change dismisses help")
    ui:SelectTab("Visuals"); named(bSlot, "Help").Activated:Fire()
    services.StateStore:Set("Settings.Tooltips", false)
    check(not card.Visible, "tooltip preference immediately hides open help")
    named(bSlot, "Help").Activated:Fire(); check(not card.Visible, "disabled tooltips ignore explicit help")
    services.StateStore:Set("Settings.Tooltips", true)
    named(bSlot, "Help").Activated:Fire(); services.StateStore:Set("Settings.MenuVisible", false)
    check(not card.Visible, "menu hide dismisses help")
    services.StateStore:Set("Settings.MenuVisible", true)
    named(bSlot, "Help").Activated:Fire(); dom:DestroyInstance(visualPanel.Parent); flushTasks()
    check(not card.Visible and tips._anchor == nil, "destroyed anchor releases sticky tooltip")
    check(tips._card == card, "all help uses one reusable card")
    local description = tips:Describe("Animation speed", "Settings.MotionSpeed", "Slider", { Min = 0.5, Max = 2, Step = 0.1 })
    check(description:find("Range: 0.5 to 2", 1, true) and description:find("Default: 1", 1, true), "slider help includes useful range and default")

    services.StateStore:Set("Settings.MotionMode", "Full"); services.StateStore:Set("Settings.MotionSpeed", 1)
    local animated = dom:Create("Frame", { Parent = screen, Visible = true })
    motion:Tween(animated, "Rate", { Rotation = 12 }, 0.12)
    check(pendingTween(animated, "Rotation").Duration == 0.12 and motion:Distance(8) == 8, "Full 1x preserves original timing and travel")
    services.StateStore:Set("Settings.MotionSpeed", 2)
    check(animated.Rotation == 12 and not pendingTween(animated, "Rotation"), "speed changes settle active motion")
    motion:Tween(animated, "Rate", { Rotation = 24 }, 0.12)
    check(pendingTween(animated, "Rotation").Duration == 0.06, "2x motion halves duration")
    services.StateStore:Set("Settings.MotionMode", "Subtle")
    motion:Tween(animated, "Rate", { Rotation = 36 }, 0.12)
    check(pendingTween(animated, "Rotation").Duration == 0.048 and motion:Distance(8) == 4, "Subtle reduces duration and travel")
    local done = 0
    motion:Tween(animated, "Rate", { Rotation = 48 }, 0.12, function() done += 1 end)
    services.StateStore:Set("Settings.MotionMode", "Off")
    check(animated.Rotation == 48 and done == 1 and next(tweens) == nil, "Off settles all tweens and runs current completion exactly once")
    local before = tweenCount
    motion:Tween(animated, "Rate", { Rotation = 60 }, 0.12, function() done += 1 end)
    check(animated.Rotation == 60 and done == 2 and before == tweenCount and motion:Distance(8) == 0, "Off applies future changes without allocating tweens")
    ui:SelectTab("Combat"); ui:SelectTab("Visuals")
    check(ui._active.Page.Position == ui._active.RestPosition and next(tweens) == nil, "Off snaps tabs directly into place")
    services.StateStore:Set("Settings.MotionMode", "Full"); services.StateStore:Set("Settings.MotionSpeed", 1)
    motion:Reveal(animated, true); flushTweens(); motion:Reveal(animated, false)
    services.StateStore:Set("Settings.MotionMode", "Off")
    check(not animated.Visible and not pendingTween(animated, "Position"), "Off completes an in-flight window close lifecycle")
    dropdownButton.Activated:Fire(); check(dropdown._open, "dropdown still opens with motion Off")
    ui:CloseAllDropdownsExcept(nil)
    check(not dropdown._open and not dropdown.Row:FindFirstChildOfClass("ScrollingFrame").Visible, "Off still finishes dropdown close cleanup")
    services.StateStore:Set("Settings.MotionMode", "Full")
    ui:Notify("Closing", "Motion change", 1); flushTweens(); local toast = ui._toasts[#ui._toasts]
    flushTasks()
    services.StateStore:Set("Settings.MotionMode", "Off")
    check(toast.Scope:IsDisposed(), "Off completes toast removal")
    services.StateStore:Set("Settings.MotionMode", "Full"); services.StateStore:Set("Settings.MotionSpeed", 1)
    dom:DestroyInstance(animated); dom:DestroyInstance(combatPanel.Parent); dom:DestroyInstance(pluginContainer)
    flushTasks(); flushTweens(); flushTasks(); flushTweens()
    local idleCount, instanceCount = tweenCount, createdInstances
    for _ = 1, 120 do RunService.RenderStepped:Fire(1 / 60) end
    check(next(tweens) == nil and tweenCount == idleCount and createdInstances == instanceCount, "new preferences, favorites and help add no idle rendering work")
end

-- Mount the actual Settings tab with actual controls, not just the callback-recording fixture.
do
    local reads, comparisons = 0, 0
    local oldConfig = services.ConfigService
    services.ConfigService = {
        ListProfiles = function() reads += 1; return { "Default", "Legit", "Rage", "Current session" } end,
        GetGameProfileStatus = function() return "No game profile" end,
        CompareProfiles = function(_, a, b)
            comparisons += 1
            check(a == nil and b == "Default", "real selectors pass current sentinel and selected profile to comparison")
            return { Left = "Current session", Right = "Default", Changes = { { Path = "Aimbot.Enabled", Before = false, After = true } } }
        end,
        FormatComparisonValue = function(_, value) return tostring(value) end,
    }
    services.HotkeyService = { GetBindTargets = function() return {} end }
    services.Environment.Capabilities = {}
    services.CompatibilityService = factory("src/Services/CompatibilityService.luau")(services)
    local tab = ui._tabByName.Settings
    check(factory("src/UI/Tabs/SettingsTab.luau")(services, tab).Name == "Settings", "real Settings tab and components construct together")
    check(reads == 1, "Settings shares one profile listing across its three selectors")
    flushTasks(); flushTweens(); ui:SelectTab("Settings"); flushTweens()
    local compareRow, motionRow, summary, compatibility
    for _, record in pairs(ui._controls) do
        if record.TabName ~= "Settings" then continue end
        if record.Label == "Compare profiles" then compareRow = record.Row end
        if record.Label == "Animation style" then motionRow = record.Row end
        if record.Label == "Differences will appear here." then summary = record.Row:FindFirstChildOfClass("TextLabel") end
        if record.SectionName == "Compatibility checker" and not record.Pin then compatibility = record.Row:FindFirstChildOfClass("TextLabel") end
    end
    check(compareRow and motionRow and summary and compatibility, "all new Settings sections register with the existing searchable layout")
    for _, child in ipairs(compareRow:GetDescendants()) do
        if child:IsA("TextButton") and child.Text == "Compare profiles" then child.Activated:Fire(); break end
    end
    check(comparisons == 1 and summary.Text:find("Aimbot.Enabled", 1, true), "actual compare button renders read-only before/after results")
    check(compatibility.Text:find("0/12", 1, true) and compatibility.Text:find("not verified", 1, true), "actual compatibility report renders detection and fallback guidance")
    check(motionRow:GetAttribute("StatePath") == "Settings.MotionMode", "actual animation preference is bound to persistent state")
    for _, child in ipairs(motionRow:GetChildren()) do if child.Name == "Help" then child.Activated:Fire() end end
    check(services.Tooltips._text.Text:find("Off applies changes immediately", 1, true), "real motion control help resolves path-specific explanation")
    ui:SelectTab("Visuals"); flushTasks(); flushTweens()
    services.ConfigService = oldConfig
end

ui._searchBox.Text="a"; ui._searchBox.Text="ab"; ui._searchBox.Text="abc"
flushTasks()
check(ui._query=="abc","search debounce applies only latest query")
ui._searchBox.Text="pending"
master:Dispose(); flushTasks(); flushTweens()
check(next(tweens)==nil,"unload cancels every tween")
check(connectionCount()==0,"unload disconnects all owned signals")
print(`PASS: {checks} UI motion/lifecycle assertions`)
