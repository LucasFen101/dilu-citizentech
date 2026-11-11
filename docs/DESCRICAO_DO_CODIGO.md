# Descrição das funções, métodos e classes

Guia de leitura do código do Dilu. Cada tabela diz **o que cada peça faz**. As peças privadas do Dart (que começam com
`_`) aparecem agrupadas, porque são detalhes internos de cada tela.

Pastas do projeto:

```
alerta_enchente/
├── database/   scripts Oracle: usuário, tabelas, PL/SQL, dados iniciais e teste das rotinas
├── backend/    API em Python (FastAPI) e seus testes
├── app/        aplicativo Flutter (lib/ = código, test/ = testes)
└── docs/       esta documentação, o DER e o MER
```

---

## 1. Banco de dados: `database/`

| Arquivo | O que faz |
|---|---|
| `00_criar_usuario.sql` | Roda como SYSTEM. Recria o usuário `ALERTA` e dá a ele as permissões necessárias |
| `01_schema.sql` | Cria as 11 tabelas, os 12 índices e as 3 views (ver [DER_MER.md](DER_MER.md)) |
| `02_plsql.sql` | Funções, package `PKG_ENCHENTE`, gatilhos e rotina agendada (tabelas abaixo) |
| `03_seed.sql` | Cadastra 12 bairros de São Paulo. Não há dados fictícios |
| `04_teste_plsql.sql` | Cenário de teste das rotinas; termina com `ROLLBACK`, então não suja o banco |

### Funções soltas

| Função | O que faz |
|---|---|
| `fn_distancia_km(lat1, lon1, lat2, lon2)` | Distância em km entre dois pontos pela fórmula de Haversine. Declarada `DETERMINISTIC` |
| `fn_bairro_proximo(lat, lon)` | Devolve o id do bairro cadastrado mais próximo do ponto (até 15 km) ou `NULL` |

### Package `PKG_ENCHENTE`

| Rotina | O que faz | Erros que pode levantar |
|---|---|---|
| `fn_score_bairro(id)` | Soma, dos relatos **ativos** do bairro, `gravidade × (1 + 0,5 × confirmações)` | |
| `fn_nivel_por_score(score)` | Converte o score em nível: abaixo de 3 `BAIXO`, abaixo de 8 `MODERADO`, abaixo de 15 `ALTO`, senão `CRITICO` | |
| `sp_recalcular_risco(id)` | Atualiza score e nível do bairro; se o nível mudou, grava em `HISTORICO_RISCO` | |
| `sp_cadastrar_usuario(...)` | Cria o morador e descobre o bairro pelas coordenadas | 20001 e-mail já cadastrado |
| `sp_registrar_alagamento(...)` | Valida, acha o bairro, impede relato repetido (mesmo morador, menos de 50 m, nos últimos 10 min) e define a validade (`gravidade × 3` horas) | 20010 gravidade inválida; 20011 relato repetido |
| `sp_confirmar_alagamento(id, usuario)` | Registra a confirmação de um vizinho e prolonga a validade em 1 hora | 20020 não encontrado ou inativo; 20021 já confirmou; 20022 é o próprio relato |
| `sp_resolver_alagamento(id, usuario)` | O autor encerra o relato (`RESOLVIDO`) | 20030 inexistente, encerrado ou de outro morador |
| `sp_pedir_ajuda(...)` | Registra "Preciso de ajuda" ou "Estou seguro". Sem coordenadas, usa o bairro do cadastro e não grava ponto. "Estou seguro" encerra os pedidos abertos | 20040 tipo inválido |
| `sp_marcar_notificacoes_lidas(usuario)` | Marca todos os avisos do morador como lidos | |
| `sp_expirar_alagamentos(qtd OUT)` | Passa a `EXPIRADO` os relatos vencidos e devolve quantos foram | |
| `sp_cadastrar_local(...)` | Cadastra um local seguro; recusa ponto a menos de 30 m de outro ativo e limita 10 por morador | 20070 nome ou tipo inválido; 20071 ponto repetido; 20072 limite |
| `sp_avaliar_local(id, usuario, voto)` | Grava ou troca o voto (`S`/`N`). Com 3 ou mais "não" e mais "não" que "sim", o local sai do mapa | 20073 voto inválido; 20074 local inexistente; 20075 é o próprio local |
| `sp_remover_local(id, usuario)` | Quem cadastrou tira o local do mapa | 20076 só quem cadastrou |
| `sp_salvar_lugar(...)` | Salva um lugar acompanhado (máximo 5, nome único por morador) e descobre o bairro | 20060 sem nome; 20061 coordenadas inválidas; 20062 limite; 20063 nome repetido |
| `sp_remover_lugar(id, usuario)` | Remove um lugar do próprio morador | 20064 não encontrado |

