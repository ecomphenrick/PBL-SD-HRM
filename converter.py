
def png_to_mif(input_png, output_mif):
    # Abrir imagem
    img = Image.open(input_png).convert('L')  # 'L' = grayscale

    # Garantir tamanho 28x28
    if img.size != (28, 28):
        raise ValueError("A imagem deve ser 28x28 pixels")

    pixels = list(img.getdata())

    with open(output_mif, 'w') as f:
        f.write("WIDTH=8;\n")        # 8 bits por pixel (0–255)
        f.write("DEPTH=784;\n\n")    # 28x28 = 784 pixels

        f.write("ADDRESS_RADIX=UNS;\n")
        f.write("DATA_RADIX=UNS;\n\n")

        f.write("CONTENT BEGIN\n")

        for addr, pixel in enumerate(pixels):
            f.write(f"{addr} : {pixel};\n")

        f.write("END;\n")

# Exemplo de uso
png_to_mif("imagem.png", "saida.mif")
