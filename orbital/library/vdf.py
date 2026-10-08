"""Parser mínimo del formato KeyValues (VDF de texto) que usa Steam."""

from __future__ import annotations

_ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"'}


def _tokens(text: str):
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif c == "/" and text.startswith("//", i):
            nl = text.find("\n", i)
            i = n if nl == -1 else nl + 1
        elif c in "{}":
            yield c
            i += 1
        elif c == '"':
            i += 1
            buf = []
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    buf.append(_ESCAPES.get(text[i + 1], text[i + 1]))
                    i += 2
                else:
                    buf.append(text[i])
                    i += 1
            i += 1
            yield ("str", "".join(buf))
        else:
            start = i
            while i < n and not text[i].isspace() and text[i] not in '{}"':
                i += 1
            yield ("str", text[start:i])


def loads(text: str) -> dict:
    """Devuelve un dict anidado. Las claves se normalizan a minúsculas."""
    root: dict = {}
    stack = [root]
    key: str | None = None
    for tok in _tokens(text):
        if tok == "{":
            if key is None:
                raise ValueError("'{' sin clave")
            child: dict = {}
            stack[-1][key] = child
            stack.append(child)
            key = None
        elif tok == "}":
            if len(stack) == 1:
                raise ValueError("'}' sin abrir")
            stack.pop()
        else:
            value = tok[1]
            if key is None:
                key = value.lower()
            else:
                stack[-1][key] = value
                key = None
    return root
