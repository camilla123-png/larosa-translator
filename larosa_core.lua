-- ============================================================================
-- LA ROSA TRANSLATOR - CORE MODULE (SERVER / GIST CORE WITH HWID)
-- ============================================================================
local core = {}

-- Kunci Keamanan Handshake
core.HANDSHAKE_TOKEN = "LAROSA_PROTECTED_CORE_SECURE_KEY_8899"

--------------------------------------------------------------------------------
-- DATABASE LISENSI & HWID (30 SLOT LICENSE KEY)
--------------------------------------------------------------------------------
-- FORMAT: ["KODE_LISENSI"] = "KODE_HWID_HP"
core.licenses = {
    ["LAROSA-CAMILLA-OWNER"] = "LR-83B9-78A3-99FA", -- Tempel HWID HP kamu di dalam tanda petik
    ["LAROSA-KEY-01"]        = "",
    ["LAROSA-KEY-02"]        = "",
    ["LAROSA-KEY-03"]        = "",
    ["LAROSA-KEY-04"]        = "",
    ["LAROSA-KEY-05"]        = "",
    ["LAROSA-KEY-06"]        = "",
    ["LAROSA-KEY-07"]        = "",
    ["LAROSA-KEY-08"]        = "",
    ["LAROSA-KEY-09"]        = "",
    ["LAROSA-KEY-10"]        = "",
    ["LAROSA-KEY-11"]        = "",
    ["LAROSA-KEY-12"]        = "",
    ["LAROSA-KEY-13"]        = "",
    ["LAROSA-KEY-14"]        = "",
    ["LAROSA-KEY-15"]        = "",
    ["LAROSA-KEY-16"]        = "",
    ["LAROSA-KEY-17"]        = "",
    ["LAROSA-KEY-18"]        = "",
    ["LAROSA-KEY-19"]        = "",
    ["LAROSA-KEY-20"]        = "",
    ["LAROSA-KEY-21"]        = "",
    ["LAROSA-KEY-22"]        = "",
    ["LAROSA-KEY-23"]        = "",
    ["LAROSA-KEY-24"]        = "",
    ["LAROSA-KEY-25"]        = "",
    ["LAROSA-KEY-26"]        = "",
    ["LAROSA-KEY-27"]        = "",
    ["LAROSA-KEY-28"]        = "",
    ["LAROSA-KEY-29"]        = "",
    ["LAROSA-KEY-30"]        = "",
}

local function normalizeStr(str)
    if not str then return "" end
    return tostring(str):gsub("^%s*(.-)%s*$", "%1"):lower()
end

function core.checkLicense(licenseKey, userHWID)
    local cleanKey = normalizeStr(licenseKey)
    local cleanHWID = normalizeStr(userHWID)

    if cleanKey == "" then
        return false, "MISSING_KEY", "Kode lisensi belum diisi di /cset!"
    end

    local registeredHWID = nil
    for keyInDb, hwidInDb in pairs(core.licenses) do
        if normalizeStr(keyInDb) == cleanKey then
            registeredHWID = hwidInDb
            break
        end
    end

    if registeredHWID == nil then
        return false, "INVALID_KEY", "Kode lisensi (" .. tostring(licenseKey) .. ") tidak terdaftar!"
    end

    local cleanRegHWID = normalizeStr(registeredHWID)

    if cleanRegHWID == "" then
        return false, "NEEDS_BINDING", "Lisensi valid! HWID belum di-bind di server."
    end

    if cleanRegHWID == cleanHWID then
        return true, "VALID", "Lisensi & Device terverifikasi!"
    else
        return false, "HWID_MISMATCH", "Lisensi ini terikat di HP lain! HWID tidak cocok."
    end
end

--------------------------------------------------------------------------------
-- CORE DEPENDENCIES & RULES
--------------------------------------------------------------------------------
local g = require("ssl.https")
g.TIMEOUT = 50
local Z7cUSR = require("ltn12")
local Sw = require("cjson")

local geminiModels = {"gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-flash-latest"}
local groqModels   = {"llama-3.3-70b-versatile", "openai/gpt-oss-20b", "llama3-8b-8192"}

local CORE_RULES = [[
You are an RP translator.

Rules:
- keep meaning exactly the same
- output ONLY the translation
- no explanation
- no extra sentences
- natural and realistic RP English
- do not repeat or paraphrase
- keep it short and realistic

IMPORTANT:
The input may be normal dialogue or a special RP command such as /me or /do.
Follow the special command rules when provided.
]]

