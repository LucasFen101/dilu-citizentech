=====================================================================
 DILU - Avise antes que a água chegue
 Global Solution 2 - CitizenTech (FIAP)
=====================================================================

Autor: Lucas Fen Avelino - RM 556647           (projeto individual)
Repositório: https://github.com/LucasFen101/dilu-citizentech


---------------------------------------------------------------------
1. O QUE É
---------------------------------------------------------------------
O Dilu é um aplicativo que ajuda o morador a se proteger de enchentes e
de clima extremo. Ao abrir, ele responde uma pergunta: "estou em risco
agora?", para o ponto exato onde a pessoa está.

O problema: enchentes pegam as pessoas de surpresa. O avô do autor
perdeu o carro numa enchente que dava para prever.

O que o Dilu faz, além do login:

  1. INÍCIO - risco de enchente no ponto do morador (chuva dos últimos 3
     dias + chuva prevista + vazão dos rios), chuva acumulada em 1, 3, 6
     e 24 horas, alertas de clima, lugares salvos e o que a vizinhança
     relatou. Funciona sem internet com o último resultado guardado.
  2. ENCHENTES - mapa do Brasil com o risco estimado de 83 cidades,
     relatos de alagamento feitos e confirmados pelos moradores (com
     foto), e painel por bairro calculado pelo Oracle.
  3. CLIMA - mapa de chuva, temperatura, umidade e qualidade do ar,
     radar de chuva ao vivo e previsão de 7 dias de cada cidade.
  4. LOCAIS SEGUROS - pontos indicados e avaliados pela comunidade
     (ponto alto para o carro, local que acolhe, ponto de encontro,
     ponto de doação) e kit de emergência.
  5. SOS - "Preciso de ajuda" avisa os vizinhos do bairro e prepara a
     mensagem de WhatsApp com a localização para os contatos de
     confiança; "Estou seguro" encerra o pedido.
  6. CONTA - lugares acompanhados (casa, trabalho, faculdade), números
     pessoais, meus relatos, texto grande (acessibilidade) e fontes
     dos dados.

Objetivos de Desenvolvimento Sustentável (ONU):

  ODS 11 - Cidades e comunidades sustentáveis (meta 11.5: reduzir o
           número de pessoas afetadas por desastres relacionados à água)
           https://brasil.un.org/pt-br/sdgs/11
  ODS 13 - Ação contra a mudança global do clima (meta 13.1: resiliência
           a riscos relacionados ao clima)
           https://brasil.un.org/pt-br/sdgs/13
  ODS 3  - Saúde e bem-estar (calor extremo, qualidade do ar, ajuda)
           https://brasil.un.org/pt-br/sdgs/3

AVISO: o risco mostrado é uma ESTIMATIVA por modelo e as informações
dos locais seguros vêm da comunidade. O Dilu não substitui os alertas da
Defesa Civil. Em emergência: 199 (Defesa Civil) ou 193 (Bombeiros).


---------------------------------------------------------------------
2. TECNOLOGIAS E JUSTIFICATIVAS (resumo)
---------------------------------------------------------------------
Detalhes em docs/TECNOLOGIAS.md.

  App ........ Flutter 3.41 / Dart. Um código para web, Android e iOS;
               visual totalmente próprio (identidade "Dilu").
  API ........ Python + FastAPI. Pouco código, validação automática,
               documentação interativa pronta em /docs.
  Banco ...... Oracle XE 21c com PL/SQL (exigência do desafio). As
               regras de negócio ficam no banco: package, gatilhos,
               views e uma rotina agendada. A API é uma casca fina.
  Segurança .. senhas com bcrypt, login por token JWT (7 dias), limite
               de tentativas de login, validação das fotos enviadas,
               variáveis de ligação em todas as consultas.
  Dados ...... Open-Meteo (previsão, rios e qualidade do ar), RainViewer
               (radar) e OpenStreetMap (mapa). Todos gratuitos e sem
               chave de acesso.
  Testes ..... pytest (contra o Oracle real) e flutter test.

