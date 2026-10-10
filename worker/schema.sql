CREATE TABLE IF NOT EXISTS equipos (
  nombre           TEXT PRIMARY KEY,
  token_hash       TEXT NOT NULL UNIQUE,
  creado           INTEGER NOT NULL,
  ultimo_contacto  INTEGER,
  estado           TEXT,          -- activo | pausado (lo informa el agente)
  info             TEXT           -- JSON: versión de Claude, carpeta, permisos
);

CREATE TABLE IF NOT EXISTS tareas (
  id          TEXT PRIMARY KEY,
  equipo      TEXT NOT NULL REFERENCES equipos(nombre) ON DELETE CASCADE,
  modo        TEXT NOT NULL,      -- tarea | continuar | comprobar
  prompt      TEXT NOT NULL,
  estado      TEXT NOT NULL,      -- pendiente | en_curso | hecha | error
  resultado   TEXT,
  creado      INTEGER NOT NULL,
  actualizado INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS tareas_cola ON tareas (equipo, estado, creado);
