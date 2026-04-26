def test_health_returns_ok(client):
    """Healthcheck должен возвращать HTTP 200 и тело {"status": "ok"}."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
