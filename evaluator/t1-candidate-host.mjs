import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import net from "node:net";
import { pathToFileURL } from "node:url";
const [pipeName, modulePath] = process.argv.slice(2);
if (!pipeName || !modulePath) process.exit(20);
const socket = net.createConnection(`\\\\.\\pipe\\${pipeName}`);
let input = "";
socket.setEncoding("utf8");
socket.on("data", async (chunk) => {
  input += chunk;
  const newline = input.indexOf("\n");
  if (newline < 0) return;
  socket.pause();
  try {
    const request = JSON.parse(input.slice(0, newline));
    const { InventoryManagement } = await import(pathToFileURL(modulePath).href);
    const queryResult = new InventoryManagement(request.products).findProductsBelowStock(request.threshold);
    let accessProbe = { denied: false, code: null };
    try { readFileSync(request.reservedProbePath, "utf8"); }
    catch (error) { accessProbe = { denied: error?.code === "EACCES" || error?.code === "EPERM", code: error?.code ?? null }; }
    const identity = execFileSync("whoami.exe", { encoding: "utf8" }).trim();
    socket.end(`${JSON.stringify({ queryResult, accessProbe, identity })}\n`);
  } catch (error) { socket.end(`${JSON.stringify({ candidateError: error?.message ?? String(error) })}\n`); }
});
socket.on("error", () => process.exit(21));
