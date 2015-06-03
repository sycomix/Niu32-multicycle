module SevenSeg(hexNumIn, displayOut);
    // Outputs the display value given (hexNumIn) as a lighting
    // value on the DE1's seven-segment hex display (displayOut).
    input  [3:0] hexNumIn;
    output [6:0] displayOut;
    assign displayOut =
        (hexNumIn == 4'h0) ? 7'b1000000 :
        (hexNumIn == 4'h1) ? 7'b1111001 :
        (hexNumIn == 4'h2) ? 7'b0100100 :
        (hexNumIn == 4'h3) ? 7'b0110000 :
        (hexNumIn == 4'h4) ? 7'b0011001 :
        (hexNumIn == 4'h5) ? 7'b0010010 :
        (hexNumIn == 4'h6) ? 7'b0000010 :
        (hexNumIn == 4'h7) ? 7'b1111000 :
        (hexNumIn == 4'h8) ? 7'b0000000 :
        (hexNumIn == 4'h9) ? 7'b0010000 :
        (hexNumIn == 4'hA) ? 7'b0001000 :
        (hexNumIn == 4'hB) ? 7'b0000011 :
        (hexNumIn == 4'hC) ? 7'b1000110 :
        (hexNumIn == 4'hD) ? 7'b0100001 :
        (hexNumIn == 4'hE) ? 7'b0000110 :
        /*hexNumIn == 4'hF*/  7'b0001110 ;
endmodule
