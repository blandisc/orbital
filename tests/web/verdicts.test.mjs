// C8 y P6 del sistema base (24 nov 2026): la cifra con su veredicto, solo con datos reales, y lo elegido que sobrevive.
import assert from "node:assert/strict";
import test from "node:test";
import { playtimeVerdict } from "../../orbital/web/js/components/game-page.js";
import { collectionVerdict } from "../../orbital/web/js/components/showcase.js";
import { keptFilters } from "../../orbital/web/js/components/list-screen.js";
import { rememberedMap } from "../../orbital/web/js/core/storage.js";

const h = 3600;

test("las horas de un juego dicen cómo van contra los de su consola (y nada si no hay con qué comparar)", () => {
  const games = [{ id: "a", playtime: 62 * h }, { id: "b", playtime: 50 * h }, { id: "c", playtime: 3 * h }, { id: "d", playtime: 2 * h }, { id: "e", playtime: 0 }];
  assert.equal(playtimeVerdict(games[0], games), "Tu más jugado · 12 h más que el segundo");
  assert.equal(playtimeVerdict(games[1], games), "Tu 2.º más jugado");
  assert.equal(playtimeVerdict(games[2], games), "Tu 3.º más jugado");
  assert.equal(playtimeVerdict(games[3], games), null, "del cuarto para abajo no se presume");
  assert.equal(playtimeVerdict(games[4], games), null, "sin jugar, sin veredicto");
  assert.equal(playtimeVerdict(games[0], [games[0]]), null, "solo, no hay con qué comparar");
  assert.equal(playtimeVerdict({ id: "x", playtime: 10 * h }, [{ id: "x", playtime: 10 * h }, { id: "y", playtime: 9.8 * h }]), "Tu más jugado");
});

test("una colección dice cuánto te falta («3 de 12 · te faltan 9») o que ya está completa", () => {
  assert.equal(collectionVerdict(3, 12), "3 de 12 · te faltan 9");
  assert.equal(collectionVerdict(12, 12), "12 de 12 · completa");
  assert.equal(collectionVerdict(0, 12), "0 de 12");
});

test("los filtros guardados de una lista vuelven sin traer basura (y sin almacenamiento, nada)", () => {
  assert.deepEqual(keptFilters("sin-guardar"), {});
});

test("rememberedMap: se usa como un objeto aunque no haya almacenamiento", () => {
  const memory = rememberedMap("orbital.prueba");
  memory.switch = "zelda";
  assert.equal(memory.switch, "zelda");
  delete memory.switch;
  assert.equal(memory.switch, undefined);
});