Regra de projeto: **as rotinas não fazem `COMMIT`**. Quem chama controla a transação.
As mensagens de erro usam `UNISTR` para manter os arquivos `.sql` só com caracteres ASCII e ainda mostrar acentos.

### Gatilhos e rotina agendada

| Objeto | Quando dispara | O que faz |
|---|---|---|
| `trg_alagamento_risco` (composto) | Insert, update ou delete em `ALAGAMENTO` | Junta os bairros afetados e recalcula o risco uma vez no fim do comando |
| `trg_confirmacao_risco` (composto) | Insert em `CONFIRMACAO_ALAGAMENTO` | Recalcula o risco do bairro do relato confirmado |
| `trg_bairro_notifica` | O nível do bairro **sobe** para `ALTO` ou `CRITICO` | Cria um aviso `RISCO` para os moradores do bairro |
| `trg_pedido_ajuda_notifica` | Insert de um pedido `AJUDA` com bairro | Avisa os vizinhos do bairro (menos quem pediu) |
| `trg_local_notifica` | Insert em `LOCAL_SEGURO` com bairro | Avisa os vizinhos que há um novo local seguro |
| `JOB_EXPIRAR_ALAGAMENTOS` | A cada 15 minutos (`DBMS_SCHEDULER`) | Executa `sp_expirar_alagamentos` e faz `COMMIT` |

---

## 2. API: `backend/app/`

| Arquivo | O que faz |
|---|---|
| `config.py` | Configurações (usuário, senha e endereço do Oracle, segredo do JWT, limites de foto), todas trocáveis por variável de ambiente |
| `db.py` | Pool de conexões e utilitários de consulta |
| `security.py` | Senhas, tokens e limite de tentativas de login |
| `schemas.py` | Modelos de entrada validados pelo Pydantic |
| `main.py` | As rotas da API e o tratamento de erros |

### `db.py`

| Função | O que faz |
|---|---|
| `init_pool()` | Cria o pool (1 a 5 conexões) |
| `close_pool()` | Fecha o pool ao desligar |
| `transaction()` | Entrega uma conexão dentro de uma transação: `commit` se deu certo, `rollback` se houve erro, e sempre devolve a conexão |
| `query(conn, sql, binds)` | Executa um `SELECT` e devolve uma lista de dicionários com chaves em minúsculo |
| `query_one(...)` | Como `query`, mas devolve só a primeira linha (ou `None`) |
| `parse_app_error(exc)` | Extrai código e mensagem de um erro `ORA-20xxx` levantado pela PL/SQL |

### `security.py`

| Item | O que faz |
|---|---|
| `hash_password(senha)` / `verify_password(senha, hash)` | Gera e confere o hash bcrypt (com *salt*) |
| `create_token(id)` | Cria um JWT válido por 7 dias |
| `current_user_id(...)` | Dependência das rotas protegidas: lê o cabeçalho `Authorization`, valida o token e devolve o id do morador (ou responde 401) |
| `class LimiteTentativas` | Trava temporária após falhas repetidas: `bloqueado(chave)`, `registrar_falha(chave)`, `limpar(chave)`. Guarda só horários recentes e tem teto de memória |
| `limite_login` | A instância usada no login: 5 falhas em 5 minutos |

### `schemas.py` (entradas validadas)

`RegisterIn` (cadastro), `LoginIn`, `ContatoIn`, `LocalIn` (local seguro), `AvaliacaoIn` (voto), `LugarIn` e `EmergenciaIn`
(a localização é opcional, mas latitude e longitude têm de vir juntas).

### `main.py`: rotas (todas, exceto `/health`, `/auth/register` e `/auth/login`, exigem token)

| Rota | O que faz |
|---|---|
| `GET /health` | Confere se a API e o banco estão no ar |
| `POST /auth/register` | Cadastra o morador (`sp_cadastrar_usuario`) e devolve o token |
| `POST /auth/login` | Confere e-mail e senha; após 5 erros devolve 429 |
| `GET /me` · `/me/resumo` · `/me/relatos` | Dados do morador, números pessoais (view) e seus relatos |
| `GET/POST/DELETE /lugares` | Lista, salva e remove lugares acompanhados |
| `GET/POST/DELETE /contatos` | Contatos de emergência (máximo 5, sem telefone repetido) |
| `GET /alagamentos` | Relatos ativos, com distância e raio |
| `POST /alagamentos` | Registra um relato, com foto opcional (validada) |
| `POST /alagamentos/{id}/confirmar` · `/resolver` | Confirma o relato de um vizinho · encerra o próprio relato |
| `POST /emergencia` | "Preciso de ajuda" ou "Estou seguro"; devolve os contatos e o bairro avisado |
| `GET/POST /locais-seguros` | Lista (por raio, com votos) e cadastra locais seguros |
| `POST /locais-seguros/{id}/avaliar` · `DELETE /locais-seguros/{id}` | Vota "é seguro / não é" · remove o próprio local |
| `GET /bairros/indicadores` · `/bairros/{id}/historico` | Painel por bairro (view) e histórico de mudanças de nível |
| `GET /dilu/numeros` | Números gerais (view) |
| `GET /notificacoes` · `POST /notificacoes/lidas` | Avisos do morador · marca todos como lidos |

