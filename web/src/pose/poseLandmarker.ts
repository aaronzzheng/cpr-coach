// MediaPipe PoseLandmarker setup: local model and wasm (works offline), GPU with CPU fallback.
import { FilesetResolver, PoseLandmarker } from "@mediapipe/tasks-vision";
import { POSE } from "../config";

export async function createPoseLandmarker(): Promise<PoseLandmarker> {
  const fileset = await FilesetResolver.forVisionTasks(POSE.wasmPath);
  const make = (delegate: "GPU" | "CPU") =>
    PoseLandmarker.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: POSE.modelPath, delegate },
      runningMode: "VIDEO",
      numPoses: 1,
    });
  try {
    return await make("GPU");
  } catch (err) {
    console.warn("PoseLandmarker GPU delegate failed, falling back to CPU", err);
    return make("CPU");
  }
}

export { PoseLandmarker };
