"""CU17 - Recibir Recomendaciones de IA.

"IA" aca es un algoritmo de recomendacion basado en contenido + reglas de negocio, no un modelo
de lenguaje: no hay llamada a ningun proveedor externo. Es UNA sola consulta SQL con CTEs que
puntua cada prenda candidata (mismo patron sin capa de servicio que el resto del backend; los
JOIN LATERAL de imagen/tallas son una copia deliberada de los de catalogo/router.py, cada modulo
arma su propio SQL, ver CLAUDE.md).

Datos del cliente que usa (para la defensa: "talla, historial y disponibilidad"):

- Historial de compra y de reserva: cada linea de venta PAGADA/ENTREGADA pesa 2 y cada linea
  de reserva pesa 1. De ahi salen tres cosas: las categorias favoritas (top 3), la talla
  habitual y el color habitual.
- Talla habitual: por cada tipo de talla (LETRA / NUMERO / CALZADO) la talla con mas peso en el
  historial. Si no hay historial de ese tipo, se usa la talla declarada en perfil_cliente
  (talla_superior/inferior/calzado). La talla UNICA no cuenta: le queda a cualquiera.
- Color preferido: perfil_cliente.color_favorito_id; si no lo declaro, el color con mas peso en
  el historial.
- Disponibilidad: stock disponible (fisico - reservado) sumado en toda la cadena. Filtro duro:
  una prenda sin stock disponible NUNCA se recomienda. Ademas se mira el stock en la talla de
  la clienta.
- Temporada: temporada.activa de la prenda; las de temporadas cerradas se bajan salvo que esten
  en promocion (cupon vigente por categoria o temporada, o variante con precio_oferta).

Puntaje de cada prenda (se ordena de mayor a menor):

    categoria favorita   +30 / +20 / +10 (1ra, 2da, 3ra del historial)
    talla habitual       +25 si hay stock en su talla; -20 si la prenda usa ese tipo de talla
                         pero su talla esta agotada; 0 si no aplica (talla UNICA, sin datos)
    temporada            +15 si es de la temporada activa; -15 si es de una cerrada y NO esta
                         en promocion; 0 si es atemporal
    promocion            +5
    color preferido      +10 si hay stock en ese color
    destacado            +5
    desempate            unidades vendidas en la cadena, despues lo mas nuevo

Asi el "relleno" de antes (destacados y mas vendidos para quien no tiene historial) sale solo:
sin categorias ni talla, lo que queda es temporada + promocion + destacado + popularidad. El
campo `motivo` explica la senal principal ("Porque te gusta Vestidos · hay tu talla M",
"Nueva temporada Primavera-Verano 2026", "Tendencia en FashionStore", ...).

Nunca se recomienda un producto que el cliente ya compro o reservo.
"""

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.recomendaciones.schemas import ProductoRecomendadoOut

router = APIRouter(prefix="/recomendaciones", tags=["recomendaciones"])

VENTA_ESTADOS_CONTADOS = ("PAGADA", "ENTREGADA")

