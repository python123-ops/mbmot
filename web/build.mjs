import { cpSync, existsSync, mkdirSync, readdirSync, realpathSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const webRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(webRoot, "..");
const output = resolve(repositoryRoot, "_build", "site");
const moon = process.env.MBMOT_MOON || "moon";

const build = spawnSync(moon, ["build", "src/web_bridge", "--target", "js", "--release"], {
  cwd: repositoryRoot,
  encoding: "utf8",
  stdio: "inherit",
});
if (build.status !== 0) process.exit(build.status ?? 1);

const expectedOutput = resolve(repositoryRoot, "_build", "js", "release", "build", "web_bridge", "web_bridge.js");
if (!existsSync(expectedOutput)) throw new Error(`MoonBit browser artifact was not created: ${expectedOutput}`);

const resolvedBuildRoot = realpathSync(resolve(repositoryRoot, "_build"));
if (!output.startsWith(`${resolvedBuildRoot}\\`) && !output.startsWith(`${resolvedBuildRoot}/`)) {
  throw new Error("site output escaped the repository build directory");
}
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });

for (const name of ["index.html", "styles.css", "app.mjs", "favicon.svg"]) {
  cpSync(join(webRoot, name), join(output, name));
}
cpSync(join(webRoot, "assets"), join(output, "assets"), { recursive: true });
cpSync(expectedOutput, join(output, "mbmot.js"));

console.log(`Built ${readdirSync(output).length} top-level site entries in ${output}`);
