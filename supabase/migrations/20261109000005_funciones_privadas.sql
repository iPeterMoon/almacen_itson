-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 5: funciones auxiliares privadas
-- Las funciones que usan las políticas RLS no deben poder llamarse desde
-- la API (/rest/v1/rpc). Se mueven al schema "privado", que Supabase no
-- expone; las políticas siguen funcionando porque apuntan a la función,
-- no a su nombre.
-- =====================================================================

create schema if not exists privado;
grant usage on schema privado to authenticated;

alter function public.mi_rol() set schema privado;
alter function public.mis_campus() set schema privado;
alter function public.ubicacion_permitida(bigint) set schema privado;

-- Funciones que las llaman por nombre: agregar privado a su search_path
alter function privado.ubicacion_permitida(bigint) set search_path = public, privado;
alter function public.validar_almacen(bigint) set search_path = public, privado;

-- La conversión de unidades no necesita privilegios elevados
alter function public.convertir_a_unidad_base(bigint, bigint, numeric) security invoker;
