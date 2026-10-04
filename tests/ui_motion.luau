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
        local value = { Name = name, _type = "EnumItem" }
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
ui:Search("choice"); check(dropdown.Row.Parent==secondTab.ResultsCol,"search reparents matching controls")
ui:ClearSearch(); check(dropdown.Row.Parent==panel,"clearing search restores original parent")
rawset(dropdown.Row,"_failLayout",true)
ui:Search("choice")
check(dropdown.Row.Parent==panel and ui._query=="" and not ui._searchActive,"failed search rolls back controls already moved")
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
ui._searchBox.Text="a"; ui._searchBox.Text="ab"; ui._searchBox.Text="abc"
flushTasks()
check(ui._query=="abc","search debounce applies only latest query")
ui._searchBox.Text="pending"
master:Dispose(); flushTasks(); flushTweens()
check(next(tweens)==nil,"unload cancels every tween")
check(connectionCount()==0,"unload disconnects all owned signals")
print(`PASS: {checks} UI motion/lifecycle assertions`)
