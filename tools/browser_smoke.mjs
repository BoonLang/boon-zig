import { spawn } from "node:child_process";
import { resolve } from "node:path";
import net from "node:net";
import {
  createFetchRenderedTextProvider,
  createHost,
  createWasmHostBoundary,
  MemoryIndexedDb,
} from "../browser/boon-browser.mjs";

const boonBin = resolve(process.cwd(), "zig-out", "bin", "boon-zig");

function fail(message) {
  console.error(message);
  process.exit(1);
}

class FakeNode {
  constructor(tagName = "") {
    this.tagName = tagName.toUpperCase();
    this.childNodes = [];
    this.parentNode = null;
    this.className = "";
    this.listeners = new Map();
    this.type = "";
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

  removeChild(child) {
    const index = this.childNodes.indexOf(child);
    if (index >= 0) {
      this.childNodes.splice(index, 1);
      child.parentNode = null;
    }
    return child;
  }

  get firstChild() {
    return this.childNodes[0] ?? null;
  }

  addEventListener(type, handler) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(handler);
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

class FakeText extends FakeNode {
  constructor(text) {
    super("#text");
    this._textContent = text;
  }
}

class FakeDocument {
  createElement(tagName) {
    return new FakeNode(tagName);
  }

  createTextNode(text) {
    return new FakeText(text);
  }
}

async function withFakeDocument(callback) {
  const originalDocument = globalThis.document;
  try {
    globalThis.document = new FakeDocument();
    return await callback();
  } finally {
    if (originalDocument === undefined) {
      delete globalThis.document;
    } else {
      globalThis.document = originalDocument;
    }
  }
}

async function pickPort() {
  return await new Promise((resolvePort, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("failed to pick browser smoke port")));
        return;
      }
      const port = address.port;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolvePort(port);
      });
    });
  });
}

async function waitForEndpoint(url, description) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { cache: "no-store" });
      if (response.ok) return response;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  fail(`${description} did not start: ${url}`);
}

async function withServedSource(sourcePath, callback) {
  const runtimeServerPort = await pickPort();
  const server = spawn(boonBin, [
    "serve-browser",
    sourcePath,
    "--port",
    `${runtimeServerPort}`,
  ], {
    cwd: process.cwd(),
    stdio: "ignore",
  });
  const baseUrl = `http://127.0.0.1:${runtimeServerPort}`;
  const originalLocation = globalThis.location;
  try {
    globalThis.location = { href: `${baseUrl}/index.html` };
    await waitForEndpoint(`${baseUrl}/index.html`, "browser server");
    return await callback(baseUrl);
  } finally {
    if (originalLocation === undefined) {
      delete globalThis.location;
    } else {
      globalThis.location = originalLocation;
    }
    server.kill("SIGTERM");
  }
}

async function smokeGenericServedSource() {
  await withServedSource("fixtures/generic_apps/single_document/app.bn", async (baseUrl) => {
    await waitForEndpoint(`${baseUrl}/__boon/render-text`, "render endpoint");
    const servedManifest = await fetch(`${baseUrl}/manifest.json`, { cache: "no-store" }).then((response) => response.json());
    if (servedManifest.served_source?.path !== "fixtures/generic_apps/single_document/app.bn") {
      fail(`generic served source manifest mismatch: ${JSON.stringify(servedManifest.served_source)}`);
    }
    if (servedManifest.render_text_endpoint !== "/__boon/render-text") {
      fail(`generic render endpoint missing: ${JSON.stringify(servedManifest)}`);
    }
    const provider = createFetchRenderedTextProvider(`${baseUrl}/__boon/render-text`);
    const host = await createHost({
      sourceName: servedManifest.served_source.name,
      storage: new MemoryIndexedDb(),
      renderedTextProvider: provider,
    });
    if (!host.textContent().includes("Generic Browser Fixture")) {
      fail(`generic served source render mismatch: ${host.textContent()}`);
    }
    await withFakeDocument(async () => {
      const root = new FakeNode("div");
      const mounted = await createHost({
        sourceName: servedManifest.served_source.name,
        storage: new MemoryIndexedDb(),
        root,
        renderedTextProvider: provider,
      });
      if (!root.textContent.includes("Generic Browser Fixture") || mounted.textContent() !== root.textContent) {
        fail(`generic served source DOM mismatch: ${root.textContent}`);
      }
    });
  });
  console.log("PASS generic_served_source");
}

