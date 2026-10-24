// Webcam video with the pose skeleton overlay drawn on a canvas on top.
import { forwardRef } from "react";
import type { CameraStatus } from "../pose/cameraPipeline";

interface Props {
  status: CameraStatus;
  error: string | null;
  canvasRef: React.Ref<HTMLCanvasElement>;
}

export const CameraView = forwardRef<HTMLVideoElement, Props>(function CameraView({ status, error, canvasRef }, videoRef) {
  return (
    <div className="camera">
      <video ref={videoRef} muted playsInline />
      <canvas ref={canvasRef} />
      {status !== "on" && (
        <div className="camera-msg">
          {status === "starting" && "Starting camera and pose model…"}
          {status === "off" && "Camera off — press C"}
          {status === "error" && `Camera error: ${error ?? "unknown"}`}
        </div>
      )}
    </div>
  );
});
