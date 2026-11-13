#!/usr/bin/env bash
# Reconstruye bd_paros desde cero (Linux/Mac). Ejecutar desde cualquier carpeta.
#   ./scripts/reconstruir.sh                 usuario postgres, conexión local
#   PGHOST=localhost ./scripts/reconstruir.sh postgres
# Si existe privado/identidades.sql, también carga los nombres (solo en equipos del proyecto).
set -euo pipefail
cd "$(dirname "$0")/.."
USUARIO="${1:-postgres}"
psql -X -U "$USUARIO" -d postgres -f sql/ejecutar_todo.sql
if [ -f privado/identidades.sql ]; then
  psql -X -q -U "$USUARIO" -d bd_paros -f privado/identidades.sql
  echo "Identidades cargadas en privado.persona_identidad"
fi
