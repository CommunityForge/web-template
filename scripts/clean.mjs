import * as Glob from "glob"
import * as Fs from "node:fs"

const dirs = [".", ...Glob.sync("packages/*/"), ...Glob.sync("apps/*/")]

const artifacts = [".tsbuildinfo", "tsconfig.tsbuildinfo", "build", "dist", "coverage"]

for (const dir of dirs) {
  for (const artifact of artifacts) {
    Fs.rmSync(`${dir}/${artifact}`, { recursive: true, force: true })
  }
}
