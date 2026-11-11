# Gerenciamento de memória e de recursos no Dilu

Este documento explica **como o Dilu usa memória e outros recursos** (conexões, arquivos, tempo do processador,
dados móveis) em cada camada, **onde isso está no código** e **por que cada escolha foi feita**.
Cobre as três camadas: banco Oracle, API em Python e app em Flutter.

A ideia central é simples: **tudo que é aberto é fechado, tudo que cresce tem limite, e nada é carregado antes de precisar.**

---

## 1. Banco de dados (Oracle)

| Prática | Onde | Por quê |
|---|---|---|
| **Índices nas consultas frequentes** | `database/01_schema.sql` (12 índices, ex.: `ix_alag_bairro_status`, `ix_alag_status_expira`, `ix_notif_usuario`) | Sem índice, o Oracle leria a tabela inteira (memória e tempo). Com índice, lê só as linhas necessárias |
| **Relatos vencidos saem do conjunto ativo** | Rotina agendada `JOB_EXPIRAR_ALAGAMENTOS` (a cada 15 min) chama `sp_expirar_alagamentos` | Mantém pequena a parte "viva" da tabela de relatos; o índice `(status, expira_em)` torna essa limpeza barata |
| **Valor de risco gravado, não recalculado** | `BAIRRO.score_risco` e `nivel_risco`, mantidos por gatilhos | O painel lê um número pronto em vez de somar todos os relatos a cada abertura |
| **Gatilhos "compostos"** | `trg_alagamento_risco`, `trg_confirmacao_risco` | Juntam os bairros afetados numa coleção em memória (`TYPE t_ids IS TABLE`) e recalculam **uma vez** no fim do comando, não a cada linha. Também evita o erro de tabela mutante (ORA-04091) |
| **Views em vez de repetir consultas** | `vw_indicadores_bairro`, `vw_dilu_numeros`, `vw_resumo_usuario` | A consulta fica escrita e otimizada num lugar só |
| **Procedures não fazem `COMMIT`** | `02_plsql.sql` | Quem chama (a API) controla a transação inteira: ou tudo é gravado, ou nada. Evita transações abertas por esquecimento |
| **Fotos fora do banco** | Coluna `ALAGAMENTO.foto` guarda só o nome do arquivo | Imagens em `BLOB` incham tabelas e backups. O arquivo fica em disco, o banco guarda a referência |

---

## 2. API (FastAPI + python-oracledb)

### 2.1 Conexões com o banco

`backend/app/db.py`

- **Pool de conexões** (`init_pool`, `min=1`, `max=5`): abrir uma conexão com o Oracle é caro. O pool mantém poucas
  conexões abertas e as reaproveita entre requisições. O teto de 5 impede que muitos acessos juntos esgotem o banco.
- **Conexão sempre devolvida** (`transaction()`): o gerenciador de contexto faz `commit` se tudo deu certo, `rollback`
  se houve erro e, **em qualquer caso**, devolve a conexão ao pool no bloco `finally`. Sem isso, cada erro "vazaria"
  uma conexão até o pool travar.
- **Pool fechado ao desligar** (`close_pool`, chamado em `lifespan`).

### 2.2 Consultas

- **Variáveis de ligação (bind variables)** em todas as consultas (`:usr`, `:lat`, `:id`...). O Oracle reaproveita o
  plano de execução (menos memória e CPU) e a entrada do usuário nunca vira SQL (proteção contra *SQL injection*).
- **Limite de linhas** com `FETCH FIRST n ROWS ONLY` em toda listagem que pode crescer:

  | Consulta | Limite |
  |---|---|
  | Alagamentos ativos (`/alagamentos`) | 200 |
  | Locais seguros (`/locais-seguros`) | 100, dentro de um raio |
  | Notificações | 100 |
  | Meus relatos | 50 |
  | Histórico de risco do bairro | 50 |

- **Filtro no banco, não no Python:** o raio de busca e a distância (`fn_distancia_km`) são calculados no Oracle, então
  só as linhas úteis chegam à memória da API.

### 2.3 Upload de fotos

`registrar_alagamento` em `backend/app/main.py`

1. **Lê no máximo `MAX_UPLOAD_BYTES + 1` (5 MB + 1 byte)**: se o arquivo for maior, a API recusa sem nunca ter
   carregado um arquivo gigante inteiro na memória.
2. **Confere o tipo** (JPEG, PNG ou WEBP) e a **assinatura real do arquivo** (`_assinatura_valida` olha os primeiros
   bytes), porque a extensão e o `Content-Type` podem ser falsos.
3. **Nome aleatório** (`uuid4`), gravado em disco.
4. **Sem foto órfã:** se o banco recusar o relato depois da gravação, o arquivo é apagado (`unlink`).

### 2.4 Proteção contra abuso, sem crescer sem limite

`LimiteTentativas` em `backend/app/security.py`

- Guarda **só os horários das falhas recentes** de cada chave (e-mail + IP) numa `deque`.
- Entradas fora da janela de 5 minutos são descartadas a cada consulta.
- Se alguém tentar encher a memória com milhares de e-mails diferentes, há um teto (`max_chaves = 5000`) que dispara uma
  limpeza geral.
- Um `Lock` protege a estrutura, porque os endpoints rodam em várias threads.

---

## 3. App (Flutter)

### 3.1 Telas só existem enquanto estão visíveis

