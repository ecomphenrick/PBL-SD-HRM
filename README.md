# PBL-SD-HRM

# Co-Processador de Rede Neural ELM - Marco 1

Este projeto implementa um co-processador de rede neural do tipo Extreme Learning Machine (ELM) quantizado (Q4.12) em uma FPGA Intel Cyclone V (Placa Terasic DE1-SoC). O objetivo deste Marco é validar o *Datapath* (Multiplicador-Acumulador, Função de Ativação Tanh e Argmax) processando inferências de imagens 28x28 gravadas nativamente no chip.

## 🛠️ Pré-requisitos para Execução

Antes de gravar o projeto na placa, garanta que:
1. O software **Intel Quartus Prime** está instalado.
2. Os seguintes arquivos de inicialização de memória (`.mif`) estão salvos na **mesma pasta raiz** do projeto:
   - `W_in_q.mif` (Pesos da camada de entrada)
   - `b_q.mif` (Bias da camada oculta)
   - `beta_q.mif` (Pesos da camada de saída)
   - `imagem_teste.mif` (A imagem a ser classificada, em formato hexadecimal Q4.12)
3. O projeto foi compilado com sucesso gerando o arquivo `pbl.sof` (ou equivalente).

---

## ⚡ Gravação na Placa (FPGA)

1. Conecte a placa DE1-SoC ao computador via cabo USB (porta USB Blaster) e ligue a energia.
2. No Quartus, abra o **Programmer** (`Tools > Programmer`).
3. Clique em **Hardware Setup** e selecione `DE-SoC [USB-1]`.
4. Clique em **Auto Detect** e selecione o chip `5CSEMA5`.
5. Selecione a linha do chip `5CSEMA5`, clique em **Change File...** e escolha o arquivo `.sof` gerado na pasta `output_files`.
6. Marque a caixa *Program/Configure* e clique em **Start**. 

Quando a luz `CONFIG DONE` acender na placa, o hardware estará pronto para uso.

---

## 🎛️ Mapeamento de Hardware e Controles

O sistema utiliza os botões (KEYs), chaves deslizantes (SWs) e displays de 7 segmentos (HEX) da placa.

### Botões e Displays
* **`KEY[0]`**: **RESET** (Botão mais à direita). Aperte para reiniciar a máquina de estados.
* **`KEY[3]`**: **EXECUTE** (Botão mais à esquerda). Aperte para enviar o comando configurado nas chaves.
* **`HEX0`**: Display de **Status** (`b` = Busy/Calculando, `d` = Done/Pronto, `E` = Erro de Memória).
* **`HEX1`**: Display de **Resultado** (Mostra o dígito numérico classificado de `0` a `9`).

### Chaves de Instrução (SW) - Ordem: Direita ➔ Esquerda
Para montar as instruções, utilizamos 5 chaves (`SW0` a `SW4`). 
A tabela abaixo mostra a ordem física na placa, da direita (SW0) para a esquerda (SW4). 
*(Para Cima = 1 / Para Baixo = 0)*

| Ordem Física | Chave | Função na Instrução | Observação |
| :---: | :---: | :--- | :--- |
| **Direita** | `SW[0]` | Bit Auxiliar (Bit 27) | **Mantenha sempre para baixo (0)**. |
| ↓ | `SW[1]` | Bit 0 do Opcode | |
| ↓ | `SW[2]` | Bit 1 do Opcode | |
| ↓ | `SW[3]` | Bit 2 do Opcode | |
| **Esquerda** | `SW[4]` | Bit 3 do Opcode | |

---

## 🚀 Guia de Operação Passo a Passo

Siga esta sequência lógica no painel da DE1-SoC para testar a rede neural:

### 1. Inicialização
Pressione e solte o botão **`KEY[0]`** (Reset).
* *Resultado:* Os displays HEX0 e HEX1 devem se apagar. O sistema está em IDLE.

### 2. Verificar Memórias (Opcode `1111`)
Garante que os arquivos `.mif` foram gravados corretamente no FPGA.
* **Chaves (Dir ➔ Esq):** `0` - `1` - `1` - `1` - `1` 
  *(Apenas SW0 para baixo, o resto para cima)*
* Pressione **`KEY[3]`** (Execute).
* *Resultado:* O display `HEX0` piscará `b` e parará em `d` (Done). Se aparecer `E` (Error), as memórias estão vazias (recompile o Quartus com os .mif na pasta correta).

### 3. Iniciar Inferência / START (Opcode `0100`)
Inicia o cálculo das matrizes multiplicando a imagem pelos pesos.
* **Chaves (Dir ➔ Esq):** `0` - `0` - `0` - `1` - `0` 
  *(Apenas a chave SW3 para cima, o resto para baixo)*
* Pressione **`KEY[3]`** (Execute).
* *Resultado:* O display `HEX0` mostrará `b` (Busy) rapidamente enquanto calcula os 128 neurônios ocultos e a camada de saída. Ao finalizar, mostrará `d` (Done).

### 4. Ler Resultado / STATUS (Opcode `0101`)
Solicita que o hardware exiba a classificação final calculada pelo bloco Argmax.
* **Chaves (Dir ➔ Esq):** `0` - `1` - `0` - `1` - `0` 
  *(Chaves SW1 e SW3 para cima)*
* Pressione **`KEY[3]`** (Execute).
* *Resultado:* O display `HEX1` acenderá mostrando o número (0 a 9) que a rede neural identificou na imagem.

---
*Desenvolvido para a disciplina de Problema Baseado em Soluções (PBL) - Sistemas Digitais / Arquitetura de Computadores.*
