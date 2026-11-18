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
  check (char_length(btrim(solicitante_nombre)) <= 100),
  add constraint boletas_solicitante_unidad_ck
  check (solicitante_unidad is null
         or char_length(btrim(solicitante_unidad)) <= 100),
  add constraint boletas_autorizo_nombre_ck
  check (autorizo_nombre is null
         or char_length(btrim(autorizo_nombre)) <= 100),
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