`app/lib/screens/home_shell.dart`

- A navegação **não usa `IndexedStack`** (que mantém todas as abas vivas na memória). Usa `AnimatedSwitcher` com
  `KeyedSubtree`: **só a aba atual é construída**. Ao trocar de aba, a anterior é destruída e a memória dela volta.
- Efeito colateral bom: cada aba busca dados novos ao abrir, então nunca mostra informação velha escondida.
- Exceção consciente: a lista de locais seguros usa `AutomaticKeepAliveClientMixin`, para que alternar entre
  "Locais seguros" e "O que fazer" não refaça a busca. É uma lista pequena (até 100 itens).

### 3.2 Tudo que é criado é descartado

Todo objeto com ciclo de vida é liberado no `dispose()` da tela:

| Recurso | Onde |
|---|---|
| `Timer` do sino de avisos (a cada 60 s) | `HomeShell` |
| `Timer` da animação do radar | `ClimaScreen` |
| `AnimationController` e `CurvedAnimation` | `ClimaScreen`, widget `Esqueleto` |
| `MapController` | todas as telas com mapa |
| `TextEditingController` | login, relato, novo local, novo lugar, SOS |

Sem isso, um timer continuaria rodando (e chamando a rede) depois de a tela sair.

Em telas que fazem várias buscas em paralelo, um **contador de versão** (`_vez` em `InicioScreen`) descarta a resposta
de uma atualização antiga e `mounted` impede de mexer numa tela que já foi fechada.

### 3.3 Imagens

- **Compressão antes de enviar:** `pickImage(maxWidth: 1280, imageQuality: 80)` reduz a foto na origem. Menos memória
  no celular, menos dados móveis, menos espaço no servidor.
- **Decodificação reduzida ao exibir:** `Image.network(..., cacheWidth: 800)` decodifica a imagem já no tamanho em
  que será mostrada, em vez de manter a foto original inteira na memória.
- **Mapa:** os blocos (*tiles*) do mapa são baixados e descartados pela biblioteca conforme a pessoa navega.
- **Radar:** só os **7 quadros mais recentes** são guardados (`lerQuadrosRadar(maximo: 7)`). Todos ficam carregados
  enquanto o radar está ligado, para a animação não piscar; ao desligar, saem da memória.

### 3.4 Rede em lotes

- A previsão das 83 cidades vai em **lotes de 40 coordenadas por chamada**, em paralelo (`buscarGrade`,
  `buscarRisco`): poucas chamadas grandes em vez de 83 pequenas.
- Todas as chamadas têm **tempo limite** (de 10 a 25 s, conforme o caso). Nenhuma fica pendurada para sempre.
- Falha de uma fonte não derruba a tela: se a qualidade do ar falha, a previsão continua; se a vazão do rio falha, o
  risco sai só pela chuva.

### 3.5 Estado leve e persistência pequena

- **`ValueNotifier`** para preferências (`Preferencias.textoGrande`, `Preferencias.kit`): só os widgets que dependem do
  valor são redesenhados, não a tela toda.
- O que fica salvo no aparelho (`shared_preferences`) é **pequeno e fixo**: token, endereço do servidor, preferência de
  texto, itens do kit e um único "retrato" da tela Início (poucas linhas de JSON, sempre sobrescrito, apagado ao sair
  da conta). Nada acumula.
- **Telas de carregamento leves:** o `Esqueleto` anima só opacidade, sem imagens.

### 3.6 Mapa de cores sem polígonos

`ManchasMapa` (`app/lib/widgets.dart`) desenha cada mancha com um **degradê radial** em vez de polígonos de região:
são 83 círculos, desenhados direto no `Canvas`. O desenho é refeito a cada gesto, por isso:

- manchas fora da tela são **puladas** (`continue` quando o círculo está fora da área visível);
- as manchas são desenhadas numa única camada (`saveLayer`) e misturadas uma vez, em vez de misturar uma a uma;
- a intensidade **diminui conforme o zoom aumenta**, o que também reduz o trabalho de pintura.

---

## 4. Como verificar

- **Pool e conexões:** `SELECT COUNT(*) FROM v$session WHERE username = 'ALERTA';` com a API rodando e o app em uso
  deve ficar em no máximo 5 (mais as sessões do próprio sqlplus).
- **Limite de upload:** enviar uma foto maior que 5 MB devolve `413 Foto maior que 5 MB.`
- **Fotos órfãs:** `backend/uploads/` só contém fotos de relatos existentes.
- **Limite de login:** 6 senhas erradas seguidas devolvem `429` (coberto por `pytest`).
- **Testes automatizados:** `python -m pytest` (backend, contra o Oracle real) e `flutter test` (app).

## 5. Limites conhecidos (honestidade técnica)

- O limite de tentativas de login fica **na memória de um processo**: se a API rodar em vários processos, cada um
  conta separado. Para produção, o certo seria um armazenamento compartilhado (Redis ou uma tabela no banco).
- As fotos ficam em disco local (`backend/uploads/`). Em produção, o ideal é um armazenamento de objetos.
- A tabela `HISTORICO_RISCO` só cresce (uma linha por mudança de nível). Para uso real, caberia uma rotina que
  arquive ou apague registros antigos.
- O radar mantém 7 camadas de imagem carregadas enquanto está ligado: é uma troca consciente de memória por fluidez.
