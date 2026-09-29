"""Config compartida de los tests. Lo primero que hace es fijar variables de entorno de
PRUEBA antes de que cualquier test importe app.core.config -- Settings() lee backend/.env si
existe (pydantic-settings), pero una variable de entorno real siempre le gana al .env, asi que
fijandolas todas aca nos asegura no leer nunca el .env real (con claves de Stripe/Anthropic/ORS
de verdad) ni pegarle a ningun servicio externo desde un test unitario.

Este archivo se importa antes de recolectar los modulos de tests/, asi que las variables quedan
puestas antes de cualquier "import app...." de los tests.
"""

import os

import pytest
import stripe

os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5433/test")
os.environ.setdefault("JWT_SECRET", "test-secret-not-for-prod")
os.environ.setdefault("JWT_ALGORITHM", "HS256")
os.environ.setdefault("JWT_EXPIRE_MINUTES", "480")
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")
os.environ.setdefault("FRONTEND_URL", "http://localhost:3000")
os.environ.setdefault("STRIPE_SECRET_KEY", "")
os.environ.setdefault("STRIPE_PUBLISHABLE_KEY", "")
os.environ.setdefault("STRIPE_WEBHOOK_SECRET", "")
os.environ.setdefault("ANTHROPIC_API_KEY", "")
os.environ.setdefault("ANTHROPIC_MODEL", "claude-haiku-4-5")
os.environ.setdefault("ORS_API_KEY", "")
os.environ.setdefault("MEDIA_DIR", "media")
os.environ.setdefault("PUBLIC_BASE_URL", "http://localhost:8081")
os.environ.setdefault("EXPIRAR_RESERVAS_INTERVALO_SEGUNDOS", "120")


@pytest.fixture
def stripe_falso(monkeypatch):
    """Registra las llamadas a Stripe en vez de hacerlas."""
    llamadas: dict[str, list] = {"refund": [], "expire": [], "cancel": []}
    monkeypatch.setattr(
        stripe.checkout.Session, "retrieve", lambda cs: {"payment_intent": "pi_de_" + cs}
    )
    monkeypatch.setattr(
        stripe.Refund, "create", lambda payment_intent: llamadas["refund"].append(payment_intent)
    )
    monkeypatch.setattr(stripe.checkout.Session, "expire", lambda cs: llamadas["expire"].append(cs))
    monkeypatch.setattr(stripe.PaymentIntent, "cancel", lambda pi: llamadas["cancel"].append(pi))
    return llamadas
