// Calibration wizard (PRD §8.6): framing check, 10 ruler-verified 5 cm compressions,
// then the computed watch depth scale and camera cm/px with an accuracy check.
import type { CalibrationResult } from "../calibration/calibrate";
import { CALIBRATION } from "../config";

export type CalibrationStep = "framing" | "compress" | "result";

interface Props {
  step: CalibrationStep;
  cameraVisible: boolean;
  watchStreaming: boolean;
  /** Which sources are being calibrated (decided when compressions start). */
  using: { watch: boolean; camera: boolean };
  counts: { watch: number; camera: number };
  result: CalibrationResult | null;
  saving: boolean;
  error: string | null;
  onBegin: () => void;
  onFinishNow: () => void;
  onSave: () => void;
  onRetry: () => void;
  onCancel: () => void;
}

const N = CALIBRATION.compressions;

function Status({ ok, label }: { ok: boolean; label: string }) {
  return <div className={`cal-status ${ok ? "ok" : "wait"}`}>{ok ? "✅" : "⏳"} {label}</div>;
}

export function CalibrationWizard(p: Props) {
  return (
    <div className="panel cal">
      <h2 className="panel-title">Calibration</h2>
      <ol className="cal-steps">
        <li className={p.step === "framing" ? "active" : "done"}>Framing</li>
        <li className={p.step === "compress" ? "active" : p.step === "result" ? "done" : ""}>5 cm compressions</li>
        <li className={p.step === "result" ? "active" : ""}>Result</li>
      </ol>

      {p.step === "framing" && (
        <>
          <p className="cal-text">Kneel beside the cushion. Your full upper body should be in view of the camera.</p>
          <Status ok={p.cameraVisible} label={p.cameraVisible ? "Arm visible" : "Shoulder, elbow and wrist not all visible yet"} />
          <Status ok={p.watchStreaming} label={p.watchStreaming ? "Watch streaming" : "Watch not streaming (camera only)"} />
          <div className="cal-actions">
            <button className="btn primary" disabled={!p.cameraVisible && !p.watchStreaming} onClick={p.onBegin}>
              Next
            </button>
            <button className="btn" onClick={p.onCancel}>
              Cancel
            </button>
          </div>
        </>
      )}

      {p.step === "compress" && (
        <>
          <p className="cal-text">
            Do {N} compressions that press the cushion down <strong>exactly 5 cm</strong>. Use the ruler. Follow the
            metronome.
          </p>
          {p.using.watch && <Status ok={p.counts.watch >= N} label={`Watch ${Math.min(p.counts.watch, N)} / ${N}`} />}
          {p.using.camera && <Status ok={p.counts.camera >= N} label={`Camera ${Math.min(p.counts.camera, N)} / ${N}`} />}
          <div className="cal-actions">
            <button className="btn" disabled={p.counts.watch < 3 && p.counts.camera < 3} onClick={p.onFinishNow}>
              Finish now
            </button>
            <button className="btn" onClick={p.onCancel}>
              Cancel
            </button>
          </div>
        </>
      )}

      {p.step === "result" && p.result && (
        <>
          {p.result.depthScale !== null && (
            <div className={`cal-result ${p.result.depthScaleOk ? "" : "bad"}`}>
              <div>
                Watch depth scale <strong>×{p.result.depthScale.toFixed(2)}</strong>
              </div>
              {p.result.depthScaleOk && p.result.watchCheck && (
                <div>
                  Watch depth check: {p.result.watchCheck.mean.toFixed(1)} ± {p.result.watchCheck.sd.toFixed(1)} cm
                </div>
              )}
              {!p.result.depthScaleOk && <div>Calibration looks off. Try again.</div>}
            </div>
          )}
          {p.result.cmPerPx !== null && p.result.cameraCheck && (
            <div className="cal-result">
              <div>
                Camera scale <strong>{p.result.cmPerPx.toFixed(3)} cm/px</strong>
              </div>
              <div>
                Camera depth check: {p.result.cameraCheck.mean.toFixed(1)} ± {p.result.cameraCheck.sd.toFixed(1)} cm
              </div>
            </div>
          )}
          {p.error && <div className="error">{p.error}</div>}
          <div className="cal-actions">
            <button
              className="btn primary"
              disabled={p.saving || (!p.result.depthScaleOk && p.result.cmPerPx === null)}
              onClick={p.onSave}
            >
              {p.saving ? "Saving…" : "Save"}
            </button>
            <button className="btn" onClick={p.onRetry}>
              Try again
            </button>
            <button className="btn" onClick={p.onCancel}>
              Cancel
            </button>
          </div>
        </>
      )}
    </div>
  );
}
