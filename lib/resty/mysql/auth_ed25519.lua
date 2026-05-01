-- Copyright (C) Yichun Zhang (agentzh)
--
-- MariaDB "client_ed25519" authentication plugin.
--
-- This is the MariaDB-specific Ed25519 variant: instead of deriving the
-- expanded secret key from a 32-byte seed via SHA-512 (RFC 8032), the
-- expanded secret key is computed directly from SHA-512(password). The
-- standard libsodium / OpenSSL Ed25519 high-level APIs cannot be used
-- as-is because they always perform that initial derivation step.
--
-- The implementation is built on `resty.openssl.bn` (libcrypto BIGNUM):
-- field and group arithmetic go through OpenSSL while Edwards-curve
-- point arithmetic is implemented here, because OpenSSL does not expose
-- Ed25519 group operations through its public API. This avoids any
-- additional system dependency beyond the libcrypto OpenResty already
-- links against.
--
-- Reference: RFC 8032 §5.1 (Ed25519); MariaDB connector-c
--            plugins/auth/ref10/sign.c.


local has_bn, bn = pcall(require, "resty.openssl.bn")
local resty_sha512 = require "resty.sha512"

local ffi = require "ffi"
local base = require "resty.core.base"
local bit = require "bit"

local ffi_string = ffi.string
local get_string_buf = base.get_string_buf
local strbyte = string.byte
local strchar = string.char
local strrep = string.rep
local sub = string.sub
local band = bit.band
local bor = bit.bor
local lshift = bit.lshift


local _M = { _VERSION = "0.02" }


-- Cached BN constants. All initialized on first use.
local bn0, bn1, bn2
local p_bn        -- 2^255 - 19, the Ed25519 field prime
local p_minus_2   -- exponent for modular inverse via Fermat
local L_bn        -- 2^252 + 27742317777372353535851937790883648493 (group order)
local d_bn        -- -121665/121666 mod p (Edwards curve parameter)
local two_d       -- 2 * d mod p (precomputed: appears in every addition)
local Bx_bn, By_bn, Bz_bn, Bt_bn  -- generator G in extended coords


local function _ensure()
    if p_bn then
        return true
    end

    if not has_bn then
        return nil, "resty.openssl.bn not available: " .. tostring(bn)
    end

    bn0 = bn.from_dec("0")
    bn1 = bn.from_dec("1")
    bn2 = bn.from_dec("2")

    p_bn = bn.from_hex(
        "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed")
    p_minus_2 = p_bn - bn2  -- 2^255 - 21, exponent for Z^-1 via Fermat

    L_bn = bn.from_hex(
        "1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed")

    d_bn = bn.from_hex(
        "52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3")
    two_d = d_bn:mod_mul(bn2, p_bn)

    Bx_bn = bn.from_hex(
        "216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a")
    By_bn = bn.from_hex(
        "6666666666666666666666666666666666666666666666666666666666666658")
    Bz_bn = bn1
    Bt_bn = Bx_bn:mod_mul(By_bn, p_bn)

    return true
end


-- ---------------------------------------------------------------------
-- Byte / BN helpers
-- ---------------------------------------------------------------------

-- Byte-reverse a string without per-byte substring allocations: write into
-- a shared lua-resty-core scratch buffer and return a single ffi.string.
local function _reverse(s)
    local n = #s
    local buf = get_string_buf(n)
    for i = 0, n - 1 do
        buf[i] = strbyte(s, n - i)
    end
    return ffi_string(buf, n)
end


-- Little-endian byte string -> BN. (OpenSSL BN uses big-endian binary I/O.)
local function _le_to_bn(s)
    return bn.from_binary(_reverse(s))
end


-- BN -> little-endian byte string of exactly `len` bytes, left-padded with
-- zeros if needed. The BN is expected to already be reduced (mod p or mod L)
-- so its big-endian encoding fits in `len` bytes; if not, that's a logic bug
-- upstream and we raise rather than silently truncate.
local function _bn_to_le(b, len)
    local be = b:to_binary()
    local n = #be
    if n > len then
        error("bn value does not fit in " .. len .. " bytes (got " .. n .. ")")
    elseif n < len then
        be = strrep("\0", len - n) .. be
    end
    return _reverse(be)
end


-- Reuse a single SHA-512 context per worker. update/final are synchronous
-- FFI calls (no yield points), so the run-to-completion model of OpenResty
-- coroutines makes shared mutable state safe across requests as long as we
-- reset() at the start of every operation.
local _sha512_ctx
local function _sha512(data)
    local h = _sha512_ctx
    if h then
        if not h:reset() then
            return nil, "failed to reset sha512"
        end
    else
        h = resty_sha512:new()
        if not h then
            return nil, "failed to create sha512 object"
        end
        _sha512_ctx = h
    end
    if not h:update(data) then
        return nil, "failed to update sha512"
    end
    local d = h:final()
    if not d then
        return nil, "failed to finalize sha512"
    end
    return d
end


-- ---------------------------------------------------------------------
-- Twisted Edwards arithmetic in extended coordinates (X:Y:Z:T) with a=-1.
--
-- Identity: (0, 1, 1, 0).
-- All BNs are kept reduced mod p (the field prime).
-- Reference: RFC 8032 §5.1.4 (point addition).
-- ---------------------------------------------------------------------

