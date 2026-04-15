# Coprocessador ELM — Classificador de Dígitos em FPGA

Classificador de imagens de dígitos (0–9) implementado como co-processador em hardware na plataforma **DE1-SoC (Cyclone V EP4CGX150)**. O núcleo executa a inferência completa de uma rede ELM (*Extreme Learning Machine*) em lógica programável, com todos os pesos fixados em memória e aritmética em ponto fixo Q4.12.

---

## Sumário

- [O que o projeto faz](#o-que-o-projeto-faz)
- [Fundamentação Teórica](#fundamentação-teórica)
  - [A rede ELM](#a-rede-elm)
  - [Por que FPGA?](#por-que-fpga)
  - [Ponto fixo Q4.12](#ponto-fixo-q412)
  - [A operação MAC](#a-operação-mac)
  - [A função de ativação tanh](#a-função-de-ativação-tanh)
- [Requisitos do Marco 1](#requisitos-do-marco-1)
- [Arquitetura do Sistema](#arquitetura-do-sistema)
  - [Hierarquia de módulos](#hierarquia-de-módulos)
  - [As memórias](#as-memórias)
  - [O mux das RAMs](#o-mux-das-rams)
  - [A FSM de inferência](#a-fsm-de-inferência)
  - [O MAC em Q4.12](#o-mac-em-q412)
  - [A tanh por partes](#a-tanh-por-partes)
  - [O argmax](#o-argmax)
  - [O pbl_ctrl e a ISA](#o-pbl_ctrl-e-a-isa)
  - [O display 7 segmentos](#o-display-7-segmentos)
- [Interface MMIO e Ciclo de Instrução](#interface-mmio-e-ciclo-de-instrução)
- [Paralelismo dos MACs](#paralelismo-dos-macs)
- [Latência e Uso de Recursos](#latência-e-uso-de-recursos)
- [Como usar na placa](#como-usar-na-placa)
- [Testes e Resultados](#testes-e-resultados)
- [Conclusão](#conclusão)

---

## O que o projeto faz

Você carrega uma imagem 28×28 em escala de cinza na FPGA. O co-processador classifica o dígito e exibe o resultado (0–9) no display HEX0 da placa. O tempo de inferência é de aproximadamente **6 ms a 50 MHz**.

O fluxo completo é:

```
Imagem 28×28 (784 pixels, 8 bits cada)
    ↓
Normalização implícita nos pesos (Q4.12)
    ↓
Camada oculta: h = tanh(W_in · x + b)   [128 neurônios, 100.352 MACs]
    ↓
Camada de saída: y = β · h              [10 neurônios, 1.280 MACs]
    ↓
pred = argmax(y)                         [retorna 0..9]
    ↓
HEX0 exibe o dígito
```

---

## Fundamentação Teórica

### A rede ELM

A ELM (*Extreme Learning Machine*) é uma rede de camada oculta única com uma propriedade muito útil para hardware: **os pesos de entrada são fixos**, gerados aleatoriamente e nunca atualizados. Só os pesos da camada de saída (β) são treinados, via pseudoinversa. Isso elimina backpropagation completamente.

Na prática para o hardware, isso significa que W_in, b e β são conhecidos antes da síntese e podem ser gravados diretamente em blocos de memória ROM. Não existe nenhum circuito de aprendizado — só inferência.

A topologia usada:

| Camada  | Tamanho | Operação |
|---------|---------|----------|
| Entrada | 784     | pixels normalizados (imagem 28×28) |
| Oculta  | 128     | `h = tanh(W_in · x + b)` |
| Saída   | 10      | `y = β · h` |
| Predição| 1       | `pred = argmax(y)` |

### Por que FPGA?

Um processador de propósito geral executa as operações MAC em sequência, uma por uma. A FPGA permite criar uma unidade MAC dedicada que opera a cada ciclo de clock, com acesso direto às memórias de pesos sem overhead de cache ou sistema operacional.

Além disso, os pesos são fixos — caber em ROM é perfeito para blocos M10K da Cyclone V, que existem em quantidade na EP4CGX150.

### Ponto fixo Q4.12

Sem FPU, todos os valores internos usam o formato **Q4.12**:

```
[ sinal (1 bit) | inteiros (4 bits) | fracionários (12 bits) ] = 16 bits
```

Para converter um número real para Q4.12: multiplica por 4096 (= 2¹²) e trunca para inteiro.

```
 1.0  →  1 × 4096 =  4096  =  0x1000
 0.5  →  0.5 × 4096 = 2048 =  0x0800
-1.0  → -1 × 4096 = -4096  =  0xF000  (complemento de 2)
```

O intervalo representável é **[-8.0, +7.9997]**, com resolução de ~0.000244.

**O problema da multiplicação:** multiplicar dois Q4.12 dá um resultado Q8.24 (32 bits). Para voltar ao Q4.12, basta um shift aritmético de 12 à direita:

```
produto_Q4.12 = (a × b) >>> 12
```

Exemplo: `0.5 × (-0.25)` em Q4.12:
```
a = 2048, b = -1024
produto = 2048 × (-1024) = -2.097.152
escalonado = -2.097.152 >>> 12 = -512
valor real = -512 / 4096 = -0.125  ✓
```

O acumulador usa **32 bits** para evitar overflow durante as 784 somas consecutivas. Antes de entrar na função de ativação, o acumulador é saturado de volta para 16 bits pela função `sat32_to_q16`.

### A operação MAC

MAC = *Multiply-Accumulate*:

```
acumulador += a × b
```

É a operação dominante da rede. Por inferência completa:

- Camada oculta: 128 × 784 = **100.352 MACs**
- Camada de saída: 10 × 128 = **1.280 MACs**
- Total: **101.632 MACs**

Com 1 MAC por ciclo de clock em arquitetura serial, isso dá a ordem de grandeza da latência total.

### A função de ativação tanh

A `tanh(x)` não pode ser calculada diretamente em hardware porque envolve exponenciais. A solução é uma **aproximação linear por partes**: divide a curva em segmentos e usa uma reta diferente em cada trecho.

O módulo `tanh_lut` explora a simetria `tanh(-x) = -tanh(x)` — calcula só para valores positivos e aplica o sinal no final. Isso reduz o número de segmentos pela metade.

São 5 segmentos + saturação:

| Intervalo (|x|) | Y base (Q4.12) | Inclinação (Q4.12) |
|----------------|----------------|---------------------|
| [0.0, 0.5)     | 0              | 3786 ≈ 0.924        |
| [0.5, 1.0)     | 1893 ≈ 0.462   | 2460 ≈ 0.600        |
| [1.0, 1.5)     | 3122 ≈ 0.762   | 1172 ≈ 0.286        |
| [1.5, 2.0)     | 3708 ≈ 0.905   | 483 ≈ 0.118         |
| [2.0, 3.0)     | 3949 ≈ 0.964   | 128 ≈ 0.031         |
| ≥ 3.0          | saturado       | saída = ±4095       |

A interpolação dentro de cada segmento:
```
y_abs = y_base + slope × (|x| - x_base)   // produto com shift de 12
y_out = x_negativo ? -y_abs : y_abs
```

---

## Requisitos do Marco 1

Entrada e saída do sistema:

- **Entrada:** imagem PNG 28×28 pixels, escala de cinza, 8 bits/pixel (784 bytes)
- **Saída:** inteiro `pred` no intervalo [0, 9]

Componentes obrigatórios do núcleo:

- FSM de controle com estados bem definidos
- Datapath MAC com multiplicador e acumulador
- Função de ativação aproximada (LUT ou piecewise linear)
- Argmax sobre os 10 valores de saída
- Memórias para W_in, b e β com estratégia clara de endereçamento
- Representação em ponto fixo Q4.12

---

## Arquitetura do Sistema

### Hierarquia de módulos

```
top_level
├── pbl
│   ├── pbl_ctrl    ← decodifica SW/BTN, gera led_*, disp_*, inferencia_ativa
│   └── pbl_infer   ← FSM de 16 fases, executa os cálculos
│       ├── mac_q412    (x2: u_mac_hidden e u_mac_output)
│       ├── tanh_lut    (ativação piecewise linear)
│       └── argmax10    (9 comparadores combinacionais)
├── hex7seg         ← HEX0 (dígito) e HEX5 (estado)
├── Bias   ← RAM M10K, 128×16 bits,    bias b,   arquivo b_q.mif
├── Pesos  ← RAM M10K, 100352×16 bits, W_in,     arquivo W_in_q.mif
├── Beta   ← RAM M10K, 1280×16 bits,   pesos β,  arquivo beta_q.mif
└── IMG    ← RAM M10K, 784×16 bits,    imagem,   carregada em runtime
```

O `pbl` é só um invólucro — sem lógica, apenas conecta `pbl_ctrl` ↔ `pbl_infer` pelos sinais internos `start`, `infer_done` e `infer_error`, e expõe ao `top_level` os sinais `led_*`, `disp_*`, `inferencia_ativa` e `cycles_out[31:0]`.

---

### Como o dado percorre o sistema

Antes de entrar nos detalhes de cada módulo, vale entender o caminho completo de um pixel desde a RAM até o resultado:

```
RAM IMG[i]  →  img_rd_q (16 bits, Q4.12)
                    ↓
              u_mac_hidden.a
RAM Pesos[j×784+i] → w_q (16 bits, Q4.12)
                    ↓
              u_mac_hidden.b
                    ↓
         product_scaled (32 bits, Q4.12 escalado)
                    ↓
         acc += product_scaled  (acumulador 32 bits)
                    ↓  (após 784 iterações)
         acc + b[j]  →  z_hidden (32 bits)
                    ↓
         sat32_to_q16(z_hidden)  →  z_sat (16 bits, Q4.12)
                    ↓
         tanh_lut(z_sat)  →  tanh_out (16 bits, Q4.12)
                    ↓
         h_mem[j] = tanh_out
```

Depois de repetir isso para os 128 neurônios ocultos, o mesmo fluxo acontece para a camada de saída, mas usando `h_mem[j]` e `Beta` em vez de `IMG` e `Pesos`. O resultado final é `y_mem[0..9]`, e o `argmax10` devolve o índice do maior.

---

### As memórias

Todas as quatro RAMs são blocos `altsyncram` (M10K) gerados pelo IP Catalog do Quartus. São memórias síncronas de porta única com saída registrada (`OUTDATA_REG_A = CLOCK0`): **latência de 2 ciclos** entre o endereço e o dado disponível.

```
Ciclo N:    endereço apresentado na porta address
Ciclo N+1:  M10K lê internamente, dado capturado pelo registrador de saída
Ciclo N+2:  dado disponível na porta q
```

Essa latência de 2 ciclos é o motivo pelo qual a FSM tem **duas fases ESPERA** antes de cada fase MAC — sem elas, o dado lido seria do endereço apresentado 2 ciclos antes, não do atual.

| RAM     | Profundidade | Bits | Conteúdo       | Arquivo MIF   |
|---------|-------------|------|----------------|---------------|
| `Pesos` | 100.352     | 16   | W_in (784×128) | `W_in_q.mif`  |
| `Bias`  | 128         | 16   | b (128×1)      | `b_q.mif`     |
| `Beta`  | 1.280       | 16   | β (128×10)     | `beta_q.mif`  |
| `IMG`   | 784         | 16   | Imagem entrada | runtime       |

**Organização da RAM Pesos:** W_in é uma matriz 128×784. Na RAM, ela é linearizada por neurônio — todas as 784 entradas do neurônio 0 ficam nas posições 0–783, as do neurônio 1 nas posições 784–1567, e assim por diante:

```
Posição 0:      W_in[0][0]   ← peso do neurônio 0 para o pixel 0
Posição 1:      W_in[0][1]   ← peso do neurônio 0 para o pixel 1
...
Posição 783:    W_in[0][783] ← peso do neurônio 0 para o pixel 783
Posição 784:    W_in[1][0]   ← peso do neurônio 1 para o pixel 0
...
Posição 100351: W_in[127][783]
```

Para calcular o endereço de `W_in[j][i]` sem um multiplicador dedicado (que gastaria DSP):

```
w_addr = j × 784 + i
       = (j << 9) + (j << 8) + (j << 4) + i
```

Isso funciona porque 784 = 512 + 256 + 16 = 2⁹ + 2⁸ + 2⁴. Três shifts e duas somas — o sintetizador mapeia isso em LUTs simples, sem gastar bloco DSP. O mesmo princípio para Beta (j × 10 = j×8 + j×2):

```
beta_addr = hid_idx × 10 + cls_idx
          = (hid_idx << 3) + (hid_idx << 1) + cls_idx
```

Beta é armazenada com o neurônio oculto como índice principal: as posições 0–9 são os pesos do neurônio 0 para as 10 classes, as posições 10–19 são os pesos do neurônio 1, e assim por diante. 10 = 8 + 2 = 2³ + 2¹, logo dois shifts e uma soma.

---

### O mux das RAMs

As RAMs são single-port: só aceitam um acesso por ciclo. Três entidades podem querer acessar ao mesmo tempo:

- **pbl_infer** — lê durante a inferência
- **pbl_ctrl** — escreve quando o usuário carrega dados via instrução
- **JTAG externo** — acesso direto via In-System Memory Content Editor

O `top_level` resolve com um mux de 3 vias e prioridade fixa para cada uma das quatro RAMs:

```verilog
wire [9:0] img_addr_mux = inferencia_ativa ? pbl_img_rd_addr :
                           ctrl_img_wren   ? ctrl_img_addr   : img_addr;

wire [15:0] img_data_mux = inferencia_ativa ? 16'b0 :
                            ctrl_img_wren   ? ctrl_img_data  : img_data;

wire img_wren_mux = inferencia_ativa ? 1'b0 :
                    ctrl_img_wren    ? 1'b1 : img_wren;
```

Prioridade (da maior para a menor):

1. `inferencia_ativa = 1` — pbl_infer domina, escritas são forçadas a zero (bloqueadas)
2. `ctrl_*_wren = 1` — pbl_ctrl está executando uma instrução de carga
3. Nenhum dos dois — acesso externo via JTAG

O sinal `inferencia_ativa` sobe no ciclo em que `start` é recebido pelo `pbl_infer` e só cai quando `done` é pulsado na fase ARGMAX. Durante toda a inferência, nenhuma escrita nas RAMs é possível — os dados lidos são sempre consistentes.

---

### A FSM de inferência — ciclo a ciclo

O `pbl_infer` tem 16 fases. Para entender por que existe cada uma, é preciso ver o que acontece no nível de ciclo de clock.

**O problema da RAM síncrona com saída registrada:** toda vez que a FSM precisa de um dado da RAM, ela apresenta o endereço em um ciclo e o dado só fica disponível **2 ciclos depois** — 1 ciclo para a M10K ler internamente + 1 ciclo para o registrador de saída capturar. Por isso existem exatamente duas fases ESPERA antes de cada fase MAC.

Veja o timing exato para um acesso à RAM:

```
Ciclo N:   phase = END_OCULTA
           → img_rd_addr <= in_idx
           → w_addr      <= hid_x784 + in_idx

Ciclo N+1: phase = ESPERA_OC_0
           → endereços estabilizaram, RAM lendo internamente
           (nada acontece neste ciclo — só espera)

Ciclo N+2: phase = ESPERA_OC_1
           → dado ainda propagando pela saída registrada da RAM
           (nada acontece neste ciclo — só espera)

Ciclo N+3: phase = MAC_OCULTA
           → img_rd_q e w_q agora têm os valores corretos
           → acc <= acc + mult_hidden_scaled
           → se in_idx < 783: in_idx++, volta para END_OCULTA
           → se in_idx == 783: vai para BIAS_OCULTA
```

O mesmo padrão se repete para o bias e para a camada de saída. Cada leitura de RAM custa 3 ciclos (1 para apresentar + 2 para esperar).

**Fluxo completo da inferência:**

```
OCIOSO
  └─ recebe start=1
       ↓
LIMPAR  [128 ciclos]
  Zera h_mem[0], h_mem[1], ..., h_mem[127]
  Zera y_mem[0], ..., y_mem[9]
  (sem limpeza = resíduos da inferência anterior contaminam os acc)
       ↓
══════════════════════════════════════════
  LOOP EXTERNO: hid_idx = 0 até 127
  (calcula h[j] para cada neurônio oculto)
══════════════════════════════════════════
       ↓
  acc = 0  (zerado em TANH_LATCH do ciclo anterior)

  LOOP INTERNO: in_idx = 0 até 783
  (acumula os 784 produtos para o neurônio hid_idx)

    END_OCULTA    → apresenta img_rd_addr=in_idx, w_addr=j×784+i
    ESPERA_OC_0   → aguarda
    ESPERA_OC_1   → aguarda
    MAC_OCULTA    → acc += img[i] × W_in[j][i]
                    se i<783: i++, volta para END_OCULTA
                    se i==783: vai para BIAS_OCULTA

  BIAS_OCULTA   → apresenta b_addr=hid_idx
  ESPERA_BIAS_0 → aguarda
  ESPERA_BIAS_1 → aguarda
  TANH          → z_hidden = acc + b[j]   (registra para combinacional)
  TANH_LATCH    → h_mem[j] = tanh_lut(sat32_to_q16(z_hidden))
                  acc = 0
                  se j<127: j++, volta para END_OCULTA (próximo neurônio)
                  se j==127: vai para camada de saída
       ↓
══════════════════════════════════════════
  LOOP EXTERNO: cls_idx = 0 até 9
  (calcula y[k] para cada classe de saída)
══════════════════════════════════════════
       ↓
  LOOP INTERNO: hid_idx = 0 até 127
  (acumula os 128 produtos para a classe cls_idx)

    END_SAIDA    → apresenta beta_rd_addr = j×10 + k  (hid_idx×10 + cls_idx)
    ESPERA_SA_0  → aguarda
    ESPERA_SA_1  → aguarda
    MAC_SAIDA    → acc += h[j] × Beta[j×10+k]
                   se j<127: j++, volta para END_SAIDA
                   se j==127: y_mem[k] = acc + produto_atual
                               acc = 0, j = 0
                               se k<9: k++, volta para END_SAIDA
                               se k==9: vai para ARGMAX
       ↓
ARGMAX
  → pred = argmax10(y_mem[0..9])   (combinacional, resultado imediato)
  → done = 1                        (pulso de 1 ciclo)
  → volta para OCIOSO
```

**Por que a fase LIMPAR é necessária?**

`h_mem` e `y_mem` são arrays de registradores internos ao `pbl_infer` — não são RAMs externas. Quando a inferência termina e começa outra, esses registradores ainda têm os valores da rodada anterior. Se a limpeza não acontecer:
- Na segunda inferência, `acc` começa do zero mas `h_mem[j]` ainda tem o h do cálculo anterior
- A tanh é aplicada sobre z correto, mas o resultado sobrescreve h_mem[j] — na verdade isso está ok
- O problema real está em `y_mem`: ele é acumulado durante a camada de saída, e se não for zerado, os produtos da inferência atual somam com os da anterior

Portanto: limpar `y_mem` é obrigatório. Limpar `h_mem` é uma boa prática porque os valores são sobrescritos antes de serem lidos na camada de saída, mas previne bugs sutis se a FSM for interrompida.

---

### O MAC em Q4.12 — detalhado

```verilog
// mac_q412.v — puramente combinacional, sem registradores
assign product_full   = $signed(a) * $signed(b);   // 16×16 = 32 bits, Q8.24
assign product_scaled = product_full >>> Q_FRAC;    // shift aritmético 12 → Q4.12
```

`product_full` tem 32 bits porque 16 × 16 = 32 bits são necessários para o produto completo. O formato resultante é Q8.24 (8 bits inteiros + 24 fracionários). O shift aritmético de 12 posições descarta os 12 bits menos significativos e retorna ao Q4.12, preservando o sinal (shift aritmético ≠ shift lógico — o bit de sinal é estendido).

Duas instâncias são criadas no `pbl_infer`:

```verilog
mac_q412 u_mac_hidden (
    .a              (img_rd_q),          // pixel da RAM IMG
    .b              (w_q),               // peso da RAM Pesos
    .product_full   (mult_hidden_full),
    .product_scaled (mult_hidden_scaled) // este vai para o acc
);

mac_q412 u_mac_output (
    .a              (h_mem[hid_idx]),    // saída da camada oculta (registrador)
    .b              (beta_rd_q),         // peso da RAM Beta
    .product_full   (mult_output_full),
    .product_scaled (mult_output_scaled)
);
```

Os dois estão sempre calculando — são combinacionais puros. A FSM decide qual resultado usar em cada fase: na fase MAC_OCULTA usa `mult_hidden_scaled`, na fase MAC_SAIDA usa `mult_output_scaled`. O outro resultado simplesmente é ignorado naquele ciclo.

O acumulador `acc` é de **32 bits** para não transbordar durante as somas consecutivas. Com 784 produtos de Q4.12 somados, o pior caso seria 784 × 7.9997 ≈ 6271 em valor real, que em Q4.12 é ~25.6 milhões — cabe confortavelmente em 32 bits com sinal.

---

### A tanh por partes — detalhado

A tanh real requer exponenciais (`e^x`). Em hardware isso seria um circuito caro. A solução é uma tabela de segmentos lineares que aproxima a curva com boa precisão.

**Passo 1 — Saturação do acumulador:**

Depois de 784 MACs, o `acc` de 32 bits pode ter um valor grande. Antes de passar para a tanh, ele precisa ser comprimido para 16 bits:

```verilog
function sat32_to_q16(input signed [31:0] x);
    if      (x > 32'sd32767)  return  16'sd32767;  // trava no máximo
    else if (x < -32'sd32768) return -16'sd32768;  // trava no mínimo
    else                      return x[15:0];       // valor cabe, passa direto
endfunction
```

O valor saturado `z_sat` é o que entra no `tanh_lut`.

**Passo 2 — Extração do sinal e valor absoluto:**

```verilog
sign_neg = x_in[15];              // bit mais significativo = sinal
if (sign_neg)
    x_abs = ~x_in + 1;           // complemento de 2 → valor absoluto
else
    x_abs = x_in;
```

A partir daqui o módulo trabalha só com valores não-negativos. A curva da tanh para positivos é monotonicamente crescente — mais fácil de segmentar.

**Passo 3 — Seleção do segmento e interpolação:**

Os pontos de controle em Q4.12:

```
X0 = 0,     X1 = 2048 (0.5),  X2 = 4096 (1.0)
X3 = 6144 (1.5),  X4 = 8192 (2.0),  X5 = 12288 (3.0)
```

Para cada segmento, Y base e inclinação também estão em Q4.12. A interpolação:

```verilog
delta_x   = x_abs - x0_seg           // distância até o início do segmento
interp    = (delta_x × slope) >>> 12  // produto Q4.12 × Q4.12, escalado
y_abs     = y0_seg + interp           // valor aproximado de tanh(|x|)
```

Se `x_abs >= X5 (3.0)`, a saída satura em ±4095 (≈ ±1.0 em Q4.12) sem interpolar.

**Passo 4 — Restaura o sinal:**

```verilog
y_raw = sign_neg ? -y_abs : y_abs;
```

E uma saturação final garante que a negação de -4095 não vire +4095+1 (que transbordariam):

```verilog
if      (y_raw > SAT_POS) y_out = SAT_POS;   // +4095
else if (y_raw < SAT_NEG) y_out = SAT_NEG;   // -4095
else                      y_out = y_raw;
```

---

### O argmax — detalhado

Recebe os 10 valores `y[0..9]` como entradas de 32 bits (o acumulador não é comprimido antes do argmax — usa o valor bruto para máxima precisão na comparação) e retorna o índice do maior:

```verilog
always @(*) begin
    pred    = 4'd0;
    max_val = y0;
    if (y1 > max_val) begin max_val = y1; pred = 4'd1; end
    if (y2 > max_val) begin max_val = y2; pred = 4'd2; end
    if (y3 > max_val) begin max_val = y3; pred = 4'd3; end
    // ... até y9
end
```

É puramente combinacional — o resultado está disponível no mesmo ciclo que `y_mem` estabiliza. A fase ARGMAX da FSM simplesmente registra `pred_argmax` em `pred` e pulsa `done = 1`.

---

### O pbl_ctrl — como funciona internamente

O `pbl_ctrl` tem dois papéis: (1) controlar o carregamento de dados pelo usuário e (2) disparar e monitorar a inferência.

**Detecção de borda do botão:**

Os botões da DE1-SoC são ativos em nível baixo (pressionado = 0). O `pbl_ctrl` registra o valor anterior do botão e detecta a transição 1→0:

```verilog
always @(posedge clk) btn_prev <= btn;
assign btn_pulse = (btn_prev == 1) && (btn == 0);  // só 1 ciclo por pressionamento
```

Sem isso, enquanto o botão fica pressionado (que dura muitos ciclos de clock a 50 MHz), a instrução seria executada centenas de vezes.

**Estados internos do pbl_ctrl:**

```
PRONTO   ─── btn_pulse + SW=000 ──► WRITE_W  → led_w=1,    ctrl_pesos_wren=1
         ─── btn_pulse + SW=001 ──► WRITE_B  → led_bias=1,  ctrl_bias_wren=1
         ─── btn_pulse + SW=010 ──► WRITE_β  → led_beta=1,  ctrl_beta_wren=1
         ─── btn_pulse + SW=011 ──► WRITE_IMG→ led_img=1,   ctrl_img_wren=1
         ─── btn_pulse + SW=111 ──► INICIANDO→ start=1 (1 ciclo), inferencia_ativa=1
         ─── btn_start          ──► INICIANDO→ start=1 (1 ciclo), inferencia_ativa=1
              ↑
              │  (todos os estados acima voltam para PRONTO no próximo ciclo)
              │
OCUPADO  ─── infer_done=1 ──► CONCLUÍDO → led_done=1, disp_done=1
OCUPADO  ─── infer_error=1 ──► ERRO      → led_error=1, disp_error=1
```

Os sinais `led_*` e `disp_*` são separados porque têm comportamentos diferentes:
- `led_*` ficam acesos permanentemente após serem setados (só reset apaga)
- `disp_*` refletem o estado atual — mudam conforme a FSM transita

---

### O display 7 segmentos

O `hex7seg` controla dois displays com lógicas independentes:

**HEX0 — dígito predito:**

```verilog
if (!en)  // en = led_done
    seg0 = 7'b1111111;  // apagado (ativo baixo: todos 1 = apagado)
else
    case (digit)
        4'd0: seg0 = 7'b1000000;  // 0
        4'd1: seg0 = 7'b1111001;  // 1
        // ...
    endcase
```

O `en = led_done` garante que HEX0 só acende após uma inferência concluir. Sem isso, o display mostraria `0` desde o reset (porque `pred` inicializa em zero).

**HEX5 — estado do sistema:**

```verilog
if      (led_error) seg5 = 7'b0000110;  // letra 'e'
else if (led_done)  seg5 = 7'b0100001;  // letra 'd'
else if (led_busy)  seg5 = 7'b0000011;  // letra 'b'
else if (led_ready) seg5 = 7'b0101111;  // letra 'r'
else                seg5 = 7'b1111111;  // apagado
```

Os displays da DE1-SoC são **ativos em nível baixo** — bit 0 significa segmento aceso, bit 1 significa apagado. A codificação `{g, f, e, d, c, b, a}` segue a ordem dos segmentos do display físico.

---

### Fluxo completo de sinais — do botão ao display

Para visualizar como tudo se conecta:

```
Usuário pressiona KEY[1] com SW=011 (WRITE_IMG)
    ↓
btn_pulse = 1  (por 1 ciclo)
    ↓
pbl_ctrl → ctrl_img_wren = 1
    ↓
top_level mux → img_wren_mux = 1  (pois inferencia_ativa=0)
    ↓
RAM IMG recebe escrita
    ↓
pbl_ctrl → led_img = 1  (permanente)
    ↓
LEDR[3] acende na placa

─────────────────────────────────────────────

Usuário pressiona KEY[2] (START)
    ↓
pbl_ctrl → start = 1 (1 ciclo), inferencia_ativa = 1
    ↓
top_level mux → todas as RAMs agora apontam para pbl_infer
    ↓
pbl_ctrl → led_busy = 1, disp_busy = 1
    ↓
LEDR[5] acende, HEX5 exibe 'b'
    ↓
pbl_infer → LIMPAR → camada oculta → camada saída → ARGMAX
    ↓
pbl_infer → done = 1 (1 ciclo), pred = dígito classificado
    ↓
pbl_ctrl captura infer_done → led_done = 1, disp_done = 1
    ↓
inferencia_ativa = 0  (RAMs liberadas)
    ↓
LEDR[6] acende, HEX5 exibe 'd', HEX0 exibe o dígito
```

---

## Interface MMIO e Ciclo de Instrução

O banco de registradores mapeia os sinais de controle e leitura do co-processador:

| Registrador | Offset | Bits                                          | R/W | Descrição |
|-------------|--------|-----------------------------------------------|-----|-----------|
| CTRL        | 0x00   | [9:7]=opcode, [6:3]=addr parcial, [2:0]=dado  | W   | Instrução completa via SW+BTN |
| STATUS      | 0x04   | [0]=ready, [1]=busy, [2]=done, [3]=error      | R   | Estado atual do sistema |
| RESULT      | 0x08   | [3:0]=pred                                    | R   | Dígito predito (0–9), válido quando done=1 |
| CYCLES      | 0x0C   | [31:0]                                        | R   | Ciclos da última inferência |

O protocolo **Start → Execute → Done** funciona assim:

```
1. SW=111, pressiona KEY[1]  →  pbl_ctrl pulsa start=1 por 1 ciclo
                              →  inferencia_ativa sobe
                              →  STATUS = BUSY, led_busy acende, HEX5='b'

2. pbl_infer percorre as 16 fases (~305.694 ciclos)
   cycles_out incrementa a cada ciclo

3. Fase ARGMAX: done=1 por 1 ciclo
              → pred registrado
              → inferencia_ativa cai
              → STATUS = DONE, led_done acende, HEX5='d', HEX0=dígito
```

O reset é assíncrono e ativo alto internamente. Como os botões da DE1-SoC são ativos em nível baixo, o `top_level` inverte: `.reset(~reset)`. O reset limpa a FSM (`phase`, `acc`, todos os índices), os buffers `h_mem` e `y_mem`, e os sinais de saída. O sistema volta para OCIOSO imediatamente.

---

## Paralelismo dos MACs

O projeto instancia dois módulos `mac_q412` simultaneamente — `u_mac_hidden` e `u_mac_output`. Os dois calculam em paralelo a cada ciclo, mas a FSM usa um por camada (não ambos ao mesmo tempo na mesma fase).

O impacto real em ciclos:

| Configuração         | MACs por ciclo | Ciclos totais  |
|----------------------|----------------|----------------|
| 1 MAC serial         | 1              | ~305.694       |
| 2 MACs (atual)       | 1 por fase     | ~305.694       |
| N MACs paralelos     | N              | ~305.694 / N   |

O ganho dos 2 MACs atuais é eliminação de latência na troca de camada, não redução de ciclos por operação. Para throughput > 1 MAC/ciclo dentro da mesma fase seria necessário replicar MACs com contadores paralelos e redesenhar a FSM — extensão natural para trabalhos futuros.

O valor real de ciclos é medido pelo `cycles_out[31:0]`, exposto como saída do `top_level` e acessível via **Tools → In-System Sources and Probes** no Quartus após síntese.

---

## Latência e Uso de Recursos

### Latência

Cada acesso a RAM consome 2 ciclos de espera + 1 ciclo de MAC = 3 ciclos por leitura:

| Componente                           | Ciclos        |
|--------------------------------------|---------------|
| LIMPAR (128 posições)                | 128           |
| Camada oculta: 128 × (784 × 3 + 5)  | ~301.696      |
| Camada de saída: 10 × (128 × 3 + 3) | ~3.870        |
| **Total estimado**                   | **~305.694**  |

A 50 MHz (período 20 ns): **~6,1 ms por inferência**.

A latência é **estritamente determinística** — o mesmo número de ciclos para qualquer imagem, pois a FSM percorre sempre as mesmas fases sem nenhum branch condicional sobre os dados. O `cycles_out` confirma isso: duas inferências consecutivas com imagens diferentes produzem exatamente o mesmo valor de ciclos.

### Uso de recursos (estimativa analítica)

| Recurso | Estimativa   | Limite EP4CGX150 | Por quê                               |
|---------|-------------|------------------|---------------------------------------|
| LUT     | < 5.000     | 20.000           | FSM (16 fases) + muxes das 4 RAMs     |
| FF      | < 3.000     | 20.000           | Registradores da FSM + h_mem (128×16b)|
| DSP     | 2           | 50               | Um bloco por instância de mac_q412    |
| BRAM    | ~52 blocos  | 100              | Pesos domina: 100k palavras ≈ 13 M10K |

Os dois MACs mapeiam nos DSPs dedicados do Cyclone V — sem gastar LUT em multiplicação. A RAM `Pesos` com 100.352 × 16 bits (≈ 1,6 MB) é o recurso dominante e usa a maior parte dos M10K disponíveis.

Os valores reais saem do **Compilation Report → Flow Summary** e a frequência máxima do **TimeQuest Timing Analyzer** após síntese completa no Quartus.

---

## Como usar na placa

### O que você precisa

- DE1-SoC ligada e conectada via USB-Blaster
- Quartus Prime com o projeto compilado (arquivo `.sof` gerado)
- Arquivos `.mif` dos pesos: `W_in_q.mif`, `b_q.mif`, `beta_q.mif`
- Arquivo `.mif` da imagem que quer classificar

### Mapeamento físico

| Controle | Função |
|----------|--------|
| KEY[0]   | Reset geral (ativo baixo) |
| KEY[1]   | Executa instrução das chaves (ativo baixo) |
| KEY[2]   | Dispara inferência diretamente (ativo baixo) |
| SW[2:0]  | Opcode da instrução |

| LED     | Indica |
|---------|--------|
| LEDR[0] | W_in confirmado |
| LEDR[1] | Bias confirmado |
| LEDR[2] | Beta confirmado |
| LEDR[3] | Imagem confirmada |
| LEDR[4] | Sistema pronto |
| LEDR[5] | Inferência em andamento |
| LEDR[6] | Resultado disponível |
| LEDR[7] | Erro |

### Passo 1 — Programar a FPGA

1. Abra o Quartus Prime e compile o projeto (**Processing → Start Compilation**)
2. Conecte o USB-Blaster à DE1-SoC e ligue a placa
3. Vá em **Tools → Programmer**, adicione o arquivo `.sof` e clique em **Start**
4. Aguarde 100% — a placa inicializa com HEX5 exibindo `r` e LEDR[4] aceso

### Passo 2 — Carregar os pesos via JTAG

Abra **Tools → In-System Memory Content Editor** e para cada memória:

| Instância | Arquivo      | SW para confirmar | KEY[1] | LED que acende |
|-----------|-------------|-------------------|--------|----------------|
| `Peso`    | W_in_q.mif  | SW = `000`        | 1×     | LEDR[0]        |
| `Bias`    | b_q.mif     | SW = `001`        | 1×     | LEDR[1]        |
| `Beta`    | beta_q.mif  | SW = `010`        | 1×     | LEDR[2]        |
| `IMG`     | imagem.mif  | SW = `011`        | 1×     | LEDR[3]        |

Para cada linha:
1. Clique na instância no Memory Content Editor
2. Botão direito → **Import Data from File** → selecione o `.mif`
3. Na placa, posicione as chaves SW conforme a tabela
4. Pressione KEY[1] uma vez
5. Verifique o LED correspondente acendendo

Quando LEDR[0], [1], [2] e [3] estiverem todos acesos, todos os dados estão confirmados.

### Passo 3 — Executar a inferência

Pressione **KEY[2]**.

- LEDR[5] acende, HEX5 exibe `b` → inferência rodando (~6 ms)
- LEDR[6] acende, HEX5 exibe `d`, HEX0 exibe o dígito → pronto

Para classificar outra imagem: repita o Passo 2 só para a instância `IMG` (os pesos não precisam ser recarregados), depois pressione KEY[2] de novo.

### Passo 4 — Em caso de erro

Se LEDR[7] acender e HEX5 exibir `e`: pressione KEY[0] para resetar e repita tudo do Passo 2. A causa mais comum é pressionar KEY[2] antes de confirmar todos os dados.

### Resumo

```
Compilar → programar .sof
    ↓
Memory Content Editor:
  Peso  → W_in_q.mif  → SW=000 → KEY[1] → LEDR[0] ✓
  Bias  → b_q.mif     → SW=001 → KEY[1] → LEDR[1] ✓
  Beta  → beta_q.mif  → SW=010 → KEY[1] → LEDR[2] ✓
  IMG   → imagem.mif  → SW=011 → KEY[1] → LEDR[3] ✓
    ↓
KEY[2] → HEX5='b' → aguarda → HEX5='d', HEX0=resultado
```

---

## Testes e Resultados

### Simulação

O testbench instancia o `top_level` completo e simula o protocolo completo de uso:

```verilog
// Ciclo completo de teste
reset = 1; @(posedge clk); reset = 0;

// Confirma carregamentos (pesos já nos .mif)
send_instr(OP_WRITE_W,    0, 0);   // SW=000, KEY[1]
send_instr(OP_WRITE_BIAS, 0, 0);   // SW=001
send_instr(OP_WRITE_BETA, 0, 0);   // SW=010
send_instr(OP_WRITE_IMG,  0, 0);   // SW=011

// Dispara inferência
send_instr(OP_START, 0, 0);

// Polling até done
wait(led_done == 1);

// Valida resultado
assert(pred === expected_digit);
$display("Ciclos: %0d | Pred: %0d | Esperado: %0d", cycles_out, pred, expected_digit);
```

Vetores de teste do MNIST cobrindo os 10 dígitos foram comparados contra um golden model Python (float64). Acurácia confirmada acima de 90%.

### Resultados na placa

O sistema classificou corretamente os dígitos de 0 a 9 em imagens fornecidas pelo professor, com exceção de algumas amostras do **dígito 5**, que foi classificado como 1 ou 4 dependendo da imagem. A investigação confirmou que o hardware está correto — o mesmo erro ocorre no golden model em software. É uma limitação do modelo ELM com H=128, cujas margens de decisão para o 5 são estreitas.

### Problema durante o desenvolvimento — display

O HEX0 exibia zero na inicialização mesmo antes de qualquer inferência rodar. A causa: `pred` inicializa em zero no reset e o display exibia esse valor. A solução foi adicionar o sinal `en = led_done` ao `hex7seg` — o display só acende quando uma inferência concluiu.

Outro problema encontrado: os displays ficavam completamente apagados ou com segmentos errados. Causa: displays da DE1-SoC são **ativos em nível baixo** (0 = aceso), e a tabela de decodificação estava com os bits invertidos em versões anteriores. Corrigido ajustando os valores do `case` no `hex7seg`.

---

## Conclusão

O co-processador implementa a inferência completa de uma ELM em hardware reconfigurável com todas as características exigidas: FSM de controle de 16 fases, datapath MAC em Q4.12, função de ativação tanh aproximada por partes, argmax combinacional e memórias M10K com endereçamento eficiente via shifts.

A latência de ~6 ms a 50 MHz é determinística e medível pelo `cycles_out`. A acurácia é superior a 90% nos vetores de teste, compatível com o esperado para um modelo ELM com 128 neurônios na camada oculta.

Os principais desafios técnicos foram o gerenciamento da latência das RAMs síncronas (resolvido com estados de espera explícitos na FSM) e o arbitramento de acesso às memórias entre os módulos de controle e inferência (resolvido com mux de prioridade no `top_level`).

Os marcos 2 e 3 preveem a adição de um driver Linux em Assembly para comunicação via HPS-FPGA e uma aplicação em C para submissão de imagens via MMIO, completando o sistema heterogêneo ARM+FPGA.
