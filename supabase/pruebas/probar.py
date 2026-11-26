"""Prueba los escenarios de HU1 a HU5 contra la base local, como usuarios reales de la app."""
import json, os, subprocess, sys, time

sys.stdout.reconfigure(encoding="utf-8")
# Corre psql dentro del contenedor que levanta reiniciar.sh
CONTENEDOR = os.environ.get("CONTENEDOR_PG", "almacenes-pruebas")
PSQL = ["docker", "exec", "-i", CONTENEDOR,
        "psql", "-U", "postgres", "-d", "almacenes", "-X", "-tA", "-v", "ON_ERROR_STOP=1"]
CEN = "11111111-1111-1111-1111-111111111111"   # almacenista Centro
NAI = "22222222-2222-2222-2222-222222222222"   # almacenista Náinari
JEFE = "33333333-3333-3333-3333-333333333333"  # supervisor jefe Náinari + Centro
SUP = "44444444-4444-4444-4444-444444444444"   # supervisor Centro


def run(sql, user=None):
    pre = ""
    if user == "anon":
        pre = "set role anon;"
    elif user:
        pre = f"set role authenticated; set request.jwt.claim.sub = '{user}';"
    r = subprocess.run(PSQL + ["-c", pre + sql], capture_output=True, text=True, encoding="utf-8")
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def admin(sql):
    ok, out = run(sql)
    if not ok:
        sys.exit("Fallo en preparación: " + out)
    return out


resultados = []


def caso(hu, desc, user, sql, espera="OK", contiene=None):
    ok, out = run(sql, user)
    if espera == "OK":
        paso = ok and (contiene is None or contiene in out)
    else:
        paso = (not ok) and espera in out
    resultados.append((paso, hu, desc, out.splitlines()[-1][:110] if out else ""))


# ---------- preparación (lo que haría un administrador) ----------
admin(f"""
insert into auth.users values ('{CEN}'), ('{NAI}'), ('{JEFE}');
insert into usuarios (id, nombre, rol, campus_id) values
 ('{CEN}', 'Alicia García', 'ALMACENISTA', (select id from campus where clave='CEN')),
 ('{NAI}', 'Pedro Luna', 'ALMACENISTA', (select id from campus where clave='NAI')),
 ('{JEFE}', 'Carlos Mendoza', 'SUPERVISOR_JEFE', (select id from campus where clave='NAI'));
insert into usuarios_campus_adicionales values ('{JEFE}', (select id from campus where clave='CEN'));
""")
A1 = admin("select a.id from almacenes a join campus c on c.id=a.campus_id where c.clave='CEN' and a.nombre='Almacén 1'")
A2 = admin("select a.id from almacenes a join campus c on c.id=a.campus_id where c.clave='CEN' and a.nombre='Almacén 2'")
AN = admin("select a.id from almacenes a join campus c on c.id=a.campus_id where c.clave='NAI' and a.nombre='Principal'")
LIQ, PAP = admin("select string_agg(id::text, ',' order by nombre) from categorias where nombre in ('Líquido','Papel')").split(",")
LITRO = admin("select id from unidades_medida where clave='L'")
PZA = admin("select id from unidades_medida where clave='pza'")

ins = "insert into productos (codigo, nombre_estandar, alias, unidad_base_id, categoria_id, tipo) values "

# ---------- HU1 ----------
caso("HU1 E1", "Alta con datos obligatorios", CEN,
     ins + f"('CD-123','Limpiador multiusos','Pinol',{LITRO},{LIQ},'SERVICIOS_GENERALES') returning codigo", contiene="CD-123")
caso("HU1 E2", "Alta sin alias", CEN,
     ins + f"('CD-500','Papel higiénico',null,{PZA},{PAP},'AMBOS') returning codigo", contiene="CD-500")
caso("HU1 E3", "Falta nombre estándar", CEN,
     ins + f"('CD-501',null,null,{PZA},{PAP},'AMBOS')", espera="null value")
caso("HU1 E3", "Nombre estándar vacío", CEN,
     ins + f"('CD-502','  ',null,{PZA},{PAP},'AMBOS')", espera="violates check")
caso("HU1 E4", "Código duplicado (minúsculas)", CEN,
     ins + f"('cd-123','Otro',null,{PZA},{PAP},'AMBOS')", espera="productos_codigo_uk")
caso("HU1 E4", "Nombre estándar duplicado", CEN,
     ins + f"('CD-999','LIMPIADOR MULTIUSOS',null,{PZA},{PAP},'AMBOS')", espera="productos_nombre_uk")
caso("HU1 E5", "Presentaciones con factor a unidad base", CEN,
     "insert into presentaciones_producto (producto_id, nombre, factor_a_base) select id, n, f from productos, "
     "(values ('Medio litro',0.5),('Galón',3.785)) v(n,f) where codigo='CD-123' returning nombre", contiene="Galón")
caso("HU1 E5", "Conversión: 2 galones = 7.57 L", CEN,
     "select convertir_a_unidad_base(p.id, pr.id, 2) from productos p join presentaciones_producto pr on pr.producto_id=p.id "
     "where p.codigo='CD-123' and pr.nombre='Galón'", contiene="7.57")
caso("HU1 E5", "Conversión con cantidad decimal se rechaza", CEN,
     "select convertir_a_unidad_base(p.id, pr.id, 1.5) from productos p join presentaciones_producto pr on pr.producto_id=p.id "
     "where p.codigo='CD-123' and pr.nombre='Galón'", espera="CANTIDAD_ENTERA_REQUERIDA")
caso("HU1 E6", "Producto nuevo aparece con existencia 0", CEN,
     "select existencia = 0 from buscar_productos('CD-500')", contiene="t")
caso("Seg", "Usuario sin sesión no puede dar de alta", "anon",
     ins + f"('CD-777','X',null,{PZA},{PAP},'AMBOS')", espera="row-level security")

P1 = admin("select id from productos where codigo='CD-123'")
P2 = admin("select id from productos where codigo='CD-500'")
GUAYMAS = admin("select id from unidades where nombre='Guaymas'")

# ---------- HU2 ----------
caso("HU2 E1", "Compra con proveedor nuevo genera folio ENT", CEN,
     f"select folio, existencia_ubicacion from registrar_entrada({P1},{A1},10,'COMPRA','E1F1',"
     "p_numero_factura=>'F-881', p_numero_partida=>'P-12', p_proveedor_nuevo=>'Químicos del Yaqui')",
     contiene="ENT-2026-0001|10")
caso("HU2 E1", "El proveedor quedó registrado para reusarlo", CEN,
     "select nombre from proveedores", contiene="Químicos del Yaqui")
caso("HU2 E2", "Traspaso desde Guaymas sin factura ni proveedor", CEN,
     f"select folio from registrar_entrada({P1},{A1},5,'REINGRESO_TRASPASO','E1F1',"
     f"p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})", contiene="ENT-2026-0002")
caso("HU2 E3", "Compra sin factura se rechaza", CEN,
     f"select * from registrar_entrada({P1},{A1},5,'COMPRA', p_numero_partida=>'P1', p_proveedor_nuevo=>'X')",
     espera="DATOS_COMPRA_FALTANTES")
caso("HU2 E3", "El folio rechazado no deja hueco", CEN,
     f"select folio from registrar_entrada({P1},{A2},4,'COMPRA', p_numero_factura=>'F-2',"
     "p_numero_partida=>'P-2', p_proveedor_nuevo=>'químicos del yaqui')", contiene="ENT-2026-0003")
caso("HU2 E4", "Existencia de campus = suma de ubicaciones (15 + 4)", CEN,
     f"select existencia from buscar_productos('CD-123')", contiene="19")
caso("HU2 E4", "Detalle por ubicación conserva cada cantidad", CEN,
     f"select string_agg(almacen||':'||coalesce(ubicacion,'-')||':'||cantidad, ' ' order by almacen) "
     f"from vista_existencias_por_ubicacion where producto_id={P1}", contiene="Almacén 1:E1F1:15.000 Almacén 2:-:4.000")
caso("HU2 E5", "Sin almacén se rechaza", CEN,
     f"select * from registrar_entrada({P1},null,5,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})",
     espera="ALMACEN_REQUERIDO")
caso("HU2 E6", "Cantidad 0 se rechaza", CEN,
     f"select * from registrar_entrada({P1},{A1},0,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})",
     espera="CANTIDAD_INVALIDA")
caso("HU2 E6", "Cantidad negativa se rechaza", CEN,
     f"select * from registrar_entrada({P1},{A1},-3,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})",
     espera="CANTIDAD_INVALIDA")
caso("HU2 E6", "Cantidad decimal se rechaza", CEN,
     f"select * from registrar_entrada({P1},{A1},1.5,'COMPRA', p_numero_factura=>'F-DEC', p_numero_partida=>'P-DEC', "
     "p_proveedor_nuevo=>'Proveedor Decimal')", espera="CANTIDAD_ENTERA_REQUERIDA")
caso("HU2 E7", "Producto no registrado", CEN,
     f"select * from registrar_entrada(999999,{A1},5,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})",
     espera="PRODUCTO_NO_REGISTRADO")
caso("Seg", "Almacenista de Centro no registra en almacén de Náinari", CEN,
     f"select * from registrar_entrada({P1},{AN},5,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})",
     espera="SIN_PERMISO")
caso("Seg", "La app no puede escribir existencias directo", CEN,
     f"update existencias set cantidad = 1000", espera="permission denied")
caso("Seg", "La app no puede borrar movimientos", CEN,
     "delete from movimientos_inventario", espera="permission denied")
caso("Seg", "La app no puede generar folios por su cuenta", CEN,
     "select siguiente_folio('ENT')", espera="permission denied")

