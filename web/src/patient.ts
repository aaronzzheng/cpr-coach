// Who is being resuscitated: same rate for everyone, depth targets by age (AHA: about 5 cm adult
// and child, 4 cm infant). Mirrors PatientProfile on the phone and PATIENT_DEPTH_CM on the backend.
import { COACH, TARGETS } from "./config";

export type Patient = "adult" | "child" | "infant";

const DEPTH: Record<Patient, [number, number]> = {
  adult: [TARGETS.depth_min_cm, TARGETS.depth_max_cm],
  child: [4.5, 5.5],
  infant: [3.5, 4.5],
};
const TOO_DEEP: Record<Patient, number> = { adult: COACH.tooDeepCm, child: 6.0, infant: 5.0 };

let current: Patient = "adult";

export const patient = () => current;
export const setPatient = (p: Patient) => (current = p);
export const depthMin = () => DEPTH[current][0];
export const depthMax = () => DEPTH[current][1];
export const tooDeepCm = () => TOO_DEEP[current];

/** Depth within this of the band counts as on target (about the measurement error). */
export const DEPTH_TOLERANCE_CM = 0.3;
export const depthOkMin = () => depthMin() - DEPTH_TOLERANCE_CM;
export const depthOkMax = () => depthMax() + DEPTH_TOLERANCE_CM;
