# PBL-SD-HRM
# Coprocessador-de-Imagem

## Sumário

- [Introdução e Definição do Problema](#introdução-e-definição-do-problema)
- [Requisitos Principais](#requisitos-principais)
- [Fundamentação Teórica](#fundamentação-teórica)
- [Descrição da Solução](#descrição-da-solução)
  - [Arquitetura do Co-processador](#arquitetura-do-co-processador)
  - [Fluxo de Dados](#fluxo-de-dados)
- [Modo de Uso](#modo-de-uso-utilizando-o-coprocessador)
- [Explicação dos Testes](#explicação-dos-testes)
- [Conclusão](#conclusão)

## Introdução e Definição do Problema

O presente projeto consiste no desenvolvimento de um classificador de imagens de dígitos numéricos embarcado em um SoC (System on Chip) heterogêneo, composto por um processador ARM e uma FPGA, utilizando a plataforma DE1-SoC como ambiente de implementação.

O sistema a ser construído tem como núcleo central um co-processador descrito em Verilog, com conjunto de instruções próprio (ISA), responsável por executar a inferência de uma rede neural baseada em Extreme Learning Machine (ELM) diretamente no hardware programável da FPGA. Essa abordagem permite explorar o paralelismo inerente à lógica reconfigurável para acelerar o processo de classificação, descarregando do processador de propósito geral a tarefa computacionalmente intensiva da inferência.

A motivação central do projeto é conectar os fundamentos teóricos de Arquitetura de Computadores — datapath, controle, paralelismo, hierarquia de memórias e I/O mapeado em memória — com a prática real de desenvolvimento de sistemas digitais de propósito específico, evidenciando os desafios técnicos envolvidos na construção de aceleradores de hardware em ambientes heterogêneos.


## Requisitos Principais 

### Entrada e Saída

O sistema recebe como entrada uma imagem em escala de cinza de 28×28 pixels,
com 8 bits por pixel, no formato PNG (784 bytes). Cada imagem representa
exatamente um dígito numérico no intervalo [0–9]. A saída correspondente é um
único valor inteiro `pred`, também no intervalo [0–9], indicando o dígito
classificado pela rede.

### Co-processador — Núcleo ELM (Marco 1)

O núcleo implementado em Verilog deve realizar a inferência completa da rede
ELM com pesos previamente fornecidos, seguindo uma arquitetura sequencial.
Os componentes obrigatórios são:

- **FSM de controle:** responsável por orquestrar as etapas do fluxo de inferência
- **Datapath MAC:** unidade de multiplicação e acumulação para o cômputo das operações matriciais
- **Função de ativação aproximada:** implementada via LUT ou aproximação piecewise linear
- **Argmax final:** seleciona a classe com maior valor de saída
- **Memórias e banco de registradores:** para armazenamento intermediário de dados e resultados

Todos os valores são representados em ponto fixo no formato **Q4.12**. Os pesos
da rede (`W_in`, `b` e `β`) devem ser armazenados em blocos de memória
dedicados, com uma estratégia clara e documentada de organização e acesso.


## Fundamentação Teórica

### Representação Digital da Imagem

As imagens utilizadas neste projeto seguem o padrão do conjunto MNIST: imagens
em escala de cinza de 28×28 pixels, onde cada pixel é representado por 8 bits,
resultando em valores no intervalo [0, 255]. Para fins de processamento pela rede
neural, a matriz bidimensional é linearizada em um vetor unidimensional `x` de
784 elementos, que serve diretamente como entrada para o co-processador.

Antes de alimentar a rede, os valores dos pixels são normalizados para o intervalo
[0, 1], dividindo cada elemento por 255. Essa normalização é essencial para garantir
compatibilidade com os pesos treinados e estabilidade numérica durante as operações
de ponto fixo.

---

### A Rede Neural ELM

#### Conceito e Motivação

A Extreme Learning Machine (ELM) é uma arquitetura de rede neural rasa (shallow),
composta por uma única camada oculta, cujos pesos de entrada (`W_in`) e biases
(`b`) são inicializados aleatoriamente e **não são ajustados durante o treinamento**.
Apenas os pesos da camada de saída (`β`) são determinados analiticamente, via
pseudoinversa. Essa característica elimina o processo iterativo de backpropagation,
tornando o modelo determinístico e com custo computacional fixo na inferência.

Para implementação em hardware, isso representa uma vantagem fundamental: todos
os parâmetros do modelo são conhecidos em tempo de síntese e podem ser gravados
diretamente em memórias ROM na FPGA, sem necessidade de qualquer mecanismo
de atualização de pesos em runtime.

#### Estrutura da Rede

A rede possui a seguinte topologia:

| Camada       | Tamanho       | Operação                        |
|--------------|---------------|---------------------------------|
| Entrada      | 784 neurônios | Vetor de pixels normalizados    |
| Oculta       | 128 neurônios | `h = activation(W_in · x + b)` |
| Saída        | 10 neurônios  | `y = β · h`                     |
| Predição     | 1 valor       | `pred = argmax(y)`              |

#### Fluxo de Inferência

O processo completo de inferência é dividido em quatro estágios sequenciais:

**Estágio 1 — Leitura da entrada:**
O vetor `x ∈ ℝ^784` é carregado na memória de entrada do co-processador,
representando os 784 pixels da imagem normalizada.

**Estágio 2 — Camada oculta:**
Para cada neurônio `j` da camada oculta (j = 0..127), calcula-se:

```
z_j = Σ (W_in[j][i] · x[i]) + b[j],   para i = 0..783
h_j = activation(z_j)
```

Essa operação envolve 784 multiplicações e acumulações por neurônio, totalizando
**128 × 784 = 100.352 operações MAC** apenas nesta camada.

**Estágio 3 — Camada de saída:**
Para cada neurônio `k` da camada de saída (k = 0..9), calcula-se:

```
y_k = Σ (β[k][j] · h[j]),   para j = 0..127
```

Essa etapa envolve **10 × 128 = 1.280 operações MAC**.

**Estágio 4 — Predição:**
O resultado final é obtido pela função argmax sobre o vetor `y`:

```
pred = argmax(y) = índice k tal que y_k é máximo,   k ∈ [0, 9]
```

---

### Operação MAC e Custo Computacional

A operação central da inferência é o **MAC (Multiply-Accumulate)**:

```
acumulador = acumulador + (a · b)
```

Em uma implementação puramente sequencial, com um único MAC por ciclo de clock,
o número total de ciclos para uma inferência completa é:

```
Ciclos_MAC = (784 × 128) + (128 × 10) = 100.352 + 1.280 = 101.632 ciclos
```

Esse número justifica tanto a necessidade de um co-processador dedicado quanto
a possibilidade de aceleração por paralelismo — replicando N unidades MAC, o
tempo de inferência cai por um fator N.

---

### Aritmética de Ponto Fixo — Formato Q4.12

Por operar sem unidade de ponto flutuante, o co-processador representa todos os
valores internos no formato de ponto fixo **Q4.12**, conforme especificado:

```
[ 1 bit sinal | 4 bits inteiros | 12 bits fracionários ] = 16 bits total
```

#### Interpretação dos valores

Um número Q4.12 representa o valor real:

```
valor_real = bits_inteiros + (bits_fracionários / 2^12)
           = bits_inteiros + (bits_fracionários / 4096)
```

**Exemplos:**

| Binário (16 bits)    | Valor Real     |
|----------------------|----------------|
| `0001_000000000000`  | +1.0           |
| `0000_100000000000`  | +0.5           |
| `1111_000000000000`  | -1.0 (complemento de 2) |
| `0111_111111111111`  | ≈ +7.9997 (máximo positivo) |

#### Multiplicação em Q4.12

Ao multiplicar dois valores Q4.12, o resultado intermediário possui **32 bits**
no formato Q8.24. Para retornar ao formato Q4.12, é necessário um **shift aritmético
de 12 bits à direita**, descartando os bits menos significativos:

```
resultado_Q4.12 = (a_Q4.12 × b_Q4.12) >>> 12
```

#### Overflow e Saturação

O intervalo representável em Q4.12 com sinal é aproximadamente [-8.0, +7.9997].
Operações de acumulação repetida (como no MAC) podem extrapolar esse intervalo.
A estratégia de **saturação** consiste em fixar o resultado no valor máximo ou
mínimo representável quando ocorre overflow, evitando inversão de sinal e
degradação severa da saída.

---

### Função de Ativação

A função de ativação é aplicada elemento a elemento sobre os resultados da camada
oculta após a operação MAC. Duas abordagens são viáveis para implementação em
hardware:

#### ReLU (Rectified Linear Unit)

```
ReLU(x) = max(0, x)
```

Implementação trivial em hardware: basta verificar o bit de sinal do valor Q4.12.
Se negativo, a saída é zero; se positivo, a saída é o próprio valor. Custo: um
multiplexador de 16 bits.

#### Piecewise Linear (Aproximação de tanh)

Para redes treinadas com `tanh`, uma aproximação linear por partes pode ser usada:

```
f(x) = -1,           se x < -2
       x/2,          se -2 ≤ x < 0
       x/2,          se 0 ≤ x < 2
       +1,           se x ≥ 2
```

Divisões por 2 em ponto fixo são implementadas como **shift de 1 bit**, sem
necessidade de divisor. O custo total é um comparador e dois multiplexadores.

> **Nota:** a função de ativação efetivamente utilizada neste projeto será
> definida com base nos pesos fornecidos e detalhada na seção de Descrição
> da Solução.

---

### Arquitetura Sequencial com FSM em FPGA

Uma FSM (Finite State Machine) de controle é o mecanismo padrão para orquestrar
operações sequenciais em hardware digital. No contexto deste co-processador, a
FSM é responsável por coordenar cada etapa do fluxo de inferência, controlando
os sinais de leitura/escrita das memórias, habilitação do MAC e progressão entre
estágios.

A arquitetura sequencial — onde um único MAC processa um elemento por ciclo —
é a abordagem mais simples e de menor custo em área, sendo o ponto de partida
natural antes de qualquer otimização por paralelismo.

Os estados típicos de uma FSM para este problema são:

| Estado     | Descrição                                          |
|------------|----------------------------------------------------|
| `IDLE`     | Aguarda sinal de início                            |
| `LOAD`     | Carrega pixel/dado da memória de entrada           |
| `COMPUTE`  | Executa operação MAC                               |
| `ACTIVATE` | Aplica função de ativação ao resultado acumulado   |
| `STORE`    | Armazena resultado intermediário na memória        |
| `DONE`     | Sinaliza conclusão e disponibiliza resultado       |



## Descrição da Solução

### Arquitetura Geral do Sistema

O sistema é organizado em uma hierarquia de módulos com responsabilidades
bem definidas, sintetizados sobre a plataforma DE1-SoC (FPGA Cyclone V —
EP4CGX150). O módulo `top_level` é a raiz do projeto e concentra três
responsabilidades: instanciar todos os submódulos, gerenciar o acesso
compartilhado às memórias por meio de multiplexadores de prioridade, e
expor os pinos físicos da placa.

```
top_level
├── pbl
│   ├── pbl_ctrl        (decodificação de instruções e controle de carregamento)
│   └── pbl_infer       (núcleo de inferência — FSM principal)
│       ├── mac_q412    (multiplicador-acumulador combinacional, x2 instâncias)
│       ├── tanh_lut    (função de ativação aproximada por partes)
│       └── argmax10    (seleção combinacional da classe com maior valor)
├── hex7seg             (decodificador para displays de 7 segmentos)
├── Bias  (RAM M10K — 128  × 16 bits — bias b)
├── Pesos (RAM M10K — 100.352 × 16 bits — pesos W_in)
├── Beta  (RAM M10K — 1.280 × 16 bits — pesos β)
└── IMG   (RAM M10K — 784  × 16 bits — imagem de entrada)
```

O módulo `pbl` atua como invólucro hierárquico: não possui lógica própria,
conectando o `pbl_ctrl` ao `pbl_infer` por meio de três sinais internos
(`start`, `infer_done`, `infer_error`), expondo uma interface unificada ao
`top_level`.

---

### 1. Correção Funcional

#### Fluxo Completo de Inferência

O sistema implementa os quatro estágios do modelo ELM de forma sequencial
e determinística:

**Estágio 1 — Carregamento da imagem:**
Os 784 pixels da imagem são escritos na RAM `IMG` via instruções do
`pbl_ctrl`, um pixel por ciclo de clock.

**Estágio 2 — Camada oculta:**
Para cada neurônio `j` (j = 0..127), o núcleo calcula:

```
z_j = Σ (W_in[j][i] × x[i]) + b[j],   i = 0..783
h_j = tanh(z_j)
```

**Estágio 3 — Camada de saída:**
Para cada classe `k` (k = 0..9), o núcleo calcula:

```
y_k = Σ (β[k][j] × h[j]),   j = 0..127
```

**Estágio 4 — Predição:**
```
pred = argmax(y),   pred ∈ [0, 9]
```

#### Validação

A correção funcional do sistema foi verificada por simulação no Questa,
utilizando vetores de teste derivados do conjunto MNIST. O resultado `pred`
foi comparado contra um modelo de referência (*golden model*) executado em
software em precisão de ponto flutuante de 64 bits. Os testes confirmaram
acurácia funcional superior a 90% dos vetores de entrada, com exceção de
algumas amostras do dígito 5 cujas margens de decisão são reduzidas no
modelo ELM com H=128 — comportamento idêntico ao observado em software,
confirmando que não se trata de erro de hardware.

> **Entrega:** código Verilog comentado disponível no repositório.
> Diagrama FSM disponível na seção seguinte.

---

### 2. Arquitetura do Datapath

#### FSM de Controle

A FSM principal, implementada no módulo `pbl_infer`, possui **16 fases**
que orquestram todas as etapas da inferência. As fases de espera absorvem
a latência de 1 ciclo das memórias síncronas M10K — o endereço é
apresentado em um ciclo e o dado fica disponível apenas no ciclo seguinte.

```
                    ┌─────────────────────────────────────────────┐
                    │                                             │
              ┌─────▼──────┐                                     │
   reset ────►│   OCIOSO   │◄── done                             │
              └─────┬──────┘                                     │
                start│                                           │
              ┌─────▼──────┐                                     │
              │   LIMPAR   │ (128 ciclos — zera h_mem e y_mem)   │
              └─────┬──────┘                                     │
                    │                                            │
         ┌──────────▼───────────┐                               │
         │      END_OCULTA      │◄──────────────────────┐       │
         └──────────┬───────────┘                       │       │
                    │                                   │       │
         ┌──────────▼───────────┐                       │       │
         │     ESPERA_OC_0      │                       │       │
         └──────────┬───────────┘                       │       │
         ┌──────────▼───────────┐                       │       │
         │     ESPERA_OC_1      │                       │       │
         └──────────┬───────────┘                       │       │
         ┌──────────▼───────────┐   in_idx < 783        │       │
         │      MAC_OCULTA      │───────────────────────┘       │
         └──────────┬───────────┘                               │
              in_idx == 783                                      │
         ┌──────────▼───────────┐                               │
         │      BIAS_OCULTA     │                               │
         └──────────┬───────────┘                               │
         ┌──────────▼───────────┐                               │
         │    ESPERA_BIAS_0     │                               │
         └──────────┬───────────┘                               │
         ┌──────────▼───────────┐                               │
         │    ESPERA_BIAS_1     │                               │
         └──────────┬───────────┘                               │
         ┌──────────▼───────────┐                               │
         │         TANH         │ (registra z = acc + b[j])     │
         └──────────┬───────────┘                               │
         ┌──────────▼───────────┐   hid_idx < 127               │
         │      TANH_LATCH      │───(volta END_OCULTA)──────────┘
         └──────────┬───────────┘
              hid_idx == 127
         ┌──────────▼───────────┐
         │      END_SAIDA       │◄──────────────────────┐
         └──────────┬───────────┘                       │
         ┌──────────▼───────────┐                       │
         │      ESPERA_SA_0     │                       │
         └──────────┬───────────┘                       │
         ┌──────────▼───────────┐                       │
         │      ESPERA_SA_1     │                       │
         └──────────┬───────────┘                       │
         ┌──────────▼───────────┐   hid_idx < 127       │
         │      MAC_SAIDA       │───────────────────────┘
         └──────────┬───────────┘
              hid_idx == 127 para cada cls_idx
         ┌──────────▼───────────┐
         │        ARGMAX        │──► done=1, pred válido
         └──────────────────────┘
```

| Fase              | Descrição                                                       |
|-------------------|-----------------------------------------------------------------|
| `OCIOSO`          | Aguarda pulso de `start`                                        |
| `LIMPAR`          | Zera `h_mem` e `y_mem` posição a posição — 128 ciclos           |
| `END_OCULTA`      | Configura endereços da RAM IMG e Pesos                          |
| `ESPERA_OC_0/1`   | Absorve latência de 2 ciclos da RAM síncrona                    |
| `MAC_OCULTA`      | Acumula `img[i] × W_in[j][i]`, avança `in_idx`                 |
| `BIAS_OCULTA`     | Configura endereço do bias `b[j]`                               |
| `ESPERA_BIAS_0/1` | Absorve latência de 2 ciclos da ROM de bias                     |
| `TANH`            | Registra `z = acc + b[j]`                                       |
| `TANH_LATCH`      | Captura saída da `tanh_lut` em `h_mem[j]`, zera acumulador      |
| `END_SAIDA`       | Configura endereço de Beta para o par `(cls, hid)` atual        |
| `ESPERA_SA_0/1`   | Absorve latência de 2 ciclos da RAM Beta                        |
| `MAC_SAIDA`       | Acumula `h[j] × β[k][j]`, avança `hid_idx`                     |
| `ARGMAX`          | Lê resultado combinacional do `argmax10`, pulsa `done`          |

#### Datapath MAC

O módulo `mac_q412` implementa a operação de multiplicação-acumulação em
ponto fixo Q4.12 de forma puramente combinacional:

```verilog
assign product_full   = $signed(a) * $signed(b);  // 32 bits (Q8.24)
assign product_scaled = product_full >>> Q_FRAC;   // shift 12 → Q4.12
```

O produto de dois valores Q4.12 gera um resultado de 32 bits no formato
Q8.24. O shift aritmético de 12 posições à direita retorna o resultado ao
formato Q4.12 preservando o sinal. Dois módulos `mac_q412` são instanciados
no `pbl_infer`: `u_mac_hidden` para a camada oculta e `u_mac_output` para
a camada de saída.

#### Função de Ativação

A função de ativação implementada é uma aproximação piecewise linear da
`tanh(x)`, exploitando sua simetria (`tanh(−x) = −tanh(x)`) para operar
apenas sobre o valor absoluto e aplicar o sinal ao final.

Antes de entrar na `tanh_lut`, o acumulador de 32 bits é saturado para
16 bits pela função `sat32_to_q16`: valores acima de +32767 são fixados
em +32767 e abaixo de −32768 em −32768, prevenindo corrupção da entrada.

A curva é aproximada em 6 segmentos lineares:

| Segmento | Intervalo (real) | Y base (Q4.12) | Inclinação (Q4.12) |
|----------|------------------|----------------|---------------------|
| 0        | [0.0, 0.5)       | 0              | 3786 (≈ 0.924)      |
| 1        | [0.5, 1.0)       | 1893 (≈ 0.462) | 2460 (≈ 0.600)      |
| 2        | [1.0, 1.5)       | 3122 (≈ 0.762) | 1172 (≈ 0.286)      |
| 3        | [1.5, 2.0)       | 3708 (≈ 0.905) | 483  (≈ 0.118)      |
| 4        | [2.0, 3.0)       | 3949 (≈ 0.964) | 128  (≈ 0.031)      |
| ≥ 3.0    | saturado         | —              | saída = ±4095       |

> **Entrega:** código Verilog comentado no repositório.
> Diagrama FSM disponível acima.

---

### 3. Paralelismo dos MACs

A arquitetura implementada instancia **dois módulos `mac_q412` em paralelo**
no `pbl_infer`: `u_mac_hidden` e `u_mac_output`. Ambos são combinacionais
e operam simultaneamente a cada ciclo de clock — enquanto a camada oculta
utiliza `u_mac_hidden`, o `u_mac_output` está disponível para a camada de
saída sem latência adicional de configuração.

A FSM controla qual MAC é efetivamente lido em cada fase, garantindo que a
transição entre camadas ocorra sem ciclos de stall adicionais.

**Comparação de ciclos — serial vs. paralelo:**

| Configuração          | MACs simultâneos | Ciclos estimados |
|-----------------------|------------------|-----------------|
| 1 MAC serial          | 1                | ≈ 406.558       |
| 2 MACs (implementado) | 2 (por camada)   | ≈ 406.558 *     |
| N MACs paralelos      | N                | ≈ 406.558 / N   |

> *Com 2 MACs em fases distintas (oculta e saída), o ganho em ciclos totais
> é marginal pois as fases não se sobrepõem. Para throughput >1 MAC/ciclo
> dentro da mesma fase seria necessário replicar MACs e ajustar a FSM com
> contadores paralelos — extensão prevista para trabalhos futuros.

> **Entrega:** simulação com `cycles_out` disponível via In-System Sources
> and Probes no Quartus após síntese.

---

### 4. Interface MMIO — Banco de Registradores

O `pbl_ctrl` implementa um conjunto de instruções mapeado em registradores,
operado por meio de botões e chaves da DE1-SoC. Cada instrução é codificada
nos switches SW e executada com um pulso no botão, com detecção de borda de
descida para evitar múltiplos disparos por bounce mecânico.

**Mapa de registradores:**

| Registrador | Opcode | Bits do campo                  | Tipo | Operação                     |
|-------------|--------|-------------------------------|------|------------------------------|
| CTRL_IMG    | 0x1    | [27:18]=addr (10b), [15:0]=pixel | W  | Escreve pixel na RAM IMG     |
| CTRL_WIN    | 0x2    | [27:11]=addr (17b), [15:0]=Q4.12 | W  | Escreve peso W_in na RAM     |
| CTRL_BIAS   | 0x3    | [22:16]=addr (7b),  [15:0]=Q4.12 | W  | Escreve bias na RAM Bias     |
| CTRL_START  | 0x4    | —                              | W    | Dispara inferência           |
| STATUS      | 0x5    | [1:0]=estado, [5:2]=pred       | R    | Lê estado e predição atual   |

**Handshake start → busy → done:**

```
SW = opcode CTRL_START → pulso no botão
              ↓
    pbl_ctrl executa instrução
              ↓
    inferencia_ativa = 1 → STATUS = BUSY → led_busy = 1
              ↓
    pbl_infer percorre 16 fases (~406k ciclos)
              ↓
    done = 1 (1 ciclo) → STATUS = DONE → led_done = 1
              ↓
    pred válido em HEX0 — cycles_out congelado com latência
```

O `pbl_ctrl` verifica o sinal `infer_done` retornado pelo `pbl_infer` para
transitar do estado BUSY para DONE, garantindo que nenhuma nova instrução
de carregamento seja aceita enquanto a inferência está em andamento.

> **Entrega:** tabela acima + testbench com verificação de escrita/leitura
> via simulação disponível no repositório.

---

### 5. Ciclo de Instrução

#### Protocolo Start-Execute-Done

O protocolo de operação do co-processador segue três fases determinísticas:

**Start:** a instrução `CTRL_START` (opcode 0x4) é enviada ao `pbl_ctrl`.
Este levanta o sinal `start` por 1 ciclo, que é capturado pelo `pbl_infer`
na fase `OCIOSO`, iniciando a execução. Simultaneamente, `inferencia_ativa`
sobe, bloqueando qualquer acesso externo às RAMs.

**Execute:** a FSM percorre sequencialmente todas as 16 fases. O registrador
`cycles_out` é incrementado a cada ciclo de clock durante toda a execução,
fornecendo medição precisa da latência.

**Done:** ao atingir a fase `ARGMAX`, o `pbl_infer` pulsa `done = 1` por 1
ciclo, registra `pred` com o índice da classe vencedora e retorna à fase
`OCIOSO`. O `pbl_ctrl` captura `infer_done` e transita para o estado DONE,
acendendo `led_done` e disponibilizando o resultado no display `HEX0`.

#### Latência Determinística

Cada acesso à RAM síncrona M10K consome 2 ciclos de espera mais 1 ciclo
de MAC, totalizando 3 ciclos de overhead por operação de leitura. A
latência analítica por componente é:

| Componente                              | Ciclos estimados |
|-----------------------------------------|-----------------|
| Limpeza de buffers (`LIMPAR`)           | 128             |
| Camada oculta: 128 × (784 × 3 + 5)     | ≈ 301.120       |
| Camada de saída: 10 × (128 × 3 + 3)    | ≈ 3.870         |
| **Total estimado**                      | **≈ 305.118**   |

A 50 MHz (período de 20 ns):

```
Latência ≈ 305.118 × 20 ns ≈ 6,1 ms por inferência
```

O valor exato é medido pelo sinal `cycles_out[31:0]`, acessível via
**In-System Sources and Probes** no Quartus após programação da placa.

#### Reset

O reset é assíncrono e ativo em nível alto internamente. Como os botões da
DE1-SoC são ativos em nível baixo, o `top_level` realiza a inversão
`~reset` na instância do `pbl`. Ao ser ativado, o reset limpa todos os
registradores da FSM (`phase`, `acc`, `hid_idx`, `in_idx`, `cls_idx`),
os buffers internos `h_mem` e `y_mem`, e os sinais de saída (`done`,
`error`, `pred`), retornando o sistema ao estado `OCIOSO` de forma
imediata, independente do ciclo de clock.

---

### 6. Uso de Recursos

O projeto foi sintetizado para o dispositivo **EP4CGX150** (Cyclone V GX)
presente na plataforma DE1-SoC, utilizando o Quartus Prime 25.1.

> **📸 Screenshot do relatório de síntese (Compilation Report →
> Flow Summary) deve ser inserido aqui.**

**Estimativa analítica dos recursos:**

| Recurso | Estimativa       | Limite (EP4CGX150) | Justificativa                            |
|---------|------------------|--------------------|------------------------------------------|
| LUT     | < 5.000          | 20.000             | FSM + muxes + lógica de controle         |
| FF      | < 3.000          | 20.000             | Registradores da FSM + h_mem (128×16b)   |
| DSP     | 2                | 50                 | Um por instância de `mac_q412`           |
| BRAM    | ≈ 52 blocos M10K | 100                | 4 RAMs — Pesos domina com ~13 blocos     |

O recurso de maior impacto é a RAM `Pesos` com 100.352 palavras de 16 bits
(≈ 1,6 MB), que demanda a maior parte dos blocos M10K disponíveis. Os dois
módulos `mac_q412` são implementados sobre os DSPs dedicados do Cyclone V,
evitando o uso de LUTs para a multiplicação.

**Frequência máxima:**

> **📸 Screenshot do TimeQuest Timing Analyzer (Fmax Summary) deve ser
> inserido aqui.**

O caminho crítico estimado está na cadeia de comparadores da `tanh_lut`
e no caminho combinacional do `mac_q412`. A frequência alvo é 50 MHz
(clock padrão da DE1-SoC), e espera-se que o projeto feche timing com
margem positiva dado o baixo número de níveis lógicos nos caminhos críticos.

---

### Interface de Saída — Display 7 Segmentos

O módulo `hex7seg` controla seis displays de 7 segmentos da DE1-SoC.
`HEX0` permanece apagado enquanto `led_done = 0`, evitando exibição
espúria do valor `pred = 0` durante o reset ou antes da primeira
inferência. Após a conclusão, `HEX0` exibe o dígito predito (0–9) e
`HEX5` exibe o estado atual do sistema com a seguinte prioridade:

| Símbolo | Estado     | Condição           |
|---------|------------|--------------------|
| `e`     | Erro       | `led_error = 1`    |
| `d`     | Concluído  | `led_done  = 1`    |
| `b`     | Ocupado    | `led_busy  = 1`    |
| `r`     | Pronto     | `led_ready = 1`    |
| —       | Apagado    | Nenhum sinal ativo |