# Náinari también recibe del mismo producto
caso("HU2", "Entrada en Náinari", NAI,
     f"select folio from registrar_entrada({P1},{AN},7,'COMPRA', p_numero_factura=>'F-9',"
     "p_numero_partida=>'P-9', p_proveedor_nuevo=>'Distribuidora Sonora')", contiene="ENT-2026-0004")

# ---------- HU3 ----------
caso("HU3 E1", "Búsqueda por alias 'pinol' muestra solo Centro (19)", CEN,
     "select codigo||'|'||existencia from buscar_productos('pinol')", contiene="CD-123|19")
caso("HU3 E1", "Náinari ve solo su existencia (7)", NAI,
     "select existencia = 7 from buscar_productos('pinol')", contiene="t")
caso("HU3 E1", "Náinari no ve ubicaciones de Centro", NAI,
     f"select count(*) from vista_existencias_por_ubicacion where producto_id={P1}", contiene="1")
caso("HU3 E1", "Supervisor jefe ve ambos campus (26)", JEFE,
     "select existencia from buscar_productos('CD-123')", contiene="26")
caso("HU3 E3", "Sin coincidencias", CEN,
     "select count(*) from buscar_productos('zzzz')", contiene="0")
caso("HU3 E4", "Filtro Mantenimiento incluye productos 'AMBOS'", CEN,
     "select string_agg(codigo, ',') from buscar_productos(p_tipo=>'MANTENIMIENTO')", contiene="CD-500")
caso("HU3 E4", "Filtro Mantenimiento excluye solo Servicios Generales", CEN,
     "select count(*) filter (where codigo='CD-123') = 0 and count(*) > 0 from buscar_productos(p_tipo=>'MANTENIMIENTO')", contiene="t")
caso("HU3 E4", "Filtro por almacén 2", CEN,
     f"select codigo||'|'||existencia from buscar_productos(p_almacen_id=>{A2})", contiene="CD-123|4")
caso("HU3 E5", "Detalle con fecha de última entrada", CEN,
     "select ultima_entrada is not null from buscar_productos('CD-123')", contiene="t")

# ---------- HU6 (AI-30): búsqueda de materiales que se pueden entregar ----------
# CD-001 no tiene entradas y por nombre queda antes que CD-123: sirve para ver que el
# filtro de existencia se aplica antes del límite.
caso("HU6 Bus", "Alta de un producto sin existencia para la búsqueda", CEN,
     ins + f"('CD-001','Aromatizante ambiental',null,{LITRO},{LIQ},'SERVICIOS_GENERALES') returning codigo",
     contiene="CD-001")
caso("HU6 Bus", "Sin el parámetro nuevo devuelve todos, también los de existencia 0", CEN,
     "select string_agg(codigo||'|'||existencia, ',' order by codigo) from buscar_productos()",
     contiene="CD-001|0,CD-123|19.000,CD-500|0")
caso("HU6 Bus", "Con p_solo_con_existencia=false se comporta igual", CEN,
     "select count(*) = 3 from buscar_productos(p_solo_con_existencia=>false)", contiene="t")
caso("HU6 Bus", "Solo con existencia oculta los de existencia 0", CEN,
     "select string_agg(codigo, ',') = 'CD-123' from buscar_productos(p_solo_con_existencia=>true)", contiene="t")
caso("HU6 Bus", "Solo con existencia y sin coincidencias en stock", CEN,
     "select count(*) from buscar_productos('CD-500', p_solo_con_existencia=>true)", contiene="0")
caso("HU6 Bus", "Solo con existencia busca por alias", CEN,
     "select codigo||'|'||existencia from buscar_productos('pinol', p_solo_con_existencia=>true)", contiene="CD-123|19")
caso("HU6 Bus", "Sin filtro, el primero de la página es el de existencia 0", CEN,
     "select codigo from buscar_productos(p_limite=>1)", contiene="CD-001")
caso("HU6 Bus", "El filtro de existencia se aplica antes del límite", CEN,
     "select string_agg(codigo, ',') = 'CD-123' from buscar_productos(p_limite=>1, p_solo_con_existencia=>true)",
     contiene="t")
caso("HU6 Bus", "Náinari ve el producto con su propia existencia (7)", NAI,
     "select codigo||'|'||existencia from buscar_productos(p_solo_con_existencia=>true)", contiene="CD-123|7")
caso("HU6 Bus", "Supervisor jefe suma la existencia de sus campus (26)", JEFE,
     "select codigo||'|'||existencia from buscar_productos(p_solo_con_existencia=>true)", contiene="CD-123|26")
caso("Seg", "Sin sesión no se usa la búsqueda", "anon",
     "select * from buscar_productos(p_solo_con_existencia=>true)", espera="permission denied")

# ---------- HU6 (AI-62): filtro "Más comunes" ----------
# Ningún producto está marcado todavía. Se marcan CD-123 (con existencia) y luego
# CD-500 (sin existencia) para ver el filtro solo y combinado con la existencia.
caso("HU6 Fil", "Sin el parámetro nuevo devuelve todos (3)", CEN,
     "select count(*) = 3 from buscar_productos()", contiene="t")
caso("HU6 Fil", "Sin productos marcados, 'Más comunes' no devuelve nada", CEN,
     "select count(*) from buscar_productos(p_solo_mas_comunes=>true)", contiene="0")
admin("update productos set mas_comunes = true where codigo = 'CD-123'")
caso("HU6 Fil", "'Más comunes' devuelve solo los marcados", CEN,
     "select string_agg(codigo, ',') = 'CD-123' from buscar_productos(p_solo_mas_comunes=>true)", contiene="t")
caso("HU6 Fil", "Con p_solo_mas_comunes=false se comporta igual (3)", CEN,
     "select count(*) = 3 from buscar_productos(p_solo_mas_comunes=>false)", contiene="t")
admin("update productos set mas_comunes = true where codigo = 'CD-500'")
caso("HU6 Fil", "Los marcados salen primero, ordenados por nombre", CEN,
     "select string_agg(codigo, ',') from buscar_productos(p_solo_mas_comunes=>true)", contiene="CD-123,CD-500")
caso("HU6 Fil", "'Más comunes' con existencia oculta los marcados en 0", CEN,
     "select string_agg(codigo, ',') = 'CD-123' from "
     "buscar_productos(p_solo_mas_comunes=>true, p_solo_con_existencia=>true)", contiene="t")
caso("HU6 Fil", "'Más comunes' se combina con el texto", CEN,
     "select string_agg(codigo, ',') = 'CD-500' from buscar_productos('papel', p_solo_mas_comunes=>true)",
     contiene="t")
caso("HU6 Fil", "'Más comunes' se combina con categoría", CEN,
     f"select string_agg(codigo, ',') = 'CD-500' from buscar_productos(p_categoria_id=>{PAP}, p_solo_mas_comunes=>true)",
     contiene="t")
caso("HU6 Fil", "Sin texto y sin filtros lista todo con existencia", CEN,
     "select string_agg(codigo, ',') = 'CD-123' from buscar_productos(p_solo_con_existencia=>true)", contiene="t")
caso("Seg", "Sin sesión no se usa el filtro de más comunes", "anon",
     "select * from buscar_productos(p_solo_mas_comunes=>true)", espera="permission denied")

# ---------- HU6 (AI-63): total de resultados para paginar ----------
# En este punto hay 3 productos (CD-001, CD-123, CD-500); solo CD-123 tiene existencia.
caso("HU6 Pag", "El total no depende del límite: 3 con límite 1", CEN,
     "select count(*)||'|'||min(total_resultados) from buscar_productos(p_limite=>1)", contiene="1|3")
caso("HU6 Pag", "Cada fila de la página trae el mismo total", CEN,
     "select count(distinct total_resultados)||'|'||min(total_resultados) from buscar_productos()", contiene="1|3")
caso("HU6 Pag", "La página 2 conserva el total", CEN,
     "select codigo||'|'||total_resultados from buscar_productos(p_limite=>1, p_desplazar=>1)", contiene="|3")
caso("HU6 Pag", "La página 2 trae el siguiente producto, no el primero", CEN,
     "select (select codigo from buscar_productos(p_limite=>1)) <> "
     "(select codigo from buscar_productos(p_limite=>1, p_desplazar=>1))", contiene="t")
caso("HU6 Pag", "El total respeta el filtro de existencia (1)", CEN,
     "select total_resultados from buscar_productos(p_solo_con_existencia=>true)", contiene="1")
caso("HU6 Pag", "El total respeta el texto (papel: 1)", CEN,
     "select total_resultados from buscar_productos('papel')", contiene="1")
caso("HU6 Pag", "El total respeta 'Más comunes' (2)", CEN,
     "select min(total_resultados)||'|'||count(*) from buscar_productos(p_solo_mas_comunes=>true)", contiene="2|2")
caso("HU6 Pag", "Una página fuera de rango no trae filas", CEN,
     "select count(*) from buscar_productos(p_limite=>8, p_desplazar=>8)", contiene="0")
caso("HU6 Pag", "Náinari cuenta solo lo que tiene existencia en su campus (1)", NAI,
     "select total_resultados from buscar_productos(p_solo_con_existencia=>true)", contiene="1")

