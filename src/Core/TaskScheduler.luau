--!nonstrict
export type Job = { Name: string, Priority: number, Enabled: boolean, Strikes: number, Disconnect: (Job) -> () }

return function(disposer: any): any
    local runService = game:GetService("RunService")
    local scope = disposer:CreateChild("TaskScheduler")
    local cameraKey = "B0XazUniversal.Camera"
    local TaskScheduler: any = { _pipelines = { PreSim = {}, Heartbeat = {}, Render = {}, Camera = {} } }

    local function run(pipeline: string, dt: number)
        if scope:IsDisposed() then return end
        -- Registration replaces the array, so a job can disconnect/register without disturbing this iteration.
        for _, job in ipairs(TaskScheduler._pipelines[pipeline]) do
            if job.Enabled and job.Connected then
                local ok, err = pcall(job.Callback, dt)
                if ok then job.Strikes = 0 else
                    job.Strikes += 1
                    warn(string.format("[B0Xaz][Job:%s/%s] strike %d/5: %s", pipeline, job.Name, job.Strikes, tostring(err)))
                    if job.Strikes == 5 then
                        job.Enabled = false
                        warn("[B0Xaz][CIRCUIT OPEN] Disabled '" .. job.Name .. "' after five consecutive failures")
                    end
                end
            end
        end
    end

    local function register(pipeline: string, name: string, priority: number, callback: (number) -> ()): any
        local jobs = table.clone(TaskScheduler._pipelines[pipeline])
        for index = #jobs, 1, -1 do
            if jobs[index].Name == name then jobs[index]:Disconnect(); table.remove(jobs, index) end
        end
        local job: any = { Name = name, Priority = priority, Callback = callback, Strikes = 0, Enabled = true, Connected = true }
        function job:Disconnect() self.Connected = false; self.Enabled = false end
        table.insert(jobs, job)
        table.sort(jobs, function(a: any, b: any)
            if a.Priority == b.Priority then return a.Name < b.Name end
            return a.Priority < b.Priority
        end)
        TaskScheduler._pipelines[pipeline] = jobs
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

    -- These four dispatch boundaries deliberately remain synchronous to retain their engine phase.
    -- All jobs are protected here; ordinary feature event handlers use Disposer:Connect (spawned).
    scope:Add(runService.Stepped:Connect(function(_time: number, dt: number) run("PreSim", dt) end))
    scope:Add(runService.Heartbeat:Connect(function(dt: number) run("Heartbeat", dt) end))
    scope:Add(runService.RenderStepped:Connect(function(dt: number) run("Render", dt) end))
    pcall(function() runService:UnbindFromRenderStep(cameraKey) end)
    runService:BindToRenderStep(cameraKey, Enum.RenderPriority.Camera.Value + 1, function(dt: number) run("Camera", dt) end)
    scope:Add(function() runService:UnbindFromRenderStep(cameraKey) end)
    return TaskScheduler
end
