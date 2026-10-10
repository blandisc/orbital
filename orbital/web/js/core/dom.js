/**
 * Helper mínimo para crear DOM de forma declarativa y segura (sin innerHTML con datos).
 *
 *   h("button", { class: ["button", primary && "button--primary"], onClick }, "Jugar")
 */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === "class") el.className = classNames(value);
    else if (key === "dataset") Object.assign(el.dataset, value);
    else if (key === "style") Object.assign(el.style, value);
    else if (key.startsWith("on") && typeof value === "function") el.addEventListener(key.slice(2).toLowerCase(), value);
    else if (value === true) el.setAttribute(key, "");
    else el.setAttribute(key, value);
  }
  append(el, children);
  return el;
}

export function classNames(value) {
  return (Array.isArray(value) ? value : [value]).filter(Boolean).join(" ");
}

export function append(parent, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    parent.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return parent;
}

/** Reemplaza el contenido de `el` por `children`. */
export function mount(el, ...children) {
  el.replaceChildren();
  return append(el, children);
}

/** Convierte un SVG estático de confianza (de icons.js) en nodo. Nunca con datos del usuario. */
export function svg(markup) {
  const tpl = document.createElement("template");
  tpl.innerHTML = markup.trim();
  return tpl.content.firstElementChild;
}

/** Valor seguro para background-image. */
export const cssUrl = (url) => (url ? `url("${String(url).replace(/["\\\n]/g, "\\$&")}")` : "none");

/**
 * Oculta `el` después de su animación de salida (la clase `leavingClass` la define en CSS).
 * Si no hay animación (movimiento reducido) se oculta igual tras `fallbackMs`.
 * Devuelve una función que cancela la salida (por si se vuelve a mostrar antes de terminar).
 */
export function hideAfterExit(el, leavingClass, fallbackMs = 250) {
  if (el.hidden) return () => {};
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    el.removeEventListener("animationend", onEnd);
    el.classList.remove(leavingClass);
    el.hidden = true;
  };
  const onEnd = (event) => { if (event.target === el) finish(); };
  const timer = setTimeout(finish, fallbackMs);
  el.addEventListener("animationend", onEnd);
  el.classList.add(leavingClass);
  return () => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    el.removeEventListener("animationend", onEnd);
    el.classList.remove(leavingClass);
  };
}
