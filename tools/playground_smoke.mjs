import { mkdir, writeFile } from "node:fs/promises";
import { createPlaygroundApi } from "../playground/playground_api.mjs";
import { compileWithLocalZig } from "../playground/edge_compile/local_compile.mjs";
import { createBrowserPlaygroundApi, mountPlayground } from "../browser/playground-browser.mjs";

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function expectCompile(api, sourcePath, name, expectedLine) {
  const result = await api.compileToZig({
    sourcePath,
    outDir: ".zig-cache/playground-smoke",
    name,
  });
  if (!result.ok) {
    fail(`${name} compile failed: ${JSON.stringify(result.diagnostics)}`);
  }
  if (!result.previewStdout.includes(expectedLine)) {
    fail(`${name} preview mismatch: ${result.previewStdout}`);
  }
  if (result.mode !== "local-zig" || result.budgets.generatedZigBytes <= 0 || result.budgets.buildMs <= 0) {
    fail(`${name} compile metadata mismatch: ${JSON.stringify(result)}`);
  }
  const viewer = await api.generatedZigViewer(result);
  if (!viewer.ok || !viewer.source.includes("semantic_source_map") || !viewer.source.includes("runGeneratedPhysicalRuntimeAdapter")) {
    fail(`${name} generated Zig viewer mismatch`);
  }
  return result;
}

class FakeNode {
  constructor(tagName = "") {
    this.tagName = tagName.toUpperCase();
    this.childNodes = [];
    this.parentNode = null;
    this.className = "";
    this.listeners = new Map();
    this.value = "";
    this.type = "";
    this.spellcheck = true;
    this._textContent = "";
  }

  append(...children) {
    for (const child of children) this.appendChild(child);
  }

  appendChild(child) {
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }

  replaceChildren(...children) {
    this.childNodes = [];
    for (const child of children) this.appendChild(child);
  }

  addEventListener(type, handler) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(handler);
  }

  dispatch(type) {
    for (const handler of this.listeners.get(type) ?? []) handler({ currentTarget: this });
  }

  set textContent(value) {
    this.childNodes = [];
    this._textContent = String(value);
  }

  get textContent() {
    if (this.childNodes.length === 0) return this._textContent;
    return this.childNodes.map((child) => child.textContent).join("");
  }
}

class FakeDocument {
  createElement(tagName) {
    return new FakeNode(tagName);
  }
}

async function smokeBrowserPlaygroundUi() {
  const originalDocument = globalThis.document;
  try {
    globalThis.document = new FakeDocument();
    const api = createBrowserPlaygroundApi({
      interpreterHostFactory: async () => ({ textContent: () => "0+" }),
      compileProvider: async (request) => ({
        ok: true,
        mode: "local-zig",
        sourcePath: request.sourcePath,
        generatedZigPath: ".zig-cache/playground-smoke/browser-ui.zig",
        generatedZig: "const semantic_source_map = [_]u8{};\n",
        previewStdout: "state[0]=number:0\n",
        diagnostics: [],
      }),
    });
    const root = new FakeNode("div");
    const mounted = await mountPlayground(root, api);
    if (!mounted.editor.value.includes("increment_button") || mounted.preview.textContent !== "0+") {
      fail("browser playground UI initial state mismatch");
    }
    await mounted.compile();
    if (!mounted.generated.textContent.includes("semantic_source_map") || !mounted.preview.textContent.includes("state[0]=number:0")) {
      fail("browser playground UI compile/viewer mismatch");
    }
  } finally {
    if (originalDocument === undefined) {
      delete globalThis.document;
    } else {
      globalThis.document = originalDocument;
    }
  }
}

async function main() {
  const api = createPlaygroundApi({
    compileProvider: compileWithLocalZig,
    interpreterHostFactory: async () => ({ textContent: () => "0+" }),
  });

  const interpreter = await api.interpreterPreview({
    sourcePath: "examples/source_physical/counter/counter.bn",
    name: "counter",
  });
  if (!interpreter.ok || interpreter.text !== "0+") {
    fail(`interpreter preview mismatch: ${JSON.stringify(interpreter)}`);
  }

  await expectCompile(
    api,
    "examples/source_physical/counter/counter.bn",
    "counter",
    "state[0]=number:0",
  );
  await expectCompile(
    api,
    "examples/source_physical/todo_mvc/todo_mvc.bn",
    "todo_mvc",
    "state[0]=number:0",
  );

  await mkdir(".zig-cache/playground-smoke", { recursive: true });
  const invalidPath = ".zig-cache/playground-smoke/invalid_link.bn";
  await writeFile(
    invalidPath,
    "button: [event: [press: SOURCE]]\nvalue: button.event.press |> LINK target\n",
  );
  const invalid = await api.compileToZig({
    sourcePath: invalidPath,
    outDir: ".zig-cache/playground-smoke",
    name: "invalid_link",
  });
  if (invalid.ok || invalid.diagnostics[0]?.sourcePath !== invalidPath) {
    fail(`diagnostic source mapping mismatch: ${JSON.stringify(invalid)}`);
  }

  await smokeBrowserPlaygroundUi();
  console.log("PASS playground compile");
}

await main();
