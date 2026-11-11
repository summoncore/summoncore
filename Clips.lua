-- Clips: voice clips dropped into Media\clips\ and picked at random by category.
-- Files are named <category>_<NN>_<who>.ogg (for example wag_01_aaron, zenit_refuse_03_sam,
-- narrator_weekopen_01_lewis). AddOns cannot list a folder, so tools\build_clip_manifest.ps1 scans it and
-- writes ClipList.lua; run it after adding or removing clips, then /reload.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Clips = {}
ST.Clips = Clips

local DIR = "Interface\\AddOns\\summoncore\\Media\\clips\\"
local byCategory, isFile, last = {}, {}, {}

-- "zenit_refuse_03_sam" -> "zenit_refuse", 3, "sam"; nil if the name does not follow the convention.
function Clips.Parse(file)
    local category, n, who = tostring(file):match("^(.-)_(%d+)_(.+)$")
    if category and category ~= "" then return category, tonumber(n), who end
end

function Clips.SetList(list)
    byCategory, isFile, last = {}, {}, {}
    for _, file in ipairs(list or {}) do
        local category = Clips.Parse(file)
        if category then
            byCategory[category] = byCategory[category] or {}
            table.insert(byCategory[category], file)
            isFile[file] = true
        end
    end
    for _, files in pairs(byCategory) do table.sort(files) end
end

-- Sorted { category, count } pairs.
function Clips.Categories()
    local out = {}
    for category, files in pairs(byCategory) do out[#out + 1] = { category, #files } end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

-- A random file from the category, never the same one twice in a row when there is a choice.
function Clips.Pick(category)
    local files = byCategory[category]
    if not files then return nil end
    local index = math.random(#files)
    if #files > 1 and files[index] == last[category] then index = index % #files + 1 end
    last[category] = files[index]
    return files[index]
end

-- Plays a random clip from a category, or one exact file. Returns the file name, or nil if there was
-- nothing to play (no clips, sound switched off, or the game refused the file).
function Clips.Play(categoryOrFile)
    if ST.db and ST.db.settings.soundOn == false then return nil end
    local file = byCategory[categoryOrFile] and Clips.Pick(categoryOrFile) or (isFile[categoryOrFile] and categoryOrFile)
    if not file then return nil end
    local ok, willPlay, handle = pcall(PlaySoundFile, DIR .. file, "Dialog")
    if not (ok and willPlay) then return nil end
    return file, handle
end

Clips.SetList(ST.clipFiles)
