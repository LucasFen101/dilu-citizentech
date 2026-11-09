-- =====================================================================
-- Dilu - 03_seed.sql
-- Dados iniciais: bairros de Sao Paulo (coordenadas aproximadas do centro).
-- Nao ha abrigos ficticios: os abrigos vem dos moradores (locais do
-- OpenStreetMap marcados como "recebendo pessoas") ou de cadastro oficial.
-- =====================================================================

INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Pinheiros',        UNISTR('S\00E3o Paulo'), 'SP', -23.5670, -46.7020);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Mooca',            UNISTR('S\00E3o Paulo'), 'SP', -23.5590, -46.5990);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Penha',            UNISTR('S\00E3o Paulo'), 'SP', -23.5260, -46.5430);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Santo Amaro',      UNISTR('S\00E3o Paulo'), 'SP', -23.6540, -46.7080);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Lapa',             UNISTR('S\00E3o Paulo'), 'SP', -23.5230, -46.7010);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Liberdade',        UNISTR('S\00E3o Paulo'), 'SP', -23.5590, -46.6350);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES (UNISTR('Tatuap\00E9'),          UNISTR('S\00E3o Paulo'), 'SP', -23.5400, -46.5760);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Vila Mariana',     UNISTR('S\00E3o Paulo'), 'SP', -23.5890, -46.6340);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES (UNISTR('Butant\00E3'),          UNISTR('S\00E3o Paulo'), 'SP', -23.5710, -46.7220);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES (UNISTR('Freguesia do \00D3'),   UNISTR('S\00E3o Paulo'), 'SP', -23.4990, -46.6940);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Itaquera',         UNISTR('S\00E3o Paulo'), 'SP', -23.5400, -46.4550);
INSERT INTO bairro (nome, cidade, uf, latitude, longitude) VALUES ('Ipiranga',         UNISTR('S\00E3o Paulo'), 'SP', -23.5870, -46.6100);

COMMIT;
