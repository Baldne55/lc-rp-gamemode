-- utils/hash.lua
-- SHA-256 with random salt for password hashing.
--
-- Algorithm: SHA-256(salt .. password) -> 64-char hex string
-- Salt:      32-char random hex string (16 bytes of entropy)
--
-- Node.js / UCP equivalent:
--   const hash = crypto.createHash('sha256').update(salt + password).digest('hex');
--   const salt = crypto.randomBytes(16).toString('hex');
--
-- Lua 5.4 only -- uses native 64-bit integer bitwise operators.

Hash = {}

-- Internal: 32-bit mask for all bitwise operations.
local M32 = 0xFFFFFFFF

local function band(a, b)   return  a & b           end
local function bxor(a, b)   return  a ~ b           end
local function bnot(a)      return (~a) & M32        end
local function rshift(a, n) return (a & M32) >> n    end
local function rrot(a, n)
    a = a & M32
    return ((a >> n) | (a << (32 - n))) & M32
end
local function add32(a, b)  return (a + b) & M32     end

-- SHA-256 round constants.
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- Internal: SHA-256 over a raw byte string, returns raw 32 bytes.
local function sha256bytes(msg)
    local h0 = 0x6a09e667
    local h1 = 0xbb67ae85
    local h2 = 0x3c6ef372
    local h3 = 0xa54ff53a
    local h4 = 0x510e527f
    local h5 = 0x9b05688c
    local h6 = 0x1f83d9ab
    local h7 = 0x5be0cd19

    -- Padding: append 0x80, zero bytes, then 64-bit big-endian bit length.
    local bitLen = #msg * 8
    msg = msg .. "\x80"
    while #msg % 64 ~= 56 do
        msg = msg .. "\x00"
    end
    -- Upper 32 bits of bit length are always 0 for messages < 512 MB.
    msg = msg .. "\x00\x00\x00\x00"
    for i = 3, 0, -1 do
        msg = msg .. string.char((bitLen >> (i * 8)) & 0xFF)
    end

    -- Process each 64-byte chunk.
    for ci = 1, #msg, 64 do
        local w = {}

        -- Load 16 big-endian 32-bit words.
        for i = 0, 15 do
            local o = ci + i * 4
            w[i] = (string.byte(msg, o)     << 24) |
                   (string.byte(msg, o + 1) << 16) |
                   (string.byte(msg, o + 2) <<  8) |
                    string.byte(msg, o + 3)
        end

        -- Extend to 64 words.
        for i = 16, 63 do
            local w15 = w[i - 15]
            local w2  = w[i - 2]
            local s0  = rrot(w15, 7) ~ rrot(w15, 18) ~ rshift(w15,  3)
            local s1  = rrot(w2, 17) ~ rrot(w2,  19) ~ rshift(w2,  10)
            w[i] = add32(add32(add32(w[i - 16], s0), w[i - 7]), s1)
        end

        -- Compression.
        local a, b, c, d, e, f, g, h =
            h0, h1, h2, h3, h4, h5, h6, h7

        for i = 0, 63 do
            local S1  = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
            local ch  = (e & f) ~ (bnot(e) & g)
            local t1  = add32(add32(add32(add32(h, S1), ch), K[i + 1]), w[i])
            local S0  = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2  = add32(S0, maj)

            h = g; g = f; f = e
            e = add32(d, t1)
            d = c; c = b; b = a
            a = add32(t1, t2)
        end

        h0 = add32(h0, a); h1 = add32(h1, b)
        h2 = add32(h2, c); h3 = add32(h3, d)
        h4 = add32(h4, e); h5 = add32(h5, f)
        h6 = add32(h6, g); h7 = add32(h7, h)
    end

    -- L10: Use table.concat instead of O(n^2) repeated string concatenation.
    local parts = {}
    for _, word in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
        for i = 3, 0, -1 do
            parts[#parts + 1] = string.char((word >> (i * 8)) & 0xFF)
        end
    end
    return table.concat(parts)
end

-- Returns the SHA-256 digest of msg as a 64-char lowercase hex string.
function Hash.sha256(msg)
    if type(msg) ~= "string" then msg = tostring(msg) end
    local raw = sha256bytes(msg)
    local parts = {}
    for i = 1, #raw do
        parts[i] = string.format("%02x", string.byte(raw, i))
    end
    return table.concat(parts)
end

-- Returns a random hex salt of the given length (default 32 chars = 16 bytes).
-- Attempts to use /dev/urandom for cryptographic randomness; falls back to
-- math.random seeded with high-resolution timer + PID.
-- M2: Improved entropy counter for the fallback PRNG path.
local _saltCounter = 0

function Hash.generateSalt(len)
    len = len or 32
    local bytes = math.ceil(len / 2)

    -- Try /dev/urandom (Linux/macOS).
    local f = io.open("/dev/urandom", "rb")
    if f then
        local raw = f:read(bytes)
        f:close()
        if raw and #raw == bytes then
            local parts = {}
            for i = 1, #raw do
                parts[i] = string.format("%02x", string.byte(raw, i))
            end
            return table.concat(parts):sub(1, len)
        end
    end

    -- Fallback: seed once with best available entropy, then use counter to avoid
    -- re-seeding (which resets the PRNG state and can produce collisions).
    _saltCounter = _saltCounter + 1
    if _saltCounter == 1 then
        math.randomseed(os.time() * 1000 + (os.clock() * 1000000))
    end
    local hexChars = "0123456789abcdef"
    local t = {}
    for i = 1, len do
        local idx = math.random(1, 16)
        t[i] = hexChars:sub(idx, idx)
    end
    return table.concat(t)
end

-- M1: PBKDF2-like iterative hashing to slow brute-force attacks.
-- Applies SHA-256 iteratively (10000 rounds) to increase computational cost.
local HASH_ITERATIONS = 10000

function Hash.hashPassword(password, salt)
    local result = Hash.sha256(salt .. password)
    for _ = 2, HASH_ITERATIONS do
        result = Hash.sha256(salt .. result)
    end
    return result
end

-- Constant-time string comparison to prevent timing attacks.
-- Returns true only if both strings are equal in length and content.
function Hash.constantTimeCompare(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    -- L11: Compare full length of the longer string to avoid length timing leak.
    local lenA, lenB = #a, #b
    local diff = lenA ~ lenB
    local maxLen = math.max(lenA, lenB)
    for i = 1, maxLen do
        local ba = (i <= lenA) and string.byte(a, i) or 0
        local bb = (i <= lenB) and string.byte(b, i) or 0
        diff = diff | (ba ~ bb)
    end
    return diff == 0
end

-- Returns true if the given plaintext password matches the stored hash and salt.
-- Uses constant-time comparison to prevent timing attacks.
function Hash.verifyPassword(password, salt, storedHash)
    local computed = Hash.hashPassword(password, salt)
    return Hash.constantTimeCompare(computed, storedHash)
end