-- Point addition: P + Q -> R
local function _padd(P, Q)
    local X1, Y1, Z1, T1 = P[1], P[2], P[3], P[4]
    local X2, Y2, Z2, T2 = Q[1], Q[2], Q[3], Q[4]

    -- A = (Y1 - X1) * (Y2 - X2) mod p
    local A = Y1:mod_sub(X1, p_bn):mod_mul(Y2:mod_sub(X2, p_bn), p_bn)
    -- B = (Y1 + X1) * (Y2 + X2) mod p
    local B = Y1:mod_add(X1, p_bn):mod_mul(Y2:mod_add(X2, p_bn), p_bn)
    -- C = T1 * 2d * T2 mod p
    local C = T1:mod_mul(two_d, p_bn):mod_mul(T2, p_bn)
    -- D = Z1 * 2 * Z2 mod p
    local D = Z1:mod_mul(bn2, p_bn):mod_mul(Z2, p_bn)
    local E = B:mod_sub(A, p_bn)
    local F = D:mod_sub(C, p_bn)
    local G = D:mod_add(C, p_bn)
    local H = B:mod_add(A, p_bn)

    return {
        E:mod_mul(F, p_bn),  -- X3 = E * F
        G:mod_mul(H, p_bn),  -- Y3 = G * H
        F:mod_mul(G, p_bn),  -- Z3 = F * G
        E:mod_mul(H, p_bn),  -- T3 = E * H
    }
end


-- Scalar multiplication: scalar (32-byte little-endian) * generator G.
-- Right-to-left double-and-add over the scalar's bits.
--
-- Per-bit work is constant: every iteration performs exactly one point
-- addition (Q + R) and one point doubling (R + R), regardless of the bit
-- value. The bit only selects whether the freshly-computed sum becomes the
-- new Q (a Lua reference assignment), so the underlying BN op count and
-- allocation pattern no longer depend on the secret scalar. This is not
-- fully constant-time -- OpenSSL BN_* and the LuaJIT branch predictor are
-- not -- but it removes the gross variable-time leak of the prior version.
local function _scalarmult_base(scalar_le)
    -- Q starts at the identity element.
    local Q = { bn0, bn1, bn1, bn0 }
    -- R starts at G; gets doubled at every bit.
    local R = { Bx_bn, By_bn, Bz_bn, Bt_bn }

    for byte_idx = 1, 32 do
        local b = strbyte(scalar_le, byte_idx)
        for bit_idx = 0, 7 do
            local sum = _padd(Q, R)
            if band(b, lshift(1, bit_idx)) ~= 0 then
                Q = sum
            end
            R = _padd(R, R)
        end
    end

    return Q
end


-- Encode a point in extended coords as the 32-byte compressed Ed25519
-- representation (RFC 8032 §5.1.2): little-endian y, with bit 7 of the
-- final byte set to the LSB of x.
local function _encode_point(P)
    local X, Y, Z = P[1], P[2], P[3]
    local Z_inv = Z:mod_exp(p_minus_2, p_bn)  -- Fermat: Z^(p-2) = Z^-1 mod p
    local x = X:mod_mul(Z_inv, p_bn)
    local y = Y:mod_mul(Z_inv, p_bn)

    local y_bytes = _bn_to_le(y, 32)
    local sign = x:is_odd() and 0x80 or 0x00
    local last = bor(band(strbyte(y_bytes, 32), 0x7f), sign)

    return sub(y_bytes, 1, 31) .. strchar(last)
end


-- Apply the Ed25519 secret-scalar clamp to a 32-byte little-endian buffer.
local function _clamp(s)
    local b1 = band(strbyte(s, 1),  248)
    local b32 = bor(band(strbyte(s, 32), 63), 64)
    return strchar(b1) .. sub(s, 2, 31) .. strchar(b32)
end


-- ---------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------

-- Sign `scramble` (a 32-byte server nonce) with the MariaDB ed25519 variant
-- where SHA-512(password) is used as the expanded secret key. Returns a
-- 64-byte signature on success, or nil + error on failure.
function _M.sign(password, scramble)
    if type(password) ~= "string" then
        return nil, "password must be a string"
    end
    if type(scramble) ~= "string" or #scramble ~= 32 then
        return nil, "scramble must be a 32-byte string"
    end

    local ok, err = _ensure()
    if not ok then
        return nil, err
    end

    -- az = SHA-512(password); split into 32-byte halves: s = clamp(first
    -- half) is the secret scalar, prefix = second half is mixed into the
    -- nonce hash.
    local az
    az, err = _sha512(password)
    if not az then
        return nil, err
    end

    local s_le = _clamp(sub(az, 1, 32))
    local prefix = sub(az, 33, 64)

    -- A = s * G  (encoded, 32 bytes)
    local A_pt = _scalarmult_base(s_le)
    local A_str = _encode_point(A_pt)

    -- r = SHA-512(prefix || M) reduced mod L; R = r * G
    local r_hash
    r_hash, err = _sha512(prefix .. scramble)
    if not r_hash then
        return nil, err
    end

    -- Reduce r mod L. Keep both forms: LE bytes feed _scalarmult_base,
    -- and r_bn feeds the final S = k*s + r computation. Computing the
    -- BN once and deriving LE from it avoids an extra LE->BN roundtrip
    -- on the way out.
    local r_bn = _le_to_bn(r_hash):mod(L_bn)
    local r_le = _bn_to_le(r_bn, 32)
    local R_pt = _scalarmult_base(r_le)
    local R_str = _encode_point(R_pt)

    -- k = SHA-512(R || A || M) reduced mod L
    local k_hash
    k_hash, err = _sha512(R_str .. A_str .. scramble)
    if not k_hash then
        return nil, err
    end

    local k_bn = _le_to_bn(k_hash):mod(L_bn)
    local s_bn = _le_to_bn(s_le)

    -- S = (k * s + r) mod L
    local S_bn = k_bn:mod_mul(s_bn, L_bn):mod_add(r_bn, L_bn)
    local S_str = _bn_to_le(S_bn, 32)

    -- signature = R || S  (64 bytes)
    return R_str .. S_str
end


return _M
