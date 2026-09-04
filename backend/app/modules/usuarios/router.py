import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.core.security import create_access_token, verify_password
from app.modules.usuarios.schemas import LoginRequest, TokenResponse, UsuarioOut

router = APIRouter(prefix="/auth", tags=["usuarios"])


@router.post("/login", response_model=TokenResponse)
async def login(
    body: LoginRequest,
    conn: asyncpg.Connection = Depends(get_connection),
) -> TokenResponse:
    row = await conn.fetchrow(
        """
        SELECT u.id, u.email, u.password_hash, u.nombre, u.apellido, u.tipo,
               u.activo, r.nombre AS rol
        FROM usuario u
        LEFT JOIN rol r ON r.id = u.rol_id
        WHERE u.email = $1
        """,
        body.email,
    )

    credenciales_invalidas = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED, detail="Email o contrasena invalidos"
    )

    if row is None or not row["activo"]:
        raise credenciales_invalidas
    if not verify_password(body.password, row["password_hash"]):
        raise credenciales_invalidas

    await conn.execute("UPDATE usuario SET ultimo_acceso = now() WHERE id = $1", row["id"])

    usuario = UsuarioOut(
        id=row["id"],
        email=row["email"],
        nombre=row["nombre"],
        apellido=row["apellido"],
        tipo=row["tipo"],
        rol=row["rol"],
    )
    token = create_access_token(subject=str(row["id"]), extra_claims={"tipo": row["tipo"]})
    return TokenResponse(access_token=token, usuario=usuario)
