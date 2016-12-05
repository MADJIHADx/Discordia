local constants = require('./constants')
local INV_TAU = 1 / constants.TAU

local sin, floor, abs = math.sin, math.floor, math.abs

local function sine(h, a)
	local t = 0
	return function()
		local s = sin(t) * a
		t = t + h
		return s, s
	end
end

local function square(h, a)
	local t = 0
	return function()
		local s = sin(t)
		s = abs(s) / s * a
		t = t + h
		return s, s
	end
end

local function sawtooth(h, a)
	local t = 0
	return function()
		local s = t * INV_TAU
		s = 2 * (s - floor(0.5 + s)) * a
		t = t + h
		return s, s
	end
end

local function triangle(h, a)
	local t = 0
	return function()
		local s = t * INV_TAU
		s = (2 * abs(2 * (s - floor(0.5 + s))) - 1) * a
		t = t + h
		return s, s
	end
end

return {
	sine = sine,
	square = square,
	sawtooth = sawtooth,
	triangle = triangle,
}