# ---------- Personal, zona y supervisor (mínimo Épica 5) ----------
admin(f"""
insert into auth.users values ('{SUP}');
insert into usuarios (id, nombre, rol, campus_id) values
 ('{SUP}', 'Patricia Ibarra', 'SUPERVISOR', (select id from campus where clave='CEN'));
insert into trabajadores (nombre, tipo, compania, dependencia, campus_id) values
 ('Juan Pérez Soto', 'ITSON', null, 'SERVICIOS_GENERALES', (select id from campus where clave='CEN')),
 ('María Sánchez', 'COMPANIA', 'Maxi Servicios', 'SERVICIOS_GENERALES', (select id from campus where clave='CEN'));
insert into zonas (campus_id, nombre, edificio, piso, num_banos)
 select id, 'Edificio 1800 - Planta baja', '1800', 'Planta baja', 4 from campus where clave='CEN';
insert into trabajadores_zonas select p.id, z.id from trabajadores p, zonas z;
insert into limites_material_zona select z.id, {P1}, 3, 5 from zonas z;
""")
JUAN = admin("select id from trabajadores where nombre='Juan Pérez Soto'")
MARIA = admin("select id from trabajadores where nombre='María Sánchez'")
CEN_ID = admin("select id from campus where clave='CEN'")
NAI_ID = admin("select id from campus where clave='NAI'")
# La app sube las firmas al bucket antes de llamar las funciones
admin("insert into storage.objects (bucket_id, name) select 'firmas', c || '/' || f from (values ('"
      + CEN_ID + "'), ('" + NAI_ID + "')) v(c), (values ('r.png'), ('e.png'), ('t.png'), ('a.png')) w(f)")
FIRMAS = f"p_firma_recibe=>'{CEN_ID}/r.png', p_firma_entrega=>'{CEN_ID}/e.png'"

# ---------- HU4 (boleta real: 2 L entregados a Juan) ----------
caso("HU6 E1", "Entrega a Juan de 2 L con firmas", CEN,
     f"select estado||'|'||folio from crear_boleta(p_materiales=>'[{{\"producto_id\":{P1},\"cantidad\":2}}]', "
     f"p_trabajador_id=>{JUAN}, {FIRMAS})", contiene="ENTREGADA|BOL-2026-0001")
BM = admin("select id from boletas_materiales limit 1")
caso("HU4 E2", "Reingresar 5 cuando se entregaron 2", CEN,
     f"select * from registrar_reingreso({BM},{A1},5,'E1F1')", espera="REINGRESO_EXCEDE")
caso("HU4 E1", "Reingreso válido de 1 L con folio REI", CEN,
     f"select folio||'|'||existencia_ubicacion from registrar_reingreso({BM},{A1},1,'E1F1')", contiene="REI-2026-0001|14")
caso("HU4 E1", "Reingreso queda ligado a la boleta", CEN,
     f"select b.folio from entradas e join boletas_materiales m on m.id=e.boleta_material_id "
     "join boletas b on b.id=m.boleta_id where e.folio='REI-2026-0001'", contiene="BOL-2026-0001")
caso("HU4 E2", "Segundo reingreso de 2 unidades rebasa lo pendiente (1)", CEN,
     f"select * from registrar_reingreso({BM},{A1},2)", espera="REINGRESO_EXCEDE")
caso("HU4", "Reingreso con cantidad decimal se rechaza", CEN,
     f"select * from registrar_reingreso({BM},{A1},1.5)", espera="CANTIDAD_ENTERA_REQUERIDA")
caso("Seg", "Náinari no reingresa una boleta de Centro", NAI,
     f"select * from registrar_reingreso({BM},{AN},1)", espera="CAMPUS_DISTINTO")
caso("HU3 E5", "Detalle con fecha de última salida", CEN,
     "select ultima_salida is not null from buscar_productos('CD-123')", contiene="t")

# ---------- HU5 ----------
caso("HU5 E2", "Ajuste sin motivo se rechaza", CEN,
     f"select * from registrar_ajuste({P1},{A1},12,'  ','E1F1')", espera="MOTIVO_REQUERIDO")
caso("HU5 E1", "Ajuste a 12 por conteo físico (diferencia -2)", CEN,
     f"select folio||'|'||diferencia from registrar_ajuste({P1},{A1},12,'Conteo físico mensual','E1F1')",
     contiene="AJU-2026-0001|-2")
caso("HU5 E1", "Ajuste visible en historial general", CEN,
     "select tipo||'|'||cantidad||'|'||existencia_resultante||'|'||motivo_ajuste||'|'||registrado_por "
     "from vista_historial_movimientos where folio='AJU-2026-0001'", contiene="AJUSTE|-2.000|12.000|Conteo físico mensual|Alicia García")
caso("HU5", "Ajuste sin diferencia se rechaza", CEN,
     f"select * from registrar_ajuste({P1},{A1},12,'Recuento','E1F1')", espera="SIN_DIFERENCIA")
caso("HU5", "Ajuste a cantidad negativa se rechaza", CEN,
     f"select * from registrar_ajuste({P1},{A1},-1,'Error','E1F1')", espera="CANTIDAD_INVALIDA")
# ---------- HU6: periodicidad, límite de zona y sugerencia de autorización ----------
def boleta(materiales, extra=""):
    return f"select estado||'|'||folio from crear_boleta(p_materiales=>'{materiales}'{extra})"

m1 = f'[{{"producto_id":{P1},"cantidad":1}}]'
m1_motivo = f'[{{"producto_id":{P1},"cantidad":1,"motivo_excepcion":"Derrame en baños"}}]'

caso("HU6 E8", "Validación muestra periodicidad no cumplida (faltan 5 días)", CEN,
     f"select excede_periodicidad||'|'||dias_faltantes||'|'||(ultima_entrega is not null) "
     f"from validar_material({P1}, 1, p_trabajador_id=>{JUAN})", contiene="true|5|true")
caso("HU6 E8", "Sin motivo no se puede entregar antes de tiempo", CEN,
     boleta(m1, f", p_trabajador_id=>{JUAN}, {FIRMAS}"), espera="MOTIVO_EXCEPCION_REQUERIDO")
caso("HU6 E8", "Con motivo se entrega de inmediato y devuelve la alerta", CEN,
     f"select estado||'|'||folio||'|'||coalesce(alertas->0->>'excede_periodicidad','') "
     f"from crear_boleta(p_materiales=>'{m1_motivo}', p_trabajador_id=>{JUAN}, {FIRMAS})",
     contiene="ENTREGADA|BOL-2026-0002|true")
caso("HU6 E8", "Descuenta existencia en el acto (12 a 11 en E1F1)", CEN,
     f"select cantidad from vista_existencias_por_ubicacion where producto_id={P1} and ubicacion='E1F1'", contiene="11.000")
caso("HU6 E8", "No se generan avisos de autorización", CEN,
     "select count(*) from notificaciones where tipo like 'AUTORIZACION%'", contiene="0")
caso("Estructura", "No existe la tabla autorizaciones", CEN,
     "select coalesce(to_regclass('public.autorizaciones')::text,'NO_EXISTE')", contiene="NO_EXISTE")
caso("Estructura", "No existen las RPC de autorización ni de entrega en dos pasos", CEN,
     "select coalesce(to_regprocedure('public.resolver_autorizacion(bigint,boolean,text)')::text,'NO_EXISTE')"
     "||'|'||coalesce(to_regprocedure('public.confirmar_entrega(bigint,text,text)')::text,'NO_EXISTE')",
     contiene="NO_EXISTE|NO_EXISTE")
caso("HU6 E1", "Las firmas siguen siendo obligatorias", CEN,
     f"select * from crear_boleta(p_materiales=>'{m1}', p_trabajador_id=>{JUAN}, "
     f"p_firma_recibe=>'', p_firma_entrega=>'{CEN_ID}/e.png')", espera="FIRMAS_REQUERIDAS")

# Pasan 6 días desde las entregas de Juan
admin("update boletas set entregado_en = entregado_en - interval '6 days' where trabajador_id is not null")
caso("HU6 E9", "Periodicidad cumplida (hace 6 días, intervalo 5)", CEN,
     f"select excede_periodicidad||'|'||excede_limite from validar_material({P1}, 1, p_trabajador_id=>{JUAN})",
     contiene="false|false")
caso("HU6 E9", "María nunca lo ha recibido: sin restricción", CEN,
     f"select excede_periodicidad::text from validar_material({P1}, 1, p_trabajador_id=>{MARIA})", contiene="false")
caso("HU6 E1", "Entrega a Juan de 2 L", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2}}]', f", p_trabajador_id=>{JUAN}, {FIRMAS}"), contiene="ENTREGADA")
caso("HU6 E10", "Límite de zona: 3 L cada 5 días, ya van 2, María pide 2", CEN,
     f"select excede_limite||'|'||limite_cantidad||'|'||entregado_periodo "
     f"from validar_material({P1}, 2, p_trabajador_id=>{MARIA})", contiene="true|3.000|2.000")
caso("HU6 E10", "Excede límite sin motivo se rechaza", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2}}]', f", p_trabajador_id=>{MARIA}, {FIRMAS}"), espera="MOTIVO_EXCEPCION_REQUERIDO")
caso("HU6 E10", "Con motivo se entrega de inmediato, sin supervisor en el sistema", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2,"motivo_excepcion":"Evento en el edificio"}}]',
            f", p_trabajador_id=>{MARIA}, p_autorizo_nombre=>'Supervisor externo', {FIRMAS}"),
     contiene="ENTREGADA|BOL-")
caso("HU6 E10", "Guarda el motivo y el nombre libre de quien autorizó", CEN,
     "select m.motivo_excepcion||'|'||b.autorizo_nombre from boletas_materiales m "
     "join boletas b on b.id=m.boleta_id where m.motivo_excepcion='Evento en el edificio'",
     contiene="Evento en el edificio|Supervisor externo")
caso("Seg", "No hay boletas pendientes ni rechazadas", CEN,
     "select count(*) from boletas where estado<>'ENTREGADA'", contiene="0")

