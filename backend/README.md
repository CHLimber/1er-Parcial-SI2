# Backend (FastAPI + asyncpg)

Ver `../CLAUDE.md` para arquitectura y comandos de desarrollo/Docker. Esto es solo tests y linter.

## Tests

Los tests son unitarios (no requieren Postgres levantado ni variables de entorno reales):
`tests/conftest.py` fija variables de entorno de prueba antes de cualquier import de `app.*`,
asi que nunca se lee el `.env` real ni se llama a Stripe/Anthropic/ORS.

```bash
cd backend
.venv\Scripts\activate        # Windows; o .venv/bin/activate en Linux/Mac
pip install -r requirements-dev.txt   # incluye requirements.txt + pytest/ruff
pytest                                # corre todo tests/
pytest -v                             # con el detalle de cada test
pytest tests/test_security.py         # un archivo puntual
```

Que cubren: `politica_password.py`, `security.py` (hash/verify bcrypt, JWT), el respaldo
Haversine de `core/ruteo.py`, `_validar_promocion` (CU10), `_normalizar`/`_rango_fechas` (CU15) y
la formula de IVA/total (CU05/CU06). Tambien hay unos pocos tests de endpoints con
`TestClient`/`dependency_overrides` que verifican 401 sin token y el 503 de `/asistente/chat`
sin `ANTHROPIC_API_KEY`, sin tocar Postgres (ver el docstring de `tests/test_endpoints.py` para
el detalle de por que el `TestClient` se usa sin bloque `with`).

Lo que NO hay todavia: tests de integracion contra Postgres real (necesitarian una base de
datos de prueba aparte, ver PENDIENTES.txt).

## Linter (ruff)

Config en `pyproject.toml` (`[tool.ruff]`), reglas E/F/I (pycodestyle, pyflakes, orden de
imports) nada mas -- a proposito conservador para no generar ruido en modulos que se esten
tocando en paralelo.

```bash
cd backend
ruff check .          # listar hallazgos
ruff check . --fix    # aplicar los que se puedan arreglar solos (imports, etc.)
```
