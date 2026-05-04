#!/usr/bin/env node
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");

const webDir = process.argv[2] || "zig-out/web";
const screenshotPath = process.argv[3] || "zig-out/verification/browser_canvas/run_playground_web.png";
const reportPath = process.argv[4] || "zig-out/reports/browser_canvas_smoke.json";
const visualReportPath = process.argv[5] || "zig-out/reports/browser_canvas_visual.json";
const minPhysicalPreviewPixels = 200000;
const smokeWindowSize = "1940,1100";
let reportWritten = false;

main().catch((err) => {
  if (!reportWritten) writeReport("BLOCKED", err && err.message ? err.message : String(err), {});
  process.exit(1);
});

async function main() {
  if (!fs.existsSync(path.join(webDir, "boon-playground-raybox.html"))) {
    throw new Error(`missing web build in ${webDir}`);
  }
  fs.mkdirSync(path.dirname(screenshotPath), { recursive: true });
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });

  const chrome = findChrome();
  const server = await startServer(webDir);
  try {
    const url = `http://127.0.0.1:${server.port}/boon-playground-raybox.html`;
    const bridge = await readTestBridge(chrome, url);
    if (!bridge.ready) throw new Error("window.__rayboxTest did not report ready");
    if (bridge.diagnostics !== 0) throw new Error(`window.__rayboxTest reported ${bridge.diagnostics} diagnostics`);
    if (bridge.traceCommands < 10) throw new Error(`render trace is too small: ${bridge.traceCommands} commands`);
    if (bridge.semanticInputs < 1) throw new Error("semantic tree is missing text inputs");
    if (bridge.semanticButtons < 4) throw new Error(`semantic tree has too few buttons: ${bridge.semanticButtons}`);
    for (const method of ["runExample", "clearState", "dispatch", "semanticTree", "renderTrace", "frameStats", "screenshotPng"]) {
      if (!bridge.methods.includes(method)) throw new Error(`window.__rayboxTest is missing ${method}`);
    }
    const expectedBridge = await verifyPhysicalExpectedBridge(chrome, url);
    const canvasShot = await captureReadyCanvas(chrome, url, screenshotPath);
    const visual = analyzeScreenshot(screenshotPath);
    writeReport("DONE", "browser canvas smoke passed", {
      screenshot: screenshotPath,
      screenshot_bytes: canvasShot.bytes,
      screenshot_data_url_bytes: canvasShot.dataUrlBytes,
      width: visual.width,
      height: visual.height,
      distinct_colors: visual.distinct_colors,
      non_black_pixels: visual.non_black_pixels,
      clay_shell_pixels: visual.clay_shell_pixels,
      physical_preview_pixels: visual.physical_preview_pixels,
      min_physical_preview_pixels: minPhysicalPreviewPixels,
      test_bridge_ready: bridge.ready,
      test_bridge_diagnostics: bridge.diagnostics,
      test_bridge_trace_commands: bridge.traceCommands,
      test_bridge_semantic_inputs: bridge.semanticInputs,
      test_bridge_semantic_buttons: bridge.semanticButtons,
      test_bridge_semantic_checkboxes: bridge.semanticCheckboxes,
      test_bridge_methods: bridge.methods,
      expected_bridge_example: expectedBridge.example,
      expected_bridge_sequences: expectedBridge.sequences,
      expected_bridge_actions: expectedBridge.actions,
      expected_bridge_render_commands: expectedBridge.renderCommands,
    });
  } finally {
    const closing = new Promise((resolve) => server.http.close(resolve));
    if (typeof server.http.closeAllConnections === "function") server.http.closeAllConnections();
    await closing;
  }
}

function readVisualReport() {
  if (!fs.existsSync(visualReportPath)) {
    throw new Error(`missing visual smoke report: ${visualReportPath}`);
  }
  return JSON.parse(fs.readFileSync(visualReportPath, "utf8"));
}

function validateVisualReport(visual) {
  if (visual.status !== "DONE") throw new Error(`browser visual smoke did not complete: ${visual.message || visual.status}`);
  if (visual.runtime_failure_seen) throw new Error("browser console reported a runtime failure");
  if (visual.distinct_colors < 8) throw new Error(`browser canvas appears blank: only ${visual.distinct_colors} distinct colors`);
  if (visual.non_black_pixels < 500000) throw new Error(`browser canvas has too few non-black pixels: ${visual.non_black_pixels}`);
  if (visual.clay_shell_pixels < 10000) throw new Error(`browser canvas is missing the Clay shell color bands: ${visual.clay_shell_pixels}`);
  if (visual.physical_preview_pixels < minPhysicalPreviewPixels) {
    throw new Error(`browser canvas is missing the Boon physical preview projection: ${visual.physical_preview_pixels}`);
  }
}