caso("HU6 E2", "Solicitante sin registro con nombre y unidad", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":1,"comentario":"Para limpieza de oficina"}}]',
            f", p_solicitante_nombre=>'Rosa Molina', p_solicitante_unidad=>'Navojoa', p_numero_solicitud=>'OT-9981', {FIRMAS}"),
     contiene="ENTREGADA")
caso("HU6 E3/E5", "Guarda número de solicitud y comentario", CEN,
     "select b.numero_solicitud||'|'||m.comentario from boletas b join boletas_materiales m on m.boleta_id=b.id "
     "where b.solicitante_nombre='Rosa Molina'", contiene="OT-9981|Para limpieza de oficina")
caso("HU6 E2", "Sin registro y sin unidad se rechaza", CEN,
     boleta(m1, f", p_solicitante_nombre=>'Rosa Molina', {FIRMAS}"), espera="SOLICITANTE_REQUERIDO")
caso("HU6 E6", "Existencia insuficiente", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":1000}}]', f", p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', {FIRMAS}"),
     espera="STOCK_INSUFICIENTE")
caso("HU6 E7", "Cantidad cero", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":0}}]', f", p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', {FIRMAS}"),
     espera="CANTIDAD_INVALIDA")
caso("HU6 E7", "Cantidad decimal se rechaza", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":1.5}}]', f", p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', {FIRMAS}"),
     espera="CANTIDAD_ENTERA_REQUERIDA")
caso("HU6", "Validación con cantidad decimal se rechaza", CEN,
     f"select * from validar_material({P1}, 1.5)", espera="CANTIDAD_ENTERA_REQUERIDA")
caso("HU6 E7", "Entrega en presentación: 2 medios litros = 1 L", CEN,
     f"select 1 from crear_boleta(p_materiales=>('[{{\"producto_id\":{P1},\"cantidad\":2,"
     f"\"presentacion_id\":'||(select id from presentaciones_producto where nombre='Medio litro')||'}}]')::jsonb, "
     f"p_solicitante_nombre=>'Ana', p_solicitante_unidad=>'Centro', {FIRMAS}); "
     "select m.cantidad||'|'||m.cantidad_base from boletas_materiales m join boletas b on b.id=m.boleta_id "
     "where b.solicitante_nombre='Ana'", contiene="2.000|1.000")
caso("HU6", "Boleta vacía", CEN, boleta('[]', f", p_trabajador_id=>{JUAN}, {FIRMAS}"), espera="BOLETA_VACIA")
caso("Seg", "Náinari no ve boletas de Centro", NAI, "select count(*) from boletas", contiene="0")
caso("Seg", "La app no puede crear boletas directo", CEN,
     "insert into boletas (folio, campus_id, solicitante_nombre, estado) values ('X', 1, 'X', 'ENTREGADA')",
     espera="permission denied")

# ---------- HU7: activos ----------
def activo(cod, nombre, modelo, serie, alm=A1, user=CEN):
    return f"select estado from registrar_activo('{cod}','{nombre}','{modelo}','{serie}',{alm},'Anaquel 2','Bosch',2500)"
caso("HU7 E1", "Registro de activo queda Disponible", CEN, activo('ACT-104','Rotomartillo','GBH 2-28','BSH-987654321'), contiene="DISPONIBLE")
caso("HU7 E2", "Código duplicado (minúsculas)", CEN, activo('act-104','Otro','X','Y'), espera="ACTIVO_DUPLICADO")
caso("HU7 E3", "Sin modelo ni serie", CEN,
     f"select * from registrar_activo('ACT-999','Taladro','','',{A1})", espera="CAMPOS_REQUERIDOS")
caso("HU7", "Otros activos", CEN, activo('ACT-200','Taladro','DCF887','DCF887D2') + "; " + activo('ACT-300','Esmeriladora','DWE4020','DW-55'),
     contiene="DISPONIBLE")
caso("Seg", "Náinari registra su propio activo", NAI, activo('ACT-N01','Escalera','C-2224','LOTE-1', alm=AN), contiene="DISPONIBLE")
caso("Seg", "La app no puede cambiar el estado directo", CEN,
     "update activos set estado='DISPONIBLE'", espera="permission denied")

ACT104 = admin("select id from activos where codigo='ACT-104'")
ACT200 = admin("select id from activos where codigo='ACT-200'")
ACT300 = admin("select id from activos where codigo='ACT-300'")
admin(f"""
set request.jwt.claim.sub = '{CEN}';
insert into productos (codigo, nombre_estandar, unidad_base_id, categoria_id, tipo, creado_por)
values ('CD-700', 'Guantes de nitrilo', {PZA}, {PAP}, 'MANTENIMIENTO', '{CEN}');
""")
P3 = admin("select id from productos where codigo='CD-700'")
run(f"select * from registrar_entrada({P3},{A1},10,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS})", CEN)

# ---------- HU8: préstamos ----------
def prestamo(personal, activo_id, dias, materiales='[]', extra=""):
    return (f"select estado||'|'||alertas::text from crear_boleta(p_materiales=>'{materiales}', "
            f"p_herramientas=>'[{{\"activo_id\":{activo_id},\"dias_prestamo\":{dias}}}]', "
            f"p_trabajador_id=>{personal}, {FIRMAS}{extra})")
caso("HU8 E1/E6", "Boleta combinada: guantes + rotomartillo 3 días", CEN,
     prestamo(JUAN, ACT104, 3, f'[{{"producto_id":{P3},"cantidad":2}}]', ", p_numero_solicitud=>'OT-9981'"),
     contiene="ENTREGADA|[]")
caso("HU8 E1", "Préstamo abierto: folio PRE, vigente, 3 días restantes", CEN,
     "select folio||'|'||seguimiento||'|'||dias_restantes||'|'||custodio from vista_seguimiento_prestamos where codigo='ACT-104'",
     contiene="PRE-2026-0001|VIGENTE|3|Juan Pérez Soto")
caso("HU8 E1", "Activo pasa a En préstamo y material se descuenta", CEN,
     f"select a.estado||'|'||(select existencia from buscar_productos('CD-700')) from activos a where a.id={ACT104}",
     contiene="EN_PRESTAMO|8")
caso("HU8 E2", "Herramienta ya prestada indica custodio", CEN, prestamo(MARIA, ACT104, 2), espera="prestado a Juan Pérez Soto")
caso("HU8 E3", "A reparación (cambio manual con motivo)", CEN,
     f"select cambiar_estado_activo({ACT300}, 'EN_REPARACION', 'Disco dañado')", contiene="EN_REPARACION")
caso("HU8 E3", "Herramienta en reparación no se presta", CEN, prestamo(MARIA, ACT300, 2), espera="ACTIVO_NO_DISPONIBLE")
caso("HU8 E4", "Código no registrado", CEN, "select * from validar_activo('NO-EXISTE')", espera="ACTIVO_NO_ENCONTRADO")
caso("Seg", "Centro no encuentra activos de Náinari", CEN, "select * from validar_activo('ACT-N01')", espera="ACTIVO_NO_ENCONTRADO")

# validar_activo (AI-84): lo que responde según el estado del activo.
def validar(codigo):
    return ("select codigo||'|'||estado||'|'||coalesce(custodio_actual, 'sin custodio')||'|'||"
            f"coalesce(to_char(fecha_prevista, 'YYYY-MM-DD'), 'sin fecha') from validar_activo('{codigo}')")
caso("HU8 Val", "Disponible: sus datos sin custodio ni fecha prevista", CEN,
     validar('ACT-200'), contiene="ACT-200|DISPONIBLE|sin custodio|sin fecha")
caso("HU8 Val", "Prestado: custodio y fecha prevista (hoy + 3 días)", CEN,
     validar('ACT-104'),
     contiene="ACT-104|EN_PRESTAMO|Juan Pérez Soto|" + admin("select to_char(now() + interval '3 days', 'YYYY-MM-DD')"))
caso("HU8 Val", "En reparación: devuelve su estado, sin custodio", CEN,
     validar('ACT-300'), contiene="ACT-300|EN_REPARACION|sin custodio|sin fecha")
caso("HU8 Val", "De baja: devuelve su estado, sin custodio", CEN,
     f"select cambiar_estado_activo({ACT300}, 'DE_BAJA', 'Motor quemado'); " + validar('ACT-300'),
     contiene="ACT-300|DE_BAJA|sin custodio|sin fecha")
caso("HU8", "Solo personal registrado recibe herramientas", CEN,
     f"select * from crear_boleta(p_herramientas=>'[{{\"activo_id\":{ACT200},\"dias_prestamo\":1}}]', "
     f"p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', {FIRMAS})", espera="HERRAMIENTA_SIN_SOLICITANTE")

# El préstamo de Juan vence: se prestó hace 5 días por 3
admin(f"update prestamos set prestado_en = now() - interval '5 days', fecha_prevista = now() - interval '2 days' "
      f"where activo_id = {ACT104}")
caso("HU8 E5", "Validación advierte que el solicitante tiene un vencido", CEN,
     f"select solicitante_con_vencido from validar_activo('ACT-200', {JUAN})", contiene="t")
# Juan ya tiene un vencido, pero sin indicar el trabajador no se revisa a nadie.
caso("HU8 Val", "Sin trabajador no advierte vencidos", CEN,
     "select codigo||'|'||solicitante_con_vencido from validar_activo('ACT-200')", contiene="ACT-200|false")
caso("HU8 Val", "Encuentra el código en minúsculas y con espacios", CEN,
     "select codigo||'|'||estado from validar_activo('  act-200  ')", contiene="ACT-200|DISPONIBLE")
