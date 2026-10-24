// Copies MediaPipe's wasm runtime into public/ so pose works offline (no CDN at demo time).
import { cpSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "node_modules", "@mediapipe", "tasks-vision", "wasm");
const dst = join(root, "public", "wasm");
mkdirSync(dst, { recursive: true });
cpSync(src, dst, { recursive: true });
console.log(`copied mediapipe wasm -> ${dst}`);
