"""Arma docs/FASHIONSTORE_BD.sql (Capitulo 8 del informe) a partir de:

  - db/01_schema.sql y db/02_logica.sql tal como estan HOY (8.2.2, vistas, 8.2.6.2 y 8.2.6.3);
  - las secciones propias del documento que viven en esta carpeta (cabecera, poblacion,
    update/delete, consultas, procedimientos y pruebas).

Uso (desde fashionstore/):  python docs/bd_documento/armar.py
Despues probarlo en una base vacia (ver README.md de esta carpeta).

Si 02_logica.sql gana una seccion nueva, el script falla hasta que se la clasifique abajo en
VISTAS, FUNCIONES o TRIGGERS: asi ninguna funcion o trigger nuevo queda fuera del documento.
"""
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]                       # fashionstore/
SCHEMA = RAIZ / "db" / "01_schema.sql"
LOGICA = RAIZ / "db" / "02_logica.sql"
SALIDA = RAIZ / "docs" / "FASHIONSTORE_BD.sql"

# Titulo de cada seccion de 02_logica.sql (linea "--  TITULO" debajo de "-- ----") -> grupo
VISTAS = ["VISTAS DE CONSULTA", "CU15 - CONSOLIDADO DE EXISTENCIAS"]
FUNCIONES = ["FUNCION CENTRAL DE INVENTARIO", "CU07 - ARQUEO DE CAJA",
             "EXPIRACION DE RESERVAS VENCIDAS", "CU20 - TARIFA DEL DELIVERY"]
TRIGGERS = ["VENTA DESCUENTA STOCK", "RESERVA COMPROMETE STOCK", "HISTORIAL AUTOMATICO",
            "RECEPCION DE MERCADERIA", "DEVOLUCIONES", "TRASPASOS ENTRE SUCURSALES",
            "CU20 - BITACORA AUTOMATICA DEL ENVIO"]


def secciones_logica():
    lineas = LOGICA.read_text(encoding="utf-8").splitlines(keepends=True)
    inicios = [i for i in range(len(lineas) - 1)
               if lineas[i].startswith("-- ---") and lineas[i + 1].startswith("--  ")]
    out = []
    for n, i in enumerate(inicios):
        fin = inicios[n + 1] if n + 1 < len(inicios) else len(lineas)
        titulo = lineas[i + 1][4:].strip()
        cuerpo = "".join(l for l in lineas[i:fin] if not l.startswith("DROP TRIGGER IF EXISTS"))
        out.append((titulo, cuerpo.rstrip() + "\n\n"))
    return out


def grupo(titulo):
    for nombre, lista in (("vistas", VISTAS), ("funciones", FUNCIONES), ("triggers", TRIGGERS)):
        if any(titulo.startswith(t) for t in lista):
            return nombre
    raise SystemExit(f"Seccion nueva en 02_logica.sql sin clasificar: '{titulo}'. "
                     "Agregala a VISTAS, FUNCIONES o TRIGGERS en armar.py")


def main():
    schema = SCHEMA.read_text(encoding="utf-8").splitlines(keepends=True)
    desde = next(i for i, l in enumerate(schema) if "EXTENSIONES" in l) - 1
    n_tablas = sum(1 for l in schema if l.startswith("CREATE TABLE"))

    g = {"vistas": [], "funciones": [], "triggers": []}
    for titulo, cuerpo in secciones_logica():
        g[grupo(titulo)].append(cuerpo)
    # mismo orden que el documento: dentro de cada grupo, el de la lista
    for nombre, lista in (("vistas", VISTAS), ("funciones", FUNCIONES), ("triggers", TRIGGERS)):
        g[nombre].sort(key=lambda c: next(k for k, t in enumerate(lista) if f"--  {t}" in c))

    parte = lambda n: (AQUI / n).read_text(encoding="utf-8")
    cab = parte("00_cabecera.sql")
    import re
    cab = re.sub(r"ENUM, \d+ tablas", f"ENUM, {n_tablas} tablas", cab)

    doc = (cab + "".join(schema[desde:]).rstrip() + "\n"
           + parte("10_vistas_cabecera.sql") + "".join(g["vistas"])
           + parte("20_poblacion_a_procedimientos.sql") + "\n" + "".join(g["funciones"])
           + parte("60_triggers_cabecera.sql") + "".join(g["triggers"])
           + parte("70_pruebas.sql"))
    SALIDA.write_text(doc, encoding="utf-8", newline="\n")
    print(f"{SALIDA.relative_to(RAIZ)}: {len(doc.splitlines())} lineas, {n_tablas} tablas, "
          f"{len(g['vistas'])} secciones de vistas, {len(g['funciones'])} de funciones, "
          f"{len(g['triggers'])} de triggers")


if __name__ == "__main__":
    main()
