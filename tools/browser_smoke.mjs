import { spawn } from "node:child_process";
import { resolve } from "node:path";
import net from "node:net";
import { createHost, createWasmHostBoundary, MemoryIndexedDb } from "../browser/boon-browser.mjs";

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
    this.attributes = new Map();
    this.listeners = new Map();
    this.value = "";
    this.type = "";
    this.id = "";
    this.placeholder = "";
    this.checked = false;
    this.htmlFor = "";
    this._textContent = "";
  }

  append(...children) {
    for (const child of children) {
      if (typeof child === "string") {
        this.appendChild(new FakeText(child));
      } else {
        this.appendChild(child);
      }
    }
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

  dispatch(type, extra = {}) {
    const handlers = this.listeners.get(type) ?? [];
    for (const handler of handlers) {
      handler({
        currentTarget: this,
        key: extra.key,
        preventDefault() {},
      });
    }
  }

  focus() {}

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

function walk(node, visitor) {
  visitor(node);
  for (const child of node.childNodes ?? []) walk(child, visitor);
}

function findNode(root, predicate) {
  let found = null;
  walk(root, (node) => {
    if (found === null && predicate(node)) found = node;
  });
  return found;
}

async function withFakeDocument(callback) {
  const originalDocument = globalThis.document;
  const originalLocation = globalThis.location;
  try {
    globalThis.document = new FakeDocument();
    globalThis.location = { href: "http://127.0.0.1/index.html" };
    return await callback();
  } finally {
    if (originalDocument === undefined) {
      delete globalThis.document;
    } else {
      globalThis.document = originalDocument;
    }
    if (originalLocation === undefined) {
      delete globalThis.location;
    } else {
      globalThis.location = originalLocation;
    }
  }
}

async function smokeCounter() {
  const storage = new MemoryIndexedDb();
  const host = await createHost({ exampleName: "counter", storage });
  if (host.textContent() !== "0+") {
    fail(`counter initial render mismatch: ${host.textContent()}`);
  }
  await host.click("+");
  await host.click("+");
  if (host.textContent() !== "2+") {
    fail(`counter click render mismatch: ${host.textContent()}`);
  }
  if (host.sourceEventTrace.length !== 2 || host.sourceEventTrace[0].sourceSlotId !== 0) {
    fail(`counter source slot trace mismatch: ${JSON.stringify(host.sourceEventTrace)}`);
  }

  const resumed = await createHost({ exampleName: "counter", storage });
  if (resumed.textContent() !== "2+") {
    fail(`counter persistence mismatch: ${resumed.textContent()}`);
  }
  await resumed.clearState();
  if (resumed.textContent() !== "0+") {
    fail(`counter clear-state mismatch: ${resumed.textContent()}`);
  }

  await withFakeDocument(async () => {
    const root = new FakeNode("div");
    const mounted = await createHost({ exampleName: "counter", storage: new MemoryIndexedDb(), root });
    const initialRootRebuilds = mounted.renderStats.rootRebuilds;
    const output = findNode(root, (node) => node.tagName === "OUTPUT");
    if (!output || output.textContent !== "0") {
      fail(`counter retained DOM initial mismatch: ${root.textContent}`);
    }
    await mounted.click("+");
    if (mounted.renderStats.rootRebuilds !== initialRootRebuilds) {
      fail("counter retained DOM rebuilt root after click");
    }
    if (mounted.renderStats.textPatches < 1 || output.textContent !== "1") {
      fail(`counter retained DOM text patch mismatch: ${root.textContent}`);
    }
  });
  console.log("PASS counter");
}

async function smokeInterval() {
  const storage = new MemoryIndexedDb();
  const host = await createHost({ exampleName: "interval", storage });
  if (host.textContent() !== "0") {
    fail(`interval initial render mismatch: ${host.textContent()}`);
  }
  await host.advanceVirtualTime(2000);
  if (host.textContent() !== "2") {
    fail(`interval virtual-time mismatch: ${host.textContent()}`);
  }
  if (host.sourceEventTrace.length !== 1 || host.sourceEventTrace[0].semanticId !== "timer.event.tick") {
    fail(`interval source slot trace mismatch: ${JSON.stringify(host.sourceEventTrace)}`);
  }
  console.log("PASS interval");
}

async function smokeTodoMvc() {
  const storage = new MemoryIndexedDb();
  const host = await createHost({ exampleName: "todo_mvc", storage });
  if (!host.textContent().includes("Buy groceries") || !host.textContent().includes("2itemsleft")) {
    fail(`todo_mvc initial render mismatch: ${host.textContent()}`);
  }
  await host.addTodo("Write tests");
  if (!host.textContent().includes("Write tests") || !host.textContent().includes("3itemsleft")) {
    fail(`todo_mvc add mismatch: ${host.textContent()}`);
  }
  if (
    host.sourceEventTrace.length < 2 ||
    host.sourceEventTrace[0].sourceSlotId !== 0 ||
    host.sourceEventTrace[1].sourceSlotId !== 1
  ) {
    fail(`todo_mvc add source slot trace mismatch: ${JSON.stringify(host.sourceEventTrace)}`);
  }
  await host.toggleTodo(0);
  if (!host.textContent().includes("2itemsleft")) {
    fail(`todo_mvc toggle mismatch: ${host.textContent()}`);
  }
  await host.setRoute("completed");
  if (!host.textContent().includes("Buy groceries") || host.textContent().includes("Clean room")) {
    fail(`todo_mvc completed filter mismatch: ${host.textContent()}`);
  }
  await host.clearCompleted();
  if (!host.sourceEventTrace.some((event) => event.semanticId === "sources.remove_completed_button.event.press")) {
    fail(`todo_mvc clear-completed source slot trace mismatch: ${JSON.stringify(host.sourceEventTrace)}`);
  }
  await host.setRoute("all");
  if (host.textContent().includes("Buy groceries") || !host.textContent().includes("Write tests")) {
    fail(`todo_mvc clear-completed mismatch: ${host.textContent()}`);
  }
  const resumed = await createHost({ exampleName: "todo_mvc", storage });
  if (resumed.textContent().includes("Buy groceries") || !resumed.textContent().includes("Write tests")) {
    fail(`todo_mvc persistence mismatch: ${resumed.textContent()}`);
  }

  await withFakeDocument(async () => {
    const root = new FakeNode("div");
    const mounted = await createHost({ exampleName: "todo_mvc", storage: new MemoryIndexedDb(), root });
    const initialRootRebuilds = mounted.renderStats.rootRebuilds;
    if (!root.textContent.includes("Buy groceries") || !root.textContent.includes("2 items left")) {
      fail(`todo_mvc retained DOM initial mismatch: ${root.textContent}`);
    }
    await mounted.addTodo("Write retained patches");
    await mounted.toggleTodo(0);
    await mounted.setRoute("completed");
    if (mounted.renderStats.rootRebuilds !== initialRootRebuilds) {
      fail("todo_mvc retained DOM rebuilt root after interactions");
    }
    if (mounted.renderStats.childListPatches < 3 || mounted.renderStats.propertyPatches < 1) {
      fail(`todo_mvc retained DOM did not record direct patches: ${JSON.stringify(mounted.renderStats)}`);
    }
    if (!root.textContent.includes("Buy groceries") || root.textContent.includes("Clean room")) {
      fail(`todo_mvc retained DOM route mismatch: ${root.textContent}`);
    }
  });
  console.log("PASS todo_mvc");
}

async function smokeCells(exampleName) {
  const storage = new MemoryIndexedDb();
  const host = await createHost({ exampleName, storage });
  const title = exampleName === "cells_dynamic" ? "Cells Dynamic" : "Cells";
  if (!host.textContent().includes(title) || !host.textContent().includes("151530")) {
    fail(`${exampleName} initial render mismatch: ${host.textContent()}`);
  }
  await host.startEditCell(1, 1);
  await host.setEditingText("7");
  await host.commitEditingCell();
  if (!host.textContent().includes("171732")) {
    fail(`${exampleName} edit commit mismatch: ${host.textContent()}`);
  }
  const resumed = await createHost({ exampleName, storage });
  if (!resumed.textContent().includes("171732")) {
    fail(`${exampleName} persistence mismatch: ${resumed.textContent()}`);
  }
  await resumed.clearState();
  if (!resumed.textContent().includes("151530") || resumed.textContent().includes("171732")) {
    fail(`${exampleName} clear-state mismatch: ${resumed.textContent()}`);
  }

  const originalDocument = globalThis.document;
  const originalLocation = globalThis.location;
  try {
    globalThis.document = new FakeDocument();
    globalThis.location = { href: `http://127.0.0.1/index.html?example=${exampleName}` };
    const root = new FakeNode("div");
    const mounted = await createHost({ exampleName, storage: new MemoryIndexedDb(), root });
    const initialRootRebuilds = mounted.renderStats.rootRebuilds;
    if (!root.textContent.includes(title) || !root.textContent.includes("51530")) {
      fail(`${exampleName} mounted DOM initial render mismatch: ${root.textContent}`);
    }
    const firstEditable = findNode(root, (node) => node.tagName === "TD" && node.textContent === "5");
    if (!firstEditable) {
      fail(`${exampleName} mounted DOM missing editable cell`);
    }
    firstEditable.dispatch("dblclick");
    const input = findNode(root, (node) => node.tagName === "INPUT" && node.className === "sheet-input");
    if (!input) {
      fail(`${exampleName} mounted DOM did not enter edit mode`);
    }
    input.value = "7";
    input.dispatch("input");
    input.dispatch("keydown", { key: "Enter" });
    await Promise.resolve();
    if (!mounted.textContent().includes("171732")) {
      fail(`${exampleName} mounted DOM commit mismatch: ${mounted.textContent()}`);
    }
    if (
      mounted.sourceEventTrace.length < 2 ||
      mounted.sourceEventTrace[0].sourceSlotId !== 0 ||
      mounted.sourceEventTrace[1].sourceSlotId !== 1
    ) {
      fail(`${exampleName} source slot trace mismatch: ${JSON.stringify(mounted.sourceEventTrace)}`);
    }
    if (mounted.renderStats.rootRebuilds !== initialRootRebuilds) {
      fail(`${exampleName} retained DOM rebuilt root after cell edit`);
    }
    if (mounted.renderStats.textPatches < 1 || mounted.renderStats.childListPatches < 1) {
      fail(`${exampleName} retained DOM did not record cell patches: ${JSON.stringify(mounted.renderStats)}`);
    }
  } finally {
    if (originalDocument === undefined) {
      delete globalThis.document;
    } else {
      globalThis.document = originalDocument;
    }
    if (originalLocation === undefined) {
      delete globalThis.location;
    } else {
      globalThis.location = originalLocation;
    }
  }

  console.log(`PASS ${exampleName}`);
}

async function smokeTodoMvcPhysical() {
  const runtimeServerPort = await pickPort();
  const server = spawn(boonBin, [
    "serve-browser",
    "examples/upstream/todo_mvc_physical/RUN.bn",
    "--port",
    `${runtimeServerPort}`,
  ], {
    cwd: process.cwd(),
    stdio: "ignore",
  });
  const storage = new MemoryIndexedDb();
  globalThis.location = { href: `http://127.0.0.1:${runtimeServerPort}/index.html?example=todo_mvc_physical` };
  try {
    await waitForBrowserServer(`http://127.0.0.1:${runtimeServerPort}`);
    const indexResponse = await fetch(`http://127.0.0.1:${runtimeServerPort}/index.html`, { cache: "no-store" });
    if (!indexResponse.ok || !(await indexResponse.text()).includes("mountExampleFromLocation")) {
      fail("todo_mvc_physical integrated host did not serve index.html");
    }
    const moduleResponse = await fetch(`http://127.0.0.1:${runtimeServerPort}/boon-browser.mjs`, { cache: "no-store" });
    if (!moduleResponse.ok || !(await moduleResponse.text()).includes("createHost")) {
      fail("todo_mvc_physical integrated host did not serve boon-browser.mjs");
    }
    const servedManifest = await fetch(`http://127.0.0.1:${runtimeServerPort}/manifest.json`, { cache: "no-store" }).then((response) => response.json());
    if (!servedManifest.physical_render_targets?.Professional) {
      fail("todo_mvc_physical integrated host did not serve manifest.json");
    }
    const host = await createHost({ exampleName: "todo_mvc_physical", storage });
    if (!host.textContent().includes("ProfessionalLight") || !host.textContent().includes("*****")) {
      fail(`todo_mvc_physical initial render mismatch: ${host.textContent()}`);
    }
    await host.setPhysicalTheme("Neobrutalism");
    if (!host.textContent().includes("NeobrutalismLight") || !host.textContent().includes("V,,,,,,,/")) {
      fail(`todo_mvc_physical theme switch mismatch: ${host.textContent()}`);
    }
    await host.togglePhysicalMode();
    if (!host.textContent().includes("NeobrutalismDark")) {
      fail(`todo_mvc_physical mode toggle mismatch: ${host.textContent()}`);
    }
    const resumed = await createHost({ exampleName: "todo_mvc_physical", storage });
    if (!resumed.textContent().includes("NeobrutalismDark")) {
      fail(`todo_mvc_physical persistence mismatch: ${resumed.textContent()}`);
    }
    await resumed.clearState();
    if (!resumed.textContent().includes("ProfessionalLight")) {
      fail(`todo_mvc_physical clear-state mismatch: ${resumed.textContent()}`);
    }
    console.log("PASS todo_mvc_physical");
  } finally {
    delete globalThis.location;
    server.kill("SIGTERM");
  }
}

async function smokeWasmHostBoundary() {
  const dispatchCalls = [];
  const boundary = createWasmHostBoundary({
    sourceBindings: {
      "increment_button.event.press": { sourceSlotId: 42, bindingId: 7 },
    },
    exports: {
      dispatch_source(sourceSlotId, bindingId, payloadTag, payloadScalar) {
        dispatchCalls.push({ sourceSlotId, bindingId, payloadTag, payloadScalar });
      },
    },
  });
  const host = await createHost({
    exampleName: "counter",
    storage: new MemoryIndexedDb(),
    hostBoundary: boundary,
  });
  await host.click("+");

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

async function waitForBrowserServer(baseUrl) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    try {
      const indexResponse = await fetch(`${baseUrl}/index.html`, { cache: "no-store" });
      const physicalResponse = await fetch(`${baseUrl}/__boon/physical-state?example=todo_mvc_physical&theme=Professional&mode=Light`, { cache: "no-store" });
      if (indexResponse.ok && physicalResponse.ok) {
        return;
      }
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  fail(`browser server did not start: ${baseUrl}`);
}

async function main() {
  const filter = process.argv[2];
  if (!filter) {
    fail("browser_smoke.mjs requires a filter argument");
  }
  if (filter === "counter") {
    await smokeCounter();
    return;
  }
  if (filter === "interval") {
    await smokeInterval();
    return;
  }
  if (filter === "todo_mvc") {
    await smokeTodoMvc();
    return;
  }
  if (filter === "cells") {
    await smokeCells("cells");
    return;
  }
  if (filter === "cells_dynamic") {
    await smokeCells("cells_dynamic");
    return;
  }
  if (filter === "todo_mvc_physical") {
    await smokeTodoMvcPhysical();
    return;
  }
  if (filter === "wasm_host_boundary") {
    await smokeWasmHostBoundary();
    return;
  }
  fail(`unsupported browser smoke filter: ${filter}`);
}

await main();
