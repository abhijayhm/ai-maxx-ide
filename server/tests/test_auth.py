import pytest
from django.test import Client
from rest_framework.test import APIClient

from core.utils.hashing import compute_device_hash


@pytest.mark.django_db
def test_health_no_auth():
    client = Client()
    resp = client.get("/api/health/")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


@pytest.mark.django_db
def test_invalid_api_key(api_key, device_hash):
    client = APIClient()
    client.credentials(
        HTTP_X_API_KEY="wrong-key",
        HTTP_X_DEVICE_IDENTIFIER=device_hash,
    )
    resp = client.get("/api/workspaces/")
    assert resp.status_code == 403
    assert resp.json()["code"] == "invalid_api_key"


@pytest.mark.django_db
def test_unregistered_device(api_key):
    client = APIClient()
    client.credentials(
        HTTP_X_API_KEY=api_key,
        HTTP_X_DEVICE_IDENTIFIER="deadbeef" * 4,
    )
    resp = client.get("/api/workspaces/")
    assert resp.status_code == 403
    assert resp.json()["code"] == "device_not_registered"


@pytest.mark.django_db
def test_device_register(api_key, device_data, device_hash):
    client = APIClient()
    client.credentials(HTTP_X_API_KEY=api_key)
    resp = client.post(
        "/api/devices/register/",
        {"hash": device_hash, "data": device_data},
        format="json",
    )
    assert resp.status_code in (200, 201)
    assert resp.json()["registered"] is True


@pytest.mark.django_db
def test_device_identifier(api_key, device_data):
    client = APIClient()
    client.credentials(HTTP_X_API_KEY=api_key)
    resp = client.post(
        "/api/devices/identifier/",
        {"data": device_data},
        format="json",
    )
    assert resp.status_code == 200
    assert resp.json()["hash"] == compute_device_hash(device_data)