local PROMPT = {}
PROMPT.formal          = CORE_RULES .. "\nTranslate into clean formal English.\nNo slang."
PROMPT.casual          = CORE_RULES .. "\nTranslate into natural casual English.\nLight slang allowed (bro, yeah, gonna, kinda)."
PROMPT.los_angeles     = CORE_RULES .. "\nTranslate using West Coast LA street English.\nUse slang naturally (homie, cuh, finna, trippin').\nDo not force slang."
PROMPT.latino          = CORE_RULES .. "\nTranslate using Chicano street English.\nUse slang naturally (ese, vato, carnal, foo)."
PROMPT.bay_area        = CORE_RULES .. "\nTranslate using Bay Area street English.\nUse slang naturally (hella, bruh, mobbin')."
PROMPT.chicago         = CORE_RULES .. "\nTranslate using Chicago street English.\nUse slang naturally (folks, gang, finna, shorty)."
PROMPT.new_york        = CORE_RULES .. "\nTranslate using New York street English.\nUse slang naturally (deadass, son, mad, buggin')."
PROMPT.atlanta         = CORE_RULES .. "\nTranslate using Atlanta street English.\nUse slang naturally (shawty, twin, finna, fr)."
PROMPT.houston         = CORE_RULES .. "\nTranslate using Houston street English.\nUse slang naturally (fam, mane, trill, finna)."
PROMPT.miami           = CORE_RULES .. "\nTranslate using Miami street English.\nUse slang naturally (dawg, bro, fam, jit)."
PROMPT.british_urban   = CORE_RULES .. "\nTranslate using London Urban English.\nUse ONLY UK slang (bruv, fam, mandem, innit, wagwan).\nNo American slang."
PROMPT.asian_american  = CORE_RULES .. "\nTranslate using Asian-American street English.\nUse slang naturally (bro, lowkey, fr, no cap, bet)."

local function getCommandRule(commandType)
    if commandType == "me" then
        return [[
SPECIAL RULE FOR /ME:
This is a GTA SA-MP roleplay CHARACTER ACTION.
The character performing the action is the player character.
The character is IMPLIED and must NEVER be written explicitly.
Translate the Indonesian action into natural English RP action text.
STRICT FORMAT:
- Write ONLY the action.
- Use THIRD-PERSON VERB GRAMMAR.
- Start directly with the action verb whenever possible.
- Use third-person singular verbs: opens, takes, grabs, walks, looks, pulls, removes, enters, exits, etc.
- NEVER write "he", "she", "they", or any character name as the subject.
]]
    elseif commandType == "do" then
        return [[
SPECIAL RULE FOR /DO:
This is a GTA SA-MP roleplay CONDITION, DESCRIPTION, or RP QUESTION.
The subject is IMPLIED. Write the result as an objective third-person RP description.
STRICT RULES:
- NEVER use first person or second person.
- Keep the description objective and neutral.
- Return ONLY the translated RP text.
]]
    elseif commandType == "low" then
        return [[
SPECIAL RULE FOR /L:
This is LOW CHAT / quiet speech. Translate it as natural spoken dialogue.
]]
    elseif commandType == "shout" then
        return [[
SPECIAL RULE FOR /S:
This is SHOUTING / LOUD SPEECH. Translate it as natural spoken dialogue preserving the urgent/loud tone.
]]
    end
    return ""
end

function core.requestTranslate(text, styleKey, commandType, provider, apiKey, gModelIdx, qModelIdx, disabled)
    if disabled then return text end
    if apiKey == "" or apiKey == nil then
        sampAddChatMessage("{FF0000}[Translator] API Key kosong! Set di /cset", -1)
        return nil
    end

    local commandRule = getCommandRule(commandType)
    local basePrompt = PROMPT[styleKey] or PROMPT.casual
    local finalPrompt = commandRule .. "\n" .. basePrompt .. "\n\nTEXT:\n" .. text

    local url, body = "", ""
    local headers = {}

    if provider == 0 then
        local modelName = geminiModels[gModelIdx + 1] or "gemini-2.0-flash"
        url = "https://generativelanguage.googleapis.com/v1beta/models/" .. modelName .. ":generateContent?key=" .. apiKey
        headers = { ["Content-Type"] = "application/json" }
        body = Sw.encode({ contents = { { parts = { { text = finalPrompt } } } } })
    else
        local modelName = groqModels[qModelIdx + 1] or "llama-3.3-70b-versatile"
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = {
            ["Authorization"] = "Bearer " .. apiKey,
            ["Content-Type"] = "application/json"
        }
        body = Sw.encode({ model = modelName, temperature = 0.7, messages = { { role = "user", content = finalPrompt } } })
    end

    headers["Content-Length"] = tostring(#body)

    local response = {}
    local code, status = g.request{
        url = url, method = "POST", headers = headers,
        source = Z7cUSR.source.string(body), sink = Z7cUSR.sink.table(response)
    }

    if status ~= 200 then
        local errBody = table.concat(response)
        sampAddChatMessage("{FF0000}[HTTPS Error] " .. tostring(code) .. " | " .. tostring(status), -1)
        sampAddChatMessage("{FF8800}[API Error] " .. errBody, -1)
        return nil
    end

    local decoded = Sw.decode(table.concat(response))
    if decoded then
        local translated = nil
        if provider == 0 then
            if decoded.candidates and decoded.candidates[1] and decoded.candidates[1].content and decoded.candidates[1].content.parts and decoded.candidates[1].content.parts[1] then
                translated = decoded.candidates[1].content.parts[1].text
            end
        else
            if decoded.choices and decoded.choices[1] and decoded.choices[1].message then
                translated = decoded.choices[1].message.content
            end
        end

        if translated then
            return translated:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    return nil
end

return core