Funções internas: `lifespan` (abre e fecha o pool), `oracle_error_handler` (traduz `ORA-20xxx` em respostas HTTP
claras: por exemplo 20001 → 409, 20020 → 404, 20030 → 403), `_out_id` (variável de saída das procedures) e
`_assinatura_valida` (confere os primeiros bytes da foto).

### Testes: `backend/tests/test_api.py`

Sobem a API e usam o **Oracle real**; apagam seus próprios dados no fim (`_limpar`).
`test_fluxo_completo`, `test_locais_seguros`, `test_meus_lugares`, `test_emergencia_sem_gps_e_limite_de_login`
e `test_contato_repetido`.

---

## 3. App: `app/lib/`

### Núcleo

| Arquivo | O que faz |
|---|---|
| `main.dart` | Ponto de entrada. `AlertaEnchenteApp` monta o tema e o modo de texto grande. `_Porteiro` decide entre login e app conforme a sessão salva |
| `api.dart` | `Api`: cliente da API do Dilu (uma função por rota). `ApiException`: erro com mensagem e status HTTP. `_enviar` aplica tempo limite e traduz falha de rede e erros do servidor em mensagens claras |
| `services.dart` | Serviços de apoio (tabela abaixo) |
| `models.dart` | Modelos de dados e as regras de negócio puras do app (tabela abaixo) |
| `risco_enchente.dart` | Cálculo do risco de enchente estimado |
| `clima_grade.dart` | Busca de previsão e de qualidade do ar para várias cidades de uma vez |
| `cidades_br.dart` | As 83 cidades do mapa de clima e `cidadeMaisProxima` |
| `radar.dart` | Leitura dos quadros do radar de chuva |
| `theme.dart` | Identidade visual: paleta, tema, escalas de cor e rótulos |
| `widgets.dart` | Peças visuais próprias do Dilu |

### `services.dart`

| Item | O que faz |
|---|---|
| `Sessao` | Guarda e apaga o token e o endereço do servidor (`restaurar`, `salvarToken`, `sair`, `salvarServidor`). Ao sair, apaga também o retrato da tela Início |
| `Preferencias` | Texto grande e kit de emergência (`ValueNotifier`), mais a leitura e a gravação do último retrato da tela Início |
| `posicaoAtual()` | Localização do aparelho, ou `null` se não houver permissão |
| `buscarClima(lat, lon)` | Chuva, calor e ar das próximas 12 horas (a previsão e o ar vão em paralelo) |
| `buscarChuvaAcumulada(lat, lon)` | Chuva das últimas 24 h e prevista nas próximas 6 h |
| `buscarQualidadeAr` · `buscarPrevisao7Dias` | Qualidade do ar agora · previsão dos 7 dias seguintes |
| `abrirWhatsApp` · `telefoneParaWhatsApp` | Abre o WhatsApp com a mensagem pronta · normaliza o telefone com o código 55 |
| `ligar` · `abrirRota` · `linkMapa` | Liga para um número · abre a rota no mapa do celular · monta o link do ponto |

### `models.dart`

| Item | O que faz |
|---|---|
| `Alagamento`, `LocalSeguro`, `Bairro`, `RegistroRisco`, `Contato`, `Notificacao`, `Lugar`, `NumerosDilu`, `ResumoUsuario`, `MeuRelato` | Espelham as respostas da API (`fromJson`) |
| `tiposLocal`, `nomeTipoLocal` | Os 4 tipos de local seguro com nome e explicação |
| `Chuva`, `Calor`, `QualidadeAr`, `Clima` | Previsão das próximas 12 horas; cada uma classifica o seu nível |
| `ChuvaAcumulada`, `chuvaAcumuladaDe` | Soma a chuva por hora em 1, 3, 6 e 24 horas e a prevista; calcula o nível de atenção |
| `alertasDoClima`, `alertaChuvaAcumulada`, `AlertaClima` | Transformam a previsão em alertas (chuva, calor, UV 8 ou mais, ar ruim, chuva acumulada) |
| `PrevisaoDia`, `previsaoDiaria` | Um dia da previsão semanal |
| `CelulaClima` | Uma cidade do mapa, com todos os valores do momento |
| `ResultadoEmergencia`, `mensagemEmergencia` | Resposta do SOS · texto do WhatsApp (nunca leva localização inventada) |
| `fraseRisco`, `orientacaoRisco` | Frase e orientação para cada nível de risco, usadas na tela Início |
| `RetratoInicio` | Último resultado da tela Início, que vai e volta de texto JSON |
| `itensKit` | Os 8 itens do kit de emergência |
| `nivelAr`, `codigoChuva`, `descricaoTempo` | Utilidades de classificação |