async function smokePhysicalServedSource() {
  await withServedSource("examples/upstream/todo_mvc_physical/RUN.bn", async (baseUrl) => {
    await waitForEndpoint(`${baseUrl}/__boon/physical-state?theme=Professional&mode=Light`, "physical endpoint");
    const servedManifest = await fetch(`${baseUrl}/manifest.json`, { cache: "no-store" }).then((response) => response.json());
    if (servedManifest.served_source?.path !== "examples/upstream/todo_mvc_physical/RUN.bn") {
      fail(`physical served source manifest mismatch: ${JSON.stringify(servedManifest.served_source)}`);
    }
    const host = await createHost({
      sourceName: servedManifest.served_source.name,
      storage: new MemoryIndexedDb(),
      physicalStateProvider: async ({ theme, mode }) => {
        const response = await fetch(`${baseUrl}/__boon/physical-state?theme=${theme}&mode=${mode}`, { cache: "no-store" });
        return await response.json();
      },
    });
    if (!host.textContent().includes("ProfessionalLight") || !host.textContent().includes("*****")) {
      fail(`physical served source initial render mismatch: ${host.textContent()}`);
    }
    await host.setPhysicalTheme("Neobrutalism");
    if (!host.textContent().includes("NeobrutalismLight")) {
      fail(`physical served source theme mismatch: ${host.textContent()}`);
    }
    await host.togglePhysicalMode();
    if (!host.textContent().includes("NeobrutalismDark")) {
      fail(`physical served source mode mismatch: ${host.textContent()}`);
    }
    await host.clearState();
    if (!host.textContent().includes("ProfessionalLight")) {
      fail(`physical served source clear-state mismatch: ${host.textContent()}`);
    }
  });
  console.log("PASS physical_served_source");
}

async function smokeWasmHostBoundary() {
  const dispatchCalls = [];
  const boundary = createWasmHostBoundary({
    sourceBindings: {
      "ui.primary.event.press": { sourceSlotId: 42, bindingId: 7 },
    },
    exports: {
      dispatch_source(sourceSlotId, bindingId, payloadTag, payloadScalar) {
        dispatchCalls.push({ sourceSlotId, bindingId, payloadTag, payloadScalar });
      },
    },
  });
  const host = await createHost({
    sourceName: "fixtures/generic_apps/source_counter/app.bn",
    storage: new MemoryIndexedDb(),
    renderedTextProvider: async () => "generic source host",
    hostBoundary: boundary,
  });
  host.dispatchBrowserSource("ui.primary.event.press");

  if (host.sourceEventTrace.length !== 1 || host.sourceEventTrace[0].sourceSlotId !== 42) {
    fail(`wasm host boundary trace used wrong source slot: ${JSON.stringify(host.sourceEventTrace)}`);
  }
  if (boundary.dispatched.length !== 1 || boundary.dispatched[0].bindingId !== 7) {
    fail(`wasm host boundary did not record dispatched event: ${JSON.stringify(boundary.dispatched)}`);
  }
  if (
    dispatchCalls.length !== 1 ||
    dispatchCalls[0].sourceSlotId !== 42 ||
    dispatchCalls[0].bindingId !== 7 ||
    dispatchCalls[0].payloadTag !== 0 ||
    dispatchCalls[0].payloadScalar !== 0
  ) {
    fail(`wasm host boundary export call mismatch: ${JSON.stringify(dispatchCalls)}`);
  }

  console.log("PASS wasm_host_boundary");
}

async function main() {
  const filter = process.argv[2];
  if (!filter) {
    fail("browser_smoke.mjs requires a filter argument");
  }
  if (filter === "generic_served_source") {
    await smokeGenericServedSource();
    return;
  }
  if (filter === "physical_served_source") {
    await smokePhysicalServedSource();
    return;
  }
  if (filter === "wasm_host_boundary") {
    await smokeWasmHostBoundary();
    return;
  }
  fail(`unsupported browser smoke filter: ${filter}`);
}

await main();
