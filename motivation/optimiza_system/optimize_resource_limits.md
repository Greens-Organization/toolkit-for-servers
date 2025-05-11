# Limites de Recursos em Sistemas Linux

Este documento explica em detalhes os limites de recursos em sistemas Linux, por que são importantes e como eles são configurados no script `optimize_system.sh` do Toolkit for Servers.

## Índice

1. [Introdução aos Limites de Recursos](#introdução-aos-limites-de-recursos)
2. [Tipos de Limites no Linux](#tipos-de-limites-no-linux)
3. [Configurações Implementadas](#configurações-implementadas)
4. [Impacto no Desempenho e Estabilidade](#impacto-no-desempenho-e-estabilidade)
5. [Casos de Uso Específicos](#casos-de-uso-específicos)
6. [Referências](#referências)

## Introdução aos Limites de Recursos

Limites de recursos no Linux são restrições impostas ao consumo de recursos pelo sistema operacional para processos e usuários. Eles desempenham um papel crucial na estabilidade, segurança e desempenho de sistemas, especialmente em ambientes de servidor.

### Objetivos dos Limites de Recursos:

- **Estabilidade**: Evitar que um processo ou usuário consuma todos os recursos do sistema
- **Segurança**: Proteger contra ataques de negação de serviço (DoS)
- **Multi-tenancy**: Permitir múltiplos usuários/aplicações em um único sistema
- **Previsibilidade**: Garantir recursos consistentes para aplicações críticas

## Tipos de Limites no Linux

O Linux possui dois mecanismos principais para limitar recursos:

### 1. Limites de Processo/Usuário (`limits.conf`)

Controlados pelo módulo PAM `pam_limits` e configurados em `/etc/security/limits.conf` ou arquivos em `/etc/security/limits.d/`.

Existem dois tipos de limites:
- **Limites Soft**: Podem ser aumentados pelo próprio processo até o limite hard
- **Limites Hard**: Limite máximo que um processo pode definir para si mesmo

### 2. Limites do Kernel (`sysctl`)

Controlados por parâmetros do kernel via `sysctl` e configurados em `/etc/sysctl.conf` ou arquivos em `/etc/sysctl.d/`.

## Configurações Implementadas

O script `optimize_system.sh` configura vários limites importantes para melhorar o desempenho e estabilidade do servidor:

### Limites de Arquivos Abertos (`nofile`)

```
*               soft    nofile          131072
*               hard    nofile          524288
```

- **Descrição**: Define o número máximo de descritores de arquivo (arquivos abertos, sockets, pipes) que um processo pode usar
- **Comportamento Padrão**: Geralmente 1024, o que é muito baixo para servidores modernos
- **Otimização**: 
  - Soft limit de 131.072 (128K) permite aplicações abrirem muitos arquivos sem configuração especial
  - Hard limit de 524.288 (512K) permite que aplicações aumentem seu próprio limite quando necessário
- **Impacto**: Previne erros "Too many open files" em servidores ocupados
- **Sintomas de Valor Baixo**: 
  - Erros de "Too many open files" nos logs
  - Falhas de conexão em serviços de rede
  - Recusas de novas conexões de cliente

### Limites de Processos (`nproc`)

```
*               soft    nproc           65535
*               hard    nproc           131072
```

- **Descrição**: Número máximo de processos que um usuário pode executar simultaneamente
- **Comportamento Padrão**: Geralmente entre 1024-4096, inadequado para ambientes de container
- **Otimização**:
  - Soft limit de 65.535 (64K) suporta muitos processos sem configuração especial
  - Hard limit de 131.072 (128K) permite escalar para ambientes de container densos
- **Impacto**: Previne erros "Cannot fork" e protege contra fork bombs acidentais
- **Sintomas de Valor Baixo**:
  - Erros "fork: Resource temporarily unavailable"
  - Falhas ao iniciar novos processos
  - Problemas com sistemas de orquestração de container

### Limites de Memória Bloqueada (`memlock`)

```
*               soft    memlock         unlimited
*               hard    memlock         unlimited
```

- **Descrição**: Quantidade de memória que um processo pode bloquear na RAM (impedir de ir para swap)
- **Comportamento Padrão**: Geralmente 64KB, o que é extremamente restritivo
- **Otimização**: Configurado como "unlimited" para permitir:
  - Bases de dados bloquearem suas páginas em memória
  - Aplicações de tempo real garantirem baixa latência
  - Software de análise de big data usar grandes blocos de memória contíguos
- **Impacto**: Melhor desempenho para aplicações sensíveis à latência
- **Sintomas de Valor Baixo**:
  - Erros "cannot allocate memory" em bancos de dados
  - Latência irregular em aplicações de tempo real
  - Desempenho reduzido em sistemas de alta performance

### Limites de Core Dumps (`core`)

```
*               soft    core            unlimited
*               hard    core            unlimited
```

- **Descrição**: Tamanho máximo dos arquivos de core dump gerados quando um processo falha
- **Comportamento Padrão**: Geralmente 0, o que desativa a geração de core dumps
- **Otimização**: Configurado como "unlimited" para:
  - Permitir debugging completo quando ocorrem falhas
  - Facilitar a identificação e solução de problemas em produção
- **Impacto**: Melhor diagnosticabilidade de problemas
- **Considerações**: Em produção, você pode querer limitar isso se o espaço em disco for uma preocupação

### Configuração do PAM

O script também verifica e configura o suporte PAM para os limites:

```bash
if [ -d "/etc/pam.d" ]; then
    if ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
        echo "session required pam_limits.so" >> /etc/pam.d/common-session
    fi
fi
```

- **Descrição**: Garante que o módulo `pam_limits.so` seja carregado durante a criação de sessão
- **Importância**: Sem esta configuração, os limites definidos em `limits.conf` não são aplicados
- **Impacto**: Garante que todos os limites configurados estejam realmente ativos

## Impacto no Desempenho e Estabilidade

Limites de recursos adequados têm impacto significativo na estabilidade e desempenho:

### Melhorias na Estabilidade

- **Proteção Contra Sobrecarga**: Previne que um único processo ou usuário consuma todos os recursos
- **Isolamento**: Limita o impacto de processos mal-comportados no resto do sistema
- **Recuperação Previsível**: Define como o sistema se comporta sob pressão de recursos

### Melhorias no Desempenho

- **Prevenção de Erros**: Elimina falhas por falta de recursos para aplicações bem-dimensionadas
- **Otimização para Concorrência**: Suporta grande número de conexões/threads/processos simultâneos
- **Flexibilidade para Aplicações**: Permite que aplicações usem recursos intensivamente quando necessário

## Casos de Uso Específicos

Diferentes cargas de trabalho se beneficiam de diferentes configurações de limites:

### Para Servidores Web

```
nofile: 131072/524288
```

- **Benefício**: Cada conexão HTTP requer um descritor de arquivo
- **Impacto**: Um servidor web como Nginx ou Apache pode lidar com dezenas de milhares de conexões simultâneas

### Para Bancos de Dados

```
memlock: unlimited
```

- **Benefício**: Bancos de dados podem pinar páginas críticas na memória
- **Impacto**: Latência mais previsível e menor, especialmente para cargas de trabalho transacionais

### Para Ambientes de Container

```
nproc: 65535/131072
```

- **Benefício**: Permite executar muitos containers em um único host
- **Impacto**: Orquestradores como Kubernetes podem gerenciar clusters maiores por servidor

### Para Aplicações de Análise de Dados

```
memlock: unlimited
nofile: 131072/524288
```

- **Benefício**: Permite grandes alocações de memória contígua e muitos arquivos abertos
- **Impacto**: Frameworks como Spark podem processar grandes conjuntos de dados eficientemente

## Referências

1. Michael Kerrisk, "The Linux Programming Interface", No Starch Press, 2010.

2. Ulrich Drepper, "What Every Programmer Should Know About Memory", Red Hat, Inc., 2007.

3. Red Hat Documentation, "Resource Management Guide", https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/resource_management_guide/

4. MongoDB Documentation, "Production Notes - Linux System Settings", https://www.mongodb.com/docs/manual/administration/production-notes/

5. PostgreSQL Wiki, "Linux Memory Overcommit", https://wiki.postgresql.org/wiki/Linux_Memory_Overcommit

6. Docker Documentation, "Runtime constraints on resources", https://docs.docker.com/config/containers/resource_constraints/

7. Kubernetes Documentation, "Managing Resources for Containers", https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

8. Oracle Documentation, "Linux Shared Memory (SysV IPC) Tunables", https://docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/setting-linux-parameters-manually.html

9. Apache HTTP Server Documentation, "Performance Tuning", https://httpd.apache.org/docs/2.4/misc/perf-tuning.html

10. NGINX Documentation, "Tuning NGINX for Performance", https://www.nginx.com/blog/tuning-nginx/

11. Elasticsearch Documentation, "Important System Configuration", https://www.elastic.co/guide/en/elasticsearch/reference/current/system-config.html

12. Thomas Gleixner, et al., "Linux Core Infrastructure and API", Linux Foundation, 2014.