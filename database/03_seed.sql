-- =====================================================================
-- Dilu - 03_seed.sql
-- Dados iniciais: bairros de Sao Paulo (coordenadas aproximadas do centro)
-- e abrigos de EXEMPLO. Os abrigos abaixo sao ficticios, apenas para
-- demonstracao: substitua por dados oficiais da Defesa Civil.
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

INSERT INTO abrigo (id_bairro, nome, endereco, latitude, longitude, capacidade, telefone)
SELECT id_bairro, UNISTR('Gin\00E1sio Poliesportivo (exemplo)'), UNISTR('Endere\00E7o de exemplo, Pinheiros'), -23.5650, -46.7000, 300, NULL
  FROM bairro WHERE nome = 'Pinheiros';
INSERT INTO abrigo (id_bairro, nome, endereco, latitude, longitude, capacidade, telefone)
SELECT id_bairro, 'Escola Municipal (exemplo)', UNISTR('Endere\00E7o de exemplo, Mooca'), -23.5570, -46.6010, 200, NULL
  FROM bairro WHERE nome = 'Mooca';
INSERT INTO abrigo (id_bairro, nome, endereco, latitude, longitude, capacidade, telefone)
SELECT id_bairro, UNISTR('Centro Comunit\00E1rio (exemplo)'), UNISTR('Endere\00E7o de exemplo, Penha'), -23.5240, -46.5450, 150, NULL
  FROM bairro WHERE nome = 'Penha';
INSERT INTO abrigo (id_bairro, nome, endereco, latitude, longitude, capacidade, telefone)
SELECT id_bairro, 'Igreja Paroquial (exemplo)', UNISTR('Endere\00E7o de exemplo, Santo Amaro'), -23.6520, -46.7090, 120, NULL
  FROM bairro WHERE nome = 'Santo Amaro';
INSERT INTO abrigo (id_bairro, nome, endereco, latitude, longitude, capacidade, telefone)
SELECT id_bairro, 'Quadra da Escola (exemplo)', UNISTR('Endere\00E7o de exemplo, Lapa'), -23.5210, -46.7030, 180, NULL
  FROM bairro WHERE nome = 'Lapa';

COMMIT;
