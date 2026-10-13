local PngToAscii = require("img-ascii.png-to-ascii")
local JpegDecoder = require("img-ascii.jpeg-decoder")

local M = {}

local PNG_SIGNATURE = "\137PNG\r\n\26\n"
local JPEG_SIGNATURE_PREFIX = "\255\216\255"
local PNG_SIGNATURE_LENGTH = #PNG_SIGNATURE
local JPEG_SIGNATURE_LENGTH = #JPEG_SIGNATURE_PREFIX
local FIRST_LUA_INDEX = 1

---@param image_data string
---@return table
function M.decode(image_data)
	if type(image_data) ~= "string" then
		error("Image data must be a string.")
	end
	if image_data:sub(FIRST_LUA_INDEX, PNG_SIGNATURE_LENGTH) == PNG_SIGNATURE then
		return PngToAscii.decode(image_data)
	end
	if image_data:sub(FIRST_LUA_INDEX, JPEG_SIGNATURE_LENGTH) == JPEG_SIGNATURE_PREFIX then
		return JpegDecoder.decode(image_data)
	end
	error("Unsupported image format; expected PNG or JPEG.")
end

M.render = PngToAscii.render
M.default_palette = PngToAscii.default_palette

---@param image_data string
---@param output_width number
---@param output_height number
---@param palette string|nil
---@return string[]
function M.to_ascii(image_data, output_width, output_height, palette)
	return M.render(M.decode(image_data), output_width, output_height, palette)
end

return M
