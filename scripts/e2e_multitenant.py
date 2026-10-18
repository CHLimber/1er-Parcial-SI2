#!/usr/bin/env python
"""Recorrido e2e del aislamiento multi-tenant (Modulo A): 2+ empresas, accesos cruzados que
tienen que dar 404, tope de sucursales del plan, reportes con IA solo en Profesional, plataforma
(registrar empresa, asignar plan, configurar topes, suspender) y tienda publica por empresa.

Uso (con el backend levantado contra una base recien sembrada con db/01-04):
    python scripts/e2e_multitenant.py http://localhost:8081

Necesita httpx (esta en backend/requirements.txt). Algunos chequeos leen la base directo con
psql para afirmar lo que la API no muestra (cuantas ventas quedaron por operacion, stock):
    E2E_PSQL   ruta a psql            (por defecto "psql")
    E2E_PG     conexion para psql     (por defecto postgresql://fashionstore:fashionstore@localhost:5433/fashionstore)
OJO: modifica datos (crea una empresa, ventas, cierra una caja): usarlo sobre una base de prueba.
"""
import os
import subprocess
import sys

import httpx

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8081"
PSQL = os.environ.get("E2E_PSQL", "psql")
PG = os.environ.get("E2E_PG", "postgresql://fashionstore:fashionstore@localhost:5433/fashionstore")
c = httpx.Client(base_url=BASE, timeout=30)
ok = fallas = 0


def chk(nombre, cond, extra=""):
    global ok, fallas
    if cond:
        ok += 1
        print("  OK ", nombre)
    else:
        fallas += 1
        print("  FALLA", nombre, extra)


def login(email, password="demo1234"):
    r = c.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, (email, r.text)
    return {"Authorization": "Bearer " + r.json()["access_token"]}, r.json()["usuario"]


fs, u_fs = login("admin@fashionstore.bo")
an, u_an = login("admin@andina.bo")
sa, u_sa = login("superadmin@fashionstore.bo")
mu, u_mu = login("admin@modaurbana.bo")
lp, _ = login("encargada.lapaz@fashionstore.bo")
cli, _ = login("cliente@fashionstore.bo")

print("== identidad")
chk("admin FS empresa", u_fs["empresa_slug"] == "fashionstore" and u_fs["plan"] == "Profesional")
chk("admin FS tiene ia_reportes", "ia_reportes" in u_fs["funciones_plan"], u_fs["funciones_plan"])
chk("admin Andina plan Basico sin IA", u_an["plan"] == "Basico" and "ia_reportes" not in u_an["funciones_plan"])
chk("superadmin sin empresa", u_sa["empresa_id"] is None and "empresas.leer" in u_sa["permisos"])
chk("moda urbana vencida -> sin funciones", u_mu["funciones_plan"] == [])

print("== datos propios")
for nombre, h, suc, prod in [("FS", fs, 6, 42), ("Andina", an, 2, 4)]:
    r = c.get("/admin/sucursales", headers=h)
    chk(f"{nombre} sucursales={suc}", r.status_code == 200 and len(r.json()) == suc, r.text[:200])
    r = c.get("/admin/catalogo/productos", headers=h)
    chk(f"{nombre} productos={prod}", r.status_code == 200 and len(r.json()) == prod, r.text[:200])
    for ruta in ["/proveedores", "/recepciones", "/traspasos", "/devoluciones", "/admin/usuarios",
                 "/admin/roles", "/admin/permisos", "/saas/suscripcion", "/auditoria", "/clientes",
                 "/admin/envios", "/admin/catalogo/referencias", "/admin/catalogo/promociones",
                 "/reportes/indicadores", "/reportes/ventas-diarias", "/reportes/top-productos",
                 "/reportes/stock-por-sucursal", "/reportes/reservas-por-estado",
                 "/reportes/perdidas", "/reportes/existencias", "/reportes/vendedores",
                 "/reportes/top-clientes", "/reportes/ocupacion-cajas",
                 "/reportes/recepciones-pendientes", "/reportes/productos-sin-movimiento",
                 "/reportes/envios-por-estado", "/traspasos/sugerencias",
                 "/devoluciones/cambios-mes", "/auditoria/entidades", "/saas/pagos",
                 ]:
        r = c.get(ruta, headers=h)
        chk(f"{nombre} GET {ruta}", r.status_code == 200, f"{r.status_code} {r.text[:300]}")
    r = c.get("/reportes/ventas-por-sucursal", headers=h)
    chk(f"{nombre} ventas-por-sucursal solo propias", r.status_code == 200 and len(r.json()) <= suc,
        r.text[:200])

