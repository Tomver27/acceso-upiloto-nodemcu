-- ============================================================
-- RFID LAB ACCESS CONTROL - PostgreSQL DDL
-- ============================================================

-- ============================================================
-- CATALOG TABLES (no dependencies)
-- ============================================================

CREATE TABLE "Roles" (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    description TEXT NOT NULL
);

CREATE TABLE "Careers" (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE "DocumentTypes" (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    name_normalized TEXT NOT NULL
);

CREATE TABLE "Reasons" (
    id          SERIAL PRIMARY KEY,
    description TEXT NOT NULL
);

CREATE TABLE "Subjects" (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);

-- ============================================================
-- CORE TABLES
-- ============================================================

CREATE TABLE "Users" (
    id                   SERIAL PRIMARY KEY,
    document             TEXT        NOT NULL,
    first_name           TEXT        NOT NULL,
    middle_name          TEXT,
    last_name            TEXT        NOT NULL,
    code                 TEXT,
    card_uuid            TEXT        UNIQUE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    id_document_type     INTEGER     NOT NULL REFERENCES "DocumentTypes"(id) ON DELETE NO ACTION ON UPDATE NO ACTION,
    id_role              INTEGER     NOT NULL REFERENCES "Roles"(id)          ON DELETE NO ACTION ON UPDATE NO ACTION,
    id_career            INTEGER              REFERENCES "Careers"(id)        ON DELETE NO ACTION ON UPDATE NO ACTION
);

CREATE TABLE "Labs" (
    id       SERIAL PRIMARY KEY,
    location TEXT    NOT NULL,
    name     TEXT,
    id_user  INTEGER REFERENCES "Users"(id) ON DELETE NO ACTION ON UPDATE NO ACTION
);

CREATE TABLE "Entries" (
    id          SERIAL PRIMARY KEY,
    granted     BOOLEAN     NOT NULL,
    card_uuid   TEXT        NOT NULL,
    practice    TEXT,
    start_date  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_date    TIMESTAMPTZ,
    id_user     INTEGER     REFERENCES "Users"(id)    ON DELETE NO ACTION ON UPDATE NO ACTION,
    id_lab      INTEGER     NOT NULL REFERENCES "Labs"(id)     ON DELETE NO ACTION ON UPDATE NO ACTION,
    id_reason   INTEGER     NOT NULL REFERENCES "Reasons"(id)  ON DELETE NO ACTION ON UPDATE NO ACTION,
    id_subject  INTEGER     REFERENCES "Subjects"(id) ON DELETE NO ACTION ON UPDATE NO ACTION
);

-- ============================================================
-- NODE MCU MODULES
-- ============================================================

CREATE TABLE "Modules" (
    id         SERIAL PRIMARY KEY,
    mac_address TEXT   NOT NULL UNIQUE,
    name        TEXT,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    id_lab      INTEGER UNIQUE REFERENCES "Labs"(id) ON DELETE NO ACTION ON UPDATE NO ACTION
);

-- ============================================================
-- MODULE CONNECTION AUDIT
-- ============================================================

CREATE TABLE "Connections" (
    id           SERIAL PRIMARY KEY,
    connected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address   TEXT,
    id_module    INTEGER NOT NULL REFERENCES "Modules"(id) ON DELETE NO ACTION ON UPDATE NO ACTION
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_entries_card_uuid  ON "Entries"(card_uuid);
CREATE INDEX idx_entries_start_date ON "Entries"(start_date);
CREATE INDEX idx_entries_id_lab     ON "Entries"(id_lab);
CREATE INDEX idx_users_document     ON "Users"(document);
CREATE INDEX idx_users_card_uuid    ON "Users"(card_uuid);
CREATE INDEX idx_connections_id_module    ON "Connections"(id_module);
CREATE INDEX idx_connections_connected_at ON "Connections"(connected_at);
CREATE INDEX idx_modules_mac_address    ON "Modules"(mac_address);

-- ============================================================
-- SEED DATA
-- ============================================================

INSERT INTO "Roles" (name, description) VALUES
    ('Estudiante',     'Estudiante universitario con acceso a laboratorios según su carrera'),
    ('Desarrollador',  'Desarrollador de software con acceso a laboratorios de sistemas'),
    ('Profesor',       'Docente con acceso extendido a laboratorios de su área'),
    ('Laboratorista',  'Encargado de la administración y supervisión de un laboratorio');

INSERT INTO "Careers" (name) VALUES
    ('Ingeniería de Sistemas'),
    ('Ingeniería Mecatrónica'),
    ('Ingeniería de Telecomunicaciones'),
    ('Ingeniería Civil');

INSERT INTO "DocumentTypes" (name, name_normalized) VALUES
    ('Cédula de Ciudadanía',  'cedula_ciudadania'),
    ('Cédula de Extranjería', 'cedula_extranjeria'),
    ('Tarjeta de Identidad',  'tarjeta_identidad');

INSERT INTO "Subjects" (name) VALUES
    ('Semillero IoT'),
    ('Electiva IoT'),
    ('Desarrollo Web'),
    ('Mecánica'),
    ('Física I'),
    ('Física II'),
    ('Física III');

INSERT INTO "Reasons" (description) values
    ('Acceso concedido'),
    ('Usuario inactivo'),
    ('Usuario no registrado'),
    ('Laboratorio inactivo');

INSERT INTO "Labs" (location, name) values
    ('F-101', 'Mecánica');

INSERT INTO "Users" (document, first_name, middle_name, last_name, code, card_uuid, created_at, id_document_type, id_role, id_career) VALUES
    ('1023082896', 'Tomás',  'David', 'Vera Molano',  '430074084', '4606f460',  NOW(), 1, 2, 1),
    ('1000654321', 'Laura',   NULL,     'Gutierrez', '430074568',  NULL,        NOW(), 1, 1, 2);