function analyzeScreenshot(filePath) {
  const result = spawnSync("convert", [filePath, "-format", "%c", "histogram:info:-"], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`failed to analyze ready browser screenshot: ${result.stderr || result.stdout}`);
  const stats = {
    width: 0,
    height: 0,
    distinct_colors: 0,
    non_black_pixels: 0,
    clay_shell_pixels: 0,
    physical_preview_pixels: 0,
  };
  const identify = spawnSync("identify", ["-format", "%w %h", filePath], { encoding: "utf8" });
  if (identify.status === 0) {
    const [width, height] = identify.stdout.trim().split(/\s+/).map((value) => Number.parseInt(value, 10));
    stats.width = width || 0;
    stats.height = height || 0;
  }
  for (const rawLine of result.stdout.split(/\n/)) {
    const line = rawLine.trim();
    const match = line.match(/^([0-9]+): \(([^)]*)\)/);
    if (!match) continue;
    const count = Number.parseInt(match[1], 10);
    const parts = match[2].split(",").slice(0, 3).map((value) => Number.parseInt(value.trim(), 10));
    if (parts.length < 3 || parts.some((value) => !Number.isFinite(value))) continue;
    const [r, g, b] = parts;
    stats.distinct_colors += 1;
    if (r !== 0 || g !== 0 || b !== 0) stats.non_black_pixels += count;
    if (closeColor(r, g, b, 36, 40, 48) || closeColor(r, g, b, 28, 32, 38) || closeColor(r, g, b, 45, 53, 65)) {
      stats.clay_shell_pixels += count;
    }
    if (closeColor(r, g, b, 245, 242, 237) || closeColor(r, g, b, 255, 252, 247) || closeColor(r, g, b, 199, 107, 59) || closeColor(r, g, b, 82, 133, 217)) {
      stats.physical_preview_pixels += count;
    }
  }
  validateVisualReport({ ...stats, status: "DONE", runtime_failure_seen: false });
  return stats;
}

function closeColor(r, g, b, er, eg, eb) {
  return Math.abs(r - er) <= 12 && Math.abs(g - eg) <= 12 && Math.abs(b - eb) <= 12;
}

async function captureReadyCanvas(chrome, url, outPath) {
  const cdp = await launchCdpChrome(chrome, url);
  try {
    await waitForCdpTestBridge(cdp);
    await waitForBridgeIdle(cdp);
    const screenshot = await cdp.send("Page.captureScreenshot", { format: "png", fromSurface: true });
    if (!screenshot || typeof screenshot.data !== "string" || screenshot.data.length === 0) {
      throw new Error("Chrome did not return a ready-page screenshot");
    }
    const bytes = Buffer.from(screenshot.data, "base64");
    if (bytes.length < 16 * 1024) throw new Error(`ready browser canvas screenshot is too small: ${bytes.length} bytes`);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, bytes);
    return { bytes: bytes.length, dataUrlBytes: screenshot.data.length };
  } finally {
    await cdp.close();
  }
}

async function verifyPhysicalExpectedBridge(chrome, url) {
  const expected = parsePhysicalExpected("examples/upstream/todo_mvc_physical/todo_mvc_physical.expected");
  const cdp = await launchCdpChrome(chrome, url);
  try {
    await waitForCdpTestBridge(cdp);
    await evaluate(cdp, `window.__rayboxTest.clearState("todo_mvc_physical")`);
    await waitForBridgeIdle(cdp);
    let actionCount = 0;
    for (const step of expected) {
      for (const action of step.actions) {
        await runExpectedBridgeAction(cdp, action, step.description);
        actionCount += 1;
      }
      if (step.expect) {
        const text = await renderedText(cdp);
        if (!normalizeVisible(text).includes(normalizeVisible(step.expect))) {
          throw new Error(`${step.description}: expected browser bridge text to contain ${JSON.stringify(step.expect)}; actual ${JSON.stringify(text.slice(0, 500))}`);
        }
      }
    }
    const renderTrace = await evaluate(cdp, `window.__rayboxTest.renderTrace()`);
    if (!renderTrace || !Array.isArray(renderTrace.commands) || renderTrace.commands.length < 10) {
      throw new Error("browser bridge renderTrace returned an empty or incomplete command list");
    }
    return {
      example: "todo_mvc_physical",
      sequences: expected.length,
      actions: actionCount,
      renderCommands: renderTrace.commands.length,
    };
  } finally {
    await cdp.close();
  }
}