caso("HU8 E5", "Se presta con advertencia registrada (1 día)", CEN,
     prestamo(JUAN, ACT200, 1), contiene='"solicitante_con_vencido": true')

# Varios activos con el mismo nombre: se prestan; la app solo avisa con los
# préstamos abiertos del trabajador (POST /activos/validar los lee de la vista).
caso("HU8", "Otros tres taladros", CEN,
     activo('ACT-201', 'Taladro', 'DCD771', 'DCD771-1') + "; " + activo('ACT-202', 'Taladro', 'DCD771', 'DCD771-2')
     + "; " + activo('ACT-203', 'Taladro', 'DCD771', 'DCD771-3'),
     contiene="DISPONIBLE")
ACT201 = admin("select id from activos where codigo='ACT-201'")
ACT202 = admin("select id from activos where codigo='ACT-202'")
ACT203 = admin("select id from activos where codigo='ACT-203'")
caso("HU8", "La vista lista los préstamos abiertos de Juan con su seguimiento", CEN,
     f"select string_agg(codigo||':'||seguimiento, ',' order by fecha_prevista) from vista_seguimiento_prestamos "
     f"where trabajador_id={JUAN} and estado='ACTIVO'", contiene="ACT-104:VENCIDO,ACT-200:PROXIMO_A_VENCER")
caso("HU8", "Un taladro con el mismo nombre que el que ya tiene sigue prestable", CEN,
     f"select estado from validar_activo('ACT-201', {JUAN})", contiene="DISPONIBLE")
caso("HU8", "Se presta otro taladro a quien ya tiene uno", CEN,
     prestamo(JUAN, ACT201, 2), contiene="ENTREGADA")
caso("HU8", "Dos taladros en la misma boleta", CEN,
     f"select estado from crear_boleta(p_herramientas=>'[{{\"activo_id\":{ACT202},\"dias_prestamo\":2}},"
     f"{{\"activo_id\":{ACT203},\"dias_prestamo\":2}}]', p_trabajador_id=>{MARIA}, {FIRMAS})",
     contiene="ENTREGADA")
caso("HU8", "María queda con dos préstamos abiertos de taladro", CEN,
     f"select count(*) from vista_seguimiento_prestamos where trabajador_id={MARIA} and estado='ACTIVO' "
     f"and herramienta='Taladro'", contiene="2")

# ---------- HU10: seguimiento ----------
caso("HU10 E1", "Vencido con 2 días de retraso", CEN,
     "select seguimiento||'|'||dias_retraso from vista_seguimiento_prestamos where codigo='ACT-104'", contiene="VENCIDO|2")
caso("HU10 E3", "Préstamo de 1 día está próximo a vencer", CEN,
     "select seguimiento from vista_seguimiento_prestamos where codigo='ACT-200'", contiene="PROXIMO_A_VENCER")
caso("HU10 E4", "Aviso de vencido al abrir la app", CEN,
     "select count(*) from obtener_notificaciones() where tipo='PRESTAMO_VENCIDO'", contiene="1")
caso("HU10 E4", "Abrir de nuevo no duplica el aviso", CEN,
     "select count(*) from obtener_notificaciones() where tipo='PRESTAMO_VENCIDO'", contiene="1")
caso("HU10 E4", "El supervisor también recibe el aviso", SUP,
     "select count(*) from obtener_notificaciones() where tipo='PRESTAMO_VENCIDO'", contiene="1")
caso("Seg", "Náinari no recibe avisos de Centro", NAI,
     "select count(*) from obtener_notificaciones()", contiene="0")
caso("HU10", "Marcar aviso como leído", CEN,
     "update notificaciones set leida_en = now() where tipo='PRESTAMO_VENCIDO' returning tipo", contiene="PRESTAMO_VENCIDO")
caso("Seg", "No se puede alterar el texto de un aviso", CEN,
     "update notificaciones set mensaje = 'x'", espera="permission denied")

# ---------- HU9: devoluciones ----------
PR104 = admin(f"select id from prestamos where activo_id={ACT104} and estado='ACTIVO'")
PR200 = admin(f"select id from prestamos where activo_id={ACT200} and estado='ACTIVO'")
caso("HU9 E1/E3", "Devolución en buen estado con 2 días de retraso", CEN,
     f"select folio||'|'||dias_retraso||'|'||estado_activo from registrar_devolucion({PR104}, 'BUEN_ESTADO', '{CEN_ID}/t.png', '{CEN_ID}/a.png')",
     contiene="DEV-2026-0001|2|DISPONIBLE")
caso("HU9 E3", "El retraso queda en el historial del préstamo", CEN,
     "select estado||'|'||dias_retraso from vista_seguimiento_prestamos where codigo='ACT-104'", contiene="DEVUELTO|2")
caso("HU9", "No se devuelve dos veces", CEN,
     f"select * from registrar_devolucion({PR104}, 'BUEN_ESTADO', '{CEN_ID}/t.png', '{CEN_ID}/a.png')", espera="PRESTAMO_CERRADO")
caso("HU9 E1", "Sin firmas se rechaza", CEN,
     f"select * from registrar_devolucion({PR200}, 'BUEN_ESTADO', '', '{CEN_ID}/a.png')", espera="FIRMAS_REQUERIDAS")
caso("HU9 E2", "Dañado sin descripción", CEN,
     f"select * from registrar_devolucion({PR200}, 'DANADO', '{CEN_ID}/t.png', '{CEN_ID}/a.png')", espera="DESCRIPCION_REQUERIDA")
caso("HU9 E2", "Dañado pasa a En reparación", CEN,
     f"select estado_activo from registrar_devolucion({PR200}, 'DANADO', '{CEN_ID}/t.png', '{CEN_ID}/a.png', 'Broca trabada')",
     contiene="EN_REPARACION")
caso("HU9 E4", "Préstamo nuevo a María para reporte de robo", CEN, prestamo(MARIA, ACT104, 2), contiene="ENTREGADA")
PR_M = admin(f"select id from prestamos where activo_id={ACT104} and estado='ACTIVO'")
caso("HU9 E4", "Robo sin declaración", CEN, f"select reportar_robo_extravio({PR_M}, '  ')", espera="DECLARACION_REQUERIDA")
caso("HU9 E4", "Robo con declaración: folio ROB", CEN,
     f"select reportar_robo_extravio({PR_M}, 'Se extravió en el estacionamiento')", contiene="ROB-2026-0001")
caso("HU9 E4", "Activo queda Robo/Extravío y conserva custodio", CEN,
     f"select a.estado||'|'||v.custodio||'|'||v.estado from activos a join vista_seguimiento_prestamos v on v.activo_id=a.id "
     f"where a.id={ACT104} and v.prestamo_id={PR_M}", contiene="ROBO_EXTRAVIO|María Sánchez|ROBO_EXTRAVIO")
caso("HU9 E4", "Un activo robado no se presta", CEN, prestamo(JUAN, ACT104, 2), espera="ACTIVO_NO_DISPONIBLE")
caso("HU8 Val", "Robo/Extravío: devuelve su estado; sin préstamo activo no hay custodio", CEN,
     validar('ACT-104'), contiene="ACT-104|ROBO_EXTRAVIO|sin custodio|sin fecha")
caso("HU7", "Bitácora de estados del rotomartillo", CEN,
     f"select string_agg(estado_nuevo, '>' order by id) from historial_estados_activo where activo_id={ACT104}",
     contiene="DISPONIBLE>EN_PRESTAMO>DISPONIBLE>EN_PRESTAMO>ROBO_EXTRAVIO")
caso("Seg", "Almacenista no da de alta personal (lo hace el supervisor)", CEN,
     f"insert into trabajadores (nombre, tipo, dependencia, campus_id) values ('X','ITSON','MANTENIMIENTO',1)",
     espera="row-level security")
caso("Kardex", "Salida de varias ubicaciones cuando una no alcanza", CEN,
     f"select 1 from crear_boleta(p_materiales=>('[{{\"producto_id\":{P1},\"cantidad\":"
     f"'||(select existencia - 1 from buscar_productos('CD-123'))||'}}]')::jsonb, p_solicitante_nombre=>'Inventario', "
     f"p_solicitante_unidad=>'Centro', {FIRMAS}); "
     "select count(distinct m.ubicacion_id)||'|'||(select existencia from buscar_productos('CD-123')) "
     "from boletas b join boletas_materiales bm on bm.boleta_id=b.id "
     "join movimientos_inventario m on m.boleta_material_id=bm.id where b.solicitante_nombre='Inventario'", contiene="2|1.000")

# ---------- Firmas (Storage) ----------
caso("Firmas", "Firma de otro campus se rechaza", CEN,
     boleta(f'[{{"producto_id":{P3},"cantidad":1}}]', f", p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', "
            f"p_firma_recibe=>'{NAI_ID}/r.png', p_firma_entrega=>'{CEN_ID}/e.png'"), espera="FIRMA_INVALIDA")
caso("Firmas", "Firma que no se subió se rechaza", CEN,
     boleta(f'[{{"producto_id":{P3},"cantidad":1}}]', f", p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', "
            f"p_firma_recibe=>'{CEN_ID}/no-existe.png', p_firma_entrega=>'{CEN_ID}/e.png'"), espera="FIRMA_NO_ENCONTRADA")
caso("Firmas", "Almacenista sube firma en la carpeta de su campus", CEN,
     f"insert into storage.objects (bucket_id, name) values ('firmas', '{CEN_ID}/nueva.png') returning name",
     contiene=f"{CEN_ID}/nueva.png")
caso("Firmas", "No puede subir en la carpeta de otro campus", CEN,
     f"insert into storage.objects (bucket_id, name) values ('firmas', '{NAI_ID}/x.png')", espera="row-level security")