Por que o Oracle e não um banco mais simples: o desafio pede PL/SQL.
Por que a regra fica no banco: o risco do bairro é recalculado dentro
da mesma transação do relato, e qualquer cliente obedece às mesmas
regras.


---------------------------------------------------------------------
3. COMO EXECUTAR
---------------------------------------------------------------------
Requisitos:
  - Oracle Database XE 21c, escutando em localhost:1521, PDB XEPDB1
  - Python 3.11 ou mais novo (testado com 3.13)
  - Flutter 3.41 ou mais novo, com o Chrome instalado (para rodar na web)
  - Git

Os comandos abaixo são para o PowerShell do Windows. No Linux/macOS,
troque a ativação do ambiente por: source .venv/bin/activate

PASSO 1 - Baixar o projeto
  git clone https://github.com/LucasFen101/dilu-citizentech.git
  cd dilu-citizentech

  (Se estiver usando a pasta entregue, entre nela. A pasta que tem as
  subpastas app, backend, database e docs é a raiz do projeto.)

PASSO 2 - Criar o banco (uma vez)
  cd database

  a) Criar o usuário ALERTA. Rode como SYSTEM (use a senha do SYSTEM
     definida na instalação do Oracle):
       sqlplus system/SENHA_DO_SYSTEM@localhost:1521/XEPDB1 @00_criar_usuario.sql

  b) Criar tabelas, rotinas PL/SQL e dados iniciais, como ALERTA:
       sqlplus 'alerta/"Alerta#2026"@localhost:1521/XEPDB1'
     No prompt do SQL*Plus, na ordem:
       @01_schema.sql
       @02_plsql.sql
       @03_seed.sql
       @04_teste_plsql.sql      (opcional: mostra as rotinas em ação e
                                 desfaz tudo no fim, com ROLLBACK)
       exit

  Resultado esperado: 11 tabelas, 3 views, 5 gatilhos e 1 rotina
  agendada, sem objetos inválidos.

  A senha "Alerta#2026" é um padrão de DESENVOLVIMENTO, definido em
  database/00_criar_usuario.sql. Para usar outra, troque lá e informe
  a mesma na API pela variável de ambiente ORACLE_PASSWORD.

