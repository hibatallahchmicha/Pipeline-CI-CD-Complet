import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import app

#Test1
def test_index():
    #Flask fournit test_client() 
    # pour simuler des requêtes HTTP sans réellement démarrer ton serveur.
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["message"].startswith("Bienvenue")

#Il vérifie généralement le health check de l'applicationavnat delpoiment
def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"
