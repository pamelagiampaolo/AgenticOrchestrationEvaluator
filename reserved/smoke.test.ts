import { add } from "../submission/src/arithmetic.ts";

describe("reserved evaluator smoke control", () => {
  test("accepts the known-good frozen fixture", () => {
    expect(add(19, 23)).toBe(42);
  });
});
