from orbital import downloads


def test_a_job_with_size_but_no_done_does_not_break_the_list(tmp_path):
    (tmp_path / downloads.INDEX_NAME).write_text(
        '[{"id": "x", "status": "queued", "size": 100}]', encoding="utf-8")
    dl = downloads.Downloads(tmp_path, resolve=lambda job: ("", ""),
                             publish=lambda e: None, autostart=False)
    assert dl.list()[0]["id"] == "x"
