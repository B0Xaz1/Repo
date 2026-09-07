--!nonstrict
-- Deployment configuration, not secrets. An empty endpoint fails closed instead of silently granting a tier.
local LICENSE_ENDPOINT: string = ""
local PUBLIC_KEY: string = ""
local KEY_SALT: string = "B0XazUniversal/key/v1"
local TIER_NAMES: { [string]: number } = { entry = 1, normal = 2, full = 3 }
local TIER_LABELS: { string } = { "Entry", "Normal", "Full" }

return function(services: any): any
    local environment = services:Get("Environment")
    local state = services:Get("StateStore")
    local scope = services:Get("Disposer"):CreateChild("KeyService")
    local http = game:GetService("HttpService")
    local KeyService = { _key = nil, _tier = 0, _generation = 0, EndpointConfigured = LICENSE_ENDPOINT ~= "" }

    local function persist(key: string)
        local json = http:JSONEncode({ Key = key, Version = 1 })
        -- XOR + base64 is obfuscation against casual inspection, NOT encryption or a trust boundary.
        local encoded = environment:Base64Encode(environment:XorCipher(json, KEY_SALT))
        local ok, message = environment:WriteFile("_key.json", encoded)
        if not ok then services:Get("EventBus"):Publish("Notify", "License", "Verified for this session; " .. tostring(message)) end
    end

    function KeyService:AuthenticateKey(raw: string): (boolean, number, string, string)
        self._generation += 1
        local generation = self._generation
        local key = tostring(raw):gsub("^%s+", ""):gsub("%s+$", "")
        if #key == 0 then return false, 0, "Enter a license key.", "rejected" end
        if #key > 4096 then return false, 0, "License key is too long.", "rejected" end
        if LICENSE_ENDPOINT == "" then return false, 0, "License endpoint is not configured. Set LICENSE_ENDPOINT and PUBLIC_KEY in KeyService.luau.", "unconfigured" end
        if not LICENSE_ENDPOINT:match("^https://") then return false, 0, "The license endpoint must use HTTPS.", "unconfigured" end
        local headers = { ["Content-Type"] = "application/json", Accept = "application/json" }
        if PUBLIC_KEY ~= "" then headers["X-B0Xaz-Public-Key"] = PUBLIC_KEY end
        local lastMessage = "The license server could not be reached. Your key has not been rejected."
        for attempt = 1, 3 do
            if scope:IsDisposed() or generation ~= self._generation then return false, 0, "Verification cancelled.", "cancelled" end
            local response, requestError = environment:Request({ Url = LICENSE_ENDPOINT, Method = "POST", Headers = headers,
                Body = http:JSONEncode({ key = key, hwid = environment:GetDeviceId() }) })
            if scope:IsDisposed() or generation ~= self._generation then return false, 0, "Verification cancelled.", "cancelled" end
            local status = if response then tonumber(response.StatusCode or response.Status) or 0 else 0
            local data = nil
            if response and type(response.Body) == "string" then
                local decoded, result = pcall(http.JSONDecode, http, response.Body)
                if decoded and type(result) == "table" then data = result end
            end
            local serverMessage = if data and type(data.message) == "string" then data.message else nil
            local transient = response == nil or status == 0 or status == 408 or status == 429 or status >= 500
            if transient then
                lastMessage = serverMessage or ("License service temporarily unavailable (" .. (if status > 0 then tostring(status) else "network") .. "). Your key has not been rejected.")
                if requestError then services:Get("EventBus"):Publish("LicenseNetworkFailure", attempt) end
                if attempt < 3 then task.wait(attempt * 0.8) end
            else
                local tier = if data and type(data.tier) == "string" then TIER_NAMES[string.lower(data.tier)] else nil
                if status >= 200 and status < 300 and data and data.success == true and tier then
                    self._key, self._tier = key, tier
                    persist(key)
                    return true, tier, serverMessage or "License verified.", "verified"
                end
                return false, 0, serverMessage or ("License rejected by the server (HTTP " .. status .. ")."), "rejected"
            end
        end
        return false, 0, lastMessage, "transient"
    end

    function KeyService:VerifySavedKey(): (boolean, number, string?, string?)
        if not self.EndpointConfigured then
            return false, 0, "License endpoint is not configured. The suite will not grant access until a real backend is configured.", "unconfigured"
        end
        local raw = environment:ReadFile("_key.json")
        if not raw or raw == "" then return false, 0, nil, "missing" end
        local ok, data = pcall(function()
            -- Plain JSON is tolerated for migration, but all subsequent successful writes use the new format.
            if raw:match("^%s*{") then return http:JSONDecode(raw) end
            return http:JSONDecode(environment:XorCipher(environment:Base64Decode(raw), KEY_SALT))
        end)
        if not ok or type(data) ~= "table" or type(data.Key or data.key) ~= "string" then
            return false, 0, "Saved license data is unreadable. Please enter your key again.", "corrupt"
        end
        return self:AuthenticateKey(data.Key or data.key)
    end
    function KeyService:ClearKey(): (boolean, string?)
        self._generation += 1
        self._key, self._tier = nil, 0
        state:SetTier(0)
        local ok, message = environment:DeleteFile("_key.json")
        if not ok then ok, message = environment:WriteFile("_key.json", "") end
        return ok, message
    end
    function KeyService:GetTierName(): string return TIER_LABELS[state:GetTier()] or "No Access" end
    function KeyService:GetMaskedKey(): string
        return if self._key then string.rep("•", 8) .. tostring(self._key):sub(-4) else "No saved key"
    end
    function KeyService:Initialize() end
    function KeyService:Destroy() self._generation += 1; self._key = nil; scope:Dispose() end
    return KeyService
end