### `risco_enchente.dart`

| Item | O que faz |
|---|---|
| `RiscoCidade` | Guarda chuva recente, prevista, vazão do rio, pontuação e nível de um ponto |
| `calcularRisco(r)` | **Pontos = 40% da chuva dos últimos 3 dias + 60% da prevista nos próximos 3.** Limites 25, 50 e 90 separam baixo, moderado, alto e crítico. Vazão do rio 2 vezes acima da média e de pelo menos 20 m³/s sobe um nível |
| `razaoVazao` | Maior vazão da semana dividida pela vazão média esperada |
| `aplicarChuvaDiaria`, `aplicarVazao` | Preenchem os dados a partir das respostas das APIs |
| `buscarRisco(lista)` | Busca chuva e vazão em lotes de 40 pontos, em paralelo, e calcula. Se a vazão falhar, o risco sai só pela chuva |

### `theme.dart` e `widgets.dart`

| Item | O que faz |
|---|---|
| `construirTema()` | Monta o tema completo (cores, fontes, botões, campos, abas) |
| `corNivel`, `rotuloNivel`, `corGravidade`, `rotuloGravidade` | Cor e texto de cada nível de risco e de cada gravidade |
| `corChuva`, `corTemperatura`, `corUmidade`, `corAr`, `corUv` | Escalas de cor contínuas (interpolam entre faixas) |
| `aviso(context, texto)` | Mostra uma mensagem rápida |
| `Gota`, `MarcadorGota`, `DiluLogo` | A gota da marca, o pino do mapa em formato de gota e o logotipo |
| `Etiqueta`, `Rotulo` | Etiqueta colorida e título de seção |
| `camadaBase`, `atribuicaoMapa`, `AtribuicaoRadar` | Mapa base com filtro de cor e os créditos obrigatórios |
| `ManchasMapa` | Degradê de cor sobre as cidades, sem polígonos; some com o zoom |
| `Esqueleto`, `EstadoTela` | Carregamento em forma de cartões e tela de erro ("Sem conexão com o Dilu") |
| `BotaoTextoGrande`, `Ondas` | Botão de acessibilidade e fundo decorativo |

### Telas: `app/lib/screens/`

| Tela | O que faz |
|---|---|
| `login_screen.dart` | Entrar ou criar conta, com escolha do servidor |
| `home_shell.dart` | Estrutura do app: 5 abas, botão da conta, sino de avisos e atalhos vindos do Início |
| `inicio_screen.dart` | **Início:** risco no ponto do morador, chuva acumulada, alertas, lugares com nível, relatos e locais por perto, kit de emergência e dados guardados para uso sem internet |
| `enchentes_screen.dart` | Risco por cidade no mapa do Brasil, com ranking e explicação do cálculo; hospeda "Relatos" e "Painel" |
| `map_screen.dart` | Mapa dos relatos da comunidade, com detalhe, confirmação e encerramento |
| `report_screen.dart` | Formulário de relato (local, gravidade, texto e foto). Sem GPS, exige marcar o local no mapa |
| `dashboard_screen.dart` | Painel por bairro e números gerais |
| `clima_screen.dart` | Mapa de clima do Brasil (chuva, temperatura, umidade e ar), radar animado e ficha da cidade com previsão de 7 dias |
| `locais_screen.dart` | Locais seguros da comunidade (mapa, filtros, votos), indicar um novo local e o kit de emergência |
| `lugares_screen.dart` | "Meus lugares" com a chuva acumulada de cada um e a tela de escolher o lugar no mapa |
| `sos_screen.dart` | Botões "Preciso de ajuda" e "Estou seguro", telefones de emergência e contatos de confiança |
| `notifications_screen.dart` | Avisos: clima onde você está, alertas dos seus lugares e avisos da comunidade |
| `conta_screen.dart` | Perfil, números pessoais, meus lugares, meus relatos, preferências, ODS, fontes de dados e limites |

### Testes: `app/test/utilidades_test.dart`

25 testes das regras puras: telefone do WhatsApp, níveis de chuva, calor e ar, alertas, lista de cidades, cálculo do risco,
leitura dos modelos, chuva acumulada, quadros do radar, retrato do Início, mensagem de emergência e kit.
