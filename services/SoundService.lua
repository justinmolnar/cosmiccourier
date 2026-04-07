-- services/SoundService.lua
-- Programmatic sound effects for dispatch rule blocks.
-- Generates simple PCM tones via love.sound — no external audio files needed.

local SoundService = {}

-- ── State ─────────────────────────────────────────────────────────────────────

local _sources = {}   -- { [name] = love.audio.Source }
local _master  = 1.0  -- master volume 0–1

-- ── Tone generators ───────────────────────────────────────────────────────────

local SR = 44100  -- sample rate (Hz)

-- Single sine tone, with a short fade-out.
local function makeSine(freq, duration, vol)
    local n  = math.floor(SR * duration)
    local sd = love.sound.newSoundData(n, SR, 16, 1)
    for i = 0, n - 1 do
        local t    = i / SR
        local fade = math.min(1.0, (n - i) / (SR * 0.04))  -- 40 ms fade-out
        sd:setSample(i, math.sin(2 * math.pi * freq * t) * vol * fade)
    end
    return sd
end

-- Frequency sweep from f1 → f2, using continuous phase accumulation.
local function makeSweep(f1, f2, duration, vol)
    local n     = math.floor(SR * duration)
    local sd    = love.sound.newSoundData(n, SR, 16, 1)
    local phase = 0.0
    for i = 0, n - 1 do
        local t    = i / n  -- 0→1
        local freq = f1 + (f2 - f1) * t
        phase      = phase + 2 * math.pi * freq / SR
        local fade = math.min(1.0, (n - i) / (SR * 0.04))
        sd:setSample(i, math.sin(phase) * vol * fade)
    end
    return sd
end

-- Three sequential notes (ascending or descending chord).
local function makeSequence(freqs, each_dur, vol)
    local seg   = math.floor(SR * each_dur)
    local total = seg * #freqs
    local sd    = love.sound.newSoundData(total, SR, 16, 1)
    for part, freq in ipairs(freqs) do
        local off = (part - 1) * seg
        for i = 0, seg - 1 do
            local t    = i / SR
            local fade = math.min(1.0, (seg - i) / (SR * 0.03))
            sd:setSample(off + i, math.sin(2 * math.pi * freq * t) * vol * fade)
        end
    end
    return sd
end

-- ── Built-in sound definitions ────────────────────────────────────────────────

local DEFS = {
    beep    = function() return makeSine(880, 0.08, 0.45) end,
    chime   = function() return makeSine(660, 0.28, 0.35) end,
    horn    = function() return makeSine(330, 0.20, 0.50) end,
    warning = function() return makeSweep(480, 220, 0.40, 0.40) end,
    success = function() return makeSequence({523, 659, 784}, 0.10, 0.35) end,
    fail    = function() return makeSequence({784, 523, 392}, 0.10, 0.35) end,
}

-- ── Public API ────────────────────────────────────────────────────────────────

-- Returns sorted list of all built-in sound names.
function SoundService.getNames()
    local t = {}
    for k in pairs(DEFS) do t[#t+1] = k end
    table.sort(t)
    return t
end

-- Play a sound by name. volume_mult optionally scales the master volume for
-- this particular play (0.0–1.0; defaults to 1.0).
function SoundService.play(name, volume_mult)
    local def = DEFS[name]
    if not def then return end

    -- Lazy-create the Source on first play.
    if not _sources[name] then
        local ok, result = pcall(function()
            return love.audio.newSource(def(), "static")
        end)
        if not ok or not result then return end
        _sources[name] = result
    end

    local src = _sources[name]
    if src:isPlaying() then src:stop() end
    src:setVolume(math.max(0, math.min(1, (volume_mult or 1.0) * _master)))
    src:play()
end

-- Stop all currently-playing managed sources.
function SoundService.stopAll()
    for _, src in pairs(_sources) do
        if src:isPlaying() then src:stop() end
    end
end

-- Change master volume (0.0–1.0). Affects future plays; ongoing plays keep
-- their current volume.
function SoundService.setMasterVolume(vol)
    _master = math.max(0, math.min(1, vol))
end

return SoundService
