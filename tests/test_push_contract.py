"""R14-A / R11-A (4 nov 2026): la forma de los avisos al iPhone en design/addons-contract.json › push. Lo leen las pruebas de
los dos lados. Apagado (PU1-B, Fernando 4 nov: no se paga el programa de Apple): nada lo construye; si un día se retoma,
esto cuida que el acuerdo no se mueva sin que alguien lo note."""

import json
from pathlib import Path

PUSH = json.loads((Path(__file__).resolve().parents[1] / "design" / "addons-contract.json").read_text("utf-8"))["push"]


def test_cada_aviso_usa_llaves_del_catalogo():
    keys = set(PUSH["keys"])
    used = {part.split(" ")[0] for event in PUSH["alerts"]["events"].values() for field in ("title", "body")
            for part in event[field][0].split(" | ")}
    assert used <= keys
    assert "push.activity.title" in keys and len(keys) == len(PUSH["keys"])  # sin repetidas


def test_cada_evento_sale_una_vez_por_su_identificador():
    ids = {name: e["collapse_id"] for name, e in PUSH["alerts"]["events"].items()}
    assert ids["ready"] == "<hash>:ready" and ids["stuck"] == "<hash>:stuck"
    assert ids["expiry"].startswith("expiry:")  # el mismo «<vence>:<etapa>» del ajuste rd_expiry_notice (VE1-A)
    assert len(set(ids.values())) == len(ids)


def test_registro_y_actividad():
    reg = PUSH["register"]
    assert set(reg["body"]) == {"kind", "token", "env", "rd_account", "hash"}
    assert reg["limits"] == {"alert": 1, "activity_start": 1, "activity": 10}
    assert "BadDeviceToken no lo borra" in reg["forget"]
    act = PUSH["activity"]
    assert act["attributes_type"] == "DebridActivityAttributes"
    assert set(act["attributes"]) == {"hash", "title", "label"} and set(act["content_state"]) == {"percent", "state", "line"}
    assert PUSH["alerts"]["headers"]["apns-topic"] == "mx.iracheta.orbital"


def test_apagado_sin_construir():
    assert PUSH["status"] == "parked" and "PU1-B" in PUSH["reason"]
