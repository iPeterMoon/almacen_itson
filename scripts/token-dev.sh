#!/bin/bash
# Imprime un token de sesión del usuario de prueba de Supabase LOCAL. Sirve solo
# para probar la API directamente (curl o Swagger); la app ya no lo usa porque
# tiene su propia pantalla de login. Solo funciona con la base local: el usuario
# lo crea supabase/seed_desarrollo.sql.
#
# Uso (desde cualquier carpeta, en Git Bash / Linux / macOS):
#   bash scripts/token-dev.sh
#
# Otro usuario local: TOKEN_EMAIL=... TOKEN_PASSWORD=... bash scripts/token-dev.sh
# Solo el token sale por la salida estándar; los avisos van a la salida de errores.
# El token vence en 1 hora (jwt_expiry en supabase/config.toml).
set -u
cd "$(dirname "$0")/.." || exit 1          # raíz del repo

EMAIL="${TOKEN_EMAIL:-almacenista.centro@almacenes.test}"
PASSWORD="${TOKEN_PASSWORD:-Almacen-Dev-2026}"   # contraseña de desarrollo del seed

ESTADO=$(npx supabase status -o env 2>/dev/null)
API_URL=$(printf '%s\n' "$ESTADO" | grep '^API_URL=' | cut -d= -f2- | tr -d '"')
ANON_KEY=$(printf '%s\n' "$ESTADO" | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"')
if [ -z "$API_URL" ] || [ -z "$ANON_KEY" ]; then
  echo "Supabase local no está corriendo. Abre Docker Desktop y ejecuta: npx supabase start" >&2
  exit 1
fi

RESPUESTA=$(curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

# Se lee el JSON con Node (ya lo pide el servidor) para no depender de jq.
printf '%s' "$RESPUESTA" | node -e '
let s = "";
process.stdin.on("data", (d) => (s += d)).on("end", () => {
  let j = {};
  try { j = JSON.parse(s); } catch {}
  if (!j.access_token) {
    console.error("No se pudo iniciar sesión: " + (j.msg || j.error_description || j.message || s));
    console.error("¿Corriste npx supabase db reset para cargar seed_desarrollo.sql?");
    process.exit(1);
  }
  const vence = new Date(j.expires_at * 1000).toLocaleTimeString("es-MX");
  console.error("Token de " + process.argv[1] + " (vence a las " + vence + ")");
  process.stdout.write(j.access_token);
});' "$EMAIL"
