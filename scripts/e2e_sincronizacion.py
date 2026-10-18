#!/usr/bin/env python
"""Recorrido e2e de la sincronizacion offline (Modulos D y E): venta y reserva sin conexion,
reenvio idempotente (tambien 5 reenvios simultaneos), conflictos de precio/stock/caja y su
resolucion, rechazos por empresa, sucursal, permiso, total y suscripcion vencida.

Uso (con el backend levantado contra una base recien sembrada con db/01-04):
    python scripts/e2e_sincronizacion.py http://localhost:8081

Necesita httpx (esta en backend/requirements.txt). Algunos chequeos leen la base directo con
psql para afirmar lo que la API no muestra (cuantas ventas quedaron por operacion, stock):
    E2E_PSQL   ruta a psql            (por defecto "psql")
    E2E_PG     conexion para psql     (por defecto postgresql://fashionstore:fashionstore@localhost:5433/fashionstore)
OJO: modifica datos (crea una empresa, ventas, cierra una caja): usarlo sobre una base de prueba.
"""
import os
import subprocess
import sys
import time as _t
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import httpx

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8081"
PSQL = os.environ.get("E2E_PSQL", "psql")
PG = os.environ.get("E2E_PG", "postgresql://fashionstore:fashionstore@localhost:5433/fashionstore")
c = httpx.Client(base_url=BASE, timeout=30)
ok = fallas = 0


def chk(nombre, cond, extra=""):
    global ok, fallas
    ok, fallas = (ok + 1, fallas) if cond else (ok, fallas + 1)
    print(("  OK  " if cond else "  FALLA ") + nombre, "" if cond else extra)


def sql(q):
    return subprocess.run([PSQL, PG, "-Atc", q], capture_output=True, text=True).stdout.strip()


def login(email):
    r = c.post("/auth/login", json={"email": email, "password": "demo1234"})
    return {"Authorization": "Bearer " + r.json()["access_token"]}, r.json()["usuario"]


caj, u_caj = login("cajera.scz@fashionstore.bo")
enc, u_enc = login("admin@fashionstore.bo")
an, u_an = login("cajero.sanmiguel@andina.bo")
ven, u_ven = login("vendedor.scz@fashionstore.bo")

# la cajera abre caja
cajas = c.get("/caja/cajas", headers=caj).json()
r = c.post("/caja/abrir", headers=caj, json={"caja_id": cajas[0]["id"], "monto_inicial": 100})
chk("abre caja", r.status_code in (201, 409), r.text)

paq = c.get("/sync/catalogo", headers=caj)
chk("descarga paquete offline", paq.status_code == 200, paq.text[:300])
paq = paq.json()
chk("paquete con productos y clientas", len(paq["productos"]) > 10 and len(paq["clientes"]) >= 1)
chk("paquete trae sesion de caja", paq["sesion_caja_id"] is not None)
empresa, sucursal = paq["empresa_id"], paq["sucursal"]["id"]
var = next(v for p in paq["productos"] for v in p["variantes"] if v["disponible"] >= 3)


def venta(precio=None, cant=1, var_=None, **extra):
    v = var_ or var
    p = Decimal(str(precio if precio is not None else v["precio"]))
    sub = p * cant
    total = (sub + (sub * Decimal("0.13")).quantize(Decimal("0.01"))).quantize(Decimal("0.01"))
    op = {"id": str(uuid.uuid4()), "tipo": "VENTA", "empresa_id": empresa, "sucursal_id": sucursal,
          "usuario_id": u_caj["id"], "registrada_en": datetime.now(timezone.utc).isoformat(),
          "venta": {"items": [{"variante_id": v["id"], "cantidad": cant, "precio_unitario": str(p)}],
                    "total": str(total), "sesion_caja_id": paq["sesion_caja_id"]}}
    op.update(extra)
    return op


def enviar(h, *ops):
    r = c.post("/sync/operaciones", headers=h, json={"operaciones": list(ops)})
    assert r.status_code == 200, r.text
    return r.json()["resultados"]


stock0 = int(sql(f"SELECT cantidad_fisica FROM inventario WHERE sucursal_id='{sucursal}' AND variante_id='{var['id']}'"))
op = venta()
r = enviar(caj, op)[0]
chk("venta offline CONFIRMADA", r["estado"] == "CONFIRMADA", r)
r2 = enviar(caj, op)[0]
chk("reenvio devuelve lo mismo y marca duplicada", r2["duplicada"] and r2["resultado"]["venta_id"] == r["resultado"]["venta_id"], r2)
chk("intentos=2", r2["intentos"] == 2)
chk("una sola venta en la base", sql(f"SELECT count(*) FROM venta WHERE operacion_id='{op['id']}'") == "1")
stock1 = int(sql(f"SELECT cantidad_fisica FROM inventario WHERE sucursal_id='{sucursal}' AND variante_id='{var['id']}'"))
chk("stock descontado UNA vez", stock1 == stock0 - 1, (stock0, stock1))
chk("kardex con un solo SALIDA de la venta", sql(f"SELECT count(*) FROM movimiento_inventario m JOIN venta v ON v.id=m.documento_id WHERE v.operacion_id='{op['id']}'") == "1")

