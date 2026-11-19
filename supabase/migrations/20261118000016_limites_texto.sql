-- Antes de agregar los CHECK, revisa que no haya datos que ya excedan los límites.
-- Si hay filas fuera de rango, la migración se detiene con el detalle para poder
-- corregirlas o recortarlas de forma consciente.
do $$
declare
  v_tabla   text;
  v_columna text;
  v_limite  int;
  v_total   bigint;
begin
  for v_tabla, v_columna, v_limite in
    select *
      from (values
        ('boletas_materiales', 'comentario', 255),
        ('boletas_materiales', 'motivo_excepcion', 255),
        ('autorizaciones', 'comentario', 255),
        ('entradas', 'observaciones', 255),
        ('entradas', 'origen_detalle', 255),
        ('ajustes_inventario', 'motivo', 255),
        ('devoluciones', 'descripcion_dano', 255),
        ('devoluciones', 'observaciones', 255),
        ('reportes_robo_extravio', 'declaracion', 255),
        ('ubicaciones', 'descripcion', 255),
        ('historial_estados_activo', 'motivo', 255),
        ('boletas', 'solicitante_nombre', 200),
        ('boletas', 'solicitante_unidad', 200),
        ('boletas', 'autorizo_nombre', 200),
        ('boletas', 'numero_solicitud', 100),
        ('trabajadores', 'nombre', 200),
        ('trabajadores', 'compania', 200),
        ('trabajadores', 'puesto', 100),
        ('usuarios', 'nombre', 200),
        ('zonas', 'nombre', 200),
        ('zonas', 'edificio', 100),
        ('zonas', 'piso', 100)
      ) as limites(tabla, columna, limite)
  loop
    execute format(
      'select count(*) from public.%I where char_length(btrim(%I)) > $1',
      v_tabla, v_columna
    ) into v_total using v_limite;

    if v_total > 0 then
      raise exception
        'DATOS_EXCEDEN_LIMITE: public.%.% tiene % fila(s) con más de % caracteres. Corrige esos datos antes de aplicar esta migración.',
        v_tabla, v_columna, v_total, v_limite;
    end if;
  end loop;
end $$;

-- Comentarios y descripciones libres
alter table public.boletas_materiales
  add constraint boletas_materiales_comentario_ck
  check (comentario is null or char_length(btrim(comentario)) <= 255);

alter table public.boletas_materiales
  add constraint boletas_materiales_motivo_excepcion_ck
  check (motivo_excepcion is null or char_length(btrim(motivo_excepcion)) <= 255);

alter table public.autorizaciones
  add constraint autorizaciones_comentario_ck
  check (comentario is null or char_length(btrim(comentario)) <= 255);

alter table public.entradas
  add constraint entradas_observaciones_ck
  check (observaciones is null or char_length(btrim(observaciones)) <= 255);

alter table public.entradas
  add constraint entradas_origen_detalle_ck
  check (origen_detalle is null or char_length(btrim(origen_detalle)) <= 255);

alter table public.ajustes_inventario
  add constraint ajustes_inventario_motivo_ck
  check (char_length(btrim(motivo)) <= 255);

alter table public.devoluciones
  add constraint devoluciones_descripcion_dano_ck
  check (descripcion_dano is null or char_length(btrim(descripcion_dano)) <= 255);

alter table public.devoluciones
  add constraint devoluciones_observaciones_ck
  check (observaciones is null or char_length(btrim(observaciones)) <= 255);

alter table public.reportes_robo_extravio
  add constraint reportes_robo_extravio_declaracion_ck
  check (char_length(btrim(declaracion)) <= 255);

alter table public.ubicaciones
  add constraint ubicaciones_descripcion_ck
  check (descripcion is null or char_length(btrim(descripcion)) <= 255);

alter table public.historial_estados_activo
  add constraint historial_estados_activo_motivo_ck
  check (char_length(btrim(motivo)) <= 255);

-- Solicitante externo en la boleta
alter table public.boletas
  add constraint boletas_solicitante_nombre_ck
  check (char_length(btrim(solicitante_nombre)) <= 200),
  add constraint boletas_solicitante_unidad_ck
  check (solicitante_unidad is null
         or char_length(btrim(solicitante_unidad)) <= 200),
  add constraint boletas_autorizo_nombre_ck
  check (autorizo_nombre is null
         or char_length(btrim(autorizo_nombre)) <= 200),
  add constraint boletas_numero_solicitud_ck
  check (numero_solicitud is null
         or char_length(btrim(numero_solicitud)) <= 100);