caso("Firmas", "No ve las firmas de otro campus", CEN,
     f"select count(*) from storage.objects where name like '{NAI_ID}/%'", contiene="0")
caso("Firmas", "Ve las firmas de su campus", CEN,
     f"select count(*) > 0 from storage.objects where name like '{CEN_ID}/%'", contiene="t")
caso("Firmas", "No puede borrar una firma", CEN,
     "delete from storage.objects returning name", contiene="DELETE 0")
caso("Firmas", "No puede reemplazar una firma", CEN,
     "update storage.objects set name = name || 'x' returning name", contiene="UPDATE 0")

# ---------- HU6: historial de entregas (AI-39) ----------
H = "select {} from vista_historial_entregas where {}"
ZONA = admin("select id from zonas where nombre='Edificio 1800 - Planta baja'")
caso("HU6 Hist", "Por solicitante registrado: 3 entregas de CD-123 a Juan (5 L)", CEN,
     H.format("count(*)||'|'||sum(cantidad_base)", f"trabajador_id={JUAN} and producto_id={P1}"), contiene="3|5.000")
caso("HU6 Hist", "La entrega con excepción consta en el historial (sin estado pendiente)", CEN,
     H.format("count(*)||'|'||sum(cantidad_base)", f"trabajador_id={MARIA}"), contiene="1|2.000")
caso("HU6 Hist", "Por solicitante sin registro (nombre parcial)", CEN,
     H.format("tipo_solicitante||'|'||solicitante_nombre||'|'||numero_solicitud||'|'||comentario", "solicitante_nombre ilike '%rosa%'"),
     contiene="SIN_REGISTRO|Rosa Molina|OT-9981|Para limpieza de oficina")
caso("HU6 Hist", "Por insumo: guantes solo en la boleta combinada", CEN,
     H.format("string_agg(folio||'|'||cantidad, ',')", f"producto_id={P3}"), contiene="BOL-2026-0007|2.000")
caso("HU6 Hist", "Conserva la presentación entregada y su equivalente", CEN,
     H.format("presentacion||'|'||cantidad||'|'||cantidad_base||'|'||unidad_base", "solicitante_nombre='Ana'"),
     contiene="Medio litro|2.000|1.000|L")
caso("HU6 Hist", "Por zona: 5 renglones entregados en el Edificio 1800", CEN,
     H.format("count(*)||'|'||min(zona)", f"zona_id={ZONA}"), contiene="5|Edificio 1800 - Planta baja")
caso("HU6 Hist", "Muestra la excepción y su motivo (sin estado de autorización)", CEN,
     H.format("excede_periodicidad||'|'||motivo_excepcion", "folio='BOL-2026-0002'"), contiene="true|Derrame en baños")
caso("HU6 Hist", "Muestra lo reingresado de cada renglón (HU4)", CEN,
     H.format("cantidad||'|'||cantidad_reingresada||'|'||entregado_por", "folio='BOL-2026-0001'"),
     contiene="2.000|1.000|Alicia García")
caso("HU6 Hist", "Entrega en Náinari", NAI,
     boleta(f'[{{"producto_id":{P1},"cantidad":1}}]', f", p_solicitante_nombre=>'Luis Ochoa', p_solicitante_unidad=>'Náinari', "
            f"p_firma_recibe=>'{NAI_ID}/r.png', p_firma_entrega=>'{NAI_ID}/e.png'"), contiene="ENTREGADA")
caso("Seg", "Centro no ve el historial de Náinari", CEN, H.format("count(*)", f"campus_id={NAI_ID}"), contiene="0")
caso("Seg", "Náinari ve solo su entrega", NAI, H.format("string_agg(solicitante_nombre, ',')", "true"), contiene="Luis Ochoa")
caso("Seg", "Supervisor jefe ve el historial de ambos campus", JEFE,
     H.format("count(distinct campus_id)", "true"), contiene="2")
caso("Seg", "Sin sesión no se lee el historial", "anon", H.format("count(*)", "true"), espera="permission denied")
caso("Seg", "El historial no se modifica desde la app", CEN,
     "select bool_or(has_table_privilege('vista_historial_entregas', p)) "
     "from unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p", contiene="f")

# ---------- HU8: boleta combinada, todo o nada (AI-50) ----------
# Materiales y herramientas se registran en una sola transacción: si algo falla no
# queda boleta, ni salida de material, ni préstamo. Usa su propio material, activos
# y personal para no mover los conteos de las secciones anteriores.
def en_paralelo(sql_a, sql_b, user, retraso=0.5):
    """Corre dos consultas en sesiones distintas; la segunda empieza `retraso` segundos después.
    Devuelve (ok, salida, segundos) de cada una."""
    pre = f"set role authenticated; set request.jwt.claim.sub = '{user}';"
    def lanzar(sql):
        return time.monotonic(), subprocess.Popen(PSQL + ["-c", pre + sql], stdout=subprocess.PIPE,
                                                  stderr=subprocess.STDOUT, text=True, encoding="utf-8")
    sesiones = [lanzar(sql_a)]
    time.sleep(retraso)
    sesiones.append(lanzar(sql_b))
    res = []
    for inicio, p in sesiones:
        salida = p.communicate()[0].strip()
        res.append((p.returncode == 0, salida, time.monotonic() - inicio))
    return res


def como_cen(sql):
    ok, out = run(sql, CEN)
    if not ok:
        sys.exit("Fallo en preparación: " + out)
    return out.splitlines()[-1]


admin(f"""
set request.jwt.claim.sub = '{CEN}';
insert into productos (codigo, nombre_estandar, unidad_base_id, categoria_id, tipo, creado_por)
values ('CD-800', 'Bolsas para basura', {PZA}, {PAP}, 'SERVICIOS_GENERALES', '{CEN}');
insert into trabajadores (nombre, tipo, compania, dependencia, campus_id) values
 ('Rosa Elena Valdez', 'ITSON', null, 'MANTENIMIENTO', {CEN_ID}),
 ('Mario Félix Ortega', 'ITSON', null, 'MANTENIMIENTO', {CEN_ID});
insert into trabajadores_zonas select t.id, {ZONA} from trabajadores t
 where t.nombre in ('Rosa Elena Valdez', 'Mario Félix Ortega');
""")
P8 = admin("select id from productos where codigo='CD-800'")
ROSA = admin("select id from trabajadores where nombre='Rosa Elena Valdez'")
MARIO = admin("select id from trabajadores where nombre='Mario Félix Ortega'")
admin(f"set role authenticated; set request.jwt.claim.sub = '{CEN}'; "
      f"select 1 from registrar_entrada({P8},{A1},10,'REINGRESO_TRASPASO', p_tipo_origen=>'UNIDAD', p_origen_unidad_id=>{GUAYMAS}); "
      + "; ".join(activo(c, n, m, s) for c, n, m, s in [
          ('ACT-501', 'Nivel láser', 'GLL 3-80', 'NL-1'), ('ACT-502', 'Multímetro', 'F117', 'MM-1'),
          ('ACT-503', 'Pinza amperimétrica', 'F323', 'PA-1'), ('ACT-504', 'Escalera de tijera', 'T-6', 'ET-1'),
          ('ACT-505', 'Detector de voltaje', 'VT-1', 'DV-1')]))
NL, MM, PA, ET, DV = admin("select string_agg(id::text, ',' order by codigo) from activos "
                           "where codigo in ('ACT-501','ACT-502','ACT-503','ACT-504','ACT-505')").split(",")


def combinada(personal, materiales, herramientas, campos="estado||'|'||alertas::text"):
    """Boleta con materiales [(producto, cantidad[, motivo])] y herramientas [activo] (2 días)."""
    mats = ",".join(f'{{"producto_id":{p},"cantidad":{c}' + (f',"motivo_excepcion":"{r[0]}"' if r else "") + "}"
                    for p, c, *r in materiales)
    hers = ",".join(f'{{"activo_id":{a},"dias_prestamo":2}}' for a in herramientas)
    return (f"select {campos} from crear_boleta(p_materiales=>'[{mats}]', "
            f"p_herramientas=>'[{hers}]', p_trabajador_id=>{personal}, {FIRMAS})")


# Fotografía de lo que una boleta fallida no debe cambiar
FOTO = ("select (select existencia from buscar_productos('CD-800'))"
        "||'|'||(select count(*) from boletas)"
        "||'|'||(select count(*) from prestamos)"
        "||'|'||(select count(*) from movimientos_inventario)"
        "||'|'||(select string_agg(estado, ',' order by codigo) from activos where codigo like 'ACT-50%')")

caso("HU8 Comb", "Boleta combinada: 3 bolsas + nivel láser + multímetro", CEN,
     combinada(ROSA, [(P8, 3)], [NL, MM]), contiene="ENTREGADA")
caso("HU8 Comb", "Descuenta el material (10 a 7)", CEN,
     "select existencia from buscar_productos('CD-800')", contiene="7.000")
caso("HU8 Comb", "Abre un préstamo PRE por herramienta, a nombre de Rosa", CEN,
     "select count(*)||'|'||bool_and(folio like 'PRE-%')||'|'||min(custodio) from vista_seguimiento_prestamos "
     f"where activo_id in ({NL},{MM}) and estado='ACTIVO'", contiene="2|true|Rosa Elena Valdez")
caso("HU8 Comb", "Las dos herramientas quedan En préstamo", CEN,
     f"select string_agg(estado, ',') from activos where id in ({NL},{MM})", contiene="EN_PRESTAMO,EN_PRESTAMO")
