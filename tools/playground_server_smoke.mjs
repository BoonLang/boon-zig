import { spawn } from "node:child_process";
import { resolve } from "node:path";
import net from "node:net";

const boonBin = resolve(process.cwd(), "zig-out", "bin", "boon-zig");

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function pickPort() {
  return await new Promise((resolvePort, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("failed to pick playground smoke port")));
        return;
      }
      const port = address.port;
      server.close((error) => {
        if (error) reject(error);
        else resolvePort(port);
      });
    });
  });
}

async function waitForServer(baseUrl) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/index.html?playground=1`, { cache: "no-store" });
      if (response.ok && (await response.text()).includes("playground-browser.mjs")) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  fail(`playground server did not start: ${baseUrl}`);
}

const source = `increment_button: [event: [press: SOURCE]]

counter: 0 |> HOLD counter {
    increment_button.event.press |> THEN { counter + 1 }
}
`;

const port = await pickPort();
const server = spawn(boonBin, [
  "serve-browser",
  "examples/upstream/todo_mvc/todo_mvc.bn",
  "--port",
  `${port}`,
], {
  cwd: process.cwd(),
  stdio: "ignore",
});

try {
  const baseUrl = `http://127.0.0.1:${port}`;
  await waitForServer(baseUrl);
  const response = await fetch(`${baseUrl}/__boon/playground/compile`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      exampleName: "counter",
      sourcePath: "examples/source_physical/counter/counter.bn",
      source,
      target: "native-preview",
    }),
  });
  const payload = await response.json();
  if (!response.ok || !payload.ok) {
    fail(`served playground compile failed: ${JSON.stringify(payload)}`);
  }
  if (!payload.generatedZig.includes("semantic_source_map") || !payload.previewStdout.includes("state[0]=number:0")) {
    fail(`served playground compile payload mismatch: ${JSON.stringify(payload)}`);
  }
  const manifest = await fetch(`${baseUrl}/manifest.json`, { cache: "no-store" }).then((manifestResponse) => manifestResponse.json());
  if (manifest.playground?.active_compiler_path !== "local-zig") {
    fail(`playground manifest mismatch: ${JSON.stringify(manifest.playground)}`);
  }
  console.log("PASS served playground compile");
} finally {
  server.kill("SIGTERM");
}
