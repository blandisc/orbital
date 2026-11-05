"""VE1-A (4 nov): el aviso de vencimiento de Real-Debrid que ya salió se guarda como «<vence>:<14|3|0>»."""

from orbital.api.ui import valid_setting


def test_rd_expiry_notice_valido():
    assert valid_setting("rd_expiry_notice", "1800000000:14")
    assert valid_setting("rd_expiry_notice", "0:0")
    assert not valid_setting("rd_expiry_notice", "1800000000:7")
    assert not valid_setting("rd_expiry_notice", 14)
    assert not valid_setting("rd_expiry_notice", "x:3")


def test_cloud_row_hidden_valido():
    """«Ocultar esta fila» (Fernando, 4 nov): cuándo la ocultaste, en segundos; 0 = se ve."""
    assert valid_setting("cloud_row_hidden", 1_800_000_000)
    assert valid_setting("cloud_row_hidden", 0)
    assert not valid_setting("cloud_row_hidden", True)
    assert not valid_setting("cloud_row_hidden", -1)
    assert not valid_setting("cloud_row_hidden", "1800000000")
