import { createHash } from "node:crypto";
import { mkdir, readFile, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";

function runCommand(command, args, options = {}) {
  return new Promise((resolveCommand) => {
    const startedAt = performance.now();
    const child = spawn(command, args, {
      cwd: options.cwd ?? process.cwd(),
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
    }, options.timeoutMs ?? 15000);
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      resolveCommand({
        code,
        stdout,
        stderr,
        durationMs: Math.round(performance.now() - startedAt),
      });
    });
  });
}

function diagnostic(sourcePath, step, result) {
  return {
    sourcePath,
    step,
    message: result.stderr.split("\n").find((line) => line.trim() !== "") ?? `${step} failed`,
    stderr: result.stderr,
  };
}

export async function compileWithLocalZig({
  sourcePath,
  outDir = ".zig-cache/playground",
  name = null,
  cwd = process.cwd(),
}) {
  const absoluteSourcePath = resolve(cwd, sourcePath);
  const source = await readFile(absoluteSourcePath, "utf8");
  const cacheKey = createHash("sha256").update(source).digest("hex").slice(0, 16);
  const outputName = name ?? cacheKey;
  const absoluteOutDir = resolve(cwd, outDir);
  await mkdir(absoluteOutDir, { recursive: true });

  const generatedZigPath = join(absoluteOutDir, `${outputName}.zig`);
  const nativePreviewPath = join(absoluteOutDir, outputName);

  const codegen = await runCommand("zig", [
    "build",
    "run",
    "--",
    "codegen-zig",
    sourcePath,
    "--out",
    generatedZigPath,
  ], { cwd, timeoutMs: 15000 });
  if (codegen.code !== 0) {
    return {
      ok: false,
      mode: "local-zig",
      cacheKey,
      diagnostics: [diagnostic(sourcePath, "codegen-zig", codegen)],
    };
  }

  const build = await runCommand("zig", [
    "build-exe",
    "--dep",
    "boon",
    `-Mroot=${generatedZigPath}`,
    "-Mboon=src/root.zig",
    `-femit-bin=${nativePreviewPath}`,
  ], { cwd, timeoutMs: 15000 });
  if (build.code !== 0) {
    return {
      ok: false,
      mode: "local-zig",
      cacheKey,
      generatedZigPath,
      diagnostics: [diagnostic(sourcePath, "zig-build-exe", build)],
    };
  }

  const preview = await runCommand(nativePreviewPath, [], { cwd, timeoutMs: 5000 });
  if (preview.code !== 0) {
    return {
      ok: false,
      mode: "local-zig",
      cacheKey,
      generatedZigPath,
      nativePreviewPath,
      diagnostics: [diagnostic(sourcePath, "native-preview", preview)],
    };
  }

  const generatedStats = await stat(generatedZigPath);
  const nativeStats = await stat(nativePreviewPath);
  return {
    ok: true,
    mode: "local-zig",
    cacheKey,
    sourcePath,
    generatedZigPath,
    nativePreviewPath,
    previewStdout: preview.stdout,
    budgets: {
      codegenMs: codegen.durationMs,
      buildMs: build.durationMs,
      previewMs: preview.durationMs,
      generatedZigBytes: generatedStats.size,
      nativePreviewBytes: nativeStats.size,
    },
    diagnostics: [],
  };
}