usuarios_fs = c.get("/admin/usuarios?tipo=STAFF", headers=fs).json()
chk("FS no ve personal de Andina", all("andina" not in u["email"] for u in usuarios_fs))
usuarios_an = c.get("/admin/usuarios?tipo=STAFF", headers=an).json()
chk("Andina ve solo su personal (4)", len(usuarios_an) == 4, [u["email"] for u in usuarios_an])
roles_an = [r["nombre"] for r in c.get("/admin/roles", headers=an).json()]
chk("Andina no ve SUPERADMIN", "SUPERADMIN" not in roles_an, roles_an)
aud_an = c.get("/auditoria?tamanio_pagina=100", headers=an).json()
chk("auditoria Andina solo de su gente", all((i["usuario_email"] or "").endswith("andina.bo") for i in aud_an["items"]), aud_an["total"])

print("== accesos cruzados (tienen que dar 404)")
prod_fs = c.get("/admin/catalogo/productos", headers=fs).json()[0]
suc_fs = c.get("/admin/sucursales", headers=fs).json()[0]
det_fs = c.get(f"/admin/catalogo/productos/{prod_fs['id']}", headers=fs).json()
var_fs = det_fs["variantes"][0]["id"]
chk("Andina GET producto FS", c.get(f"/admin/catalogo/productos/{prod_fs['id']}", headers=an).status_code == 404)
chk("Andina PUT producto FS", c.patch(f"/admin/catalogo/productos/{prod_fs['id']}/estado", json={"activo": False}, headers=an).status_code == 404)
chk("Andina GET sucursal FS", c.get(f"/admin/sucursales/{suc_fs['id']}", headers=an).status_code == 404)
chk("Andina cajas de sucursal FS", c.get(f"/admin/sucursales/{suc_fs['id']}/cajas", headers=an).status_code == 404)
suc_an = c.get("/admin/sucursales", headers=an).json()[0]
r = c.post("/inventario/ajustes", headers=an, json={"sucursal_id": suc_an["id"], "variante_id": var_fs, "cantidad_fisica_nueva": 0, "motivo": "intento cruzado"})
chk("Andina ajusta stock de prenda FS en su sucursal", r.status_code == 404, r.text)
r = c.post("/inventario/ajustes", headers=an, json={"sucursal_id": suc_fs["id"], "variante_id": var_fs, "cantidad_fisica_nueva": 0, "motivo": "intento cruzado"})
chk("Andina ajusta stock en sucursal FS", r.status_code == 404, r.text)
chk("Andina reporte de sucursal FS", c.get(f"/reportes/indicadores?sucursal_id={suc_fs['id']}", headers=an).status_code == 404)
chk("Andina kardex FS", c.get(f"/inventario/{var_fs}/kardex?sucursal_id={suc_fs['id']}", headers=an).status_code == 404)
usr_fs = usuarios_fs[0]["id"]
chk("Andina GET usuario FS", c.get(f"/admin/usuarios/{usr_fs}", headers=an).status_code == 404)
chk("Andina resetea password FS", c.post(f"/admin/usuarios/{usr_fs}/password", json={"password": "Otra1234!"}, headers=an).status_code == 404)
rec_fs = c.get("/recepciones", headers=fs).json()
if rec_fs:
    chk("Andina GET recepcion FS", c.get(f"/recepciones/{rec_fs[0]['id']}", headers=an).status_code == 404)
