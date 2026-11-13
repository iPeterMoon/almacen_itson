"""Prueba los escenarios de HU1 a HU5 contra la base local, como usuarios reales de la app."""
import os, subprocess, sys

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
caso("HU4 E2", "Segundo reingreso de 1.5 L rebasa lo pendiente (1 L)", CEN,
     f"select * from registrar_reingreso({BM},{A1},1.5)", espera="REINGRESO_EXCEDE")
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
# ---------- HU6: periodicidad, límite de zona y autorización ----------
def boleta(materiales, extra=""):
    return f"select estado||'|'||folio from crear_boleta(p_materiales=>'{materiales}'{extra})"

m1 = f'[{{"producto_id":{P1},"cantidad":1}}]'
m1_motivo = f'[{{"producto_id":{P1},"cantidad":1,"motivo_excepcion":"Derrame en baños"}}]'

caso("HU6 E8", "Validación muestra periodicidad no cumplida (faltan 5 días)", CEN,
     f"select excede_periodicidad||'|'||dias_faltantes||'|'||(ultima_entrega is not null) "
     f"from validar_material({P1}, 1, p_trabajador_id=>{JUAN})", contiene="true|5|true")
caso("HU6 E8", "Sin motivo no se puede entregar antes de tiempo", CEN,
     boleta(m1, f", p_trabajador_id=>{JUAN}, {FIRMAS}"), espera="MOTIVO_EXCEPCION_REQUERIDO")
caso("HU6 E8", "Con motivo pero sin supervisor", CEN,
     boleta(m1_motivo, f", p_trabajador_id=>{JUAN}, {FIRMAS}"), espera="AUTORIZADOR_REQUERIDO")
caso("HU6 E8", "Con motivo y supervisor queda pendiente", CEN,
     boleta(m1_motivo, f", p_trabajador_id=>{JUAN}, p_supervisor_id=>'{SUP}'"), contiene="PENDIENTE_AUTORIZACION|BOL-2026-0002")
caso("HU6 E8", "Pendiente no descuenta existencia (sigue 12 en E1F1)", CEN,
     f"select cantidad from vista_existencias_por_ubicacion where producto_id={P1} and ubicacion='E1F1'", contiene="12.000")
caso("HU6 E8", "El supervisor recibe el aviso", SUP,
     "select string_agg(tipo, ',') from obtener_notificaciones()", contiene="AUTORIZACION_PENDIENTE")
B2 = admin("select id from boletas where folio='BOL-2026-0002'")
caso("Seg", "El almacenista no puede autorizarse a sí mismo", CEN,
     f"select resolver_autorizacion({B2}, true)", espera="SIN_PERMISO")
caso("HU6 E8", "No se entrega antes de autorizar", CEN,
     f"select confirmar_entrega({B2}, '{CEN_ID}/r.png', '{CEN_ID}/e.png')", espera="BOLETA_NO_AUTORIZADA")
caso("HU6 E8", "Supervisor autoriza", SUP,
     f"select resolver_autorizacion({B2}, true, 'Autorizado por derrame')", contiene="AUTORIZADA")
caso("HU6 E8", "El almacenista recibe aviso de la resolución", CEN,
     "select string_agg(tipo, ',') from obtener_notificaciones()", contiene="AUTORIZACION_RESUELTA")
caso("HU6 E1", "Confirmar sin firmas se rechaza", CEN,
     f"select confirmar_entrega({B2}, '', '{CEN_ID}/e.png')", espera="FIRMAS_REQUERIDAS")
caso("HU6 E1", "Confirmar entrega autorizada descuenta 1 L (12 a 11)", CEN,
     f"select confirmar_entrega({B2}, '{CEN_ID}/r.png', '{CEN_ID}/e.png'); "
     f"select cantidad from vista_existencias_por_ubicacion where producto_id={P1} and ubicacion='E1F1'", contiene="11.000")

# Pasan 6 días desde las entregas de Juan
admin("update boletas set entregado_en = entregado_en - interval '6 days' where trabajador_id is not null")
caso("HU6 E9", "Periodicidad cumplida (hace 6 días, intervalo 5)", CEN,
     f"select excede_periodicidad||'|'||excede_limite from validar_material({P1}, 1, p_trabajador_id=>{JUAN})",
     contiene="false|false")
caso("HU6 E9", "María nunca lo ha recibido: sin restricción", CEN,
     f"select excede_periodicidad::text from validar_material({P1}, 1, p_trabajador_id=>{MARIA})", contiene="false")
caso("HU6 E1", "Entrega a Juan de 2 L sin autorización", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2}}]', f", p_trabajador_id=>{JUAN}, {FIRMAS}"), contiene="ENTREGADA")
caso("HU6 E10", "Límite de zona: 3 L cada 5 días, ya van 2, María pide 2", CEN,
     f"select excede_limite||'|'||limite_cantidad||'|'||entregado_periodo "
     f"from validar_material({P1}, 2, p_trabajador_id=>{MARIA})", contiene="true|3.000|2.000")