async function waitForCdpTestBridge(cdp) {
  const started = Date.now();
  while (Date.now() - started < 30000) {
    try {
      const ready = await evaluate(cdp, `!!(window.__rayboxTest && window.__rayboxTest.ready && window.__rayboxTest.ready())`);
      if (ready) return;
    } catch (err) {
      if (!/Execution context was destroyed|Cannot find context/i.test(err.message || String(err))) throw err;
    }
    await sleep(100);
  }
  throw new Error("timed out waiting for window.__rayboxTest");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parsePhysicalExpected(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const parts = text.split(/\n\[\[sequence\]\]\s*\n/).slice(1);
  const sequences = [];
  for (const part of parts) {
    const description = jsonStringAssignment(part, "description") || "unnamed sequence";
    const actionsStart = part.indexOf("actions");
    if (actionsStart < 0) throw new Error(`${filePath}: ${description} is missing actions`);
    const arrayStart = part.indexOf("[", actionsStart);
    const actions = JSON.parse(extractJsonArray(part, arrayStart));
    const expect = jsonStringAssignment(part, "expect") || "";
    sequences.push({ description, actions, expect });
  }
  if (sequences.length === 0) throw new Error(`${filePath}: no [[sequence]] blocks found`);
  return sequences;
}

function jsonStringAssignment(text, name) {
  const re = new RegExp(`${name}\\s*=\\s*("(?:(?:\\\\.)|[^"\\\\])*")`);
  const match = text.match(re);
  return match ? JSON.parse(match[1]) : null;
}

function extractJsonArray(text, start) {
  if (start < 0 || text[start] !== "[") throw new Error("expected JSON array");
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i += 1) {
    const ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === "\"") {
        inString = false;
      }
      continue;
    }
    if (ch === "\"") {
      inString = true;
    } else if (ch === "[") {
      depth += 1;
    } else if (ch === "]") {
      depth -= 1;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  throw new Error("unterminated JSON array in expected file");
}

async function runExpectedBridgeAction(cdp, action, description) {
  const name = action[0];
  if (name === "assert_focused") {
    const index = Number(action[1] || 0);
    const semantic = await semanticTree(cdp);
    if (!semantic.inputs[index] || !semantic.inputs[index].focused) throw new Error(`${description}: assert_focused failed`);
    return;
  }
  if (name === "assert_input_typeable") {
    const index = Number(action[1] || 0);
    const semantic = await semanticTree(cdp);
    if (!semantic.inputs[index] || semantic.inputs[index].disabled) throw new Error(`${description}: assert_input_typeable failed`);
    return;
  }
  if (name === "assert_not_contains") {
    const text = await renderedText(cdp);
    if (normalizeVisible(text).includes(normalizeVisible(String(action[1] || "")))) throw new Error(`${description}: assert_not_contains failed for ${JSON.stringify(action[1])}`);
    return;
  }
  if (name === "assert_button_has_outline") {
    const label = String(action[1] || "");
    const semantic = await semanticTree(cdp);
    if (!semantic.buttons.some((button) => button.outlined && button.label.includes(label))) {
      throw new Error(`${description}: assert_button_has_outline failed for ${JSON.stringify(label)}`);
    }
    return;
  }

  let bridgeAction;
  if (name === "type") bridgeAction = { type: "type", text: String(action[1] || "") };
  else if (name === "key") bridgeAction = { type: "key", key: String(action[1] || "") };
  else if (name === "click_checkbox") bridgeAction = { type: "click_checkbox", index: Number(action[1] || 0), checked: true };
  else if (name === "click_text") bridgeAction = { type: "click_text", text: String(action[1] || "") };
  else if (name === "wait") bridgeAction = { type: "wait", ms: Number(action[1] || 0) };
  else if (name === "clear_states") bridgeAction = { type: "clear_states" };
  else if (name === "run") bridgeAction = { type: "run" };
  else throw new Error(`${description}: unsupported browser expected action ${name}`);

  const before = await evaluate(cdp, `window.__rayboxTest.frameStats().frames`);
  await evaluate(cdp, `window.__rayboxTest.dispatch(${JSON.stringify(bridgeAction)})`);
  await waitForBridgeIdle(cdp, before);
  const diagnostics = await evaluate(cdp, `window.__rayboxTest.diagnostics()`);
  if (Array.isArray(diagnostics) && diagnostics.length !== 0) {
    throw new Error(`${description}: browser bridge diagnostics after ${name}: ${diagnostics.join("; ")}`);
  }
}