caso("HU8 Comb", "Material y préstamos quedan en la misma boleta", CEN,
     "select count(distinct bm.id)||'|'||count(distinct bh.id) from boletas b "
     "join boletas_materiales bm on bm.boleta_id=b.id join boletas_herramientas bh on bh.boleta_id=b.id "
     f"where b.trabajador_id={ROSA}", contiene="1|2")

admin(f"set role authenticated; set request.jwt.claim.sub = '{CEN}'; "
      f"select cambiar_estado_activo({PA}, 'EN_REPARACION', 'Display dañado')")
ANTES = como_cen(FOTO)
caso("HU8 Comb", "Herramienta en reparación: la boleta combinada se rechaza", CEN,
     combinada(MARIO, [(P8, 2)], [ET, PA]), espera="ACTIVO_NO_DISPONIBLE")
caso("HU8 Comb", "Herramienta prestada: la boleta combinada se rechaza", CEN,
     combinada(MARIO, [(P8, 2)], [ET, NL]), espera="ACTIVO_PRESTADO")
caso("HU8 Comb", "Sin stock de un material: la boleta combinada se rechaza", CEN,
     combinada(MARIO, [(P8, 1), (P3, 500)], [ET]), espera="STOCK_INSUFICIENTE")
caso("HU8 Comb", "Los rechazos no dejan boleta, salida, préstamo ni cambio de estado", CEN,
     FOTO, contiene=ANTES)
caso("HU8 Comb", "La escalera de la boleta rechazada sigue Disponible y sin préstamo", CEN,
     f"select a.estado||'|'||count(p.id) from activos a left join prestamos p on p.activo_id=a.id "
     f"where a.id={ET} group by a.estado", contiene="DISPONIBLE|0")

# Dos ventanillas prestan el mismo detector al mismo tiempo. La primera retiene su
# transacción 2 s. La segunda espera el folio BOL que la primera tiene bloqueado y,
# cuando la primera confirma, ya ve el detector prestado a Rosa. Si llegara a
# pasar esa revisión, ejecutar_entrega bloquea la fila del activo y el índice
# prestamos_activo_abierto_uk impide el segundo préstamo abierto.
ANTES_CARRERA = como_cen("select existencia from buscar_productos('CD-800')")
(ok_a, out_a, _), (ok_b, out_b, espera_b) = en_paralelo(
    combinada(ROSA, [(P8, 1)], [DV]) + "; select pg_sleep(2);",
    combinada(MARIO, [(P8, 1)], [DV]), CEN)
resultados.append((ok_a and "ENTREGADA" in out_a and not ok_b and "prestado a Rosa Elena Valdez" in out_b
                    and espera_b > 1,
                   "HU8 Comb", "Dos boletas simultáneas con el mismo activo: solo gana la primera",
                   f"A: {out_a.splitlines()[-1] if out_a else ''} / B ({espera_b:.1f} s): "
                   f"{out_b.splitlines()[-1] if out_b else ''}"[:110]))
caso("HU8 Comb", "Un solo préstamo abierto del detector, a nombre de Rosa", CEN,
     f"select count(*)||'|'||min(custodio) from vista_seguimiento_prestamos where activo_id={DV} and estado='ACTIVO'",
     contiene="1|Rosa Elena Valdez")
caso("HU8 Comb", "La boleta perdedora no descontó su material", CEN,
     f"select {ANTES_CARRERA} - existencia from buscar_productos('CD-800')", contiene="1.000")
caso("HU8 Comb", "El índice impide un segundo préstamo abierto del mismo activo", None,
     "with nueva as (insert into boletas_herramientas (boleta_id, activo_id, dias_prestamo) "
     f"  select b.id, {DV}, 1 from boletas b where b.trabajador_id={ROSA} order by b.id limit 1 returning id) "
     "insert into prestamos (folio, boleta_herramienta_id, activo_id, dias_prestamo, fecha_prevista, creado_por) "
     f"select 'PRE-DUPLICADO', id, {DV}, 1, now() + interval '1 day', '{CEN}' from nueva",
     espera="prestamos_activo_abierto_uk")

# Material que excede el límite de la zona junto con una herramienta: sin
# autorizaciones en el sistema, con el motivo se entrega todo en el acto.
admin(f"insert into limites_material_zona values ({ZONA}, {P8}, 1, 30)")
ANTES = como_cen(FOTO)
caso("HU8 Comb", "Excede el límite sin motivo: no se presta la herramienta", CEN,
     combinada(MARIO, [(P8, 2)], [ET]), espera="MOTIVO_EXCEPCION_REQUERIDO")
caso("HU8 Comb", "El rechazo por motivo no deja nada registrado", CEN, FOTO, contiene=ANTES)
caso("HU8 Comb", "Con motivo se entrega en el acto con su préstamo y la alerta", CEN,
     combinada(MARIO, [(P8, 2, 'Limpieza profunda')], [ET], "estado||'|'||(alertas->0->>'excede_limite')"),
     contiene="ENTREGADA|true")
caso("HU8 Comb", "La boleta con excepción ya tiene préstamo y la escalera En préstamo", CEN,
     "select b.estado||'|'||a.estado||'|'||p.estado||'|'||bm.motivo_excepcion from boletas b "
     "join boletas_herramientas bh on bh.boleta_id=b.id join prestamos p on p.boleta_herramienta_id=bh.id "
     "join activos a on a.id=bh.activo_id join boletas_materiales bm on bm.boleta_id=b.id "
     f"where b.trabajador_id={MARIO} and a.id={ET}", contiene="ENTREGADA|EN_PRESTAMO|ACTIVO|Limpieza profunda")

# ---------- HU11: detalle de una boleta (AI-70) ----------
D = "select {} from vista_detalle_boleta where {}"
B_MAT = admin("select id from boletas where folio='BOL-2026-0001'")
B_COMB = admin("select id from boletas where folio='BOL-2026-0007'")
B_AUT = admin("select id from boletas where autorizo_nombre='Supervisor externo'")
B_NAI = admin("select id from boletas where solicitante_nombre='Luis Ochoa'")
caso("HU11 E4", "Boleta solo con materiales: encabezado completo", CEN,
     D.format("folio||'|'||solicitante_nombre||'|'||dependencia||'|'||entregado_por||'|'||campus", f"boleta_id={B_MAT}"),
     contiene="BOL-2026-0001|Juan Pérez Soto|SERVICIOS_GENERALES|Alicia García|Centro")
caso("HU11 E4", "Materiales entregados: código, concepto, almacén y cantidad", CEN,
     D.format("(materiales->0->>'codigo')||'|'||(materiales->0->>'concepto')||'|'||(materiales->0->>'almacen')"
              "||'|'||(materiales->0->>'cantidad')", f"boleta_id={B_MAT}"),
     contiene="CD-123|Limpiador multiusos|Almacén 1|2.000")
caso("HU11 E4", "Sin herramientas ni autorización: arreglo vacío y autorizó nulo", CEN,
     D.format("jsonb_array_length(herramientas)||'|'||(autorizo_nombre is null)", f"boleta_id={B_MAT}"), contiene="0|true")
caso("HU11 E4", "El renglón conserva la presentación y su cantidad", CEN,
     D.format("(materiales->0->>'presentacion')||'|'||(materiales->0->>'cantidad')", "solicitante_nombre='Ana'"),
     contiene="Medio litro|2.000")
caso("HU11 E4", "Boleta con herramientas: código, modelo y serie del activo", CEN,
     D.format("(herramientas->0->>'codigo')||'|'||(herramientas->0->>'modelo')||'|'||(herramientas->0->>'numero_serie')",
              f"boleta_id={B_COMB}"), contiene="ACT-104|GBH 2-28|BSH-987654321")
caso("HU11 E4", "El estado del activo es el actual (después robado), no el del préstamo", CEN,
     D.format("herramientas->0->>'estado'", f"boleta_id={B_COMB}"), contiene="ROBO_EXTRAVIO")
caso("HU11 E4", "La boleta combinada trae su material y su herramienta", CEN,
     D.format("jsonb_array_length(materiales)||'|'||jsonb_array_length(herramientas)||'|'||(materiales->0->>'codigo')",
              f"boleta_id={B_COMB}"), contiene="1|1|CD-700")
caso("HU11 E4", "Boleta con autorización: quién autorizó", CEN,
     D.format("autorizo_nombre||'|'||folio", f"boleta_id={B_AUT}"), contiene="Supervisor externo|BOL-")
caso("HU11 E4", "El almacén sale de donde se descontó (Náinari: Principal)", NAI,
     D.format("materiales->0->>'almacen'", f"boleta_id={B_NAI}"), contiene="Principal")
caso("Seg", "Centro no ve el detalle de una boleta de Náinari", CEN, D.format("count(*)", f"boleta_id={B_NAI}"), contiene="0")
caso("Seg", "Náinari ve el detalle de su boleta", NAI, D.format("solicitante_nombre", f"boleta_id={B_NAI}"), contiene="Luis Ochoa")
caso("Seg", "Supervisor jefe ve el detalle de ambos campus", JEFE, D.format("count(distinct campus_id)", "true"), contiene="2")
caso("Seg", "Sin sesión no se lee el detalle", "anon", D.format("count(*)", "true"), espera="permission denied")
caso("Seg", "El detalle no se modifica desde la app", CEN,
     "select bool_or(has_table_privilege('vista_detalle_boleta', p)) "
     "from unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p", contiene="f")

# ---------- HU11: búsqueda del historial de boletas (AI-69) ----------
# buscar_boletas(texto, límite, desplazamiento, desde, hasta): una fila por boleta,
# de la más reciente a la más antigua, con el total de las que cumplen los filtros.
caso("HU11 E1", "Sin texto empieza por la boleta más reciente", CEN,
     "select (select folio from buscar_boletas(null, 1, 0)) = "
     "(select folio from boletas order by creado_en desc, id desc limit 1)", contiene="t")
