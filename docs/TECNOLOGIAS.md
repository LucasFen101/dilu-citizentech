# Tecnologias adotadas e seus benefícios

Para cada tecnologia: **o que é**, **por que foi escolhida**, **o que ela entrega ao projeto** e, quando houve,
**o que foi descartado**.

## Visão geral

```
App Flutter (web / Android / iOS)
        │  HTTPS + JSON, token JWT
        ▼
API FastAPI (Python) ──► Oracle XE 21c (tabelas, PL/SQL, gatilhos, job)
        │
        └─ o app consulta direto, sem chave: Open-Meteo (previsão, ar, rios) e RainViewer (radar)
```

A regra de negócio mora no **banco** (PL/SQL). A API é uma casca fina que valida a entrada, chama a rotina certa e
traduz os erros. O app mostra e coleta dados.

---

## Aplicativo

### Flutter e Dart
- **O que é:** framework do Google para criar apps a partir de um único código.
- **Por que:** a rubrica aceita Flutter; é o que permite **um app só para web, Android e iOS**, e o resultado visual
  é totalmente controlável (o Dilu tem identidade própria: gota laranja, tinta petróleo, papel quente).
- **Benefício:** desenvolvimento e testes rápidos (*hot reload*), verificação direto no navegador sem instalar o
  Android Studio, tipagem forte do Dart que pega erros antes de rodar.

### flutter_map + OpenStreetMap
- **O que é:** biblioteca de mapas e os dados abertos do OpenStreetMap (licença ODbL).
- **Por que:** gratuito, sem chave, e permite aplicar um filtro de cor para combinar com a identidade do app.
- **Benefício:** mapas em várias telas (risco, relatos, clima, locais seguros, relato e novo lugar) sem custo. O crédito "© OpenStreetMap contributors" fica sempre visível, como a
  licença exige.
- **Descartado:** os mapas da CARTO (pediam chave de API) e o mapa do Google (cobrança).

### google_fonts
- **O que é:** carrega as fontes Fraunces (títulos) e Manrope (texto).
- **Benefício:** tipografia própria, que ajuda o app a **não parecer um modelo padrão**.

### geolocator
- **O que é:** pega a localização do aparelho com pedido de permissão.
- **Benefício:** o risco, o clima e os locais seguros são calculados **no ponto onde a pessoa está**. Quando a pessoa
  nega o GPS, o app não inventa um local: usa um lugar salvo ou pede para marcar no mapa.

### image_picker
- **O que é:** câmera e galeria. **Benefício:** foto do alagamento, já comprimida na origem.

### shared_preferences
- **O que é:** armazenamento pequeno no aparelho.
- **Benefício:** guarda a sessão, o kit de emergência e o **último retrato da tela Início**, para o app mostrar algo
  útil mesmo **sem internet**.

### url_launcher
- **O que é:** abre outros apps.
- **Benefício:** liga para 193, 199 e 190; abre rota no mapa do celular; **abre o WhatsApp com a mensagem de
  emergência pronta** (`wa.me`). Sem servidor de SMS, sem custo.

### http, intl, latlong2, http_parser
- Chamadas à rede, formatação de datas e números em português, cálculo de coordenadas e envio de fotos (multipart).

---

## Servidor

### Python e FastAPI
- **O que é:** FastAPI é um framework moderno para APIs.
- **Por que:** pouco código, validação automática da entrada, **documentação interativa pronta** (`/docs`), ótima
  integração com o Oracle.
- **Benefício:** 26 rotas organizadas por assunto, testáveis pelo navegador, com erros em português.

### python-oracledb (modo *thin*)
- **O que é:** driver oficial da Oracle para Python.
- **Por que:** o modo *thin* não exige instalar o Oracle Instant Client.
- **Benefício:** pool de conexões, variáveis de ligação e chamada direta de procedures PL/SQL.

### Pydantic
- **O que é:** valida os dados que chegam à API.
- **Benefício:** coordenadas fora do intervalo, tipos inválidos e e-mails malformados são recusados com `422` antes de
  chegar ao banco.

