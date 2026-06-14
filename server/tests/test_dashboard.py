from django.test import Client


def test_dashboard_localhost(client: Client):
    response = client.get("/dashboard/")
    assert response.status_code == 200
    assert b"ai-maxx-ide server" in response.content


def test_dashboard_run_rejects_unknown_script(client: Client):
    response = client.post(
        "/api/dashboard/run/",
        {"script_id": "not-a-real-script"},
        content_type="application/json",
    )
    assert response.status_code == 400
