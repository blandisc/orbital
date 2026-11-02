import { storage } from "./storage.js";

/** «Para hoy» (el ★ del mazo «¿Qué vemos hoy?», como el iPhone): la que elegiste hoy va primera en Mi lista hasta que cambie el
 * día. Se guarda en este aparato: { meta_id, day }. */
export const TONIGHT = "match-tonight";

export const today = (now = new Date()) => `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`;

/** La que elegiste «Para hoy», si fue hoy (si no, null). */
export function tonightPick(saved = storage.get(TONIGHT, null), now = new Date()) {
  return saved?.day === today(now) ? saved.meta_id : null;
}
