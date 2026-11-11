#!/bin/bash
# Levanta un PostgreSQL 16 en Docker (si no está corriendo) y recrea la base
# "almacenes" con el stub de Supabase, todas las migraciones y seed.sql.
# Uso (desde cualquier carpeta, en Git Bash / Linux / macOS):
#   bash supabase/pruebas/reiniciar.sh && python supabase/pruebas/probar.py
set -u
cd "$(dirname "$0")/.." || exit 1          # carpeta supabase/

C=almacenes-pruebas

if [ -z "$(docker ps -q -f name=^${C}$)" ]; then
  if [ -n "$(docker ps -aq -f name=^${C}$)" ]; then
    docker start $C >/dev/null || exit 1
  else
    # Puerto 54329 solo en localhost, para herramientas como "supabase gen types --db-url"
    docker run -d --name $C -p 127.0.0.1:54329:5432 -e POSTGRES_PASSWORD=postgres postgres:16 >/dev/null || exit 1
  fi
  # Por TCP: en la primera corrida la imagen arranca un servidor temporal solo por
  # socket para inicializarse y luego lo reinicia; el socket daría falso "listo".
  until docker exec $C pg_isready -h 127.0.0.1 -U postgres -q 2>/dev/null; do sleep 1; done
fi

P="docker exec -i -e PGOPTIONS=-cclient_min_messages=warning $C psql -X -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists almacenes" -c "create database almacenes" || exit 1

for f in pruebas/00_stub_supabase.sql migrations/*.sql seed.sql; do
  $P -d almacenes < "$f" 2>&1 | grep -v NOTICE | sed "s|^|$(basename "$f"): |"
  [ "${PIPESTATUS[0]}" -ne 0 ] && { echo "Falló $f"; exit 1; }
done
echo "migraciones OK"
