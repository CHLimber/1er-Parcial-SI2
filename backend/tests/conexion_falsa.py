"""Conexion asyncpg falsa para testear routers sin Postgres: responde a fetch/fetchrow/fetchval
buscando un fragmento del SQL en `respuestas` (el primero que aparezca, en orden de insercion) y
anota cada sentencia de execute/fetchrow/fetchval para poder afirmar que se ejecuto o no.

Multi-tenant: antes de las respuestas del test se consultan las de RESPUESTAS_TENANT, que hacen
pasar los chequeos de pertenencia de app/core/tenant.py (todo es de la EMPRESA de prueba). Un
test que quiera probar un acceso cruzado las pisa pasando el mismo fragmento con otro valor. Un
valor callable recibe el SQL, o (sql, args) si acepta dos parametros."""

import inspect
from uuid import UUID

EMPRESA = UUID("e0000000-0000-4000-8000-0000000000aa")

RESPUESTAS_TENANT = {
    # exigir_sucursal
    "FROM sucursal WHERE id = $1 AND empresa_id = $2": {"activa": True},
    # empresa_de_sucursal
    "SELECT empresa_id FROM sucursal WHERE id = $1": EMPRESA,
    # exigir_variantes: devuelve la cantidad de ids pedidos (todas son de la empresa)
    "WHERE pv.id = ANY($1::uuid[]) AND p.empresa_id = $2": lambda sql, args: len(args[0]),
    # exigir_fila
    "WHERE id = $1 AND empresa_id = $2)": True,
}


def staff(**datos) -> dict:
    """Usuario de personal de la empresa de prueba (lo que arma get_staff_actual)."""
    return {"id": UUID(int=1), "empresa_id": EMPRESA, "sucursal_id": None, "permisos": [], **datos}


class _Transaccion:
    def __init__(self, conn: "ConexionFalsa"):
        self.conn = conn

    async def __aenter__(self):
        self.conn.profundidad_tx += 1
        return self

    async def __aexit__(self, *exc):
        self.conn.profundidad_tx -= 1
        return False


class ConexionFalsa:
    def __init__(self, respuestas: dict):
        # las del test pisan a las de tenant con el mismo fragmento
        self.respuestas = {
            **{k: v for k, v in RESPUESTAS_TENANT.items() if k not in respuestas},
            **respuestas,
        }
        self.ejecutado: list[str] = []
        # sentencias que corrieron dentro de conn.transaction() (no hay rollback real: esto
        # permite afirmar que algo quedo adentro de la transaccion y se desharia si falla)
        self.ejecutado_en_tx: list[str] = []
        # (sql, args) de cada sentencia anotada, para afirmar con que valores se llamo
        self.llamadas: list[tuple[str, tuple]] = []
        self.profundidad_tx = 0

    def transaction(self):
        return _Transaccion(self)

    def _anotar(self, sql: str, args: tuple = ()) -> None:
        self.ejecutado.append(sql)
        self.llamadas.append((sql, args))
        if self.profundidad_tx:
            self.ejecutado_en_tx.append(sql)

    def _buscar(self, sql: str, args: tuple = ()):
        for fragmento, valor in self.respuestas.items():
            if fragmento in sql:
                if not callable(valor):
                    return valor
                if len(inspect.signature(valor).parameters) == 2:
                    return valor(sql, args)
                return valor(sql)
        return None

    async def fetchrow(self, sql, *args):
        self._anotar(sql, args)
        return self._buscar(sql, args)

    async def fetchval(self, sql, *args):
        self._anotar(sql, args)
        return self._buscar(sql, args)

    async def fetch(self, sql, *args):
        return self._buscar(sql, args) or []

    async def execute(self, sql, *args):
        self._anotar(sql, args)
        return "OK"

    def ejecuto(self, fragmento: str) -> bool:
        return any(fragmento in sql for sql in self.ejecutado)

    def ejecuto_en_tx(self, fragmento: str) -> bool:
        return any(fragmento in sql for sql in self.ejecutado_en_tx)

    def args_de(self, fragmento: str) -> tuple:
        """Argumentos de la primera sentencia que contiene `fragmento`."""
        return next(args for sql, args in self.llamadas if fragmento in sql)
