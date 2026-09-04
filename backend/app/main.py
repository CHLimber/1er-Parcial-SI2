from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.db import connect_pool, disconnect_pool
from app.modules.caja.router import router as caja_router
from app.modules.carrito.router import router as carrito_router
from app.modules.catalogo.router import router as catalogo_router
from app.modules.pagos.router import router as pagos_router
from app.modules.reservas.router import router as reservas_router
from app.modules.sucursales.router import router as sucursales_router
from app.modules.usuarios.router import router as usuarios_router
from app.modules.ventas.router import router as ventas_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_pool()
    yield
    await disconnect_pool()


app = FastAPI(title="FashionStore API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(usuarios_router)
app.include_router(catalogo_router)
app.include_router(sucursales_router)
app.include_router(reservas_router)
app.include_router(carrito_router)
app.include_router(ventas_router)
app.include_router(pagos_router)
app.include_router(caja_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