PASSO 3 - Subir a API
  cd ..\backend
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r requirements.txt
  uvicorn app.main:app --host 0.0.0.0 --port 8000

  Conferir: abra http://localhost:8000/health  (deve mostrar
  {"status":"ok"}). A documentação interativa fica em
  http://localhost:8000/docs

  Variáveis de ambiente opcionais (valores padrão entre parênteses):
    ORACLE_USER (alerta)   ORACLE_PASSWORD (Alerta#2026)
    ORACLE_DSN (localhost:1521/XEPDB1)
    JWT_SECRET (um segredo de desenvolvimento; troque em produção)

PASSO 4 - Rodar o app (em outro terminal)
  cd app
  flutter pub get
  flutter run -d chrome --web-port 8090

  O app abre no Chrome. Clique em "Criar conta" e entre. Quando o
  navegador pedir, PERMITA a localização (o app funciona sem ela, mas
  o risco e os locais seguros ficam muito melhores com ela).

  Android: use "flutter run" com um emulador (a API é encontrada em
  10.0.2.2:8000). Em um celular de verdade, use "Configurar servidor"
  na tela de login e informe http://IP_DO_COMPUTADOR:8000, com o
  celular na mesma rede Wi-Fi.

PASSO 5 - Testes
  API (precisa do Oracle no ar), dentro de backend com o ambiente ativo:
    python -m pytest -v
  App, dentro de app:
    flutter test
  Análise estática do código do app:
    flutter analyze


---------------------------------------------------------------------
4. SUGESTÃO DE ROTEIRO PARA TESTAR
---------------------------------------------------------------------
  1. Criar duas contas (use duas janelas do navegador, uma anônima).
  2. Conta A: Conta > "Adicionar lugar" para salvar a casa.
  3. Conta A: Enchentes > Relatos > "Relatar alagamento" (com foto).
  4. Conta B (mesmo bairro, p.ex. Mooca): confirmar o relato e ver o
     risco do bairro subir no Painel; o aviso chega no sino.
  5. Conta B: Seguros > "Indicar um local seguro". A conta A recebe o
     aviso e pode votar "é seguro" ou "não é".
  6. Conta A: SOS > "Preciso de ajuda": os vizinhos recebem o aviso e o
     WhatsApp sai com a mensagem pronta para os contatos.
  7. Clima: ligar o radar (botão à direita) e tocar numa cidade para ver
     a previsão de 7 dias.
  8. Desligar a internet (ou a API) e recarregar: o Início mostra o
     último resultado com a hora.


---------------------------------------------------------------------
5. ESTRUTURA DO PROJETO
---------------------------------------------------------------------
  database/   00_criar_usuario.sql  usuário ALERTA
              01_schema.sql         tabelas, índices e views
              02_plsql.sql          funções, package, gatilhos, rotina
              03_seed.sql           bairros de São Paulo
              04_teste_plsql.sql    cenário de teste das rotinas
  backend/    app/main.py           rotas da API
              app/db.py             pool de conexões Oracle
              app/security.py       senhas, token e limite de login
              app/schemas.py        validação das entradas
              tests/                testes contra o Oracle real
  app/        lib/                  código do aplicativo Flutter
              lib/screens/          as telas
              test/                 testes do app
  docs/       DER_MER.md, MER.png, DER.png   modelo de dados
              TELAS.md, telas/      prints do aplicativo
              GERENCIAMENTO_DE_MEMORIA.md
              DESCRICAO_DO_CODIGO.md   classes, funções e métodos
              TECNOLOGIAS.md        tecnologias e benefícios


---------------------------------------------------------------------
6. DOCUMENTAÇÃO
---------------------------------------------------------------------
  docs/DER_MER.md                  MER e DER (também como imagem, em
                                   docs/MER.png e docs/DER.png), chaves,
                                   índices, views, normalização
  docs/TELAS.md                    prints de todas as telas do app
  docs/GERENCIAMENTO_DE_MEMORIA.md como o projeto usa memória e outros
                                   recursos no banco, na API e no app
  docs/DESCRICAO_DO_CODIGO.md      descrição de cada função, método e
                                   classe, e de cada rotina PL/SQL
  docs/TECNOLOGIAS.md              tecnologias adotadas, benefícios e o
                                   que foi estudado e descartado


---------------------------------------------------------------------
7. FONTES DE DADOS E CRÉDITOS
---------------------------------------------------------------------
  Mapa .................. © OpenStreetMap contributors (licença ODbL)
                          https://www.openstreetmap.org/copyright
  Previsão, rios, ar .... Open-Meteo (https://open-meteo.com), com os
                          modelos GloFAS (rios) e CAMS (ar)
  Radar de chuva ........ RainViewer (https://www.rainviewer.com)

Os créditos também aparecem dentro do app, na aba Conta > "Sobre o
Dilu", e nos mapas.


---------------------------------------------------------------------
8. LIMITES CONHECIDOS
---------------------------------------------------------------------
  - O risco é uma estimativa: a vazão de rios vem de um modelo global
    e pode não representar o rio de uma cidade específica.
  - A cobertura de radares de chuva no Brasil não é completa.
  - O limite de tentativas de login fica na memória de um processo.
  - As fotos ficam no disco do servidor (backend/uploads/).
  - Não há notificação "push": os avisos aparecem dentro do app.
  Veja docs/GERENCIAMENTO_DE_MEMORIA.md (seção 5) para o restante.
