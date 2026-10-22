from datetime import datetime, time
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.modules.acceso_y_organizacion.usuarios.politica_password import validar_password


class PlanOut(BaseModel):
    id: int
    codigo: str
    nombre: str
    descripcion: str | None
    precio_mensual: Decimal
    max_sucursales: int | None  # None = sin limite
    max_empleados: int | None
    max_cajas: int | None
    perfiles_clientes: bool
    traspasos: bool
    operacion_offline: bool
    reportes: bool
    ia_reportes: bool
    analitica_ml: bool


class PlanIn(BaseModel):
    """CU03 - Configurar limites del plan (SUPERADMIN). Los topes en None = sin limite."""

    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = Field(default=None, max_length=300)
    precio_mensual: Decimal = Field(ge=0, le=100000)
    max_sucursales: int | None = Field(default=None, ge=1, le=1000)
    max_empleados: int | None = Field(default=None, ge=1, le=10000)
    max_cajas: int | None = Field(default=None, ge=1, le=10000)
    perfiles_clientes: bool = True
    traspasos: bool = True
    operacion_offline: bool = True
    reportes: bool = True
    ia_reportes: bool = False
    analitica_ml: bool = False
    activo: bool = True


class TiendaOut(BaseModel):
    slug: str
    nombre: str


class UsoOut(BaseModel):
    sucursales: int
    empleados: int
    cajas: int


class SuscripcionOut(BaseModel):
    """La suscripcion de un tenant (empresa) con su uso actual contra los topes del plan."""

    empresa_id: UUID
    empresa: str
    empresa_slug: str
    empresa_activa: bool
    plan: PlanOut
    estado: str  # el guardado; `vigente` es el que manda
    vigente: bool
    inicio: datetime
    vence_en: datetime
    dias_restantes: int
    uso: UsoOut


class EmpresaOut(BaseModel):
    id: UUID
    slug: str
    nombre: str
    razon_social: str
    nit: str
    email: str | None
    telefono: str | None
    activa: bool
    creada_en: datetime
    administradores: list[str]  # emails del rol ADMIN de la empresa
    suscripcion: SuscripcionOut | None


class AdminEmpresaIn(BaseModel):
    email: EmailStr
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    password: str = Field(max_length=72)

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return validar_password(value)


class SucursalInicialIn(BaseModel):
    codigo: str = Field(min_length=2, max_length=20)
    nombre: str = Field(min_length=2, max_length=120)
    ciudad: str = Field(min_length=3, max_length=20)
    direccion: str = Field(min_length=3, max_length=250)
    hora_apertura: time | None = None
    hora_cierre: time | None = None


class EmpresaDatosIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=120)
    razon_social: str = Field(min_length=2, max_length=180)
    nit: str = Field(min_length=3, max_length=30)
    email: EmailStr | None = None
    telefono: str | None = Field(default=None, max_length=30)


class EmpresaIn(EmpresaDatosIn):
    """CU01 - Registrar empresa: el tenant, su administrador, su plan y (opcional) su primera
    sucursal con una caja."""

    slug: str = Field(min_length=2, max_length=40, pattern=r"^[a-z0-9][a-z0-9-]{1,38}$")
    plan_codigo: str = Field(min_length=3, max_length=20)
    dias_prueba: int = Field(default=14, ge=1, le=90)
    administrador: AdminEmpresaIn
    sucursal: SucursalInicialIn | None = None


class EstadoEmpresaIn(BaseModel):
    activa: bool


class AsignarPlanIn(BaseModel):
    """CU02 - Asignar / cambiar plan con fecha de inicio y vencimiento (sin cobro: el cobro
    queda registrado aparte con la renovacion)."""

    plan_codigo: str = Field(min_length=3, max_length=20)
    estado: Literal["PRUEBA", "ACTIVA", "VENCIDA", "CANCELADA"] = "ACTIVA"
    inicio: datetime | None = None
    vence_en: datetime


class CheckoutSuscripcionIn(BaseModel):
    plan_codigo: str = Field(min_length=3, max_length=20)
    meses: int = Field(default=1, ge=1, le=12)


class CheckoutSuscripcionOut(BaseModel):
    pago_id: UUID
    monto: Decimal
    url_pago: str  # Checkout hospedado de Stripe


class PagoManualIn(BaseModel):
    """CU05 - Renovacion simulada: la plataforma registra un pago recibido fuera de Stripe."""

    plan_codigo: str = Field(min_length=3, max_length=20)
    meses: int = Field(default=1, ge=1, le=12)
    metodo: Literal["EFECTIVO", "TRANSFERENCIA"]


class PagoSuscripcionOut(BaseModel):
    id: UUID
    empresa: str
    plan: str
    meses: int
    monto: Decimal
    metodo: str
    estado: str
    periodo_desde: datetime | None
    periodo_hasta: datetime | None
    pagado_por: str | None
    creado_en: datetime
    confirmado_en: datetime | None
