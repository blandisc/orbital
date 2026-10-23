from orbital import downloads


def test_saving_a_title_with_a_lone_surrogate_does_not_escape(tmp_path):
    dl = downloads.Downloads(tmp_path, resolve=lambda job: ("", ""),
                             publish=lambda e: None, autostart=False)
    dl._jobs["x"] = {"id": "x", "kind": "movie", "meta_id": "tt1", "video_id": "tt1",
                     "title": "Malo\ud800", "name": "Malo", "status": "queued",
                     "size": 0, "done": 0, "added": 0.0}
    dl._save()