# $1 = id del cliente, $2 = estados de venta que cuentan como compra, $3 = limite
_SQL_RECOMENDACIONES = """
WITH historial AS (
    -- cada linea de compra pesa 2, cada linea de reserva pesa 1
    SELECT vd.variante_id, 2 AS peso
    FROM venta_detalle vd
    JOIN venta v ON v.id = vd.venta_id
    WHERE v.usuario_id = $1 AND v.estado = ANY($2::estado_venta[])
    UNION ALL
    SELECT rd.variante_id, 1 AS peso
    FROM reserva_detalle rd
    JOIN reserva r ON r.id = rd.reserva_id
    WHERE r.usuario_id = $1
),
hist AS (
    SELECT h.peso, pv.producto_id, pv.talla_id, pv.color_id, p.categoria_id,
           t.tipo AS talla_tipo, t.codigo AS talla_codigo
    FROM historial h
    JOIN producto_variante pv ON pv.id = h.variante_id
    JOIN producto p           ON p.id = pv.producto_id
    JOIN talla t              ON t.id = pv.talla_id
),
tocados AS (
    SELECT DISTINCT producto_id FROM hist
),
categorias_pref AS (
    SELECT categoria_id,
           ROW_NUMBER() OVER (ORDER BY SUM(peso) DESC, categoria_id) AS rn
    FROM hist
    GROUP BY categoria_id
),
tallas_hist AS (
    -- la talla con mas peso por cada tipo (LETRA / NUMERO / CALZADO)
    SELECT talla_tipo AS tipo, talla_id,
           ROW_NUMBER() OVER (PARTITION BY talla_tipo ORDER BY SUM(peso) DESC, talla_id) AS rn
    FROM hist
    WHERE talla_codigo <> 'UNICA'
    GROUP BY talla_tipo, talla_id
),
tallas_declaradas AS (
    SELECT t.tipo, t.id AS talla_id
    FROM perfil_cliente pc
    JOIN talla t ON t.id IN (pc.talla_superior_id, pc.talla_inferior_id, pc.talla_calzado_id)
    WHERE pc.usuario_id = $1 AND t.codigo <> 'UNICA'
),
tallas_cliente AS (
    -- el historial manda; lo declarado en el perfil cubre los tipos sin historial
    SELECT tipo, talla_id FROM tallas_hist WHERE rn = 1
    UNION
    SELECT td.tipo, td.talla_id FROM tallas_declaradas td
    WHERE NOT EXISTS (SELECT 1 FROM tallas_hist th WHERE th.tipo = td.tipo)
),
color_cliente AS (
    SELECT COALESCE(
        (SELECT color_favorito_id FROM perfil_cliente WHERE usuario_id = $1),
        (SELECT color_id FROM hist GROUP BY color_id ORDER BY SUM(peso) DESC, color_id LIMIT 1)
    ) AS color_id
),
variantes AS (
    -- variantes activas de productos activos con su stock disponible en toda la cadena
    SELECT pv.id, pv.producto_id, pv.talla_id, pv.color_id, pv.precio_oferta,
           t.codigo AS talla_codigo, t.tipo AS talla_tipo, t.orden AS talla_orden,
           COALESCE(inv.disponible, 0) AS disponible
    FROM producto_variante pv
    JOIN producto p ON p.id = pv.producto_id AND p.activo
    JOIN talla t    ON t.id = pv.talla_id
    LEFT JOIN (
        SELECT variante_id, SUM(disponible) AS disponible
        FROM inventario
        GROUP BY variante_id
    ) inv ON inv.variante_id = pv.id
    WHERE pv.activa
),
stock_producto AS (
    SELECT producto_id,
           SUM(disponible) AS total_disponible,
           COALESCE(BOOL_OR(color_id = (SELECT color_id FROM color_cliente) AND disponible > 0),
                    false) AS color_ok,
           BOOL_OR(precio_oferta IS NOT NULL) AS con_oferta
    FROM variantes
    GROUP BY producto_id
),
talla_producto AS (
    -- una fila por producto que usa un tipo de talla del que conocemos la de la clienta;
    -- talla_ok = codigo de su talla si hay stock disponible en ella, NULL si esta agotada
    SELECT v.producto_id,
           (ARRAY_AGG(v.talla_codigo ORDER BY v.talla_orden)
                FILTER (WHERE v.talla_id = tc.talla_id AND v.disponible > 0))[1] AS talla_ok
    FROM variantes v
    JOIN tallas_cliente tc ON tc.tipo = v.talla_tipo
    WHERE v.talla_codigo <> 'UNICA'
    GROUP BY v.producto_id
),
popularidad AS (
    SELECT pv.producto_id, SUM(vd.cantidad) AS unidades
    FROM venta_detalle vd
    JOIN venta v              ON v.id = vd.venta_id
    JOIN producto_variante pv ON pv.id = vd.variante_id
    WHERE v.estado = ANY($2::estado_venta[])
    GROUP BY pv.producto_id
),
candidatos AS (
    SELECT p.id, p.destacado,
           cp.rn AS categoria_rank,
           tp.producto_id IS NOT NULL AS talla_aplica,
           tp.talla_ok,
           sp.color_ok,
           tem.nombre AS temporada,
           tem.activa AS temporada_activa,
           (sp.con_oferta OR EXISTS (
               SELECT 1 FROM promocion pr
               WHERE pr.activa
                 AND CURRENT_DATE BETWEEN pr.fecha_inicio AND pr.fecha_fin
                 AND (pr.uso_maximo IS NULL OR pr.usos_actuales < pr.uso_maximo)
                 AND ((pr.alcance = 'CATEGORIA' AND pr.categoria_id = p.categoria_id)
                   OR (pr.alcance = 'TEMPORADA' AND pr.temporada_id = p.temporada_id))
           )) AS en_promocion,
           COALESCE(pop.unidades, 0) AS unidades_vendidas
    FROM producto p
    JOIN stock_producto sp       ON sp.producto_id = p.id
    LEFT JOIN categorias_pref cp ON cp.categoria_id = p.categoria_id AND cp.rn <= 3
    LEFT JOIN talla_producto tp  ON tp.producto_id = p.id
    LEFT JOIN temporada tem      ON tem.id = p.temporada_id
    LEFT JOIN popularidad pop    ON pop.producto_id = p.id
    WHERE p.activo
      AND sp.total_disponible > 0  -- disponibilidad: filtro duro, nunca se recomienda un agotado
      AND NOT EXISTS (SELECT 1 FROM tocados tc WHERE tc.producto_id = p.id)
),
puntuados AS (
    SELECT ca.*,
           CASE ca.categoria_rank WHEN 1 THEN 30 WHEN 2 THEN 20 WHEN 3 THEN 10 ELSE 0 END
         + CASE WHEN ca.talla_ok IS NOT NULL THEN 25 WHEN ca.talla_aplica THEN -20 ELSE 0 END
         + CASE WHEN ca.temporada_activa THEN 15
                WHEN NOT ca.temporada_activa AND NOT ca.en_promocion THEN -15
                ELSE 0 END
         + CASE WHEN ca.en_promocion THEN 5 ELSE 0 END
         + CASE WHEN ca.color_ok THEN 10 ELSE 0 END
         + CASE WHEN ca.destacado THEN 5 ELSE 0 END AS puntaje
    FROM candidatos ca
)
SELECT p.id, p.codigo, p.nombre, p.slug, p.descripcion, p.precio_base, p.genero,
       c.nombre AS categoria, c.slug AS categoria_slug, m.nombre AS marca, p.destacado,
       img.url AS imagen_url,
       COALESCE(tallas_agg.tallas, ARRAY[]::varchar[]) AS tallas,
       false AS agotado,  -- los agotados ya quedaron afuera en `candidatos`
       CASE
           WHEN pu.categoria_rank IS NOT NULL THEN 'Porque te gusta ' || c.nombre
           WHEN pu.temporada_activa THEN 'Nueva temporada ' || pu.temporada
           WHEN NOT pu.temporada_activa AND pu.en_promocion
               THEN 'En liquidacion: ' || pu.temporada
           WHEN pu.en_promocion THEN 'En promocion'
           WHEN pu.color_ok THEN 'En tu color favorito'
           WHEN p.destacado THEN 'Destacado en FashionStore'
           ELSE 'Tendencia en FashionStore'
       END
       || CASE WHEN pu.talla_ok IS NOT NULL THEN ' · hay tu talla ' || pu.talla_ok ELSE '' END
       AS motivo
FROM puntuados pu
JOIN producto p   ON p.id = pu.id
JOIN categoria c  ON c.id = p.categoria_id
LEFT JOIN marca m ON m.id = p.marca_id
LEFT JOIN LATERAL (
    SELECT url FROM producto_imagen pi
    WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
    ORDER BY pi.es_principal DESC, pi.orden
    LIMIT 1
) img ON true
LEFT JOIN LATERAL (
    SELECT array_agg(codigo ORDER BY orden) AS tallas
    FROM (
        SELECT DISTINCT t.codigo, t.orden
        FROM producto_variante pv
        JOIN talla t ON t.id = pv.talla_id
        WHERE pv.producto_id = p.id AND pv.activa
    ) sub
) tallas_agg ON true
ORDER BY pu.puntaje DESC, pu.unidades_vendidas DESC, p.creado_en DESC
LIMIT $3
"""


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Las recomendaciones son solo para clientes",
        )


@router.get("", response_model=list[ProductoRecomendadoOut])
async def obtener_recomendaciones(
    limite: int = Query(default=8, ge=1, le=20),
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> list[ProductoRecomendadoOut]:
    _exigir_cliente(usuario)
    filas = await conn.fetch(
        _SQL_RECOMENDACIONES,
        usuario["id"],
        list(VENTA_ESTADOS_CONTADOS),
        limite,
    )
    return [ProductoRecomendadoOut(**dict(fila)) for fila in filas]
