`timescale 1ns / 1ps

module oled_font (
  input wire [7:0] character,
  input wire [2:0] column,
  output reg [7:0] pixels
);
  reg [39:0] glyph;

  // 5×7 글꼴의 Column을 왼쪽부터 저장하며 Bit 0이 위쪽 Pixel이다.
  always @* begin
    case (character)
      "0": glyph = 40'h3E5149453E;
      "1": glyph = 40'h00427F4000;
      "2": glyph = 40'h4261514946;
      "3": glyph = 40'h2141454B31;
      "4": glyph = 40'h1814127F10;
      "5": glyph = 40'h2745454539;
      "6": glyph = 40'h3C4A494930;
      "7": glyph = 40'h0171090503;
      "8": glyph = 40'h3649494936;
      "9": glyph = 40'h064949291E;
      "A": glyph = 40'h7E1111117E;
      "B": glyph = 40'h7F49494936;
      "C": glyph = 40'h3E41414122;
      "D": glyph = 40'h7F4141221C;
      "E": glyph = 40'h7F49494941;
      "F": glyph = 40'h7F09090901;
      "G": glyph = 40'h3E4149497A;
      "H": glyph = 40'h7F0808087F;
      "I": glyph = 40'h00417F4100;
      "J": glyph = 40'h2040413F01;
      "K": glyph = 40'h7F08142241;
      "L": glyph = 40'h7F40404040;
      "M": glyph = 40'h7F020C027F;
      "N": glyph = 40'h7F0408107F;
      "O": glyph = 40'h3E4141413E;
      "P": glyph = 40'h7F09090906;
      "Q": glyph = 40'h3E4151215E;
      "R": glyph = 40'h7F09192946;
      "S": glyph = 40'h4649494931;
      "T": glyph = 40'h01017F0101;
      "U": glyph = 40'h3F4040403F;
      "V": glyph = 40'h1F2040201F;
      "W": glyph = 40'h7F2018207F;
      "X": glyph = 40'h6314081463;
      "Y": glyph = 40'h0304780403;
      "Z": glyph = 40'h6151494543;
      ".": glyph = 40'h0060600000;
      "-": glyph = 40'h0808080808;
      ":": glyph = 40'h0036360000;
      "%": glyph = 40'h2313086462;
      default: glyph = 40'b0;
    endcase
    case (column)
      0: pixels = glyph[39:32];
      1: pixels = glyph[31:24];
      2: pixels = glyph[23:16];
      3: pixels = glyph[15:8];
      4: pixels = glyph[7:0];
      default: pixels = 8'b0;
    endcase
  end
endmodule
