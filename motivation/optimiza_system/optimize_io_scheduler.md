# Escalonadores de I/O no Linux

Este documento explica em mais detalhes os escalonadores de I/O no Linux, como funcionam e por que as escolhas específicas no script `optimize_system.sh` foram feitas para diferentes tipos de armazenamento.

## Índice

1. [Introdução aos Escalonadores de I/O](#introdução-aos-escalonadores-de-io)
2. [Tipos de Escalonadores](#tipos-de-escalonadores)
3. [Escolhendo o Escalonador Correto](#escolhendo-o-escalonador-correto)
4. [Parâmetros de Ajuste Adicionais](#parâmetros-de-ajuste-adicionais)
5. [Impacto no Desempenho](#impacto-no-desempenho)
6. [Referências](#referências)

## Introdução aos Escalonadores de I/O

Os escalonadores de I/O determinam como e quando as operações de entrada e saída são enviadas aos dispositivos de armazenamento. Eles desempenham um papel crucial no desempenho do sistema, afetando a latência e o throughput das operações de disco.

**Objetivos dos escalonadores:**
- Minimizar movimentos do cabeçote de leitura em discos rígidos
- Priorizar operações de I/O com base em critérios como deadlines ou justiça
- Balancear latência vs. throughput para diferentes cargas de trabalho
- Adaptar-se às características físicas do dispositivo de armazenamento

## Tipos de Escalonadores

O Linux suporta vários escalonadores de I/O, cada um com características distintas:

### None (No-op)

```
echo "none" > /sys/block/nvme0n1/queue/scheduler
```

- **Descrição**: Praticamente sem escalonamento, enviando as requisições diretamente para o dispositivo
- **Funcionamento**: Mantém uma FIFO (First-In-First-Out) simples para requisições
- **Vantagens**: Sobrecarga mínima, permite que o dispositivo gerencie suas próprias filas
- **Melhor para**: NVMe SSDs, que já possuem controladores sofisticados e paralelismo interno
- **Quando usar**: Dispositivos NVMe modernos que têm seu próprio escalonamento interno

**Por que usamos para NVMe no script:**
Os dispositivos NVMe têm controllers avançados que já implementam algoritmos de escalonamento internos. Adicionar outro nível de escalonamento no kernel Linux apenas adiciona latência sem benefícios, por isso "none" é a melhor opção para NVMe.

### MQ-Deadline

```
echo "mq-deadline" > /sys/block/sda/queue/scheduler
```

- **Descrição**: Versão multiqueue do escalonador deadline clássico
- **Funcionamento**: Garante que nenhuma operação de I/O espere indefinidamente, usando deadlines separados para leituras e escritas
- **Vantagens**: Baixa latência garantida, especialmente para leituras, com sobrecarga moderada
- **Melhor para**: SSDs, onde a ordenação espacial é menos importante que a garantia de tempo
- **Quando usar**: Cargas de trabalho sensíveis à latência em SSDs como bancos de dados OLTP

**Por que usamos para SSDs no script:**
SSDs não sofrem com o problema de movimento do cabeçote como HDDs, mas ainda se beneficiam de alguma ordenação de requisições. O escalonador mq-deadline oferece garantias de latência para evitar starvation, mas sem a sobrecarga desnecessária de escalonadores mais complexos como o BFQ.

### BFQ (Budget Fair Queuing)

```
echo "bfq" > /sys/block/sdb/queue/scheduler
```

- **Descrição**: Escalonador baseado em justiça com alocação de budget
- **Funcionamento**: Aloca "orçamentos" de tempo de dispositivo para cada processo e otimiza a ordem das requisições
- **Vantagens**: Melhor isolamento entre processos, previne starvation, otimiza movimentos do cabeçote
- **Melhor para**: HDDs, onde a ordenação de requisições para minimizar movimentos do cabeçote é crítica
- **Quando usar**: Sistemas com múltiplos processos competindo por I/O em discos rígidos

**Por que usamos para HDDs no script:**
HDDs têm componentes mecânicos que se movem fisicamente para acessar diferentes partes do disco. O escalonador BFQ agrupa solicitações baseadas na sua localização física no disco, reduzindo os movimentos do cabeçote e melhorando significativamente o desempenho para esses dispositivos.

## Escolhendo o Escalonador Correto

A escolha do escalonador de I/O ideal depende de diversos fatores:

1. **Tipo de hardware de armazenamento**:
   - HDDs: Precisam de escalonamento agressivo (BFQ)
   - SSDs: Precisam de escalonamento moderado (mq-deadline)
   - NVMe: Precisam de escalonamento mínimo (none)

2. **Tipo de carga de trabalho**:
   - Leitura aleatória (bancos de dados): Preferir latência baixa, especialmente para leituras
   - Streaming sequencial (mídia, backups): Preferir throughput alto
   - Mista (servidores web): Equilibrar latência e throughput

3. **Número de processos concorrentes**:
   - Poucos processos: Escalonadores simples são suficientes
   - Muitos processos: Escalonadores justos como BFQ são melhores

## Parâmetros de Ajuste Adicionais

Além de escolher o escalonador certo, outros parâmetros afetam o desempenho de I/O:

### nr_requests

```
echo 1024 > /sys/block/sda/queue/nr_requests
```

- **Descrição**: Tamanho máximo da fila de requisições para um dispositivo
- **Comportamento Padrão**: Varia por distribuição (128-256 é comum)
- **Otimização**:
  - SSDs/NVMe: Valores altos (1024+) aproveitam o paralelismo
  - HDDs: Valores moderados (128-512) fornecem bom equilíbrio
- **Impacto**: Valores mais altos podem melhorar throughput em troca de latência potencialmente maior

### read_ahead_kb

```
echo 2048 > /sys/block/sda/queue/read_ahead_kb
```

- **Descrição**: Quantidade de dados lidos antecipadamente durante leituras sequenciais
- **Comportamento Padrão**: Geralmente 128 KB
- **Otimização**:
  - Leitura sequencial (streaming, backup): Valores altos (1024-4096 KB)
  - Leitura aleatória (banco de dados): Valores baixos (16-128 KB)
- **Impacto**: Valores maiores melhoram o desempenho sequencial mas podem desperdiçar memória em padrões aleatórios

### nomerges

```
echo 2 > /sys/block/sda/queue/nomerges
```

- **Descrição**: Controla se o kernel tenta mesclar requisições de I/O adjacentes
- **Valores**:
  - 0: Sempre tenta mesclar (padrão)
  - 1: Mescla apenas requisições adjacentes do mesmo processo
  - 2: Nunca mescla
- **Otimização**: 
  - 2 para SSDs de alta performance onde a sobrecarga de mesclagem não compensa
  - 0 para HDDs onde mesclagem reduz movimento do cabeçote
- **Impacto**: Desativar mesclagem pode reduzir latência em SSDs mas aumentar o número de operações de I/O

## Impacto no Desempenho

O impacto das otimizações de escalonador pode ser substancial:

### Para NVMe SSDs (usando "none"):
- **Vantagem**: -5% a -15% de redução na latência em comparação com outros escalonadores
- **Beneficia**: Bancos de dados OLTP, trading de alta frequência, servidores de cache

### Para SSDs (usando "mq-deadline"):
- **Vantagem**: Equilíbrio entre latência e throughput, com garantias de tempo de resposta
- **Beneficia**: Servidores web, ambientes de uso geral, sistemas mistos

### Para HDDs (usando "bfq"):
- **Vantagem**: Até +30% de throughput em comparação com escalonadores não otimizados
- **Beneficia**: NAS, servidores de arquivos, backups, armazenamento em massa

## Exemplos Práticos

### Servidor de Banco de Dados em NVMe:

```bash
# Checando o escalonador atual
cat /sys/block/nvme0n1/queue/scheduler

# Alterando para 'none'
echo "none" > /sys/block/nvme0n1/queue/scheduler

# Aumentando a fila para melhorar paralelismo
echo 1024 > /sys/block/nvme0n1/queue/nr_requests

# Reduzindo read-ahead para workloads aleatórios
echo 64 > /sys/block/nvme0n1/queue/read_ahead_kb
```

### Servidor de Streaming em HDD:

```bash
# Alterando para 'bfq'
echo "bfq" > /sys/block/sda/queue/scheduler

# Aumentando read-ahead para leitura sequencial
echo 4096 > /sys/block/sda/queue/read_ahead_kb

# Habilitando mesclagem para reduzir operações
echo 0 > /sys/block/sda/queue/nomerges
```

## Referências

1. Jens Axboe, "Linux Block IO: Present and Future", Proceedings of the Linux Symposium, 2004.

2. Paolo Valente, et al., "BFQ I/O Scheduler", https://www.kernel.org/doc/html/latest/block/bfq-iosched.html

3. Adrian Huang, "Selecting the right I/O scheduler for SSDs on database workloads", 2019, Oracle Technology Network.

4. Matias Bjørling, et al., "Linux block IO: introducing multi-queue SSD access on multi-core systems", SYSTOR '13, 2013.

5. Brendan Gregg, "Linux Storage I/O Performance", 2017, http://www.brendangregg.com/linuxio.html

6. Keith Busch, "NVMe Driver and I/O Subsystem Performance", Intel Developer Forum, 2016.

7. Red Hat Documentation, "Performance Tuning Guide - Storage and File Systems", Red Hat Enterprise Linux 8, https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/monitoring_and_managing_system_status_and_performance/setting-the-disk-scheduler_monitoring-and-managing-system-status-and-performance

8. PostgreSQL Wiki, "I/O Tuning", https://wiki.postgresql.org/wiki/Performance_Optimization

9. Kun Gao, et al., "Are Current I/O Schedulers Suitable for SSDs?", IEEE 28th International Performance Computing and Communications Conference, 2009.

10. Ted Ts'o, "Random I/O operations per second on an SSD with Different I/O Schedulers", https://ext4.wiki.kernel.org/index.php/Main_Page