function normalizeVisible(text) {
  return String(text).replace(/\s+/g, "").toLowerCase();
}

async function semanticTree(cdp) {
  const tree = await evaluate(cdp, `window.__rayboxTest.semanticTree()`);
  if (!tree || typeof tree.renderedText !== "string") throw new Error("browser bridge returned invalid semantic tree");
  return tree;
}

async function renderedText(cdp) {
  return (await semanticTree(cdp)).renderedText;
}

async function waitForBridgeIdle(cdp, initialFrame = null) {
  return await evaluate(cdp, `
    new Promise((resolve, reject) => {
      const started = performance.now();
      const startFrame = ${initialFrame == null ? "(window.__rayboxTest && window.__rayboxTest.frameStats ? window.__rayboxTest.frameStats().frames : 0)" : JSON.stringify(initialFrame)};
      let scheduled = false;
      function tick() {
        scheduled = false;
        const state = window.__rayboxState;
        const queue = window.__rayboxBridgeQueue || [];
        const frames = state && state.frameStats ? state.frameStats.frames : 0;
        if (window.__rayboxTest && queue.length === 0 && frames > startFrame) {
          resolve(window.__rayboxTest.snapshot());
          return;
        }
        if (performance.now() - started > 30000) {
          reject(new Error("timed out waiting for browser bridge action"));
          return;
        }
        if (!scheduled) {
          scheduled = true;
          requestAnimationFrame(tick);
          setTimeout(tick, 50);
        }
      }
      tick();
    })
  `);
}

async function launchCdpChrome(chrome, url) {
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "raybox-chrome-cdp-"));
  const port = await getFreePort();
  // This is a headless browser launch. Visible/manual browser launches from
  // repo tools must use `cosmic-background-launch -- <browser> ...`.
  const child = spawn(chrome, [
    "--headless=new",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--enable-unsafe-swiftshader",
    "--use-angle=swiftshader",
    "--allow-file-access-from-files",
    `--window-size=${smokeWindowSize}`,
    `--user-data-dir=${userDataDir}`,
    `--remote-debugging-port=${port}`,
    url,
  ], { stdio: ["ignore", "ignore", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString("utf8");
  });
  child.on("error", () => {});
  const page = await pollJson(`http://127.0.0.1:${port}/json/list`, 30000).then((pages) => pages.find((item) => item.type === "page") || pages[0]);
  if (!page || !page.webSocketDebuggerUrl) {
    child.kill("SIGTERM");
    fs.rmSync(userDataDir, { recursive: true, force: true });
    throw new Error(`Chrome CDP did not expose a page target: ${stderr}`);
  }
  const client = await connectCdp(page.webSocketDebuggerUrl);
  return {
    send: client.send,
    async close() {
      try {
        await client.send("Browser.close");
      } catch {}
      child.kill("SIGTERM");
      client.close();
      rmSyncRetry(userDataDir);
    },
  };
}

function rmSyncRetry(dir) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
      return;
    } catch (err) {
      const until = Date.now() + 25;
      while (Date.now() < until) {}
      if (attempt === 19) throw err;
    }
  }
}

function pollJson(url, timeoutMs) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      http.get(url, (res) => {
        let body = "";
        res.on("data", (chunk) => {
          body += chunk.toString("utf8");
        });
        res.on("end", () => {
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            retry(err);
          }
        });
      }).on("error", retry);
    };
    const retry = (err) => {
      if (Date.now() - started > timeoutMs) {
        reject(err);
      } else {
        setTimeout(tick, 100);
      }
    };
    tick();
  });
}

function connectCdp(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let nextId = 1;
    const pending = new Map();
    const timer = setTimeout(() => reject(new Error("timed out connecting to Chrome CDP")), 8000);
    ws.addEventListener("open", () => {
      clearTimeout(timer);
      resolve({
        send(method, params = {}) {
          const id = nextId++;
          ws.send(JSON.stringify({ id, method, params }));
          return new Promise((res, rej) => {
            const timer = setTimeout(() => {
              pending.delete(id);
              rej(new Error(`Chrome CDP command timed out: ${method}`));
            }, 60000);
            pending.set(id, {
              resolve(value) {
                clearTimeout(timer);
                res(value);
              },
              reject(err) {
                clearTimeout(timer);
                rej(err);
              },
            });
          });
        },
        close() {
          for (const entry of pending.values()) entry.reject(new Error("CDP connection closed"));
          pending.clear();
          ws.close();
        },
      });
    });
    ws.addEventListener("error", (event) => {
      clearTimeout(timer);
      reject(new Error(`Chrome CDP websocket error: ${event.message || "unknown error"}`));
    });
    ws.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (!message.id || !pending.has(message.id)) return;
      const entry = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) entry.reject(new Error(message.error.message || JSON.stringify(message.error)));
      else entry.resolve(message.result);
    });
  });
}