# precio cambiado -> conflicto -> aceptar precio actual
opp = venta(precio=float(var["precio"]) - 10)
r = enviar(caj, opp)[0]
chk("precio cambiado -> CONFLICTO", r["estado"] == "CONFLICTO" and r["codigo_motivo"] == "PRECIO_CAMBIADO", r)
rr = c.post(f"/sync/operaciones/{opp['id']}/resolver", headers=caj, json={"accion": "ACEPTAR_PRECIO_ACTUAL"})
chk("cajera no puede aceptar precio (403)", rr.status_code == 403, rr.text)
rr = c.post(f"/sync/operaciones/{opp['id']}/resolver", headers=enc, json={"accion": "ACEPTAR_PRECIO_ACTUAL", "nota": "ok"})
chk("encargado acepta precio -> CONFIRMADA", rr.status_code == 200 and rr.json()["estado"] == "CONFIRMADA", rr.text)
chk("venta a nombre de la cajera", sql(f"SELECT registrada_por_id FROM venta WHERE operacion_id='{opp['id']}'") == u_caj["id"])

# stock insuficiente -> conflicto -> descartar
ops = venta(cant=int(var["disponible"]) + 50)
r = enviar(caj, ops)[0]
chk("stock insuficiente -> CONFLICTO", r["estado"] == "CONFLICTO" and r["codigo_motivo"] == "STOCK_INSUFICIENTE", r)
rr = c.post(f"/sync/operaciones/{ops['id']}/resolver", headers=enc, json={"accion": "DESCARTAR", "nota": "se devolvio el efectivo"})
chk("descartar -> RECHAZADA", rr.json()["estado"] == "RECHAZADA", rr.text)
rr = c.post(f"/sync/operaciones/{ops['id']}/resolver", headers=enc, json={"accion": "REINTENTAR"})
chk("no se resuelve dos veces", rr.status_code == 409)

# rechazos
r = enviar(caj, venta(empresa_id=u_an["empresa_id"]))[0]
chk("empresa ajena -> RECHAZADA", r["estado"] == "RECHAZADA" and r["codigo_motivo"] == "EMPRESA_AJENA", r)
r = enviar(caj, venta(usuario_id=u_enc["id"]))[0]
chk("responsable distinto -> RECHAZADA", r["codigo_motivo"] == "RESPONSABLE_DISTINTO", r)
otra_suc = sql("SELECT id FROM sucursal WHERE codigo='LP-01'")
r = enviar(caj, venta(sucursal_id=otra_suc))[0]
chk("sucursal no asignada -> RECHAZADA", r["codigo_motivo"] == "SUCURSAL_NO_AUTORIZADA", r)
var_an = sql("SELECT pv.id FROM producto_variante pv JOIN producto p ON p.id=pv.producto_id WHERE p.codigo='AND-001' LIMIT 1")
r = enviar(caj, venta(var_={"id": var_an, "precio": 420.0}))[0]
chk("prenda de otra empresa -> RECHAZADA", r["codigo_motivo"] == "PRENDA_AJENA", r)
mal = venta(); mal["venta"]["total"] = "1.00"
r = enviar(caj, mal)[0]
chk("total que no cierra -> RECHAZADA", r["codigo_motivo"] == "TOTAL_INCONSISTENTE", r)
fut = venta(registrada_en=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat())
chk("fecha futura -> RECHAZADA", enviar(caj, fut)[0]["codigo_motivo"] == "FECHA_INVALIDA")
r = enviar(ven, {**venta(), "usuario_id": u_ven["id"]})[0]
chk("vendedor sin caja.crear -> SIN_PERMISO", r["codigo_motivo"] == "SIN_PERMISO", r)
r = c.post("/sync/operaciones", headers=caj, json={"operaciones": [{**venta(), "venta": {**venta()["venta"], "metodo_pago": "TARJETA"}}]})
chk("pago no contado -> 422 de validacion", r.status_code == 422)

