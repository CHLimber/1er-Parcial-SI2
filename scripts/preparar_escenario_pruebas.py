#!/usr/bin/env python
"""Prepara la tienda FashionStore para recorrer a mano los 30 casos de uso (docs/GUIA_PRUEBAS_CU.md).

Parte de una base sembrada con db/01-04 (catalogo, 6 sucursales, usuarios demo, 60 dias de ventas)
y deja, usando la API real (no SQL directo), un caso PENDIENTE para cada flujo que la persona que
prueba tiene que ejecutar: reservas por confirmar, pagos por aprobar, un pedido por retirar, un
envio por despachar, devoluciones y cambios por resolver, una recepcion por confirmar, traspasos por
despachar/recibir y operaciones offline en conflicto.

Uso (backend levantado, desde fashionstore/):
    python scripts/preparar_escenario_pruebas.py http://localhost:8081
    python scripts/preparar_escenario_pruebas.py http://localhost:8081 --forzar   # repite aunque ya corrio

NO es idempotente: cada corrida suma datos. Por eso se niega a repetirse si encuentra la marca
"[ESCENARIO]" en las reservas, salvo con --forzar. Para dejar todo de cero:
    docker compose down -v && docker compose up --build
Necesita httpx (esta en backend/requirements.txt).
"""
import sys
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import httpx

BASE = next((a for a in sys.argv[1:] if a.startswith("http")), "http://localhost:8081")
FORZAR = "--forzar" in sys.argv
# Reanudar tras un fallo a mitad de camino: --desde 3 --ventas V-AAA,V-BBB,V-CCC,V-DDD (las ventas POS del paso 1)
DESDE = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--desde=")), 1))
VENTAS_PREVIAS = next((a.split("=")[1].split(",") for a in sys.argv if a.startswith("--ventas=")), None)
MARCA = "[ESCENARIO]"
c = httpx.Client(base_url=BASE, timeout=60)
resumen = []  # (caso de uso, que quedo listo)


def paso(txt):
    print(f"\n== {txt}")


def ok(txt):
    print(f"   OK  {txt}")


def aviso(txt):
    print(f"   !!  {txt}")


def login(email):
    r = c.post("/auth/login", json={"email": email, "password": "demo1234"})
    if r.status_code != 200:
        sys.exit(f"No pude iniciar sesion con {email}: {r.status_code} {r.text}\n"
                 "Revisa que la base este sembrada con db/03_datos_iniciales.sql.")
    j = r.json()
    return {"Authorization": "Bearer " + j["access_token"]}, j["usuario"]


def tienda(h):
    return {**h, "X-Empresa": "fashionstore"}


def llamar(metodo, url, h, esperado=(200, 201, 202), **kw):
    r = c.request(metodo, url, headers=h, **kw)
    if r.status_code not in esperado:
        sys.exit(f"FALLO {metodo} {url} -> {r.status_code}: {r.text[:400]}")
    return r.json() if r.content else None


adm, u_adm = login("admin@fashionstore.bo")            # ENCARGADO de Equipetrol (y ADMIN)
caj, u_caj = login("cajera.scz@fashionstore.bo")
enc_lp, _ = login("encargada.lapaz@fashionstore.bo")

paso("0. Chequeos previos")
if not FORZAR and any(MARCA in (r.get("observaciones") or "")
                      for e in ("PENDIENTE", "CONFIRMADA")
                      for r in llamar("GET", "/reservas/sucursal", adm, params={"estado": e})
                      for e in ("PENDIENTE", "CONFIRMADA")):
    sys.exit("El escenario ya esta armado (hay reservas con la marca). Usa --forzar para repetirlo.")

paq = llamar("GET", "/sync/catalogo", caj)
SC = paq["sucursal"]["id"]
EMPRESA = paq["empresa_id"]
sucursales = {s["codigo"]: s["id"] for s in llamar("GET", "/sucursales", tienda(login("cliente@fashionstore.bo")[0]))}
LP = sucursales["LP-01"]
ok(f"Equipetrol {SC[:8]}, La Paz {LP[:8]}")

# variantes con buen stock en Equipetrol, de productos distintos, y una pareja de tallas para el cambio
prods = [p for p in paq["productos"] if sum(v["disponible"] >= 6 for v in p["variantes"]) >= 2]
def variante(i, minimo=6):
    return next(v for v in prods[i]["variantes"] if v["disponible"] >= minimo)
