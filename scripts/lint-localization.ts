import { join } from "node:path";

const repositoryRoot = join(import.meta.dir, "..");
const catalogPath = "App/Resources/Localizable.xcstrings";
const sourceRoot = "App/Sources";
const requiredLanguages = ["ko", "ja", "zh-Hans"];

const literalPatterns = [
  /Text\("((?:[^"\\]|\\.)+)"\)/g,
  /String\(localized:\s*"((?:[^"\\]|\\.)+)"\)/g,
  /L10n\.string\("((?:[^"\\]|\\.)+)"\)/g,
  /Label\("((?:[^"\\]|\\.)+)",/g,
  /Button\("((?:[^"\\]|\\.)+)"[,)]/g,
  /Toggle\("((?:[^"\\]|\\.)+)",/g,
  /Picker\("((?:[^"\\]|\\.)+)",/g,
  /LabeledContent\("((?:[^"\\]|\\.)+)"\)/g,
  /Recorder\("((?:[^"\\]|\\.)+)",/g,
  /section\("((?:[^"\\]|\\.)+)"\)/g,
  /\.alert\(\s*"((?:[^"\\]|\\.)+)"/g,
  /accessibilityLabel\(Text\("((?:[^"\\]|\\.)+)"\)\)/g,
  /accessibilityHint\(Text\("((?:[^"\\]|\\.)+)"\)\)/g,
  /Text\((?:[^()"\n]*)\?\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)+)"\)/g,
  /Button\((?:[^()"\n]*)\?\s*"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)+)",/g,
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isInterpolationOnly(literal: string): boolean {
  return /^(?:\\\([^)]*\)|\s)*$/.test(literal);
}

async function extractSourceKeys(): Promise<Array<{ key: string; path: string }>> {
  const files: string[] = [];
  for await (const path of new Bun.Glob("**/*.swift").scan({
    cwd: join(repositoryRoot, sourceRoot),
    onlyFiles: true,
  })) {
    files.push(path);
  }

  const keys = new Map<string, { key: string; path: string }>();
  for (const relativePath of files.sort()) {
    const path = `${sourceRoot}/${relativePath}`;
    const source = await Bun.file(join(repositoryRoot, path)).text();
    const filtered = source
      .split("\n")
      .filter((line) => !line.includes("verbatim"))
      .join("\n");

    for (const pattern of literalPatterns) {
      for (const match of filtered.matchAll(pattern)) {
        for (const group of match.slice(1)) {
          if (group && !isInterpolationOnly(group)) {
            const key = group.replaceAll("\\n", "\n");
            keys.set(`${key}\0${path}`, { key, path });
          }
        }
      }
    }
  }

  return [...keys.values()].sort(
    (left, right) =>
      (left.key < right.key ? -1 : left.key > right.key ? 1 : 0) ||
      (left.path < right.path ? -1 : left.path > right.path ? 1 : 0),
  );
}

async function main(): Promise<void> {
  const parsed: unknown = JSON.parse(
    await Bun.file(join(repositoryRoot, catalogPath)).text(),
  );
  if (!isRecord(parsed) || !isRecord(parsed.strings)) {
    throw new Error(`${catalogPath} must contain a strings object`);
  }

  const catalogKeys = new Set(Object.keys(parsed.strings));
  const failures: string[] = [];

  for (const { key, path } of await extractSourceKeys()) {
    if (!catalogKeys.has(key)) {
      failures.push(`[missing-key] ${path}: "${key}" not in ${catalogPath}`);
    }
  }

  for (const [key, entry] of Object.entries(parsed.strings).sort()) {
    if (!isRecord(entry)) {
      throw new Error(`${catalogPath} entry "${key}" must be an object`);
    }
    const localizations = isRecord(entry.localizations) ? entry.localizations : {};
    for (const language of requiredLanguages) {
      const localization = localizations[language];
      const stringUnit =
        isRecord(localization) && isRecord(localization.stringUnit)
          ? localization.stringUnit
          : {};
      if (
        stringUnit.state !== "translated" ||
        typeof stringUnit.value !== "string" ||
        stringUnit.value.length === 0
      ) {
        failures.push(`[untranslated] "${key}" missing ${language}`);
      }
    }
  }

  if (failures.length > 0) {
    console.log(failures.join("\n"));
    console.log(`\nFAILED: ${failures.length} localization issue(s)`);
    process.exitCode = 1;
    return;
  }

  console.log(
    `OK: ${catalogKeys.size} keys, ${requiredLanguages.length} languages fully translated`,
  );
}

await main();