caso("HU11 E1", "Página de 2 con el total de boletas del campus", CEN,
     "select count(*) = 2 and min(total_resultados) = (select count(*) from boletas) from buscar_boletas(null, 2, 0)",
     contiene="t")
caso("HU11 E1", "La página 2 no repite boletas de la página 1", CEN,
     "select count(*) from buscar_boletas(null, 2, 0) a join buscar_boletas(null, 2, 2) b using (boleta_id)",
     contiene="0")
caso("HU11 E2", "Por solicitante sin acentos ni mayúsculas: 'MARIA sanchez' encuentra a María Sánchez", CEN,
     "select count(*) > 0 and bool_and(solicitante_nombre = 'María Sánchez') "
     "and min(total_resultados) = (select count(*) from boletas where solicitante_nombre = 'María Sánchez') "
     "from buscar_boletas('MARIA sanchez')", contiene="t")
caso("HU11 E2", "Por folio en minúsculas", CEN,
     "select string_agg(folio, ',') from buscar_boletas('bol-2026-0007')", contiene="BOL-2026-0007")
caso("HU11 E2", "Sin registro muestra la unidad capturada y el campus", CEN,
     "select dependencia||'|'||campus from buscar_boletas('rosa molina')", contiene="Navojoa|Centro")
caso("HU11 E2", "Registrado muestra la dependencia del trabajador", CEN,
     "select string_agg(distinct dependencia, ',') from buscar_boletas('juan perez')", contiene="SERVICIOS_GENERALES")
caso("HU11 E3", "Sin coincidencias no devuelve boletas", CEN,
     "select count(*) from buscar_boletas('zzz')", contiene="0")
# Entrega a las 23:30 del 20/11 en Hermosillo (ya es 21/11 en UTC).
admin(f"insert into boletas (folio, campus_id, solicitante_nombre, solicitante_unidad, "
      "estado, importada, entregado_en, creado_en, creado_por) values ('FECHA-2026-0001', "
      f"(select id from campus where clave='CEN'), 'Prueba Fecha', 'PRUEBAS', 'ENTREGADA', true, "
      f"'2026-11-21T06:30:00Z', '2026-11-21T06:30:00Z', '{CEN}')")
caso("HU11 E5", "El rango de fechas usa el día de Hermosillo", CEN,
     "select count(*) from buscar_boletas('FECHA-2026-0001', 50, 0, '2026-11-20', '2026-11-20')",
     contiene="1")
caso("HU11 E5", "El día siguiente en UTC no incluye la entrega", CEN,
     "select count(*) from buscar_boletas('FECHA-2026-0001', 50, 0, '2026-11-21', '2026-11-21')",
     contiene="0")
caso("HU11 E5", "El rango se combina con la búsqueda", CEN,
     "select count(*) from buscar_boletas('FECHA-2026-0001', 50, 0, null, '2026-11-19')",
     contiene="0")
caso("HU11 E5", "El total corresponde solo a las fechas filtradas", CEN,
     "select bool_and(total_resultados = 1) from "
     "buscar_boletas('FECHA-2026-0001', 50, 0, '2026-11-20', '2026-11-20')", contiene="t")
caso("Seg", "Centro no encuentra boletas de Náinari", CEN,
     "select count(*) from buscar_boletas('luis ochoa')", contiene="0")
caso("Seg", "Náinari encuentra su propia boleta", NAI,
     "select solicitante_nombre from buscar_boletas('luis ochoa')", contiene="Luis Ochoa")
caso("Seg", "Sin sesión no se busca en el historial", "anon",
     "select * from buscar_boletas()", espera="permission denied")

# ---------- HU11: importar entregas anteriores ----------
# La plantilla de la HU solo trae materiales; el RPC ignora cualquier clave
# extra que llegue en el JSON (por ejemplo, herramientas de un Excel ajeno).
IMP_BOLETAS = [
    {
        "fila": 2, "folio": "IMP-2025-0001", "fecha": "2025-03-04",
        "solicitante": "Solicitante Importado", "dependencia": "MANTENIMIENTO",
        "almacen": "Almacén 1",
        "materiales": [
            {"fila": 2, "codigo": "CD-123", "cantidad": 2},
            {"fila": 3, "codigo": "CD-700", "cantidad": 1},
        ],
    },
    {
        "fila": 4, "folio": "IMP-2025-0002", "fecha": "2025-03-05",
        "solicitante": "Otra Persona", "dependencia": "MANTENIMIENTO",
        "almacen": "Almacén 1",
        "materiales": [{"fila": 4, "codigo": "CD-700", "cantidad": 3}],
    },
]


def json_sql(datos):
    return json.dumps(datos, ensure_ascii=False).replace("'", "''")


IMP_JSON = json_sql(IMP_BOLETAS)
FALLIDAS = json.loads(json.dumps(IMP_BOLETAS))
FALLIDAS[0]["materiales"][1]["codigo"] = "CD-NO-EXISTE"
FALLIDAS[0]["folio"] = "IMP-2025-0099"
CON_EXTRAS = [json.loads(json.dumps(IMP_BOLETAS[1]))]
CON_EXTRAS[0]["folio"] = "IMP-2025-0097"
CON_EXTRAS[0]["herramientas"] = [
    {"fila": 4, "codigo": "ACT-NO-EXISTE", "dias_prestamo": 3}
]

caso("HU11 Imp", "Importa dos boletas de materiales", CEN,
     f"select importar_entregas('{IMP_JSON}'::jsonb, {CEN_ID})", contiene='"importadas": 2')
caso("HU11 Imp", "Dos filas del mismo folio forman una sola boleta", CEN,
     "select count(*)||'|'||(select jsonb_array_length(materiales) from vista_detalle_boleta "
     "where folio='IMP-2025-0001') from boletas where folio like 'IMP-2025-%'", contiene="2|2")
caso("HU11 Imp", "Detalle usa el almacén declarado en la importación", CEN,
     "select materiales->0->>'almacen' from vista_detalle_boleta where folio='IMP-2025-0001'",
     contiene="Almacén 1")
caso("HU11 Imp", "No se crea ningún préstamo ni boleta de herramienta", None,
     "select (select count(*) from prestamos where folio in "
     "(select folio from boletas where folio like 'IMP-2025-%'))||'|'||"
     "(select count(*) from boletas_herramientas bh join boletas b on b.id=bh.boleta_id "
     "where b.folio like 'IMP-2025-%')", contiene="0|0")
caso("HU11 Imp", "Las importadas quedan marcadas y sin firmas", None,
     "select (select count(*) from boletas where folio like 'IMP-2025-%' and importada "
     "and firma_recibe_path is null and firma_entrega_path is null)||'|'||"
     "(select count(*) from boletas where folio like 'IMP-2025-%')", contiene="2|2")
caso("HU11 Imp", "No se inventa ningún archivo de firma en Storage", None,
     "select count(*) from storage.objects where bucket_id='firmas' "
     "and name like '%/importacion/%'", contiene="0")
caso("HU11 Imp", "La importación no descuenta stock (sin movimientos)", None,
     "select count(*) from movimientos_inventario mi "
     "join boletas_materiales bm on bm.id=mi.boleta_material_id "
     "join boletas b on b.id=bm.boleta_id where b.folio like 'IMP-2025-%'", contiene="0")
caso("HU11 Imp", "Un folio ya existente no importa nada", CEN,
     f"select importar_entregas('{IMP_JSON}'::jsonb, {CEN_ID})",
     contiene='"importadas": 0')
caso("HU11 Imp", "El motivo indica el folio duplicado", CEN,
     f"select (importar_entregas('{IMP_JSON}'::jsonb, {CEN_ID})->'errores'->0->>'motivo')",
     contiene="IMP-2025-0001 ya existe")
caso("HU11 Imp", "Código de material inexistente: cero importadas", CEN,
     f"select importar_entregas('{json_sql(FALLIDAS)}'::jsonb, {CEN_ID})",
     contiene='"importadas": 0')
caso("HU11 Imp", "El error del código inexistente señala su fila", CEN,
     f"select (importar_entregas('{json_sql(FALLIDAS)}'::jsonb, {CEN_ID})->'errores'->0->>'fila')",
     contiene="3")
caso("HU11 Imp", "Ninguna boleta del archivo fallido se insertó", None,
     "select count(*) from boletas where folio like 'IMP-2025-009%'", contiene="0")
caso("HU11 Imp", "Claves extra de herramienta se ignoran", CEN,
     f"select importar_entregas('{json_sql(CON_EXTRAS)}'::jsonb, {CEN_ID})",
     contiene='"importadas": 1')
caso("Seg", "Otro campus no puede importar en Centro", CEN,
     f"select importar_entregas('{IMP_JSON}'::jsonb, {NAI_ID})", espera="SIN_PERMISO")

cuadre = admin("""select count(*) from existencias e where e.cantidad <>
  (select coalesce(sum(m.cantidad),0) from movimientos_inventario m where m.producto_id=e.producto_id and m.ubicacion_id=e.ubicacion_id)""")
resultados.append((cuadre == "0", "Kardex", "Saldo = suma del historial en cada ubicación", f"descuadres: {cuadre}"))

fallas = 0
for paso, hu, desc, out in resultados:
    fallas += not paso
    print(f"{'PASA ' if paso else 'FALLA'} | {hu:8} | {desc}" + ("" if paso else f"\n        -> {out}"))
print(f"\n{len(resultados) - fallas}/{len(resultados)} casos pasan")
sys.exit(1 if fallas else 0)
