package = "lua-img-ascii"
version = "0.1-1"
source = {
	url = "git://github.com/tiberium/lua-img-ascii",
	tag = "v0.1.0",
}
description = {
	summary = "Pure Lua PNG and baseline JPEG to ASCII renderer",
	detailed = [[
		Decode PNG and baseline JPEG image bytes and render them as ASCII art.
		The library has no runtime dependencies.
	]],
	homepage = "https://github.com/tiberium/lua-img-ascii",
	license = "MIT",
}
dependencies = {
	"lua >= 5.1",
}
build = {
	type = "builtin",
	modules = {
		["img-ascii"] = "lua/img-ascii.lua",
		["img-ascii.jpeg-decoder"] = "lua/img-ascii/jpeg-decoder.lua",
		["img-ascii.png-to-ascii"] = "lua/img-ascii/png-to-ascii.lua",
	},
}