import subprocess
num_fs = subprocess.run([PSQL, PG, "-Atc",
    "SELECT v.numero FROM venta v JOIN sucursal s ON s.id=v.sucursal_id JOIN empresa e ON e.id=s.empresa_id WHERE e.slug='fashionstore' LIMIT 1"], capture_output=True, text=True).stdout.strip()
dev = c.get(f"/devoluciones/venta?numero={num_fs}", headers=an)
chk("FS encuentra su venta por numero", c.get(f"/devoluciones/venta?numero={num_fs}", headers=fs).status_code == 200)
chk("Andina busca venta de FS por numero", dev.status_code == 404, dev.text)
roles_fs = c.get("/admin/roles", headers=fs).json()
admin_rol = next(r for r in roles_fs if r["nombre"] == "ADMIN")
chk("rol del sistema no editable", c.put(f"/admin/roles/{admin_rol['id']}/permisos", json={"permisos": []}, headers=fs).status_code == 409)

for nombre, h in [("FS", fs), ("Andina", an)]:
    s0 = c.get("/admin/sucursales", headers=h).json()[0]["id"]
    for ruta in [f"/inventario/variantes?q=a&sucursal_id={s0}", f"/recepciones/variantes?q=a&sucursal_id={s0}",
                 f"/traspasos/variantes?q=a&origen_id={s0}"]:
        r = c.get(ruta, headers=h)
        chk(f"{nombre} GET {ruta[:22]}", r.status_code == 200, r.text[:200])
    vs = c.get(f"/inventario/variantes?q=a&sucursal_id={s0}", headers=h).json()
    chk(f"{nombre} buscador solo trae prendas propias", all(v["sku"].startswith("AND-") == (nombre == "Andina") for v in vs), [v["sku"] for v in vs][:5])
chk("Andina busca variantes en sucursal FS -> 404", c.get(f"/inventario/variantes?q=a&sucursal_id={suc_fs['id']}", headers=an).status_code == 404)

print("== limites y plan")
r = c.post("/admin/sucursales", headers=an, json={"codigo": "AN-XX1", "nombre": "Andina 3", "ciudad": "LA_PAZ", "direccion": "Calle 1", "cantidad_vestidores": 1})
chk("Andina 3ra sucursal -> 409 (plan Basico 2)", r.status_code == 409, r.text)
r = c.post("/reportes/consulta-ia", headers=an, json={"mensajes": [{"rol": "user", "texto": "ventas del mes"}]})
chk("Andina consulta IA -> 403 plan", r.status_code == 403 and "Profesional" in r.text, r.text)
r = c.post("/reportes/consulta-ia", headers=fs, json={"mensajes": [{"rol": "user", "texto": "ventas del mes"}]})
chk("FS consulta IA pasa el plan (503 sin API key)", r.status_code == 503, r.text)
chk("Moda Urbana reportes -> 402", c.get("/reportes/indicadores", headers=mu).status_code == 402)
chk("Moda Urbana ve su suscripcion", c.get("/saas/suscripcion", headers=mu).status_code == 200)

