"""VE1-A (4 nov): el aviso de vencimiento de Real-Debrid que ya salió se guarda como «<vence>:<14|3|0>»."""

from orbital.api.ui import valid_setting


def test_rd_expiry_notice_valido():
    assert valid_setting("rd_expiry_notice", "1800000000:14")
    assert valid_setting("rd_expiry_notice", "0:0")
    assert not valid_setting("rd_expiry_notice", "1800000000:7")
    assert not valid_setting("rd_expiry_notice", 14)
    assert not valid_setting("rd_expiry_notice", "x:3")