async function evaluate(cdp, expression) {
  const result = await cdp.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });
  if (result.exceptionDetails) {
    const text = result.exceptionDetails.exception && result.exceptionDetails.exception.description
      ? result.exceptionDetails.exception.description
      : result.exceptionDetails.text;
    throw new Error(text);
  }
  return result.result ? result.result.value : undefined;
}

async function readTestBridge(chrome, url) {
  const cdp = await launchCdpChrome(chrome, url);
  try {
    await waitForCdpTestBridge(cdp);
    return await evaluate(cdp, `({
      ready: window.__rayboxTest.ready(),
      diagnostics: window.__rayboxTest.diagnostics().length,
      traceCommands: window.__rayboxTest.renderTrace().commands.length,
      semanticInputs: window.__rayboxTest.semanticTree().inputs.length,
      semanticButtons: window.__rayboxTest.semanticTree().buttons.length,
      semanticCheckboxes: window.__rayboxTest.semanticTree().checkboxes.length,
      methods: Object.keys(window.__rayboxTest).filter((key) => typeof window.__rayboxTest[key] === "function"),
    })`);
  } finally {
    await cdp.close();
  }
}

function attrText(html, name) {
  const pattern = new RegExp(`${name}="([^"]*)"`);
  const match = html.match(pattern);
  if (!match) throw new Error(`browser test bridge did not expose ${name}`);
  return match[1];
}

function attrInt(html, name) {
  const pattern = new RegExp(`${name}="([0-9]+)"`);
  const match = html.match(pattern);
  if (!match) throw new Error(`browser test bridge did not expose ${name}`);
  return Number.parseInt(match[1], 10);
}

function runChrome(chrome, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(chrome, args, { stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error("chrome timed out during browser canvas smoke"));
    }, 20000);
    child.stdout.on("data", (chunk) => {
      output += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      output += chunk.toString("utf8");
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("exit", (status, signal) => {
      clearTimeout(timer);
      if (signal) {
        resolve({ status: 1, output: `${output}\nchrome terminated by ${signal}` });
      } else {
        resolve({ status: status || 0, output });
      }
    });
  });
}

function findChrome() {
  const envChrome = process.env.RAYBOX_CHROME;
  const candidates = envChrome
    ? [envChrome]
    : ["google-chrome", "chromium-browser", "chromium", "/usr/bin/google-chrome", "/usr/bin/chromium-browser", "/snap/bin/chromium"];
  for (const candidate of candidates) {
    if (candidate.includes("/")) {
      if (fs.existsSync(candidate)) return candidate;
      continue;
    }
    const result = spawnSync("command", ["-v", candidate], { shell: true, encoding: "utf8" });
    const resolved = result.stdout.trim();
    if (result.status === 0 && resolved.length !== 0) return resolved;
  }
  throw new Error("no Chrome/Chromium executable found for browser canvas smoke");
}

async function startServer(root) {
  const server = http.createServer((req, res) => {
    const rawUrl = req.url === "/" ? "/boon-playground-raybox.html" : req.url || "/";
    const urlPath = decodeURIComponent(rawUrl.split("?")[0]);
    const filePath = path.resolve(root, `.${urlPath}`);
    if (!filePath.startsWith(path.resolve(root))) {
      res.writeHead(403);
      res.end("forbidden");
      return;
    }
    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(404);
        res.end("not found");
        return;
      }
      res.writeHead(200, { "content-type": contentType(filePath) });
      res.end(data);
    });
  });
  const port = await getFreePort();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });
  return { http: server, port };
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
    srv.once("error", reject);
  });
}

function contentType(filePath) {
  if (filePath.endsWith(".html")) return "text/html";
  if (filePath.endsWith(".js")) return "text/javascript";
  if (filePath.endsWith(".wasm")) return "application/wasm";
  return "application/octet-stream";
}

function writeReport(status, message, extra) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify({ status, message, ...extra }, null, 2)}\n`);
  reportWritten = true;
}
