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