print("== plataforma")
emp = c.get("/saas/empresas", headers=sa)
chk("superadmin lista 3 empresas", emp.status_code == 200 and len(emp.json()) >= 3, emp.text[:200])
chk("superadmin no opera catalogo", c.get("/admin/catalogo/productos", headers=sa).status_code == 403)
plan_b = next(p for p in c.get("/saas/planes").json() if p["codigo"] == "BASICO")
cuerpo = {k: plan_b[k] for k in ["nombre", "descripcion", "precio_mensual", "max_sucursales", "max_empleados", "max_cajas", "perfiles_clientes", "traspasos", "operacion_offline", "reportes", "ia_reportes", "analitica_ml"]}
r = c.put("/saas/planes/BASICO", headers=sa, json={**cuerpo, "max_sucursales": 3})
chk("superadmin sube tope Basico a 3", r.status_code == 200 and r.json()["max_sucursales"] == 3, r.text)
r = c.post("/admin/sucursales", headers=an, json={"codigo": "AN-XX1", "nombre": "Andina 3", "ciudad": "LA_PAZ", "direccion": "Calle 1", "cantidad_vestidores": 1})
chk("con tope 3 Andina crea su 3ra sucursal", r.status_code == 201, r.text)
r = c.put("/saas/planes/BASICO", headers=sa, json={**cuerpo, "max_sucursales": 2})
chk("superadmin vuelve el tope a 2", r.status_code == 200)
chk("empresa no puede configurar planes", c.put("/saas/planes/BASICO", headers=an, json=cuerpo).status_code == 403)
nueva = c.post("/saas/empresas", headers=sa, json={
    "slug": "e2e-tienda", "nombre": "Tienda E2E", "razon_social": "E2E SRL", "nit": "1112223",
    "plan_codigo": "BASICO", "administrador": {"email": "admin@e2e.bo", "nombre": "Ad", "apellido": "Min", "password": "Demo1234!"},
    "sucursal": {"codigo": "E2E-1", "nombre": "E2E Centro", "ciudad": "SUCRE", "direccion": "Plaza 25 de Mayo"}})
chk("superadmin registra empresa con admin y sucursal", nueva.status_code == 201, nueva.text)
if nueva.status_code == 201:
    e2e, _ = login("admin@e2e.bo", "Demo1234!")
    chk("admin nuevo ve 1 sucursal", len(c.get("/admin/sucursales", headers=e2e).json()) == 1)
    chk("admin nuevo ve catalogo vacio", c.get("/admin/catalogo/productos", headers=e2e).json() == [])
    r = c.put(f"/saas/empresas/{nueva.json()['id']}/plan", headers=sa, json={"plan_codigo": "PROFESIONAL", "estado": "ACTIVA", "vence_en": "2027-12-31T00:00:00Z"})
    chk("superadmin cambia plan a Profesional", r.status_code == 200 and r.json()["plan"]["codigo"] == "PROFESIONAL", r.text)
    r = c.patch(f"/saas/empresas/{nueva.json()['id']}/estado", headers=sa, json={"activa": False})
    chk("superadmin suspende empresa", r.status_code == 200)
    chk("empresa suspendida: login 403", c.post("/auth/login", json={"email": "admin@e2e.bo", "password": "Demo1234!"}).status_code == 403)
    chk("empresa suspendida: token viejo 403", c.get("/admin/sucursales", headers=e2e).status_code == 403)

print("== tienda publica")
r = c.get("/catalogo/productos?limit=100")
chk("vitrina por defecto = FashionStore", r.status_code == 200 and len(r.json()) == 42, len(r.json()))
r = c.get("/catalogo/productos?empresa=andina")
chk("vitrina andina = 4", r.status_code == 200 and len(r.json()) == 4, r.text[:200])
r = c.get("/sucursales", headers={"X-Empresa": "andina"})
chk("sucursales andina (header)", r.status_code == 200 and len(r.json()) >= 2, r.text[:200])
chk("tienda inexistente 404", c.get("/catalogo/productos?empresa=nada").status_code == 404)
slug_an = c.get("/catalogo/productos?empresa=andina").json()[0]["slug"]
chk("detalle de prenda andina por su vitrina", c.get(f"/catalogo/productos/{slug_an}?empresa=andina").status_code == 200)
chk("prenda andina no aparece en vitrina FS", c.get(f"/catalogo/productos/{slug_an}").status_code == 404)
c.delete("/carrito", headers=cli)
det_an = c.get(f"/catalogo/productos/{slug_an}?empresa=andina").json()
r1 = c.post("/carrito/items", headers=cli, json={"variante_id": var_fs, "cantidad": 1})
r2 = c.post("/carrito/items", headers=cli, json={"variante_id": det_an["variantes"][0]["id"], "cantidad": 1})
chk("carrito no mezcla tiendas", r1.status_code == 201 and r2.status_code == 409, f"{r1.status_code} {r2.status_code} {r2.text}")

print(f"\n{ok} OK, {fallas} fallas")
