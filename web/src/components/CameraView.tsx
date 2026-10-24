// Webcam with the pose overlay on a canvas; a calm placeholder when the camera isn't running.
import { Camera, CameraOff } from "lucide-react";
import { forwardRef } from "react";
import { t } from "../i18n";
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
        <div className="camera-empty">
          {status === "starting" ? <Camera size={32} aria-hidden="true" /> : <CameraOff size={32} aria-hidden="true" />}
          <p className="camera-empty-title">
            {status === "starting" ? t("Starting camera") : status === "error" ? t("Camera unavailable") : t("Camera off")}
          </p>
          <p className="camera-empty-body">
            {status === "starting"
              ? t("Loading the pose model…")
              : status === "error"
                ? t("%@. Allow camera access for this page, then press C.", error ?? t("Unknown error"))
                : t("Press C to turn it on. Posture coaching needs a side view.")}
          </p>
        </div>
      )}
    </div>
  );
});
