import { join } from "node:path";

const repositoryRoot = join(import.meta.dir, "..");
const recordPathSources = [
  "RokugaCore/Sources/CaptureKit",
  "RokugaCore/Sources/EncoderKit",
];
const forbidden =
  /CVPixelBufferLockBaseAddress|CVPixelBufferGetBaseAddress|vImage|CGBitmapContextCreate/;

const violations: string[] = [];

for (const sourceRoot of recordPathSources) {
  const files: string[] = [];
  for await (const path of new Bun.Glob("**/*.swift").scan({
    cwd: join(repositoryRoot, sourceRoot),
    onlyFiles: true,
  })) {
    files.push(path);
  }

  for (const relativePath of files.sort()) {
    const path = `${sourceRoot}/${relativePath}`;
    const lines = (await Bun.file(join(repositoryRoot, path)).text()).split(/\r?\n/);
    for (const [index, line] of lines.entries()) {
      if (forbidden.test(line)) {
        violations.push(`${path}:${index + 1}:${line}`);
      }
    }
  }
}

if (violations.length > 0) {
  console.log(violations.join("\n"));
  console.log("FAILED: CPU pixel readback detected in the record path");
  process.exitCode = 1;
} else {
  console.log("OK: no CPU pixel readback APIs in the record path");
}
