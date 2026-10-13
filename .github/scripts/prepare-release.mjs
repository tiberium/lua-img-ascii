import { readdir, readFile, unlink, writeFile } from "node:fs/promises";

const ROCKSPEC_FILE_PATTERN = /^lua-img-ascii-(\d+(?:\.\d+){1,2}-\d+)\.rockspec$/;
const STABLE_SEMVER_PATTERN = /^\d+\.\d+\.\d+$/;
const ROCKSPEC_REVISION = 1;
const ROCKSPEC_VERSION_PATTERN = /^version = "[^"]+"$/m;
const SOURCE_TAG_PATTERN = /^\ttag = "v[^"]+",$/m;
const REPOSITORY_ROOT = new URL("../..", import.meta.url);

const releaseVersion = process.argv[2];

if (!releaseVersion || !STABLE_SEMVER_PATTERN.test(releaseVersion)) {
	throw new Error("Expected a stable SemVer release version.");
}

const rockspecFiles = (await readdir(REPOSITORY_ROOT)).filter(filename =>
	ROCKSPEC_FILE_PATTERN.test(filename)
);

if (rockspecFiles.length !== 1) {
	throw new Error("Expected exactly one versioned rockspec.");
}

const currentRockspecPath = rockspecFiles[0];
const currentRockspec = await readFile(new URL(currentRockspecPath, REPOSITORY_ROOT), "utf8");
const luaRocksVersion = `${releaseVersion.replace(/\.0$/, "")}-${ROCKSPEC_REVISION}`;
const nextRockspecPath = `lua-img-ascii-${luaRocksVersion}.rockspec`;

if (!ROCKSPEC_VERSION_PATTERN.test(currentRockspec)) {
	throw new Error("Could not find the rockspec version field.");
}

if (!SOURCE_TAG_PATTERN.test(currentRockspec)) {
	throw new Error("Could not find the rockspec source tag field.");
}

const nextRockspec = currentRockspec
	.replace(ROCKSPEC_VERSION_PATTERN, `version = "${luaRocksVersion}"`)
	.replace(SOURCE_TAG_PATTERN, `\ttag = "v${releaseVersion}",`);

if (nextRockspecPath !== currentRockspecPath) {
	await writeFile(new URL(nextRockspecPath, REPOSITORY_ROOT), nextRockspec);
	await unlink(new URL(currentRockspecPath, REPOSITORY_ROOT));
} else {
	await writeFile(new URL(currentRockspecPath, REPOSITORY_ROOT), nextRockspec);
}
