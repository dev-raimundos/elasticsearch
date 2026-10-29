# Elasticsearch com Docker Compose

Instância única com autenticação, HTTPS e dados persistentes. Requer Docker
com contêineres Linux, Compose v2 e memória disponível para o limite de 4 GiB
do Elasticsearch e 2 GiB do Kibana, além do sistema operacional.

## Versão e licença

Imagem oficial fixa: `docker.elastic.co/elasticsearch/elasticsearch:9.5.5`.
Consulta em 29/10/2026. A Elastic mantém as duas versões menores mais recentes
da versão principal atual e a última menor da principal anterior, conforme
os prazos da política. Não há uma classificação LTS equivalente à Extended
do Redis; acompanhe a manutenção e atualize a tag após homologação.
A tag fixa a versão, mas um digest é necessário para imutabilidade da imagem.

- [Download e versão atual](https://www.elastic.co/downloads/elasticsearch)
- [Política de manutenção](https://www.elastic.co/support/eol)
- [Configuração Docker](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-configure)
- [Requisitos do sistema](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration)

Os arquivos deste repositório usam a licença [MIT](LICENCE), copyright 2026
Raimundos Marques. A distribuição oficial Elasticsearch tem termos próprios
da Elastic, independentes da licença do projeto. O serviço usa a licença Basic.

## Arquivos e variáveis

| Arquivo | Função |
| --- | --- |
| `compose.yaml` | Setup de certificados e serviço Elasticsearch |
| `.docker/elasticsearch.yml` | Instância única, HTTPS, autenticação e snapshots |
| `.docker/setup.sh` | Gera a CA e o certificado; preserva os existentes |
| `.docker/kibana-setup.sh` | Configura a senha técnica de `kibana_system` |
| `.docker/kibana.yml` | HTTP para o Tunnel e HTTPS para o Elasticsearch |
| `.env` | Configuração local com senha aleatória exclusiva, ignorada pelo Git |
| `.env.example` | Modelo público com senha de exemplo |
| `.gitattributes` | Preserva LF nos scripts Linux |
| `.gitignore` | Exclui dados, backups e segredos |

| Variável | Valor local | Função |
| --- | --- | --- |
| `ELASTIC_PASSWORD` | Gerada no `.env` | Senha inicial do administrador `elastic` |
| `ES_BIND_IP` | `127.0.0.1` | Interface do host que publica a API |
| `ES_PORT` | `9200` | Porta do host; interna sempre `9200` |
| `ES_CERT_IP` | `100.64.10.1` | IPv4 adicional incluído no certificado |
| `ES_DATA_DIR` | `/home/docker-data/elasticsearch` | Diretório de dados no servidor Linux; para Windows/local use `./data` |
| `ES_BACKUP_DIR` | `./backups` | Repositório de snapshots no host |
| `ES_HEAP_SIZE` | `2g` | Heap Java inicial e máximo |
| `ES_MEMORY_LIMIT` | `4g` | Memória total do contêiner |

Mantenha heap em até aproximadamente metade do limite do contêiner para deixar
memória para cache e memória nativa. O limite de CPU é 2 no Compose.
A porta de transporte `9300` não é publicada.

## Preparação do host

No servidor Linux, ajuste o kernel antes de iniciar:

```bash
echo 'vm.max_map_count = 1048576' | sudo tee /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

No Docker Desktop com backend WSL2, pelo PowerShell:

```powershell
wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=1048576
```

O ajuste no WSL pode precisar ser reaplicado após reiniciar o ambiente Docker.
Não é um parâmetro do `.env` ou do Elasticsearch: pertence ao kernel Linux.

Para dados no servidor em `/home/`, configure no `.env`:

```dotenv
ES_BIND_IP=100.64.10.1
ES_CERT_IP=100.64.10.1
ES_DATA_DIR=/home/docker-data/elasticsearch
ES_BACKUP_DIR=/home/elasticsearch/backups
```

Prepare as permissões no servidor (usuário do contêiner: UID 1000, grupo 0):

```bash
sudo mkdir -p /home/docker-data/elasticsearch /home/elasticsearch/backups
sudo chown 1000:0 /home/docker-data/elasticsearch /home/elasticsearch/backups
sudo chmod 770 /home/docker-data/elasticsearch /home/elasticsearch/backups
```

O IP publicado precisa existir no host Docker. O valor local `127.0.0.1` evita
o erro de bind do IP do servidor no Windows. `0.0.0.0` publica em todas as
interfaces IPv4; o certificado ainda precisa incluir o IP usado pelo cliente.

## Iniciar e conectar

O `.env` desta instalação já está preenchido. Em outro clone, copie
`.env.example` para `.env` e substitua a senha de exemplo por uma aleatória:

```powershell
Copy-Item .env.example .env
$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$rng.Dispose()
$password = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
# Cole o valor de $password no campo ELASTIC_PASSWORD do .env.
```

Execute na raiz do projeto:

```powershell
docker compose config --quiet
docker compose up -d --wait --wait-timeout 300
docker compose ps
docker compose exec -T elasticsearch bash -c 'curl --fail --silent --cacert config/certs/ca/ca.crt -u "elastic:$ELASTIC_PASSWORD" https://localhost:9200'
```

O setup encerra com código 0; isso é esperado. O Elasticsearch fica em execução.
O healthcheck aceita `yellow` ou `green`, pois uma instância única não consegue
alocar réplicas em outro nó. Não existe um banco padrão numerado como no Redis:
os documentos são organizados em índices.

Para clientes externos, exporte somente o certificado público da CA:

```powershell
New-Item -ItemType Directory -Force certs | Out-Null
docker compose cp elasticsearch:/usr/share/elasticsearch/config/certs/ca/ca.crt ./certs/ca.crt
curl.exe --cacert ./certs/ca.crt -u elastic https://127.0.0.1:9200
```

O curl solicitará a senha. No servidor, use `https://100.64.10.1:9200`, com
usuário `elastic`, senha do `.env` e CA confiável. Não use `-k` para ignorar TLS.
Na mesma rede Compose, use `https://elasticsearch:9200`; fora dela, use IP/DNS
estável do host e a porta publicada. DNS personalizado exige certificado com
esse DNS nos SANs; ajuste `--dns` no setup antes da primeira inicialização.

O certificado inclui localhost, elasticsearch, 127.0.0.1 e ES_CERT_IP. A CA dura
3650 dias e o certificado do servidor 825 dias. Planeje a renovação antes de
expirar. Alterar ES_CERT_IP não regenera certificados existentes: para renovar,
pare o serviço, faça backup do volume de certificados, remova somente os arquivos
do certificado do servidor e execute o setup novamente, preservando a CA.
Não apague o volume inteiro sem planejar a distribuição de uma nova CA aos clientes.

## Operação e senhas

```powershell
docker compose logs -f --tail 100 elasticsearch
docker compose down
docker compose up -d --wait --wait-timeout 300
```

`down` preserva os bind mounts e volumes. `down -v` remove os volumes de
certificados, CA pública e dados locais do Kibana, mas não apaga `data/` ou
`backups/`; evite perder a CA.
Mudar ES_DATA_DIR aponta para outro armazenamento e não migra dados existentes.

ELASTIC_PASSWORD é aplicada somente na inicialização de dados novos. Para trocar
a senha em uma instalação existente:

```powershell
docker compose exec elasticsearch bin/elasticsearch-reset-password -u elastic -i --url https://localhost:9200
```

Depois atualize o `.env` com a mesma senha e recrie o serviço para atualizar o
healthcheck: `docker compose up -d --force-recreate --wait --wait-timeout 300`.
Não compartilhe `docker compose config` sem `--quiet`: ele mostra o segredo.
Use usuários ou API keys com permissões específicas para aplicações.

## Backup e restauração

Use a API de snapshots. Copiar o diretório de dados de um nó não é um backup
suportado. Abra um shell com cliente autenticado:

```powershell
docker compose exec elasticsearch bash
```

Dentro dele, registre o repositório e crie um snapshot:

```bash
escurl() { curl --fail-with-body --silent --show-error --cacert config/certs/ca/ca.crt -u "elastic:$ELASTIC_PASSWORD" -H 'Content-Type: application/json' "$@"; }
escurl -X PUT https://localhost:9200/_snapshot/local -d '{"type":"fs","settings":{"location":"/mnt/snapshots"}}'
escurl -X PUT 'https://localhost:9200/_snapshot/local/manual-001?wait_for_completion=true' -d '{"include_global_state":false}'
escurl https://localhost:9200/_snapshot/local/manual-001
```

Use um nome novo para cada snapshot e confirme `SUCCESS`. Esse exemplo salva os
índices comuns sem o estado global; para recuperação completa, planeje também
feature states, usuários, configurações, certificados e segredos. Copie o
repositório completo para armazenamento externo somente sem gravações concorrentes
(por exemplo, depois de desregistrá-lo pela API DELETE /_snapshot/local).
Não altere arquivos internos nem copie apenas parte do repositório.

Para restaurar um índice como outro nome, no mesmo shell, com o repositório registrado:

```bash
escurl -X POST 'https://localhost:9200/_snapshot/local/manual-001/_restore?wait_for_completion=true' -d '{"indices":"meu-indice","include_global_state":false,"rename_pattern":"(.+)","rename_replacement":"restaurado-$1"}'
```

Substitua `meu-indice` pelo índice salvo e valide os documentos restaurados.
Não sobrescreva índices importantes sem planejar conflitos e indisponibilidade.
Snapshots têm regras de compatibilidade entre versões; teste a recuperação.
[Documentação de snapshots](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore).

## Atualização e diagnóstico

Antes de atualizar, crie e valide um snapshot, consulte as notas da versão e
as regras de upgrade e homologue. Altere a imagem fixa em `x-image`, execute
`docker compose pull` e recrie. Não faça downgrade de um diretório atualizado.

- Erro de bind: ES_BIND_IP não está presente no host ou ES_PORT está ocupada.
- Permission denied nos dados: revise UID 1000/grupo 0 e permissões do bind mount.
- Falha de TLS: confira CA, IP/DNS nos SANs e validade dos certificados.
- HTTP 401: confira senha; mudar `.env` não altera a senha de dados existentes.
- vm.max_map_count: ajuste o kernel do host Linux conforme a preparação.
- Exit 137/OOM: confira memória disponível, limite do contêiner e heap.
- Cluster yellow: pode ser esperado com réplicas e apenas um nó; não há redundância.
- Escritas bloqueadas por disco: libere espaço e examine os limites de disco do Elasticsearch.

Esta topologia tem um único nó e não oferece alta disponibilidade. Restrinja
o firewall às redes/clientes necessários, monitore disco/memória e mantenha
snapshots externos. A senha pode ser lida por administradores do Docker.

## Kibana e Cloudflare Tunnel

Kibana usa a imagem oficial `docker.elastic.co/kibana/kibana:9.5.5`, em um
contêiner separado no mesmo Compose. Atualize Elasticsearch e Kibana juntos
para a mesma versão após homologação. O setup de certificados publica apenas
a CA pública em um volume separado: o Kibana não recebe as chaves privadas do
Elasticsearch nem da CA.

O serviço `kibana-setup` aguarda o Elasticsearch saudável e define a senha de
`kibana_system` por API. Ele encerra com código 0. Essa conta é técnica; para
entrar no navegador, use `elastic` e a senha `ELASTIC_PASSWORD`. Crie usuários
com permissões específicas para o uso cotidiano.

| Variável | Valor local | Função |
| --- | --- | --- |
| `KIBANA_PASSWORD` | Aleatória no `.env` | Senha técnica hexadecimal com no mínimo 64 caracteres |
| `KIBANA_BIND_IP` | `127.0.0.1` | IP de publicação do Kibana no host |
| `KIBANA_PORT` | `5601` | Porta publicada; interna sempre 5601 |
| `KIBANA_PUBLIC_URL` | `http://localhost:5601` | URL externa completa, sem barra final |
| `KIBANA_SECURE_COOKIES` | `false` | Use `true` quando o navegador acessar por HTTPS |
| `KIBANA_MEMORY_LIMIT` | `2g` | Limite de memória do Kibana |
| `KIBANA_SECURITY_KEY` | Aleatória no `.env` | Chave persistente das sessões |
| `KIBANA_SAVED_OBJECTS_KEY` | Aleatória no `.env` | Chave persistente de objetos criptografados |
| `KIBANA_REPORTING_KEY` | Aleatória no `.env` | Chave persistente de relatórios |

As três chaves precisam ter pelo menos 32 caracteres. No `.env` desta instalação
foram geradas com 64 caracteres hexadecimais exclusivos. Em novos clones, substitua
todos os exemplos por segredos aleatórios; o gerador PowerShell acima serve para
cada chave. Preserve-as entre deploys e guarde cópias protegidas junto aos
segredos da instalação. Perder a chave de objetos pode impedir sua descriptografia.

Inicie tudo com `docker compose up -d --wait --wait-timeout 420` e abra
`http://localhost:5601`. Para logs: `docker compose logs -f --tail 100 kibana`.
Para reiniciar somente a interface: `docker compose restart kibana`.

Para acesso pelo domínio do Tunnel, ajuste no `.env`:

```dotenv
KIBANA_PUBLIC_URL=https://kibana.seu-dominio.com
KIBANA_SECURE_COOKIES=true
```

Substitua pelo domínio real e recrie o serviço com
`docker compose up -d --wait --wait-timeout 420`. O trecho navegador–Cloudflare
usa HTTPS; o trecho local cloudflared–Kibana usa HTTP. Kibana–Elasticsearch
continua usando HTTPS com verificação da CA e do hostname.

Se o cloudflared roda diretamente no host Linux, encaminhe o Tunnel para
`http://127.0.0.1:5601`, mantendo KIBANA_BIND_IP=127.0.0.1. Se roda em contêiner,
conecte-o à rede Docker `elasticsearch-db_default` e encaminhe para
`http://kibana:5601`; nesse caso não use localhost. Para um Compose separado,
declare essa rede como externa no projeto do cloudflared. Se os dois serviços
estiverem em hosts diferentes, use o IP Tailscale e publique o Kibana nesse IP.

Proteja o domínio com Cloudflare Access e mantenha o login do Kibana. Nenhuma
rota pública do Elasticsearch é necessária. O Tunnel e suas credenciais não
são criados por este projeto. Para acessar o Kibana diretamente por HTTP,
secure cookies deve estar false; com true, faça o login pelo domínio HTTPS.

Se quiser trocar KIBANA_PASSWORD, altere o `.env` e rode o comando de inicialização
completo para executar `kibana-setup` antes de iniciar o Kibana com a nova senha.
Isso pressupõe ELASTIC_PASSWORD sincronizada com a senha real do Elasticsearch.
Falhas de autenticação entre serviços aparecem nos logs de kibana-setup ou Kibana.

[Instalação oficial do Kibana](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-kibana-with-docker)
e [configurações de segurança](https://www.elastic.co/docs/reference/kibana/configuration-reference/security-settings).
