# Otimizações de Rede para Servidores Linux

Este documento detalha as otimizações de rede implementadas pelo script `optimize_system.sh` do Toolkit for Servers, explicando os conceitos, motivações e impactos no desempenho.

## Índice

1. [Introdução à Pilha de Rede do Linux](#introdução-à-pilha-de-rede-do-linux)
2. [Parâmetros do Kernel para Rede](#parâmetros-do-kernel-para-rede)
3. [Otimizações de Interface de Rede](#otimizações-de-interface-de-rede)
4. [TCP Tuning](#tcp-tuning)
5. [Segurança de Rede](#segurança-de-rede)
6. [Ajuste para Casos de Uso Específicos](#ajuste-para-casos-de-uso-específicos)
7. [Referências](#referências)

## Introdução à Pilha de Rede do Linux

A pilha de rede do Linux é composta por várias camadas que processam pacotes desde a interface física até a aplicação. A otimização dessas camadas pode melhorar significativamente o desempenho da rede, a latência e a capacidade de lidar com cargas pesadas.

### Componentes Principais

- **Interface de Rede**: Hardware e drivers que lidam com pacotes físicos
- **Filas de Recepção/Transmissão**: Buffers onde pacotes são armazenados antes/depois do processamento
- **Protocolo IP**: Gerencia o roteamento de pacotes
- **Protocolo TCP/UDP**: Gerencia conexões e transferência de dados
- **Sockets**: Interface entre aplicações e a pilha de rede

## Parâmetros do Kernel para Rede

O script `optimize_system.sh` ajusta vários parâmetros do kernel relacionados à rede para melhorar o desempenho:

### Tamanho Máximo da Fila de Conexões

```
net.core.somaxconn = 65536
```

- **Descrição**: Define o tamanho máximo da fila de conexões pendentes para um socket
- **Comportamento Padrão**: 128-4096 na maioria das distribuições
- **Otimização**: Aumentado para 65536 para suportar um grande número de conexões simultâneas
- **Benefícios**: Evita erros "connection refused" em servidores sob alta carga
- **Casos de Uso**: Servidores web, load balancers, proxies reversos

### Backlog de Dispositivo de Rede

```
net.core.netdev_max_backlog = 65536
```

- **Descrição**: Número máximo de pacotes na fila para processamento quando a interface recebe pacotes mais rápido que o kernel pode processá-los
- **Comportamento Padrão**: 1000 na maioria das distribuições
- **Otimização**: Aumentado para 65536 para lidar com tráfego de alta velocidade (10Gbps+)
- **Benefícios**: Reduz o descarte de pacotes durante picos de tráfego
- **Casos de Uso**: Servidores com interfaces de rede de alta velocidade, CDNs, streaming

### Tamanhos de Buffer de Socket

```
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
```

- **Descrição**: Tamanhos máximo e padrão para buffers de recepção (rmem) e envio (wmem) para todos os tipos de conexões
- **Comportamento Padrão**: Valores baixos que limitam o throughput em redes de alta latência
- **Otimização**: Aumentados para permitir maior throughput em redes de alta latência ou alta velocidade
- **Benefícios**: Maior throughput TCP, especialmente em conexões de longa distância
- **Casos de Uso**: Transferências de dados em massa, redes com alta latência (WAN, conexões internacionais)

## Otimizações de Interface de Rede

O script também otimiza as interfaces de rede físicas:

### Tamanho de Buffers (RX/TX)

```
ethtool -G "$iface" rx 4096 tx 4096
```

- **Descrição**: Ajusta os tamanhos dos rings buffers de hardware para recepção (rx) e transmissão (tx)
- **Comportamento Padrão**: Varia por driver e hardware (geralmente 256-1024)
- **Otimização**: Aumentados para 4096 entradas, equilibrando uso de memória e desempenho
- **Benefícios**: Reduz perdas de pacotes em interfaces de alta velocidade
- **Casos de Uso**: Redes de 10Gbps+, tráfego em rajadas, servidores de streaming

### Offloads de Hardware

```
ethtool -K "$iface" gso on gro on tso on
```

- **Descrição**: Ativa recursos de offload na placa de rede
  - **GSO** (Generic Segmentation Offload): Move a segmentação de pacotes grandes para o hardware
  - **GRO** (Generic Receive Offload): Combina pacotes similares na recepção
  - **TSO** (TCP Segmentation Offload): Específico para segmentação TCP
- **Comportamento Padrão**: Varia por driver e distribuição
- **Otimização**: Todos os offloads ativados para reduzir a carga da CPU
- **Benefícios**: Menor uso de CPU para processamento de pacotes, maior throughput
- **Casos de Uso**: Servidores com alta taxa de transferência, deixando a CPU livre para aplicações

## TCP Tuning

Os parâmetros TCP foram ajustados para otimizar o desempenho em várias situações:

### Buffers TCP

```
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
```

- **Descrição**: Define os tamanhos mínimo, padrão e máximo de buffer para conexões TCP
- **Comportamento Padrão**: Valores conservadores que limitam throughput
- **Otimização**: Valores maiores que permitem alto throughput em conexões de alta latência
- **Benefícios**: Melhor desempenho em conexões WAN e redes congestionadas
- **Casos de Uso**: Downloads/uploads de arquivos grandes, replicação de dados, backups

### Timeout de FIN_WAIT

```
net.ipv4.tcp_fin_timeout = 15
```

- **Descrição**: Tempo que uma conexão permanece no estado FIN_WAIT_2 antes de ser encerrada
- **Comportamento Padrão**: 60 segundos
- **Otimização**: Reduzido para 15 segundos para liberar recursos mais rapidamente
- **Benefícios**: Mais conexões disponíveis, menor consumo de memória para conexões em fechamento
- **Casos de Uso**: Servidores web com muitas conexões de curta duração

### Backlog de SYN

```
net.ipv4.tcp_max_syn_backlog = 65536
```

- **Descrição**: Número máximo de conexões TCP "meio abertas" (receberam SYN mas não completaram o handshake)
- **Comportamento Padrão**: 128-1024 dependendo da distribuição
- **Otimização**: Aumentado para suportar muitas conexões simultâneas
- **Benefícios**: Melhor resposta durante picos de tráfego e tentativas de conexão
- **Casos de Uso**: Servidores web com tráfego em rajadas

### Inicialização Lenta TCP

```
net.ipv4.tcp_slow_start_after_idle = 0
```

- **Descrição**: Controla se o TCP reinicia a janela de congestionamento após período de inatividade
- **Comportamento Padrão**: 1 (ativado)
- **Otimização**: Desativado (0) para manter a janela de congestionamento após períodos curtos de inatividade
- **Benefícios**: Melhor throughput para conexões com tráfego em rajadas
- **Casos de Uso**: APIs, microserviços, conexões intermitentes

### SYN Cookies

```
net.ipv4.tcp_syncookies = 1
```

- **Descrição**: Mecanismo de proteção contra ataques SYN flood
- **Comportamento Padrão**: Geralmente ativado (1)
- **Otimização**: Mantido ativado para proteção contra ataques
- **Benefícios**: Protege contra um tipo comum de ataque DDoS
- **Casos de Uso**: Qualquer servidor exposto à internet

## Segurança de Rede

As otimizações não são apenas para desempenho, mas também para segurança:

### Filtro de Pacotes Falsificados

```
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
```

- **Descrição**: Verifica se o pacote recebido vem da interface correta (anti-spoofing)
- **Comportamento Padrão**: Varia por distribuição
- **Otimização**: Ativado para todas as interfaces
- **Benefícios**: Proteção contra ataques de IP spoofing
- **Casos de Uso**: Todos os servidores públicos

### Desativação de Redirecionamentos ICMP

```
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
```

- **Descrição**: Controla se o sistema aceita redirecionamentos ICMP que podem alterar tabelas de roteamento
- **Comportamento Padrão**: Ativado (1) em muitas distribuições
- **Otimização**: Desativado (0) para evitar ataques man-in-the-middle
- **Benefícios**: Previne manipulação de rotas por terceiros
- **Casos de Uso**: Qualquer servidor, especialmente em redes públicas

### Proteção contra Broadcast ICMP

```
net.ipv4.icmp_echo_ignore_broadcasts = 1
```

- **Descrição**: Ignora pacotes ICMP echo dirigidos a endereços de broadcast
- **Comportamento Padrão**: Geralmente ativado
- **Otimização**: Mantido ativado
- **Benefícios**: Previne que o servidor seja usado em ataques "Smurf"
- **Casos de Uso**: Todos os servidores

## Ajuste para Casos de Uso Específicos

Diferentes cargas de trabalho podem se beneficiar de ajustes específicos:

### Para Servidores Web de Alto Tráfego

```
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.ip_local_port_range = 1024 65535
```

- **Benefícios**: Suporta dezenas de milhares de conexões simultâneas
- **Exemplos**: Nginx, Apache com muitos usuários simultâneos

### Para Transferência de Dados em Massa

```
net.ipv4.tcp_rmem = 4096 1048576 33554432  # Valores ainda maiores
net.ipv4.tcp_wmem = 4096 65536 33554432    # Valores ainda maiores
```

- **Benefícios**: Maximiza throughput para transferências grandes
- **Exemplos**: Backups, sincronização de dados, CDNs

### Para Serviços de Baixa Latência

```
net.ipv4.tcp_fastopen = 3
net.core.busy_poll = 50
net.core.busy_read = 50
```

- **Benefícios**: Reduz latência para conexões frequentes
- **Exemplos**: APIs de microserviços, jogos online, trading

## Referências

1. Linux Advanced Routing & Traffic Control HOWTO, https://lartc.org/

2. Dhaval Giani, et al., "Tuning 10Gb network cards on Linux", Proceedings of the Linux Symposium, 2010.

3. Brendan Gregg, "Linux Performance Analysis: New Tools and Old Secrets", ACM Queue, 2018.

4. Red Hat Performance Tuning Guide, "Networking", https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/performance_tuning_guide/sect-red_hat_enterprise_linux-performance_tuning_guide-networking

5. Ilya Grigorik, "High Performance Browser Networking", O'Reilly Media, 2013.

6. Netflix Technology Blog, "Linux Performance Analysis in 60 seconds", 2019.

7. Digital Ocean, "How To Optimize Nginx Configuration", https://www.digitalocean.com/community/tutorials/how-to-optimize-nginx-configuration

8. Cisco, "TCP/IP Performance Tuning", https://www.cisco.com/c/en/us/support/docs/ip/routing-information-protocol-rip/16376-15.html

9. Tom Herbert, "XDP (eXpress Data Path): Programmable In-Kernel Fast Path", NetDev 1.2, 2016.

10. Facebook Engineering, "Building Zero protocol for fast, secure mobile connections", 2018.

11. CloudFlare Blog, "Optimizing TCP for high WAN performance", 2017.

12. Arch Linux Wiki, "Sysctl - Network", https://wiki.archlinux.org/title/Sysctl#Network