import { readFile } from "node:fs/promises";
import { createHost, MemoryIndexedDb } from "../browser/boon-browser.mjs";

export function createPlaygroundApi({ compileProvider }) {
  return {
    async interpreterPreview({ exampleName }) {
      const host = await createHost({
        exampleName,
        storage: new MemoryIndexedDb(),
      });
      return {
        ok: true,
        mode: "interpreter",
        exampleName,
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
