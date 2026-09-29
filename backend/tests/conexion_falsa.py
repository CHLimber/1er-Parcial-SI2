"""Conexion asyncpg falsa para testear routers sin Postgres: responde a fetch/fetchrow/fetchval
buscando un fragmento del SQL en `respuestas` (el primero que aparezca, en orden de insercion) y
anota cada sentencia de execute/fetchrow/fetchval para poder afirmar que se ejecuto o no."""


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
        self.respuestas = respuestas
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

    def _buscar(self, sql: str):
        for fragmento, valor in self.respuestas.items():
            if fragmento in sql:
                return valor(sql) if callable(valor) else valor
        return None

    async def fetchrow(self, sql, *args):
        self._anotar(sql, args)
        return self._buscar(sql)

    async def fetchval(self, sql, *args):
        self._anotar(sql, args)
        return self._buscar(sql)

    async def fetch(self, sql, *args):
        return self._buscar(sql) or []

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