V = [variante(i) for i in range(10)]
nombres = {v["id"]: prods[i]["nombre"] for i, v in enumerate(V)}
tallas_prod = {}
for v in prods[1]["variantes"]:
    if v["color"] == V[1]["color"] and v["talla"] != V[1]["talla"] and v["disponible"] >= 3:
        tallas_prod.setdefault("otra", v)
V_CAMBIO = tallas_prod.get("otra") or next(v for v in prods[1]["variantes"] if v["id"] != V[1]["id"] and v["disponible"] >= 3)
ok(f"{len(prods)} productos con stock; cambio de talla {V[1]['talla']} -> {V_CAMBIO['talla']} en {prods[1]['nombre']}")

manana = (datetime.now() + timedelta(days=1)).date().isoformat()

# ---------------------------------------------------------------- caja y ventas de hoy
paso("1. Caja abierta y ventas presenciales de hoy (CU14)")
if DESDE > 1:
    SESION = llamar("GET", "/caja/sesion-actual", caj)["id"]
    numeros = VENTAS_PREVIAS or sys.exit("Con --desde hace falta --ventas=V-..,V-..,V-..,V-.. (las 4 del paso 1)")
else:
    caja_id = llamar("GET", "/caja/cajas", caj)[0]["id"]
    ses = llamar("GET", "/caja/sesion-actual", caj)
    if not ses:
        ses = llamar("POST", "/caja/abrir", caj, json={"caja_id": caja_id, "monto_inicial": 200})
    SESION = ses["id"]
    ok("caja de Equipetrol abierta con Bs 200")

    def pos(items, metodo, recibido=None):
        body = {"items": [{"variante_id": v["id"], "cantidad": q} for v, q in items], "metodo_pago": metodo}
        if recibido:
            body["monto_recibido"] = recibido
        return llamar("POST", "/ventas/pos", caj, json=body)

    v_a = pos([(V[0], 1), (V[2], 2)], "EFECTIVO", 2000)
    v_b = pos([(V[1], 1)], "TARJETA")
    v_c = pos([(V[3], 1), (V[4], 1)], "QR")
    v_d = pos([(V[5], 1)], "EFECTIVO", 1000)
    numeros = [x["numero"] for x in (v_a, v_b, v_c, v_d)]
    ok(f"4 ventas POS de hoy: {numeros}")
    resumen.append(("CU14", f"Ventas de hoy {', '.join(map(str, numeros))} (efectivo, tarjeta, QR) y caja abierta"))

# ---------------------------------------------------------------- reservas
paso("2. Reservas en distintos estados (CU12)")
if DESDE <= 2:

    def reservar(email, items, hora, obs):
        h = tienda(login(email)[0])
        return llamar("POST", "/reservas", h, json={
            "sucursal_id": SC, "fecha_visita": manana, "hora_visita": hora,
            "observaciones": f"{MARCA} {obs}", "items": [{"variante_id": v["id"], "cantidad": q} for v, q in items]})

    r1 = reservar("clienta01@demo.bo", [(V[6], 1), (V[7], 1)], "11:00", "pendiente: el encargado debe confirmarla o rechazarla")
    r2 = reservar("clienta02@demo.bo", [(V[8], 1), (V[9], 2)], "12:00", "para confirmar y atender en el vestidor")
    r3 = reservar("cliente@fashionstore.bo", [(V[6], 1)], "16:00", "la clienta la cancela desde Mis reservas")
    r4 = reservar("clienta03@demo.bo", [(V[7], 1), (V[8], 1)], "17:00", "confirmada, para marcar no-presentada")
    for r in (r2, r4):
        llamar("POST", f"/reservas/{r['id']}/confirmar", adm)
    ok("R1 PENDIENTE (clienta01), R2 y R4 CONFIRMADAS (clienta02/03), R3 PENDIENTE de cliente@ para cancelar")
    resumen.append(("CU12", "4 reservas: 2 PENDIENTES (clienta01, cliente@) y 2 CONFIRMADAS (clienta02, clienta03)"))

