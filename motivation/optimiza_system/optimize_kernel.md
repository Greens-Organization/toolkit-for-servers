# Otimizações do Kernel Linux

Este documento explica as otimizações implementadas pelo script `optimize_system.sh` do Toolkit for Servers, detalhando o propósito de cada ajuste, seus benefícios e os casos de uso que mais se beneficiam dessas configurações.

## Índice

1. [Otimização de Parâmetros do Kernel](#otimização-de-parâmetros-do-kernel)
2. [Limites de Recursos do Sistema](#limites-de-recursos-do-sistema)
3. [Escalonador de I/O](#escalonador-de-io)
4. [Otimização da Pilha de Rede](#otimização-da-pilha-de-rede)
5. [Casos de Uso Específicos](#casos-de-uso-específicos)
6. [Referências](#referências)

## Otimização de Parâmetros do Kernel

A função `optimize_kernel_parameters` ajusta parâmetros do kernel Linux via `sysctl` para melhorar o desempenho e a estabilidade do sistema.

### Limites de Arquivos

```
fs.file-max = [valor calculado baseado na memória]
fs.nr_open = [valor calculado baseado na memória]
```

- **Propósito**: Define o número máximo de arquivos abertos permitidos no sistema.
- **Comportamento Padrão**: Muitas distribuições Linux definem valores relativamente baixos.
- **Otimização**: Aumenta o limite baseado na quantidade de memória disponível (256K arquivos por GB de RAM).
- **Benefícios**: Evita erros "too many open files" em servidores com alta carga.
- **Casos de Uso**: Servidores web, proxies, caches e qualquer serviço que mantenha muitas conexões simultâneas.

### Swappiness

```
vm.swappiness = [5-30 baseado na memória]
```

- **Propósito**: Controla a agressividade do kernel ao mover memória para o espaço de swap.
- **Comportamento Padrão**: A maioria das distribuições usa o valor 60, que é muito agressivo para servidores.
- **Otimização**:
  - Servidores com pouca RAM (< 4GB): 30
  - Servidores com RAM média (4-64GB): 10
  - Servidores com muita RAM (> 64GB): 5
- **Benefícios**: Reduz a troca desnecessária de páginas para o disco, melhorando a latência e o desempenho.
- **Casos de Uso**: 
  - Valores baixos (5-10): Ideal para bancos de dados, caches em memória, aplicações de tempo real
  - Valores moderados (30): Melhor para servidores com memória limitada rodando muitos processos

### Pressão de Cache VFS

```
vm.vfs_cache_pressure = 50
```

- **Propósito**: Controla a tendência do kernel em recuperar memória usada para cache de metadados do sistema de arquivos.
- **Comportamento Padrão**: O valor padrão é 100, o que significa que o kernel trata caches de dentries/inodes igualmente a páginas de dados.
- **Otimização**: Valor 50 reduz a pressão sobre caches de sistema de arquivos.
- **Benefícios**: Melhora o desempenho de I/O, mantendo mais metadados de arquivos em memória.
- **Casos de Uso**: Servidores de arquivos, NAS, sistemas com I/O intenso.

### Mapas de Memória

```
vm.max_map_count = 262144
```

- **Propósito**: Define o número máximo de regiões de mapeamento de memória que um processo pode ter.
- **Comportamento Padrão**: Muitas distribuições definem valores entre 65536-262144.
- **Otimização**: Aumenta para permitir aplicações que precisam mapear muitas regiões de memória.
- **Benefícios**: Evita erros "mmap failed" em aplicações que usam muitos mapeamentos de memória.
- **Casos de Uso**: Elasticsearch, JVMs, bancos de dados, containers.

### Parâmetros TCP

```
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_syncookies = 1
```

- **Propósito**: Ajustar como o TCP gerencia conexões e buffers.
- **Comportamento Padrão**: Valores conservadores que não são ideais para redes modernas de alta velocidade.
- **Otimização**: 
  - Buffers maiores para melhor throughput em conexões de alta latência
  - Timeout de FIN reduzido para liberar recursos mais rápido
  - Backlog de SYN aumentado para lidar com muitas conexões simultâneas
  - SYN cookies ativados para proteção contra ataques SYN flood
- **Benefícios**: Melhor desempenho de rede, menor latência, maior throughput, proteção contra alguns ataques.
- **Casos de Uso**: Servidores web, aplicações em nuvem, jogos, streaming, aplicações em tempo real.

### Proteções de Segurança

```
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
```

- **Propósito**: Desativar recursos que podem ser usados em ataques.
- **Comportamento Padrão**: Muitas distribuições habilitam recursos que podem ser explorados.
- **Otimização**: Desativa redirecionamentos ICMP, roteamento de origem e resposta a broadcast ICMP.
- **Benefícios**: Reduz superfície de ataque e melhora a segurança geral.
- **Casos de Uso**: Todos os servidores, especialmente os expostos à internet.

## Limites de Recursos do Sistema

A função `optimize_resource_limits` configura limites de sistema via `/etc/security/limits.conf` para controlar recursos que processos podem usar.

### Limites de Arquivos Abertos (nofile)

```
*               soft    nofile          131072
*               hard    nofile          524288
```

- **Propósito**: Define o número máximo de descritores de arquivo que um usuário/processo pode abrir.
- **Comportamento Padrão**: O limite padrão (1024) é muito baixo para servidores modernos.
- **Otimização**: Aumenta para valores que suportam servidores de alta capacidade.
- **Benefícios**: Evita erros "too many open files" em nível de usuário/processo.
- **Casos de Uso**: Servidores web, proxy, banco de dados, cache.

### Limites de Processos (nproc)

```
*               soft    nproc           65535
*               hard    nproc           131072
```

- **Propósito**: Define o número máximo de processos que um usuário pode executar simultaneamente.
- **Comportamento Padrão**: Os limites padrão (1024-4096) são baixos para ambientes modernos.
- **Otimização**: Aumenta substancialmente para suportar ambientes de container e microserviços.
- **Benefícios**: Proteção contra fork bombs enquanto permite carga de trabalho legítima.
- **Casos de Uso**: Servidores de container, CI/CD, ambientes multi-usuário.

### Limites de Memória Bloqueada (memlock)

```
*               soft    memlock         unlimited
*               hard    memlock         unlimited
```

- **Propósito**: Controla quanto de memória um processo pode bloquear (impedir de ir para swap).
- **Comportamento Padrão**: Valores baixos que podem limitar aplicações de alto desempenho.
- **Otimização**: Remove limitações para permitir que aplicações gerenciem sua própria memória.
- **Benefícios**: Permite aplicações reservarem memória para operações críticas.
- **Casos de Uso**: Bancos de dados, aplicações de tempo real, análise de big data.

## Escalonador de I/O

A função `optimize_io_scheduler` configura como o kernel programa operações de entrada/saída para dispositivos de armazenamento.

### Escalonadores por Tipo de Dispositivo

```
# NVMe SSDs
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"

# SSDs regulares
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDDs
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
```

- **Propósito**: Seleciona o escalonador de I/O mais apropriado para cada tipo de dispositivo.
- **Comportamento Padrão**: Muitas distribuições usam um único escalonador para todos os dispositivos.
- **Otimização**:
  - **none**: Para NVMe, que já tem hardware avançado de gerenciamento de I/O
  - **mq-deadline**: Para SSDs, oferece garantias de latência com sobrecarga mínima
  - **bfq** (Budget Fair Queueing): Para HDDs, otimiza movimentos da cabeça de leitura
- **Benefícios**: Melhor desempenho de I/O adaptado às características físicas do dispositivo.
- **Casos de Uso**:
  - **NVMe**: Servidores de banco de dados, análise em tempo real
  - **SSD**: Servidores web, aplicações com I/O misto
  - **HDD**: Armazenamento de backup, arquivos grandes

### Parâmetros de Fila

```
# Para dispositivos SSD/NVMe
echo 1024 > "${device}nr_requests"
echo 2048 > "${device}read_ahead_kb"
```

- **Propósito**: Ajusta como o kernel gerencia filas de I/O para diferentes dispositivos.
- **Comportamento Padrão**: Valores conservadores que não aproveitam o paralelismo de dispositivos modernos.
- **Otimização**:
  - **nr_requests**: Aumenta o tamanho da fila para SSDs para melhor paralelismo
  - **read_ahead_kb**: Aumenta leitura antecipada para melhorar desempenho sequencial
- **Benefícios**: Melhor throughput e capacidade de lidar com cargas de trabalho intensivas.
- **Casos de Uso**: Bancos de dados, streaming de mídia, análise de dados.

## Otimização da Pilha de Rede

A função `optimize_network_stack` ajusta como o sistema gerencia conexões de rede e buffers.

### Buffers de Interface

```
ethtool -G "$iface" rx 4096 tx 4096
```

- **Propósito**: Define o tamanho dos buffers de recepção (rx) e transmissão (tx) da placa de rede.
- **Comportamento Padrão**: Valores conservadores que podem causar perdas de pacotes em redes rápidas.
- **Otimização**: Aumenta para 4096, um bom equilíbrio entre uso de memória e desempenho.
- **Benefícios**: Reduz perdas de pacotes e interrupções em redes congestionadas.
- **Casos de Uso**: Servidores com tráfego de rede intenso, CDNs, streaming.

### Offload de Rede

```
ethtool -K "$iface" gso on gro on tso on
```

- **Propósito**: Habilita recursos de offload na placa de rede.
  - **GSO** (Generic Segmentation Offload)
  - **GRO** (Generic Receive Offload)
  - **TSO** (TCP Segmentation Offload)
- **Comportamento Padrão**: Varia por distribuição e driver.
- **Otimização**: Habilita todos os offloads para reduzir carga da CPU.
- **Benefícios**: Menor uso de CPU para processamento de pacotes.
- **Casos de Uso**: Servidores de alto tráfego, transferência de dados em massa.

## Casos de Uso Específicos

### Para Servidores Web

- **Parâmetros TCP otimizados**: Permitem mais conexões simultâneas e menor latência
- **Limites de arquivos mais altos**: Suportam mais conexões de clientes
- **Escalonador de I/O para SSD**: Melhora a entrega de conteúdo estático

### Para Bancos de Dados

- **Swappiness baixo**: Mantém dados críticos na RAM
- **Limites de memória bloqueada**: Permitem reserva de memória para operações críticas
- **Escalonador de I/O otimizado**: Melhora latência de operações de leitura/escrita

### Para Contêineres/Kubernetes

- **Parâmetros de kernel**: Suportam mais contêineres por host
- **Limites de processos elevados**: Permitem múltiplas instâncias de aplicações
- **Limites de arquivos**: Suportam sistemas com muitos contêineres e conexões

### Para Aplicações de Alto Desempenho

- **Limites de recursos elevados**: Permitem uso máximo do hardware
- **Escalonador de I/O para NVMe**: Minimiza latência de armazenamento
- **Otimizações de rede**: Melhoram a transferência de dados entre nós

### Para Servidores de Mídia/Streaming

- **Parâmetros de rede otimizados**: Reduzem buffer/jitter
- **Read-ahead maior**: Melhora leitura sequencial de arquivos grandes
- **Offload de rede**: Reduz carga da CPU durante streaming

## Referências

1. Red Hat Documentation, "Performance Tuning Guide", https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/performance_tuning_guide/

2. Brendan Gregg, "Systems Performance: Enterprise and the Cloud", 2nd Edition, Addison-Wesley Professional, 2020.

3. Linux Documentation Project, "Linux Kernel Networking", https://www.kernel.org/doc/Documentation/networking/

4. Arch Linux Wiki, "Sysctl", https://wiki.archlinux.org/title/Sysctl

5. Digital Ocean Community, "How To Optimize System Resources on Ubuntu", https://www.digitalocean.com/community/tutorials/how-to-optimize-nginx-configuration

6. Adrian Cockcroft, "Systems Performance Analysis", Netflix Technology Blog, 2018.

7. Adi Habusha, "Kernel Parameters for Large Scale Databases", Oracle Blog, 2019.

8. Facebook Engineering, "Scaling Linux Services: Network Stack Optimizations", Facebook Engineering Blog, 2020.

9. Joyent, "Linux Performance Tools", https://www.brendangregg.com/linuxperf.html

10. PostgreSQL Wiki, "Tuning Your PostgreSQL Server", https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server

11. MongoDB Documentation, "Production Notes - Linux System Settings", https://www.mongodb.com/docs/manual/administration/production-notes/

12. NGINX Documentation, "Tuning NGINX for Performance", https://www.nginx.com/blog/tuning-nginx/

13. Elasticsearch Documentation, "Important System Configuration", https://www.elastic.co/guide/en/elasticsearch/reference/current/system-config.html