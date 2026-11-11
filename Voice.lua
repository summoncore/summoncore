-- Voice: the Index says the same fact a few different ways. Lines that repeat all season (an answer, "Summon logged",
-- where the week stands) come in small pools, and Say picks one at random without repeating the one before it.
-- Every variant of a pool carries the same facts, so which one a client shows is only flavour: nothing is synced.
-- The first variant is the plain one; the self-tests set `fixed` so they always get it.
local ADDON, ST = ...
setfenv(1, ST.env) -- the addon's own globals (Core.lua)
local Voice = { fixed = false }
ST.Voice = Voice

local last = {}

-- The index of the variant to use for `key` out of `count`: never the one used last time, unless there is only one.
function Voice.Choose(key, count, random)
    if Voice.fixed or count <= 1 then
        last[key] = 1
        return 1
    end
    random = random or math.random
    local i
    repeat i = random(count) until i ~= last[key]
    last[key] = i
    return i
end

-- Say("answer.accepted", { "%s accepted it.", "%s said yes." }, who): one template, formatted with the arguments.
function Voice.Say(key, templates, ...)
    return string.format(templates[Voice.Choose(key, #templates)], ...)
end