# ---------------------------------------------------------------- pedidos online
paso("3. Pedidos online por pasarela (CU13)")
if DESDE <= 3:
    direccion_id = None

    def pedido(email, items, metodo, entrega="RETIRO_SUCURSAL", direccion=None):
        h = tienda(login(email)[0])
        for v, q in items:
            llamar("POST", "/carrito/items", h, json={"variante_id": v["id"], "cantidad": q})
        body = {"sucursal_id": SC, "entrega": entrega, "metodo_pago": metodo, "canal": "WEB"}
        if direccion:
            body["direccion_id"] = direccion
        return h, llamar("POST", "/ventas/checkout", h, json=body)

    if DESDE > 2:  # reanudando: o1 y o2 ya existen, solo falta informar el QR
        h5 = tienda(login("clienta05@demo.bo")[0])
        o2 = {"venta_id": next(p["venta_id"] for p in llamar("GET", "/caja/pagos-pendientes", caj)
                               if p["cliente_email"] == "clienta05@demo.bo")}
    else:
        h4, o1 = pedido("clienta04@demo.bo", [(V[0], 1)], "EFECTIVO")
        h5, o2 = pedido("clienta05@demo.bo", [(V[1], 1)], "QR")
    llamar("POST", f"/pagos/qr/{o2['venta_id']}/informar", h5, json={"referencia": "Operacion 88421, Banco Union"})
    h7, o3 = pedido("clienta07@demo.bo", [(V[2], 1)], "EFECTIVO")
    h8 = tienda(login("clienta08@demo.bo")[0])
    dir_r = llamar("POST", "/direcciones", h8, json={
        "alias": "Casa", "ciudad": "SANTA_CRUZ", "direccion": "Av. Cristo Redentor, 3er anillo #450",
        "referencia": "Porton negro", "latitud": -17.7480, "longitud": -63.1650, "es_principal": True})
    h8, o4 = pedido("clienta08@demo.bo", [(V[3], 2)], "EFECTIVO", "DOMICILIO", dir_r["id"])
    ok("O1 efectivo PENDIENTE (clienta04), O2 QR informado (clienta05), O3 y O4 efectivo")

    pend = llamar("GET", "/caja/pagos-pendientes", caj)
    def pago_de(venta_id):
        return next(p for p in pend if str(p.get("venta_id")) == str(venta_id))
    for o in (o3, o4):  # estos dos se aprueban ya: quedan PAGADA para entregar / despachar
        llamar("POST", f"/caja/pagos/{pago_de(o['venta_id'])['pago_id']}/aprobar", caj)
    ok("O3 (retiro) y O4 (domicilio) aprobados -> PAGADA; O1 y O2 quedan esperando a la cajera")
    resumen.append(("CU13", "Pagos pendientes: efectivo (clienta04) y QR informado (clienta05); pedido por retirar (clienta07)"))
    resumen.append(("Envios", "Pedido a domicilio de clienta08 pagado, envio PENDIENTE por despachar"))

# ---------------------------------------------------------------- operaciones sin conexion
paso("4. Operaciones offline ya sincronizadas y en conflicto (CU19-CU24)")

def op(tipo, **extra):
    base = {"id": str(uuid.uuid4()), "tipo": tipo, "empresa_id": EMPRESA, "sucursal_id": SC,
            "usuario_id": u_caj["id"], "registrada_en": datetime.now(timezone.utc).isoformat()}
    base.update(extra)
    return base

def venta_off(v, cant=1, precio=None, sesion=SESION):
    p = Decimal(str(precio if precio is not None else v["precio"]))
    sub = p * cant
    total = (sub + (sub * Decimal("0.13")).quantize(Decimal("0.01"))).quantize(Decimal("0.01"))
    body = {"items": [{"variante_id": v["id"], "cantidad": cant, "precio_unitario": str(p)}], "total": str(total)}
    if sesion:
        body["sesion_caja_id"] = sesion
    return op("VENTA", venta=body)

def enviar(*ops, h=None):
    return llamar("POST", "/sync/operaciones", h or caj, json={"operaciones": list(ops)})["resultados"]

o_ok = venta_off(V[4])
o_res = op("RESERVA", usuario_id=u_caj["id"], reserva={"cliente_email": "clienta10@demo.bo", "fecha_visita": manana, "hora_visita": "10:00",
                               "items": [{"variante_id": V[5]["id"], "cantidad": 1}], "observaciones": f"{MARCA} offline"})
