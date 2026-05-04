import { readFile } from "node:fs/promises";
import { MemoryIndexedDb } from "../browser/boon-browser.mjs";

export function createPlaygroundApi({ compileProvider, interpreterHostFactory = null }) {
  return {
    async interpreterPreview({ sourcePath, name }) {
      if (!interpreterHostFactory) {
        return {
          ok: false,
          mode: "interpreter-unavailable",
          sourcePath,
          diagnostics: [{ sourcePath, message: "interpreter preview host unavailable" }],
        };
      }
      const host = await interpreterHostFactory({
        sourceName: sourcePath ?? name,
        storage: new MemoryIndexedDb(),
      });
      return {
        ok: true,
        mode: "interpreter",
        sourcePath,
        name,
        text: host.textContent(),
      };
    },

    async compileToZig(request) {
      return compileProvider(request);
    },

    async generatedZigViewer(compileResult) {
      if (!compileResult.ok) {
        return {
          ok: false,
          diagnostics: compileResult.diagnostics,
        };
      }
      return {
        ok: true,
        path: compileResult.generatedZigPath,
        source: await readFile(compileResult.generatedZigPath, "utf8"),
      };
    },
  };
}
