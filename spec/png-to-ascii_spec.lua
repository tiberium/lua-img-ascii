package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local PngToAscii = require("img-ascii.png-to-ascii")

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_PADDING = "="
local FIRST_LUA_INDEX = 1
local BYTE_MAXIMUM = 255

local function decode_base64(encoded)
	local values = {}
	for index = FIRST_LUA_INDEX, #encoded do
		local character = encoded:sub(index, index)
		if character ~= BASE64_PADDING then
			local alphabet_index = assert(BASE64_ALPHABET:find(character, FIRST_LUA_INDEX, true))
			table.insert(values, alphabet_index - FIRST_LUA_INDEX)
		end
	end

	local bytes = {}
	for index = FIRST_LUA_INDEX, #values, 4 do
		local first = values[index]
		local second = values[index + 1]
		local third = values[index + 2]
		local fourth = values[index + 3]
		table.insert(bytes, string.char(first * 4 + math.floor(second / 16)))
		if third then
			table.insert(bytes, string.char((second % 16) * 16 + math.floor(third / 4)))
		end
		if fourth then
			table.insert(bytes, string.char((third % 4) * 64 + fourth))
		end
	end

	return table.concat(bytes)
end

describe("PNG to ASCII", function()
	it("decodes an 8-bit RGB PNG and renders sampled pixels", function()
		local png = decode_base64(
			"iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAG0lEQVR4nGNgYGCor6////8/438g8///hoYGAE87CPlapiOBAAAAAElFTkSuQmCC"
		)

		local image = PngToAscii.decode(png)

		assert.same({
			width = 3,
			height = 2,
			channels = 3,
			pixels = {
				0,
				0,
				0,
				127,
				127,
				127,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				0,
				0,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				127,
				127,
				127,
			},
		}, image)
		assert.same({ " .@", " @." }, PngToAscii.render(image, 3, 2, " .@"))
	end)

	it("decodes 8-bit RGBA PNG scanlines using every PNG filter", function()
		local png = decode_base64(
			"iVBORw0KGgoAAAANSUhEUgAAAAEAAAAFCAYAAACEhIafAAAAHklEQVR4nA3BgQEAIAjD"
				.. "sE75231eTBAM0kN8V9vJt3AtCAl0dWUAAAAAAElFTkSuQmCC"
		)

		local image = PngToAscii.decode(png)

		assert.same({
			width = 1,
			height = 5,
			channels = 4,
			pixels = {
				BYTE_MAXIMUM,
				0,
				0,
				BYTE_MAXIMUM,
				0,
				BYTE_MAXIMUM,
				0,
				128,
				0,
				0,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				BYTE_MAXIMUM,
				0,
				0,
				0,
				0,
			},
		}, image)
		assert.same({ ".", "@", ".", "@", "@" }, PngToAscii.to_ascii(png, 1, 5, ".@"))
	end)
end)
