import assert from "node:assert/strict";
import test from "node:test";
import { swipeSteps } from "../../orbital/web/js/core/swipe.js";

test("deslizar: un paso por tarjeta recorrida, al menos uno, en cualquier sentido", () => {
  assert.equal(swipeSteps(50, 200), 1);
  assert.equal(swipeSteps(-450, 200), 2);
  assert.equal(swipeSteps(600, 0), 600); // tamaño 0: no divide entre cero
});
