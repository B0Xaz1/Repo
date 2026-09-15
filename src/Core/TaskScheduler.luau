--!strict
local RunService = game:GetService("RunService")

local CONFIG = table.freeze({
    CAMERA_RENDER_KEY = "B0XazUniversal.Camera",
    MAX_STRIKES = 5,
})

export type Job = { Name: string, Priority: number, Enabled: boolean, Strikes: number, CircuitOpen: boolean, Disconnect: (Job) -> () }

return function(disposer: any): any
    local scope = disposer:CreateChild("TaskScheduler")
    local TaskScheduler: any = { _pipelines = { PreSim = {}, Heartbeat = {}, Render = {}, Camera = {} } }
    -- Job arrays stay sorted by (Priority, Name) at all times. Registering or
    -- disconnecting used to clone the whole array and re-sort it, on every call,
    -- including while a pipeline was mid-dispatch. Instead an in-flight dispatch
    -- queues its mutations and replays them once the pass ends: the running loop
    -- never sees a half-applied array, and the common path allocates nothing.
    local pending: any = { PreSim = {}, Heartbeat = {}, Render = {}, Camera = {} }
    local dispatching: any = { PreSim = 0, Heartbeat = 0, Render = 0, Camera = 0 }

    local function comesBefore(a: any, b: any): boolean
        if a.Priority ~= b.Priority then return a.Priority < b.Priority end
        return a.Name < b.Name
    end

    -- Binary search keeps a registration at O(log n) comparisons plus one shift,
    -- instead of a full O(n log n) sort of the pipeline.
    local function insertSorted(jobs: any, job: any)
        local low, high = 1, #jobs
        while low <= high do
            local middle = (low + high) // 2
            if comesBefore(jobs[middle], job) then low = middle + 1 else high = middle - 1 end
        end
        table.insert(jobs, low, job)
    end

    local function removeJob(jobs: any, job: any)
        local at = table.find(jobs, job)
        if at then table.remove(jobs, at) end
    end

    local function enqueue(pipeline: string, job: any, add: boolean)
        table.insert(pending[pipeline], { Add = add, Job = job })
    end

    local function flush(pipeline: string)
        local queue = pending[pipeline]
        if #queue == 0 then return end
        local jobs = TaskScheduler._pipelines[pipeline]
        for index = 1, #queue do
            local change = queue[index]
            queue[index] = nil
            if change.Add then
                -- A job disconnected before its queued add landed is dropped, not inserted.
                if change.Job.Connected then insertSorted(jobs, change.Job) end
            else
                removeJob(jobs, change.Job)
            end
        end
    end

    local function run(pipeline: string, dt: number)
        if scope:IsDisposed() then return end
        -- Captured up front: mutations requested by jobs below are queued, so this
        -- array cannot be swapped or re-ordered while it is being iterated.
        local jobs = TaskScheduler._pipelines[pipeline]
        dispatching[pipeline] += 1
        for _, job in ipairs(jobs) do
            -- The breaker only clears Enabled; an observer re-enabling it requests a retry.
            if job.CircuitOpen and job.Enabled then job.CircuitOpen, job.Strikes = false, 0 end
            if job.Enabled and job.Connected then
                local ran = pcall(job.Callback, dt)
                if ran then
                    job.Strikes = 0
                else
                    job.Strikes += 1
                    if job.Strikes == CONFIG.MAX_STRIKES then
                        job.Enabled = false
                        job.CircuitOpen = true
                    end
                end
            end
        end
        dispatching[pipeline] -= 1
        flush(pipeline)
    end

    local function register(pipeline: string, name: string, priority: number, callback: (number) -> ()): any
        local jobs = TaskScheduler._pipelines[pipeline]
        -- Retire any earlier registration with the same name, both in the live array
        -- (walked backwards so in-place removal cannot skip an entry) and in the
        -- queue, where it has not been applied yet.
        for index = #jobs, 1, -1 do
            if jobs[index].Name == name then jobs[index]:Disconnect() end
        end
        local queue = pending[pipeline]
        for _, change in ipairs(queue) do
            if change.Add and change.Job.Name == name then change.Job:Disconnect() end
        end
        local job: any = { Name = name, Priority = priority, Callback = callback, Strikes = 0, Enabled = true, Connected = true, CircuitOpen = false }
        function job:Disconnect()
            if self.Connected ~= true then return end
            self.Connected, self.Enabled = false, false
            if dispatching[pipeline] > 0 then
                enqueue(pipeline, self, false)
            else
                removeJob(TaskScheduler._pipelines[pipeline], self)
            end
            -- Forget stops dead entries from accumulating in the scope across re-registers.
            scope:Forget(self)
        end
        if dispatching[pipeline] > 0 then
            -- Queued jobs start dispatching on the next pass, exactly as a clone-swap did.
            enqueue(pipeline, job, true)
        else
            insertSorted(jobs, job)
        end
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

    -- Dispatch boundaries stay synchronous to preserve their engine phase.
    scope:Add(RunService.Stepped:Connect(function(_time: number, dt: number) run("PreSim", dt) end))
    scope:Add(RunService.Heartbeat:Connect(function(dt: number) run("Heartbeat", dt) end))
    scope:Add(RunService.RenderStepped:Connect(function(dt: number) run("Render", dt) end))
    pcall(function() RunService:UnbindFromRenderStep(CONFIG.CAMERA_RENDER_KEY) end)
    RunService:BindToRenderStep(CONFIG.CAMERA_RENDER_KEY, Enum.RenderPriority.Camera.Value + 1, function(dt: number) run("Camera", dt) end)
    scope:Add(function() RunService:UnbindFromRenderStep(CONFIG.CAMERA_RENDER_KEY) end)

    return TaskScheduler
end
