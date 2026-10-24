import { describe, expect, it } from "vitest";
import { matchCommand } from "../voice/commands";

describe("matchCommand", () => {
  it("understands English commands", () => {
    expect(matchCommand("okay swap", "en")).toBe("swap");
    expect(matchCommand("How am I doing?", "en")).toBe("status");
    expect(matchCommand("how long have I been going", "en")).toBe("time");
    expect(matchCommand("stop", "en")).toBe("stop");
  });
  it("never stops on 'don't stop' or matches inside words", () => {
    expect(matchCommand("don't stop", "en")).toBeNull();
    expect(matchCommand("I know", "en")).toBeNull();
  });
  it("only hears 'done' during breaths", () => {
    expect(matchCommand("done", "en")).toBeNull();
    expect(matchCommand("done", "en", true)).toBe("done");
  });
  it("works in other languages", () => {
    expect(matchCommand("cambio", "es")).toBe("swap");
    expect(matchCommand("不要停", "zh")).toBeNull();
    expect(matchCommand("换人", "zh")).toBe("swap");
    expect(matchCommand("얼마나 됐어", "ko")).toBe("time");
    expect(matchCommand("रुको", "hi")).toBe("stop");
  });
});