o_precio = venta_off(V[6], precio=float(V[6]["precio"]) - 20)
o_stock = venta_off(V[7], cant=int(V[7]["disponible"]) + 40)
res = enviar(o_ok, o_precio, o_stock) + enviar(o_res, h=caj)  # la reserva tambien la registra la cajera (reservas.actualizar)
ok("estados: " + ", ".join(f"{r['estado']}({r.get('codigo_motivo') or '-'})" for r in res))

# caja cerrada con arqueo exacto, y recien ahi la venta que llega sin caja abierta (SIN_CAJA_ABIERTA)
arq = llamar("GET", "/caja/arqueo", caj)
esperado = arq["monto_sistema"]
llamar("POST", "/caja/cerrar", caj, json={"monto_declarado": float(esperado)})
ok(f"caja cerrada con arqueo exacto (Bs {esperado})")
o_sin_caja = venta_off(V[8], sesion=None)
res2 = enviar(o_sin_caja)
ok(f"venta sin caja abierta -> {res2[0]['estado']}({res2[0].get('codigo_motivo')})")
resumen.append(("CU19-CU24", "3 conflictos abiertos (precio, stock, sin caja), 1 venta y 1 reserva offline confirmadas"))

# ---------------------------------------------------------------- devoluciones y cambios
paso("5. Devoluciones y cambio de talla (CU15, CU16)")
def devolver(numero, motivo_tipo, motivo, **linea):
    venta = llamar("GET", "/devoluciones/venta", adm, params={"numero": numero})
    det = next(l for l in venta["lineas"] if l["devolvible"] >= 1)
    return llamar("POST", "/devoluciones", adm, json={
        "venta_id": venta["venta_id"], "motivo_tipo": motivo_tipo, "motivo": f"{MARCA} {motivo}",
        "con_etiqueta": True, "sin_uso": True, "con_comprobante": True,
        "lineas": [{"venta_detalle_id": det["venta_detalle_id"], "cantidad": 1, **linea}]})

d1 = devolver(numeros[0], "DEFECTO", "costura abierta en la manga")
d2 = devolver(numeros[1], "TALLA", "la talla no calza", variante_solicitada_id=V_CAMBIO["id"])
ok(f"devolucion por DEFECTO (venta {numeros[0]}) y cambio por TALLA (venta {numeros[1]}), ambas PENDIENTES")
resumen.append(("CU15-CU16", f"Devolucion por defecto (venta {numeros[0]}) y cambio de talla (venta {numeros[1]}) PENDIENTES"))

# ---------------------------------------------------------------- recepcion y traspasos
paso("6. Recepcion de mercaderia y traspasos (CU09, CU10)")
prov = llamar("GET", "/proveedores", adm)[0]
rec = llamar("POST", "/recepciones", adm, json={"sucursal_id": SC, "proveedor_id": prov["id"],
                                                 "numero": f"GR-ESC-{datetime.now():%H%M%S}"})
for v, q, costo in ((V[0], 12, 90), (V[3], 8, 70), (V[9], 20, 55)):
    llamar("POST", f"/recepciones/{rec['id']}/detalle", adm,
           json={"variante_id": v["id"], "cantidad": q, "costo_unitario": costo})
ok(f"recepcion en borrador con 3 lineas de {prov['nombre']}")

def traspaso(origen, destino, lineas, h):
    return llamar("POST", "/traspasos", h, json={"sucursal_origen_id": origen, "sucursal_destino_id": destino,
                                                 "lineas": [{"variante_id": v["id"], "cantidad": q} for v, q in lineas]})
t1 = traspaso(SC, LP, [(V[0], 3), (V[2], 2)], adm)
t2 = traspaso(SC, LP, [(V[3], 4)], adm)
llamar("POST", f"/traspasos/{t2['id']}/despachar", adm)
ok("traspaso 1 creado (por despachar) y traspaso 2 EN_TRANSITO hacia La Paz (lo recibe encargada.lapaz)")
resumen.append(("CU09", "Recepcion en borrador con 3 lineas por confirmar (admin, encargado de Equipetrol)"))
resumen.append(("CU10", "Traspaso por despachar y traspaso en transito hacia La Paz por recibir"))

# ---------------------------------------------------------------- cierre
paso("Listo")
for cu, txt in resumen:
    print(f"  {cu:<10} {txt}")
print("\nAhora sigue docs/GUIA_PRUEBAS_CU.md. La caja de Equipetrol quedo CERRADA: abrela como cajera.scz.")
