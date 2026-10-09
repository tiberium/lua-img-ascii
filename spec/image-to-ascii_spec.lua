package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ImageToAscii = require("img-ascii")

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_PADDING = "="
local FIRST_LUA_INDEX = 1

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

describe("image-to-ascii", function()
	it("detects and decodes a baseline JPEG", function()
		local jpeg = decode_base64(
			"/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsN"
				.. "DhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQU"
				.. "FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAIAAgDAREAAhEBAxEB/8QA"
				.. "FAABAAAAAAAAAAAAAAAAAAAACP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAA"
				.. "AAAHCf/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/ADoDFU3/2Q=="
		)

		local image = ImageToAscii.decode(jpeg)

		assert.equals(8, image.width)
		assert.equals(8, image.height)
		assert.equals(3, image.channels)
		assert.is_true(image.pixels[1] > 200)
		assert.is_true(image.pixels[2] < 40)
		assert.is_true(image.pixels[3] < 40)
		assert.same({ ".", "." }, ImageToAscii.to_ascii(jpeg, 1, 2, ".@"))
	end)

	it("rejects unrecognized image data", function()
		assert.has_error(function()
			ImageToAscii.decode("not an image")
		end, "Unsupported image format; expected PNG or JPEG.")
	end)
end)
