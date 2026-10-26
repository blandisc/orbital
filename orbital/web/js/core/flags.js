// Generado por scripts/flags.py desde orbital/flags.py: no lo edites a mano.
/** El idioma («es-419», «eng»…) y lo que dice la pista («Latino») → el archivo de su bandera, o null. */
const LANG_FLAGS = { "chi": "cn", "de": "de", "deu": "de", "dut": "nl", "en": "us", "en-gb": "gb", "en-uk": "gb", "en-us": "us", "eng": "us", "es-419": "mx", "es-es": "es", "es-la": "mx", "es-mx": "mx", "es-us": "mx", "fr": "fr", "fra": "fr", "fre": "fr", "ger": "de", "hi": "in", "hin": "in", "it": "it", "ita": "it", "ja": "jp", "jpn": "jp", "ko": "kr", "kor": "kr", "nl": "nl", "nld": "nl", "pl": "pl", "pob": "br", "pol": "pl", "por": "br", "pt": "br", "pt-br": "br", "pt-pt": "pt", "ru": "ru", "rus": "ru", "tr": "tr", "tur": "tr", "uk": "ua", "ukr": "ua", "zh": "cn", "zho": "cn" };
const LATINO = ["latino", "latin", "latam", "419", "méxico", "mexico", "hispanoam"];
const CASTELLANO = ["castellano", "castilian", "españa", "spain", "european", "europe"];
const PORTUGAL = ["portugal", "european", "europeu", "pt-pt"];
export function flagFor(code, hint = "") {
  const c = String(code || "").trim().toLowerCase().replace("_", "-");
  const said = String(hint || "").toLowerCase();
  if (c === "es" || c === "spa" || c.startsWith("es-")) {
    if (LANG_FLAGS[c]) return LANG_FLAGS[c];
    if (CASTELLANO.some((w) => said.includes(w)) && !LATINO.some((w) => said.includes(w))) return "es";
    return "mx"; // latino, o un español que no dice cuál
  }
  if ((c === "pt" || c === "por") && PORTUGAL.some((w) => said.includes(w))) return "pt";
  return LANG_FLAGS[c] || LANG_FLAGS[c.split("-")[0]] || null;
}