# mismo uuid desde otra empresa
r = enviar(an, {**op, "empresa_id": u_an["empresa_id"], "usuario_id": u_an["id"], "sucursal_id": sql("SELECT id FROM sucursal WHERE codigo='AN-LP1'")})[0]
chk("mismo id desde otra empresa no ve la operacion ajena", r["codigo_motivo"] == "ID_REPETIDO" and r["resultado"] is None, r)

# sin caja abierta -> conflicto -> reintentar tras abrir
sesion = paq["sesion_caja_id"]
sql(f"UPDATE sesion_caja SET estado='CERRADA', cerrada_en=now(), monto_sistema=0, monto_declarado=0 WHERE id='{sesion}'")
opc = venta()
r = enviar(caj, opc)[0]
chk("caja cerrada -> CONFLICTO SIN_CAJA_ABIERTA", r["codigo_motivo"] == "SIN_CAJA_ABIERTA", r)
c.post("/caja/abrir", headers=caj, json={"caja_id": cajas[0]["id"], "monto_inicial": 0})
rr = c.post(f"/sync/operaciones/{opc['id']}/resolver", headers=caj, json={"accion": "REINTENTAR"})
chk("la cajera reintenta tras abrir caja -> CONFIRMADA", rr.json()["estado"] == "CONFIRMADA", rr.text)

# reserva offline (la registra el encargado de la tienda)
cli = paq["clientes"][0]
res = {"id": str(uuid.uuid4()), "tipo": "RESERVA", "empresa_id": empresa, "sucursal_id": sucursal,
       "usuario_id": u_enc["id"], "registrada_en": datetime.now(timezone.utc).isoformat(),
       "reserva": {"cliente_email": cli["email"], "fecha_visita": (date.today() + timedelta(days=1)).isoformat(),
                   "hora_visita": "11:00", "items": [{"variante_id": var["id"], "cantidad": 1}]}}
r = enviar(enc, res)[0]
chk("reserva offline CONFIRMADA", r["estado"] == "CONFIRMADA" and r["resultado"]["codigo"].startswith("RES-"), r)
chk("reserva compromete stock", sql(f"SELECT estado FROM reserva WHERE operacion_id='{res['id']}'") == "CONFIRMADA")
r = enviar(enc, {**res, "id": str(uuid.uuid4()), "reserva": {**res["reserva"], "cliente_email": "nadie@x.bo"}})[0]
chk("reserva con clienta inexistente -> RECHAZADA", r["codigo_motivo"] == "CLIENTE_INEXISTENTE", r)

# suscripcion vencida
sql("UPDATE suscripcion SET vence_en = now() - interval '1 hour' WHERE empresa_id = (SELECT id FROM empresa WHERE slug='fashionstore')")
antes = venta(registrada_en=(datetime.now(timezone.utc) - timedelta(hours=3)).isoformat())
despues = venta()
r = enviar(caj, antes, despues)
estados = {x["id"]: x for x in r}
chk("vendida antes de vencer -> se acepta", estados[antes["id"]]["estado"] == "CONFIRMADA", estados[antes["id"]])
chk("registrada despues de vencer -> SUSCRIPCION_VENCIDA", estados[despues["id"]]["codigo_motivo"] == "SUSCRIPCION_VENCIDA", estados[despues["id"]])
sql("UPDATE suscripcion SET vence_en = now() + interval '30 days' WHERE empresa_id = (SELECT id FROM empresa WHERE slug='fashionstore')")

# log y consulta
log = c.get("/sync/operaciones", headers=enc)
chk("encargado ve el log", log.status_code == 200 and len(log.json()) >= 10, log.text[:200])
chk("andina no ve el log de FS", all(o["id"] != op["id"] for o in c.get("/sync/operaciones", headers=login("admin@andina.bo")[0]).json()))
chk("la cajera consulta su operacion", c.get(f"/sync/operaciones/{op['id']}", headers=caj).status_code == 200)
chk("otra empresa no la consulta", c.get(f"/sync/operaciones/{op['id']}", headers=an).status_code == 404)

# concurrencia: 5 reenvios simultaneos del mismo id
import concurrent.futures
opx = venta()
with concurrent.futures.ThreadPoolExecutor(5) as ex:
    rs = list(ex.map(lambda _: httpx.post(BASE + "/sync/operaciones", headers=caj, json={"operaciones": [opx]}, timeout=30).json()["resultados"][0], range(5)))
chk("5 reenvios simultaneos: 1 venta", sql(f"SELECT count(*) FROM venta WHERE operacion_id='{opx['id']}'") == "1", [x["estado"] for x in rs])
chk("todos ven CONFIRMADA", all(x["estado"] == "CONFIRMADA" for x in rs))
print(f"\n{ok} OK, {fallas} fallas")