-- Fuentes que se copian a la boleta
alter table public.trabajadores
  add constraint trabajadores_nombre_ck
  check (char_length(btrim(nombre)) <= 200),
  add constraint trabajadores_compania_ck_largo
  check (compania is null or char_length(btrim(compania)) <= 200),
  add constraint trabajadores_puesto_ck
  check (puesto is null or char_length(btrim(puesto)) <= 100);

alter table public.usuarios
  add constraint usuarios_nombre_ck
  check (char_length(btrim(nombre)) <= 200);

-- Si el alta también crea zonas
alter table public.zonas
  add constraint zonas_nombre_ck
  check (char_length(btrim(nombre)) <= 200),
  add constraint zonas_edificio_ck
  check (edificio is null or char_length(btrim(edificio)) <= 100),
  add constraint zonas_piso_ck
  check (piso is null or char_length(btrim(piso)) <= 100);

-- HU9: el historial también tiene límite de 255. La descripción del daño se
-- guarda completa en devoluciones.descripcion_dano; en el historial se recorta
-- el texto combinado con el prefijo "Devuelto dañado: ".
create or replace function public.registrar_devolucion(
  p_prestamo_id       bigint,
  p_condicion         text,      -- 'BUEN_ESTADO' | 'DANADO'
  p_firma_entrega     text,      -- firma del trabajador que regresa el equipo
  p_firma_recibe      text,      -- firma del almacenista
  p_descripcion_dano  text default null,
  p_observaciones     text default null)
returns table (devolucion_id bigint, folio text, dias_retraso int, estado_activo text)
language plpgsql security definer set search_path = public, privado as $$
declare
  v_pre     prestamos%rowtype;
  v_campus  bigint;
  v_folio   text;
  v_retraso int;
  v_estado  text;
  v_id      bigint;
begin
  select * into v_pre from prestamos where id = p_prestamo_id for update;
  if v_pre.id is null then
    raise exception 'PRESTAMO_NO_EXISTE: El préstamo no existe.';
  end if;
  select al.campus_id into v_campus from activos a
    join ubicaciones u on u.id = a.ubicacion_id join almacenes al on al.id = u.almacen_id
   where a.id = v_pre.activo_id;
  perform campus_de_operacion(v_campus);
  if v_pre.estado <> 'ACTIVO' then
    raise exception 'PRESTAMO_CERRADO: El préstamo ya está cerrado (%).', lower(v_pre.estado);
  end if;
  if p_condicion not in ('BUEN_ESTADO', 'DANADO') then
    raise exception 'CONDICION_INVALIDA: Indica si el equipo regresó en buen estado o dañado.';
  end if;
  if p_condicion = 'DANADO' and nullif(btrim(p_descripcion_dano), '') is null then
    raise exception 'DESCRIPCION_REQUERIDA: Describe el daño o la falla.';
  end if;
  if nullif(btrim(p_firma_entrega), '') is null or nullif(btrim(p_firma_recibe), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Deben firmar el trabajador y el almacenista.';
  end if;

  -- HU9 E3: días naturales de retraso, en hora de Sonora
  v_retraso := greatest(0, (now() at time zone 'America/Hermosillo')::date
                         - (v_pre.fecha_prevista at time zone 'America/Hermosillo')::date);
  v_folio := siguiente_folio('DEV');
  insert into devoluciones (folio, prestamo_id, condicion, descripcion_dano, dias_retraso,
                              firma_entrega_path, firma_recibe_path, observaciones)
  values (v_folio, v_pre.id, p_condicion, nullif(btrim(p_descripcion_dano), ''), v_retraso,
          btrim(p_firma_entrega), btrim(p_firma_recibe), nullif(btrim(p_observaciones), ''))
  returning id into v_id;
  update prestamos set estado = 'DEVUELTO' where id = v_pre.id;

  v_estado := case when p_condicion = 'DANADO' then 'EN_REPARACION' else 'DISPONIBLE' end;
  perform registrar_cambio_estado_activo(v_pre.activo_id, v_estado,
    case when p_condicion = 'DANADO'
         then left('Devuelto dañado: ' || btrim(p_descripcion_dano), 255)
         else 'Devolución' end,
    v_folio);
  return query select v_id, v_folio, v_retraso, v_estado;
end $$;