### bcrypt
- **O que é:** função de hash de senha, lenta de propósito e com *salt*.
- **Benefício:** nenhuma senha é guardada em texto. Mesmo com o banco vazado, as senhas não são lidas.

### JWT (PyJWT)
- **O que é:** token assinado que identifica o usuário (validade de 7 dias).
- **Benefício:** a API não guarda sessão em memória, e o token expira sozinho.

### pytest + TestClient
- **O que é:** testes automáticos. **Benefício:** 5 testes que sobem a API e conversam com o **Oracle de verdade**,
  cobrindo cadastro, relatos, confirmações, locais seguros, lugares, SOS sem GPS e limite de login.

---

## Banco de dados

### Oracle XE 21c e PL/SQL
- **O que é:** banco relacional da Oracle (edição gratuita) e sua linguagem de programação interna.
- **Por que:** a rubrica pede Oracle e rotinas PL/SQL. SQLite foi descartado por isso.
- **Benefício:** as **regras de negócio ficam junto dos dados**. Um relato só entra se passar pelas validações; o risco
  do bairro é recalculado dentro da mesma transação; os avisos nascem de gatilhos. Qualquer cliente que fale com o
  banco obedece às mesmas regras.

O que o projeto usa do Oracle: package (`pkg_enchente`, 15 rotinas), 2 funções soltas (distância de Haversine e bairro
mais próximo), 5 gatilhos (incluindo compostos), 1 rotina agendada (`DBMS_SCHEDULER`), 3 views, restrições `CHECK`,
`UNIQUE`, chaves estrangeiras com `ON DELETE` e códigos de erro próprios (`RAISE_APPLICATION_ERROR`).

---

## Fontes de dados (todas gratuitas e sem chave)

| Fonte | Para que | Observação |
|---|---|---|
| **Open-Meteo** (previsão) | Chuva, temperatura, umidade, vento, UV, previsão de 7 dias, chuva por hora | Atualiza de hora em hora |
| **Open-Meteo Flood** (modelo GloFAS) | Vazão dos rios, que reforça o risco de enchente | Modelo global: pode não representar o rio de uma cidade específica |
| **Open-Meteo Air Quality** (modelo CAMS) | Índice de qualidade do ar (US AQI) e partículas finas | Mostra fumaça de queimadas |
| **RainViewer** | Radar de chuva das últimas 2 horas | Crédito "Radar: RainViewer" sempre visível; cobertura de radares no Brasil não é completa |
| **OpenStreetMap** | Mapa base | Crédito sempre visível |

## O que foi estudado e descartado (e por quê)

| Ideia | Motivo |
|---|---|
| **Banco SQLite** | A rubrica pede Oracle e PL/SQL |
| **Mapa CARTO** | Exigia chave de API |
| **Lista de abrigos fixa** | Não existe lista aberta e completa; endereços inventados em enchente seriam perigosos. Trocada por **locais seguros indicados e avaliados pela comunidade** |
| **Abrigos do OpenStreetMap (Overpass)** | Servidores públicos caíam com frequência e o dado não indica quem está aberto |
| **Agente de IA para achar abrigos** | Pode inventar endereços e gasta *tokens* a cada consulta |
| **Google Flood Hub** | Acesso por pedido e só para cheias de rios grandes |
| **Alertas oficiais do INMET** | O servidor recusa chamadas automatizadas; o caminho correto seria pedir acesso, não contornar o bloqueio |
| **Notificações push** | Exigem Firebase e servidor de produção; o aviso é dado dentro do app |
| **Rotas que evitam alagamento** | Dependem de um serviço de rotas pago |

## Responsabilidade

O Dilu mostra **estimativas** de risco (chuva recente, chuva prevista e vazão de rios) e informações **indicadas pela
comunidade**. Ele **não substitui** os alertas da Defesa Civil. Em emergência, ligue **199** (Defesa Civil) ou **193**
(Bombeiros). Essa mensagem aparece no app, na tela Início e na aba Conta.