caso("HU6 E10", "Excede límite sin motivo se rechaza", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2}}]', f", p_trabajador_id=>{MARIA}, {FIRMAS}"), espera="MOTIVO_EXCEPCION_REQUERIDO")
caso("HU6 E10", "Con motivo queda pendiente", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":2,"motivo_excepcion":"Evento en el edificio"}}]',
            f", p_trabajador_id=>{MARIA}, p_supervisor_id=>'{SUP}'"), contiene="PENDIENTE_AUTORIZACION")
BM_RECH = admin("select m.id from boletas_materiales m join boletas b on b.id=m.boleta_id "
                "where b.estado='PENDIENTE_AUTORIZACION'")
B_RECH = admin("select id from boletas where estado='PENDIENTE_AUTORIZACION'")
caso("HU6", "Supervisor rechaza", SUP, f"select resolver_autorizacion({B_RECH}, false, 'No procede')", contiene="RECHAZADA")
caso("HU6", "Una boleta rechazada no se entrega", CEN,
     f"select confirmar_entrega({B_RECH}, '{CEN_ID}/r.png', '{CEN_ID}/e.png')", espera="BOLETA_NO_AUTORIZADA")
caso("HU4", "No se reingresa material de una boleta no entregada", CEN,
     f"select * from registrar_reingreso({BM_RECH},{A1},1)", espera="BOLETA_NO_ENTREGADA")

caso("HU6 E2", "Solicitante sin registro con nombre y unidad", CEN,
     boleta(f'[{{"producto_id":{P1},"cantidad":0.5,"comentario":"Para limpieza de oficina"}}]',
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
caso("HU8", "Solo personal registrado recibe herramientas", CEN,
     f"select * from crear_boleta(p_herramientas=>'[{{\"activo_id\":{ACT200},\"dias_prestamo\":1}}]', "
     f"p_solicitante_nombre=>'X', p_solicitante_unidad=>'Y', {FIRMAS})", espera="HERRAMIENTA_SIN_SOLICITANTE")

# El préstamo de Juan vence: se prestó hace 5 días por 3
admin(f"update prestamos set prestado_en = now() - interval '5 days', fecha_prevista = now() - interval '2 days' "
      f"where activo_id = {ACT104}")
caso("HU8 E5", "Validación advierte que el solicitante tiene un vencido", CEN,
     f"select solicitante_con_vencido from validar_activo('ACT-200', {JUAN})", contiene="t")
caso("HU8 E5", "Se presta con advertencia registrada (1 día)", CEN,
     prestamo(JUAN, ACT200, 1), contiene='"solicitante_con_vencido": true')

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
caso("HU6 Hist", "Boletas rechazadas o pendientes no son entregas", CEN,
     H.format("count(*)", f"trabajador_id={MARIA}"), contiene="0")
caso("HU6 Hist", "Por solicitante sin registro (nombre parcial)", CEN,
     H.format("tipo_solicitante||'|'||solicitante_nombre||'|'||numero_solicitud||'|'||comentario", "solicitante_nombre ilike '%rosa%'"),
     contiene="SIN_REGISTRO|Rosa Molina|OT-9981|Para limpieza de oficina")
caso("HU6 Hist", "Por insumo: guantes solo en la boleta combinada", CEN,
     H.format("string_agg(folio||'|'||cantidad, ',')", f"producto_id={P3}"), contiene="BOL-2026-0007|2.000")
caso("HU6 Hist", "Conserva la presentación entregada y su equivalente", CEN,
     H.format("presentacion||'|'||cantidad||'|'||cantidad_base||'|'||unidad_base", "solicitante_nombre='Ana'"),
     contiene="Medio litro|2.000|1.000|L")
caso("HU6 Hist", "Por zona: 4 renglones entregados en el Edificio 1800", CEN,
     H.format("count(*)||'|'||min(zona)", f"zona_id={ZONA}"), contiene="4|Edificio 1800 - Planta baja")
caso("HU6 Hist", "Muestra la excepción autorizada y su motivo", CEN,
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

cuadre = admin("""select count(*) from existencias e where e.cantidad <>
  (select coalesce(sum(m.cantidad),0) from movimientos_inventario m where m.producto_id=e.producto_id and m.ubicacion_id=e.ubicacion_id)""")
resultados.append((cuadre == "0", "Kardex", "Saldo = suma del historial en cada ubicación", f"descuadres: {cuadre}"))

fallas = 0
for paso, hu, desc, out in resultados:
    fallas += not paso
    print(f"{'PASA ' if paso else 'FALLA'} | {hu:8} | {desc}" + ("" if paso else f"\n        -> {out}"))
print(f"\n{len(resultados) - fallas}/{len(resultados)} casos pasan")
