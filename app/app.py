from flask import Flask, jsonify
#Jsonify :permet de retourner facilement une réponse au format JSON.
import os

app = Flask(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "dev")

#endpoint / permet à la fois de vérifier que 
# l'application fonctionne et de connaître la version actuellement déployée
@app.route("/")
def index():
    return jsonify(
        message="Bienvenue sur l'API de démo Smartovate",
        version=APP_VERSION,
    )


@app.route("/health")
def health():
    # Utilisé par le Health Check du Target Group de l'ALB 
    return jsonify(status="healthy"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
