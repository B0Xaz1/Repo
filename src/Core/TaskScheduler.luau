local RunService = game:GetService("RunService")

local CONFIG = table.freeze({
    CAMERA_RENDER_KEY = "B0XazUniversal.Camera",
    MAX_STRIKES = 5,
})

export type Job = { Name: string, Priority: number, Enabled: boolean, Strikes: number, CircuitOpen: boolean, Disconnect: (Job) -> () }

return function(disposer: any): any
    local scope = disposer:CreateChild("TaskScheduler")
    local TaskScheduler: any = { _pipelines = { PreSim = {}, Heartbeat = {}, Render = {}, Camera = {} } }

    local function run(pipeline: string, dt: number)
        if scope:IsDisposed() then return end
        for _, job in ipairs(TaskScheduler._pipelines[pipeline]) do
            -- Re-enabling a job clears its strike history, so the breaker only counts consecutive failures
            if job.CircuitOpen and job.Enabled then job.CircuitOpen, job.Strikes = false, 0 end
            if job.Enabled and job.Connected then
                local ran, jobError = pcall(job.Callback, dt)
                if ran then
                    job.Strikes = 0
                else
                    job.Strikes += 1
                    if job.Strikes == CONFIG.MAX_STRIKES then
                        job.Enabled = false
                        job.CircuitOpen = true
                        warn(`[B0Xaz] Task '{job.Name}' disabled after {CONFIG.MAX_STRIKES} consecutive errors: {tostring(jobError)}`)
                    end
                end
            end
        end
    end

    local function register(pipeline: string, name: string, priority: number, callback: (number) -> ()): any
        local jobs = TaskScheduler._pipelines[pipeline]
        for index = #jobs, 1, -1 do
            if jobs[index].Name == name then jobs[index]:Disconnect(); table.remove(jobs, index) end
        end
        local job: any = { Name = name, Priority = priority, Callback = callback, Strikes = 0, Enabled = true, Connected = true, CircuitOpen = false }
        function job:Disconnect()
            if self.Connected ~= true then return end
            self.Connected, self.Enabled = false, false
            local current = TaskScheduler._pipelines[pipeline]
            local at = table.find(current, self)
            if at then
                local remaining = table.clone(current)
                table.remove(remaining, at)
                TaskScheduler._pipelines[pipeline] = remaining
            end
            scope:Forget(self)
        end
        local insertAt = #jobs + 1
        for index, existing in ipairs(jobs) do
            if priority < existing.Priority or (priority == existing.Priority and name < existing.Name) then
                insertAt = index
                break
            end
        end
        table.insert(jobs, insertAt, job)
        scope:Add(job)
        return job
    end

    function TaskScheduler:RegisterPreSim(name: string, priority: number, callback: (number) -> ()): Job
        return register("PreSim", name, priority, callback)
    end

    function TaskScheduler:RegisterHeartbeat(name: string, priority: number, callback: (number) -> ()): Job
        return register("Heartbeat", name, priority, callback)
    end

    function TaskScheduler:RegisterRender(name: string, priority: number, callback: (number) -> ()): Job
        return register("Render", name, priority, callback)
    end

    function TaskScheduler:RegisterCamera(name: string, priority: number, callback: (number) -> ()): Job
        return register("Camera", name, priority, callback)
    end

    function TaskScheduler:Destroy() scope:Dispose() end

    scope:Add(RunService.Stepped:Connect(function(_time: number, dt: number) run("PreSim", dt) end))
    scope:Add(RunService.Heartbeat:Connect(function(dt: number) run("Heartbeat", dt) end))
    scope:Add(RunService.RenderStepped:Connect(function(dt: number) run("Render", dt) end))
    pcall(function() RunService:UnbindFromRenderStep(CONFIG.CAMERA_RENDER_KEY) end)
    RunService:BindToRenderStep(CONFIG.CAMERA_RENDER_KEY, Enum.RenderPriority.Camera.Value + 1, function(dt: number) run("Camera", dt) end)
    scope:Add(function() RunService:UnbindFromRenderStep(CONFIG.CAMERA_RENDER_KEY) end)

    return TaskScheduler
end
