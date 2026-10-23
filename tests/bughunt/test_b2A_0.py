def test_public_foryou_list_hides_tv_only_lists(library):
    from fastapi.testclient import TestClient

    from orbital.server import create_app, create_public_app

    main = create_app(library.config, library)
    with TestClient(main, base_url="http://127.0.0.1:8710", client=("127.0.0.1", 1)):
        public = TestClient(create_public_app(library.config, main),
                            base_url="https://legion.ts.net", client=("127.0.0.1", 2))
        auth = {"Authorization": "Bearer secreto"}
        assert public.get("/api/foryou/list", params={"id": "award:oscar"},
                          headers=auth).status_code == 404
